---
name: webhook-replay-protection
description: Idempotent webhook handlers via UNIQUE provider_message_id index plus DataIntegrityViolationException catch at the repo boundary. Concurrent acceptance test on shared Postgres. Postgres as coordina...
origin: ECC
triggers: webhook replay, replay protection, idempotency, providermessageid, DataIntegrityViolationException, UNIQUE constraint, ON CONFLICT, Stripe webhook, Meta WhatsApp webhook, Twilio webhook, Slack webhook, deduplication
paths:
  - "**/*.java"
  - "**/*.kt"
  - "**/*.ts"
---
# Webhook Replay Protection

A signature on a webhook proves authenticity, not freshness. An attacker (or a bug, or a retry storm) that captures one valid `(signature, body)` pair can re-POST it indefinitely. The signature still verifies; the handler still runs; the metrics, side effects, and downstream calls fire again.

The fix is **idempotency at the persistence boundary**, keyed on the provider's own message identifier, enforced by a database UNIQUE index — not by Java synchronization, not by Redis, not by an in-process map.

## When to use

- Stripe webhooks (`event.id`).
- Meta WhatsApp Cloud API webhooks (`messages[].id` aka `wamid.*`).
- Twilio webhooks (`MessageSid`, `CallSid`).
- Slack Events API (`event_id`).
- GitHub webhooks (`X-GitHub-Delivery`).
- Any webhook that has a provider-issued, unique-per-event id and a "process once, ack 2xx, never retry" semantics.
- Internal queue consumers where the broker can redeliver (SQS at-least-once, Kafka with non-zero retries, RabbitMQ with `requeue=true`).

## When NOT to use

- The webhook explicitly carries no identifier (some Salesforce outbound messages, legacy SOAP). Use a content hash (`sha256(body)`) plus a time window as a weaker proxy. Document the trade-off.
- The webhook is **inherently** a stream of repeatable status updates (delivery receipts, presence updates) where re-applying is a no-op. Per-event idempotency may be over-engineering.

## The pattern

### 1. Schema — partial UNIQUE index

```sql
-- V27__add_unique_index_whatsapp_inbound_provider_message_id.sql
CREATE UNIQUE INDEX IF NOT EXISTS uniq_whatsapp_inbound_provider_message_id
    ON whatsapp_inbound_messages (provider_message_id)
    WHERE provider_message_id IS NOT NULL;
```

The constraint is **partial** because some payloads (status updates, reactions) arrive with no `messages[].id`. Those still persist (one row per delivery, audit trail), but cannot be deduped via this mechanism — and shouldn't be, because they aren't the replay vector.

### 2. Service — extract, normalize, insert, catch

```java
@Override
public Outcome accept(byte[] rawBody) {
    String fullPayload = new String(rawBody, StandardCharsets.UTF_8);
    ExtractedFields extracted = extract(fullPayload);

    // Unicode-NFC normalize before lookup AND insert. The DB compares bytes;
    // a decomposed-form variant of a previously-seen id would otherwise bypass.
    String providerMessageId = canonicalize(extracted.providerMessageId);

    // Fast-path: in-process lookup avoids the round-trip in the common
    // sequential case. The DB UNIQUE index is the actual concurrency proof.
    if (providerMessageId != null) {
        Optional<WhatsAppInboundMessageEntity> existing =
            repository.findByProviderMessageId(providerMessageId);
        if (existing.isPresent()) {
            meterRegistry.counter(WHATSAPP_INBOUND_REPLAY).increment();
            return new Outcome(existing.get().toDto().id(), null);
        }
    }

    UUID id = UUID.randomUUID();
    WhatsAppInboundMessage persisted = new WhatsAppInboundMessage(
        id, providerMessageId, extracted.senderPhoneE164(),
        extracted.textBody(), storedPayload, Instant.now(clock));
    try {
        repository.saveAndFlush(WhatsAppInboundMessageEntity.fromDto(persisted));
    } catch (DataIntegrityViolationException ex) {
        // Lost the race. Re-fetch the winner and return its outcome.
        if (providerMessageId != null) {
            Optional<WhatsAppInboundMessageEntity> winner =
                repository.findByProviderMessageId(providerMessageId);
            if (winner.isPresent()) {
                meterRegistry.counter(WHATSAPP_INBOUND_REPLAY).increment();
                return new Outcome(winner.get().toDto().id(), null);
            }
        }
        throw ex; // genuine integrity violation — propagate
    }

    // ... only NOW invoke parser + orchestrator. Duplicates skip both.
}
```

`saveAndFlush` (not `save`) forces the INSERT immediately so the `DataIntegrityViolationException` surfaces inside the try-block instead of at transaction commit, far away from the catch.

### 3. Response — `200 OK` on duplicate

Meta, Stripe, GitHub all use non-2xx as a retry signal. Returning 409 on a duplicate would drive the provider into a retry loop fighting your own idempotency.

```java
return ResponseEntity.ok().build();   // duplicate? still 200.
```

## Why not a separate dedupe table with TTL?

- The inbound-messages table already keys on `provider_message_id` and is the natural location for the constraint. A separate dedupe table creates two sources of truth that can diverge under partial failure.
- Provider retry windows are hours, not days. The inbound table is already long-lived for audit. No TTL cleanup is load-bearing.

## Why not Redis?

- The inbound-messages table is already cluster-shared via Postgres. Any replica sees any other replica's writes immediately — strong consistency by definition.
- Redis is a cache that can lag the source of truth. During Redis failover, a replay window opens.
- Postgres is already in the stack. Adding Redis adds a second coordination point and a second failure mode.

The single source of truth is the database. Coordination at the DB is **strong consistency, by construction**.

## Concurrency proof

```java
@Test
void should_let_exactly_one_concurrent_replay_persist_and_orchestrate() throws Exception {
    String providerMessageId = "wamid.race-" + UUID.randomUUID();
    String body = "...{\"id\":\"" + providerMessageId + "\",...}...";

    AtomicInteger orchestratorCalls = new AtomicInteger(0);
    int contenders = 100; // 12 wasn't enough on low-parallelism CI runners
    ExecutorService pool = Executors.newFixedThreadPool(contenders);
    CountDownLatch start = new CountDownLatch(1);

    List<Future<UUID>> futures = new ArrayList<>();
    for (int i = 0; i < contenders; i++) {
        futures.add(pool.submit(() -> {
            start.await();
            return service.accept(body.getBytes(UTF_8)).persistedId();
        }));
    }
    start.countDown();
    List<UUID> persistedIds = new ArrayList<>();
    for (Future<UUID> f : futures) persistedIds.add(f.get(30, SECONDS));

    assertThat(repository.count()).isEqualTo(1);
    assertThat(orchestratorCalls.get()).isEqualTo(1);
    assertThat(persistedIds).containsOnly(persistedIds.get(0));
}
```

The latch + 100 contenders pattern is required: 12 contenders is not enough to reliably observe the race on low-parallelism CI runners. The assertions are the load-bearing ones — exactly one row, exactly one orchestrator call, every caller sees the **same** UUID.

This test runs against a real Postgres via a Testcontainers singleton, not H2. H2 honors `UNIQUE` constraints, but its concurrency model differs enough from Postgres that race tests against H2 do not generalize.

## Common gotchas / variants

- **Catching `Exception` instead of `DataIntegrityViolationException`** — masks a genuine bug as "duplicate detected".
- **Forgetting `saveAndFlush`** — the INSERT is queued; the violation surfaces at commit time, outside any try/catch in the service.
- **Normalizing on lookup but not on INSERT (or vice versa)** — Unicode NFC vs NFD, casing, whitespace. Canonicalize once, before both reads and writes.
- **Hash of body instead of provider id** — works, but a body that is byte-for-byte identical except for whitespace bypasses. If you must hash, hash a canonicalized form.
- **Redis-based dedupe with `SET NX EX`** — works in single-region, fails on Redis failover with a replay window. Use the DB.
- **Trying to dedupe before signature verification** — leaks a "this id already seen" oracle to unauthenticated callers. Verify signature first, dedupe second.
- **Partial constraint missed on initial migration** — full UNIQUE on a nullable column rejects every status update because Postgres treats multiple NULLs as distinct, but other databases (SQL Server) treat them as equal. Use the partial form with `WHERE col IS NOT NULL` for cross-database portability and explicitness.

## Node.js / TypeScript equivalent

The same `INSERT ... ON CONFLICT DO NOTHING` pattern works in any Node Express service backed by Postgres. Sequelize and `pg` both expose the raw query escape; the equivalent of `saveAndFlush` is `await transaction.commit()` after the insert.

### Express + Sequelize

```typescript
// migration: add the partial UNIQUE index
await queryInterface.addIndex('whatsapp_inbound_messages', ['provider_message_id'], {
  name: 'uniq_whatsapp_inbound_provider_message_id',
  unique: true,
  where: { provider_message_id: { [Op.ne]: null } },  // partial index
});

// service: race-safe insert
async function accept(rawBody: Buffer): Promise<Outcome> {
  const fullPayload = rawBody.toString('utf-8');
  const extracted = extract(fullPayload);
  const providerMessageId = canonicalize(extracted.providerMessageId);

  // Fast-path: avoid the round-trip in the sequential case
  if (providerMessageId) {
    const existing = await WhatsAppInboundMessage.findOne({
      where: { providerMessageId },
    });
    if (existing) {
      meterRegistry.counter('whatsapp.inbound.replay').inc();
      return { id: existing.id, replay: true };
    }
  }

  try {
    const persisted = await WhatsAppInboundMessage.create({
      id: uuid.v4(),
      providerMessageId,
      senderPhoneE164: extracted.senderPhoneE164,
      textBody: extracted.textBody,
      payload: extracted.payload,
      receivedAt: new Date(),
    });
    return { id: persisted.id, replay: false };
  } catch (e) {
    // Sequelize wraps unique-constraint violations in UniqueConstraintError
    if (e instanceof UniqueConstraintError && providerMessageId) {
      const winner = await WhatsAppInboundMessage.findOne({
        where: { providerMessageId },
      });
      if (winner) {
        meterRegistry.counter('whatsapp.inbound.replay').inc();
        return { id: winner.id, replay: true };
      }
    }
    throw e;
  }
}
```

### Express + raw `pg`

```typescript
const result = await client.query(`
  INSERT INTO whatsapp_inbound_messages (id, provider_message_id, ...)
  VALUES ($1, $2, ...)
  ON CONFLICT (provider_message_id) WHERE provider_message_id IS NOT NULL DO NOTHING
  RETURNING id
`, [id, providerMessageId, ...]);
if (result.rows.length === 0) {
  // Lost the race — read the winner
  const winner = await client.query(
    'SELECT id FROM whatsapp_inbound_messages WHERE provider_message_id = $1',
    [providerMessageId]
  );
  return { id: winner.rows[0].id, replay: true };
}
```

### Differences from Java

- Sequelize's `UniqueConstraintError` is the equivalent of `DataIntegrityViolationException`. Use `instanceof`, not `e.name`.
- No `saveAndFlush` distinction — every Sequelize `create()` issues the INSERT immediately.
- Raw SQL via `client.query` with `ON CONFLICT ... DO NOTHING RETURNING id` is the cleanest variant; check `result.rows.length === 0` to detect the loss-of-race.

### When NOT to use the Node variant

- Same as Java: webhooks without a stable identifier, or pure status-update streams.

## References

- Implementation:
- Stripe — `event.id`, https://stripe.com/docs/webhooks/best-practices
- Meta — `messages[].id` (`wamid.*`), https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks
- GitHub — `X-GitHub-Delivery` header
