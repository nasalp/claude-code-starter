---
name: concurrent-idempotency-saveAndFlush
description: Close the read-then-write race in JPA idempotency guards by replacing save() with saveAndFlush() plus a UNIQUE constraint and a duplicate-row reconciliation branch.
origin: ECC
triggers: idempotency, idempotencykey, deduplication, double-send, double-charge, saveAndFlush, DataIntegrityViolationException, ON CONFLICT DO NOTHING, EmailDispatcher, payment dispatcher, JPA race condition
paths:
  - "**/*.java"
---
# Concurrent Idempotency with `saveAndFlush`

## When to use

A service exposes an "at-most-once" operation keyed by an `idempotency_key`
(send email, charge card, publish artifact, deliver webhook). The current
guard reads `existsByKeyAndStatus(key, "SENT")` and only writes the SENT row
*after* the side-effect (network call, payment, dispatch) returns. Two
threads with the same key both see "no SENT row", both pass the guard, both
fire the side-effect.

The DB-level `UNIQUE (idempotency_key, provider)` constraint exists but is
not protective: Hibernate buffers the PENDING-row INSERT in the persistence
context until commit. Both threads have already called the network sender
by the time the constraint sees a second row.

## When NOT to use

- The operation is naturally idempotent on the receiver side (PUT to the
  same key, GET, etc.) — no guard needed.
- You can route every key through a single partition or single consumer
  (Kafka key-based partitioning, single-threaded Sidekiq queue). The race
  cannot happen.
- The side-effect is local and cheap — pessimistic `SELECT ... FOR UPDATE`
  on the parent aggregate is simpler.

## The pattern

Three pieces, all required:

1. A DB-level `UNIQUE` constraint on the idempotency tuple.
2. `saveAndFlush(...)` (or `INSERT ... ON CONFLICT DO NOTHING`) so the
   INSERT goes to the database *before* the side-effect, holding a
   row-level lock on the uncommitted transaction.
3. A `catch (DataIntegrityViolationException)` branch that reads the
   existing row and reconciles based on its status.

### 1. Schema

```sql
CREATE TABLE email_send_attempts (
    id              UUID PRIMARY KEY,
    idempotency_key VARCHAR(255) NOT NULL,
    provider        VARCHAR(64)  NOT NULL,
    status          VARCHAR(16)  NOT NULL,  -- PENDING | SENT | FAILED
    -- ...
    UNIQUE (idempotency_key, provider)
);
```

### 2. Dispatcher

```java
@Service
@Transactional
class DualProviderEmailDispatcher implements EmailDispatcher {

    private final EmailSendAttemptRepository attemptRepository;
    private final EmailSender primary;

    @Override
    public EmailSendResult dispatch(EmailMessage message) {
        // Cheap fast-path for the already-SENT case.
        if (attemptRepository.existsByIdempotencyKeyAndStatus(
                message.idempotencyKey(), "SENT")) {
            return EmailSendResult.accepted("duplicate", null, 200);
        }
        return attemptWith(primary, message);
    }

    private EmailSendResult attemptWith(EmailSender sender, EmailMessage msg) {
        UUID rowId = UUID.randomUUID();
        // ON CONFLICT DO NOTHING: 1 row claimed, 0 rows = lost the race.
        int claimed = attemptRepository.claimPendingSlot(
                rowId, msg.idempotencyKey(), msg.template().slug(),
                msg.recipientEmail(), sender.providerName(), Instant.now());
        if (claimed == 0) {
            return resolveConcurrentDuplicate(msg, sender);
        }
        EmailSendResult result = sender.send(msg);    // network call
        EmailSendAttempt row = attemptRepository.findById(rowId).orElseThrow();
        row.recordOutcome(result.accepted(), result.providerMessageId(),
                          result.errorCode(), result.errorMessage());
        attemptRepository.save(row);
        return result;
    }

    private EmailSendResult resolveConcurrentDuplicate(
            EmailMessage msg, EmailSender sender) {
        EmailSendAttempt existing = attemptRepository
            .findByIdempotencyKeyAndProvider(msg.idempotencyKey(),
                                              sender.providerName())
            .orElseThrow(() -> new IllegalStateException(
                "Conflict reported but row not found"));
        if ("SENT".equals(existing.status())) {
            // Winner already finished. Return accepted-duplicate.
            return EmailSendResult.accepted("duplicate", null, 200);
        }
        // Winner is still PENDING (in flight). Don't cascade to fallback —
        // they may yet succeed. Return non-retryable rejection.
        return EmailSendResult.rejected(sender.providerName(), 409,
                "CONCURRENT_DISPATCH",
                "Another dispatcher claimed this idempotency_key", false);
    }
}
```

The repository method:

```java
@Modifying
@Query(value = """
    INSERT INTO email_send_attempts
        (id, idempotency_key, template_slug, recipient_email,
         provider, status, attempted_at)
    VALUES (?1, ?2, ?3, ?4, ?5, 'PENDING', ?6)
    ON CONFLICT (idempotency_key, provider) DO NOTHING
    """, nativeQuery = true)
int claimPendingSlot(UUID id, String idempotencyKey, String templateSlug,
                     String recipientEmail, String provider, Instant attemptedAt);
```

If you stay with vanilla Spring Data, replace `attemptRepository.save(row)`
with `saveAndFlush(row)` and `try { ... } catch (DataIntegrityViolationException)`
the same reconciliation branch.

### 3. The concurrency test

```java
@Testcontainers
@SpringBootTest
class DualProviderEmailDispatcherConcurrencyIT {

    @Container
    static PostgreSQLContainer<?> pg = new PostgreSQLContainer<>("postgres:16");

    @Autowired DualProviderEmailDispatcher dispatcher;
    @MockBean EmailSender sendGridEmailSender;

    @Test
    void exactly_one_send_when_two_threads_race_on_same_idempotency_key()
            throws Exception {
        var startGate     = new CountDownLatch(1);
        var senderEntered = new CountDownLatch(2);
        var senderRelease = new CountDownLatch(1);
        var sendCalls     = new AtomicInteger(0);

        when(sendGridEmailSender.send(any(), any())).thenAnswer(inv -> {
            sendCalls.incrementAndGet();
            senderEntered.countDown();
            senderRelease.await();   // hold both threads inside send(...)
            return EmailSendResult.accepted("sendgrid", "msg-1", 200);
        });

        var message = sampleMessageWithKey("idem-42");
        var pool = Executors.newFixedThreadPool(2);
        Future<EmailSendResult> a = pool.submit(() -> {
            startGate.await(); return dispatcher.dispatch(message);
        });
        Future<EmailSendResult> b = pool.submit(() -> {
            startGate.await(); return dispatcher.dispatch(message);
        });
        startGate.countDown();
        senderRelease.countDown();

        var ra = a.get(5, TimeUnit.SECONDS);
        var rb = b.get(5, TimeUnit.SECONDS);

        assertThat(sendCalls.get()).isEqualTo(1);
        assertThat(attemptRepository.countByIdempotencyKeyAndStatus("idem-42", "SENT"))
            .isEqualTo(1);
        // One thread accepted with the real provider, the other accepted="duplicate"
        // OR rejected with CONCURRENT_DISPATCH depending on timing.
        assertThat(List.of(ra, rb))
            .anyMatch(r -> r.accepted() && "sendgrid".equals(r.provider()));
    }
}
```

The two latches are required: without them the test passes vacuously
because thread A finishes the entire `dispatch` before thread B even
starts.

## Common gotchas / variants

- **PENDING winner case is NOT a duplicate-accepted.** When the existing
  row is `PENDING`, the winner is still in-flight; their network call
  may still fail. If you return `accepted=true, provider="duplicate"`
  here and the winner later flips to `FAILED`, you have lied. Return a
  non-retryable rejection (`CONCURRENT_DISPATCH` / `409`) so the caller
  does not cascade to the fallback provider.
- **Don't catch `DataIntegrityViolationException` and call the sender
  anyway.** That recreates the original race. The caught branch must
  read the existing row and decide based on its status.
- **The fast-path `existsByKeyAndStatus(key, "SENT")` is an optimization,
  not a guard.** It exists to skip the INSERT when the answer is already
  known. The actual guard is the `UNIQUE` constraint plus
  `saveAndFlush` / `ON CONFLICT`.
- **Hibernate's `@Version` does NOT help here.** Optimistic locking
  protects existing rows from concurrent UPDATE; the race is an INSERT
  problem.
- **`INSERT ... ON CONFLICT DO NOTHING` returns 0 rows on conflict** —
  that is your race-loser signal. `saveAndFlush + DataIntegrityViolation`
  is the JPA-portable equivalent; both are correct.

## Verification

Required test shape:

1. `CountDownLatch` to synchronize the start of two threads.
2. A second `CountDownLatch` (or an `await` inside the mock sender) so
   both threads are demonstrably inside the network call simultaneously.
3. Assert `sender.send(...)` was called exactly once.
4. Assert exactly one `SENT` row exists for the idempotency key.
5. Assert the loser thread receives either `accepted=true, provider="duplicate"`
   (race lost after winner committed SENT) or `CONCURRENT_DISPATCH`
   rejection (race lost while winner is still PENDING).

If your test passes without the second latch, it isn't testing the race —
it's testing the sequential duplicate case, which the original `existsBy...`
guard already covered.

## Node.js / TypeScript equivalent

### Sequelize: don't use `findOrCreate` for race-safety

`Model.findOrCreate({ where, defaults })` is convenient but races: under concurrent calls, both can return the row they each created. The correct race-safe pattern is the raw `INSERT ... ON CONFLICT` plus read-back-winner reconciliation:

```typescript
async function reserveSlot(idempotencyKey: string, request: Request): Promise<Slot> {
  const id = uuid.v4();
  try {
    return await Slot.create({ id, idempotencyKey, ...request });
  } catch (e) {
    if (e instanceof UniqueConstraintError) {
      const winner = await Slot.findOne({ where: { idempotencyKey } });
      if (!winner) throw new Error('lost-race-but-winner-vanished');
      // Reconciliation: same caller? idempotent. Different? throw.
      if (winner.requesterId !== request.requesterId) {
        throw new ConflictError(`slot ${idempotencyKey} owned by another requester`);
      }
      return winner;
    }
    throw e;
  }
}
```

### Concurrency proof in Vitest

```typescript
import pLimit from 'p-limit';

it('exactly one concurrent reservation succeeds', async () => {
  const idempotencyKey = `race-${uuid.v4()}`;
  const N = 100;
  const limit = pLimit(N);   // run all concurrently
  const results = await Promise.all(
    Array.from({ length: N }).map(() =>
      limit(() => reserveSlot(idempotencyKey, fakeRequest()))
    )
  );
  const ids = new Set(results.map(r => r.id));
  expect(ids.size).toBe(1);
});
```

Run against a real Postgres via Testcontainers (or `dockerode`). H2/SQLite concurrency models don't generalize.

### Differences from Java

- No `saveAndFlush` distinction — Sequelize INSERTs immediately.
- `UniqueConstraintError` (named class) replaces `DataIntegrityViolationException`. Use `instanceof`.
- `p-limit` or `bluebird` give you the closest analogue to JUnit `CountDownLatch` in async TS.
