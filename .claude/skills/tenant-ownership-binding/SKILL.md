---
name: tenant-ownership-binding
description: Multi-tenant resource ownership via (resource, owner_id) UNIQUE table plus INSERT ON CONFLICT DO NOTHING. Hostname/email normalization at the port boundary. Denial mapped to RFC 7807 ProblemDetail.
origin: ECC
triggers: tenant isolation, multi-tenant, ownership binding, IDOR, cross-tenant leak, hostname ownership, subdomain provisioning, INSERT ON CONFLICT, RFC 7807, ProblemDetail, HostnameOwnershipDeniedException, first-write-wins
paths:
  - "**/*.java"
---
# Tenant Ownership Binding

A multi-tenant API that accepts `(merchantId, resource)` from the request and operates on the resource without checking that the merchant owns it has an Insecure Direct Object Reference (IDOR) that scales as badly as it sounds: tenant A can read, modify, or provision against tenant B's resources by guessing the resource id.

The fix is **first-write-wins ownership binding** in a database table with a UNIQUE constraint on the resource id, plus normalization of the resource id at the port boundary, plus a domain exception mapped to a structured 4xx response.

The worked example below is a subdomain-onboarding feature, where the resource is a hostname and the threat is "Tenant A provisions Cloudflare-managed traffic for `facts.competitor.com` after Tenant B claimed it".

## When to use

- Any feature where a tenant claims a globally-unique external resource: hostname, custom domain, vanity slug, GitHub org name, Stripe Connect account, S3 bucket name, AWS Route 53 record, magic-link email, license key, integration nickname.
- Any operation that takes `(tenantId, resourceId)` from the request and trusts the tenant's claim.
- Any "first user to register a workspace gets it" flow.

## When NOT to use

- Resources whose ids are already namespaced by tenant (`/tenants/{tid}/orders/{oid}`). The path enforces ownership; the binding table would be redundant.
- Strictly-public resources (read-only directory). No tenant; no binding.
- Resources with explicit transfer semantics (workspaces, organizations). Use a richer ownership model with audit trail.

## The pattern

### 1. Schema — UNIQUE on the resource id

```sql
-- V26__create_subdomain_ownership.sql
CREATE TABLE subdomain_ownership (
    hostname    VARCHAR(253) PRIMARY KEY CHECK (hostname = lower(hostname)),
    merchant_id UUID                     NOT NULL,
    claimed_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_subdomain_ownership_merchant ON subdomain_ownership (merchant_id);
```

The `hostname` column is the PRIMARY KEY (UNIQUE + NOT NULL) — that is the load-bearing constraint. The `CHECK (hostname = lower(hostname))` is a defense-in-depth: even if the application forgets to normalize, the DB rejects upper-case writes that would let a tenant bypass the binding by claiming a case-variant.

### 2. Port — public interface, normalization in the contract

```java
public interface SubdomainOwnerships {

    /**
     * First-write-wins, idempotent for the same merchant.
     * @throws HostnameOwnershipDeniedException when the hostname is already
     *         owned by a different merchant.
     */
    void claim(String hostname, UUID merchantId);

    Optional<UUID> findOwnerOf(String hostname);

    /**
     * Canonicalizes a hostname for storage: trim + lower-case per RFC 1034.
     * Implementations call this before every read or write; consumers may
     * also call it to compare hostnames consistently.
     */
    static String normalize(String hostname) {
        return hostname.trim().toLowerCase(Locale.ROOT);
    }
}
```

`normalize` is `static` on the port interface so every adapter and every caller uses **exactly one** canonicalization. The adapter doesn't get to define its own; the consumer doesn't get to bypass.

### 3. Adapter — INSERT ... ON CONFLICT DO NOTHING

```java
@Repository
class PostgresSubdomainOwnerships implements SubdomainOwnerships {

    private final SubdomainOwnershipJpaRepository jpaRepository;
    private final Clock clock;

    @Override
    @Transactional
    public void claim(String hostname, UUID merchantId) {
        String normalized = SubdomainOwnerships.normalize(hostname);
        int rowsInserted = this.jpaRepository.tryInsert(normalized, merchantId, this.clock.instant());
        if (rowsInserted == 1) {
            return;                                       // first claim wins
        }
        UUID owner = this.jpaRepository.findById(normalized)
            .map(SubdomainOwnershipEntity::getMerchantId)
            .orElseThrow(() -> new IllegalStateException(
                "subdomain_ownership row for '" + normalized + "' vanished after a no-op insert"));
        if (!owner.equals(merchantId)) {
            throw new HostnameOwnershipDeniedException(merchantId, owner, normalized);
        }
        // Same merchant — idempotent no-op, return silently.
    }
}

interface SubdomainOwnershipJpaRepository
        extends JpaRepository<SubdomainOwnershipEntity, String> {

    @Modifying
    @Query(value = """
            INSERT INTO subdomain_ownership (hostname, merchant_id, claimed_at)
            VALUES (:hostname, :merchantId, :claimedAt)
            ON CONFLICT (hostname) DO NOTHING
            """, nativeQuery = true)
    int tryInsert(@Param("hostname") String hostname,
                  @Param("merchantId") UUID merchantId,
                  @Param("claimedAt") Instant claimedAt);
}
```

`INSERT ... ON CONFLICT DO NOTHING` is **atomic** against the primary key. Two callers racing the first claim cannot both insert. The losing caller observes `rowsInserted == 0`, reads the winning row, and decides:

- Same merchant → idempotent no-op (return silently). The same merchant retrying its own claim must succeed.
- Different merchant → throw `HostnameOwnershipDeniedException`.

This avoids the read-then-write race that a naive `SELECT ... INSERT IF ABSENT` pattern exposes.

### 4. Service — claim at the top of every scoped operation

```java
class DefaultSubdomainOnboardingService implements SubdomainOnboardingService {

    public ProvisionOutcome provision(UUID merchantId, String hostname) {
        ownerships.claim(hostname, merchantId);            // gate
        // ... derive CNAME, call DnsVerifier, call HostnameProvisioner ...
    }

    public ApprovalOutcome approve(UUID merchantId, String hostname) {
        ownerships.claim(hostname, merchantId);            // gate
        // ...
    }
    // ... and getStatus, getInstructions
}
```

Every hostname-scoped operation claims first. `claim` is idempotent for the same merchant, so a re-call is cheap. Pure derivations (e.g. "show me three candidate hostnames for this brand") don't claim — ownership is recorded the first time any of the four hostname-scoped operations runs.

### 5. Exception → RFC 7807 ProblemDetail

```java
public class HostnameOwnershipDeniedException extends RuntimeException {
    private final UUID requestingMerchantId, owningMerchantId;
    private final String hostname;

    public HostnameOwnershipDeniedException(UUID requestingMerchantId,
                                             UUID owningMerchantId,
                                             String hostname) {
        super("hostname '" + hostname + "' is owned by another merchant");
        // ...
    }
}

@RestControllerAdvice
@Order(Ordered.HIGHEST_PRECEDENCE)
class SubdomainExceptionHandler {

    @ExceptionHandler(HostnameOwnershipDeniedException.class)
    public ProblemDetail handleOwnershipDenied(HostnameOwnershipDeniedException ex,
                                                HttpServletRequest request) {
        return ProblemDetails.create(HttpStatus.FORBIDDEN, "FORBIDDEN",
            "Hostname is owned by another merchant", request);
    }
}
```

Choices:
- **403** (Forbidden) — the requester is authenticated, they just don't own this resource. Not 401 (which would mean re-auth fixes it).
- **Generic message body** — "Hostname is owned by another merchant", not "Hostname is owned by merchant `8a2c...`". The owning tenant's id is itself sensitive.
- **RFC 7807 ProblemDetail** — structured `type`, `title`, `status`, `detail` fields. Clients can branch on `type=FORBIDDEN`.

## Common gotchas / variants

- **Normalizing on write but not on read.** `findOwnerOf("FACTS.example.com")` must hit the same row as `claim("facts.example.com", ...)`. Normalize **inside** the adapter, on every code path.
- **Email-as-resource.** Same pattern, normalize with `email.trim().toLowerCase(Locale.ROOT)` and consider Unicode NFC. Beware Gmail's `+`/`.` aliasing — that's a product decision, not a security one. Decide upfront.
- **Auth-context-vs-path mismatch.** This pattern fixes the IDOR even if the path-bound `merchantId` doesn't match the authenticated principal — but you should ALSO close that gap separately (`@PreAuthorize("#merchantId == principal.merchantId")` or equivalent). Defense in depth.
- **Per-resource read projections leak the owning merchant id.** Don't include the owning merchant id in error responses, in metric labels (label cardinality + leak), or in client-visible logs.
- **Migration of existing data.** If the table already has rows with `hostname` in mixed case, lower-case in a backfill migration **before** adding the `CHECK` constraint, or the migration fails on legacy rows.
- **No in-memory production stub.** The production wiring is exclusively the Postgres adapter. An `InMemorySubdomainOwnerships` fake exists in `src/test/java/` for unit tests; it must not be on the production classpath.

## Verification

A concurrent-claim test on a real Postgres pins the contract:

```java
@Test
void exactly_one_concurrent_claim_for_distinct_merchants_succeeds() throws Exception {
    String hostname = "race.example.com";
    int contenders = 50;
    ExecutorService pool = Executors.newFixedThreadPool(contenders);
    CountDownLatch start = new CountDownLatch(1);

    AtomicInteger successes = new AtomicInteger();
    AtomicInteger denials = new AtomicInteger();

    List<Future<?>> futures = new ArrayList<>();
    for (int i = 0; i < contenders; i++) {
        UUID merchantId = UUID.randomUUID();              // distinct each
        futures.add(pool.submit(() -> {
            start.await();
            try {
                ownerships.claim(hostname, merchantId);
                successes.incrementAndGet();
            } catch (HostnameOwnershipDeniedException ex) {
                denials.incrementAndGet();
            }
            return null;
        }));
    }
    start.countDown();
    for (Future<?> f : futures) f.get(30, SECONDS);

    assertThat(successes.get()).isEqualTo(1);
    assertThat(denials.get()).isEqualTo(contenders - 1);
}
```

The DB UNIQUE constraint is the proof. Java synchronization is not required and would not help across replicas.

A second test pins idempotency:

```java
@Test
void same_merchant_claiming_twice_is_a_silent_noop() {
    UUID merchantId = UUID.randomUUID();
    ownerships.claim("idempotent.example.com", merchantId);
    assertThatCode(() -> ownerships.claim("idempotent.example.com", merchantId))
        .doesNotThrowAnyException();
}
```

## Node.js / TypeScript equivalent

The same `(resource, owner_id)` UNIQUE table + `INSERT ... ON CONFLICT DO NOTHING` works in any Node Express + Postgres stack. Sequelize gives you the type-safe ORM path; raw `pg` gives you the explicit-SQL path.

### Sequelize: port + adapter

```typescript
// port (interface)
export interface SubdomainOwnerships {
  claim(hostname: string, merchantId: string): Promise<void>;
  findOwnerOf(hostname: string): Promise<string | null>;
}

export const normalize = (h: string) => h.trim().toLowerCase();

// adapter
export class PostgresSubdomainOwnerships implements SubdomainOwnerships {
  constructor(private sequelize: Sequelize) {}

  async claim(hostname: string, merchantId: string): Promise<void> {
    const normalized = normalize(hostname);
    const [, [{ rowsInserted }]] = await this.sequelize.query<{ rowsInserted: number }>(
      `
      WITH inserted AS (
        INSERT INTO subdomain_ownership (hostname, merchant_id, claimed_at)
        VALUES (:hostname, :merchantId, NOW())
        ON CONFLICT (hostname) DO NOTHING
        RETURNING 1
      )
      SELECT (SELECT count(*) FROM inserted)::int AS "rowsInserted"
      `,
      {
        replacements: { hostname: normalized, merchantId },
        type: QueryTypes.SELECT,
      }
    ) as any;
    if (rowsInserted === 1) return;

    const owner = await this.findOwnerOf(normalized);
    if (!owner) throw new Error(`row vanished after no-op insert: ${normalized}`);
    if (owner !== merchantId) {
      throw new HostnameOwnershipDeniedError(merchantId, owner, normalized);
    }
    // Same merchant — idempotent no-op.
  }

  async findOwnerOf(hostname: string): Promise<string | null> {
    const row = await SubdomainOwnership.findByPk(normalize(hostname));
    return row?.merchantId ?? null;
  }
}
```

### Mongo equivalent (`findOneAndUpdate` with upsert)

If your tenant store is MongoDB, use a different primitive:

```typescript
const result = await collection.findOneAndUpdate(
  { hostname: normalize(hostname) },
  { $setOnInsert: { merchantId, claimedAt: new Date() } },
  { upsert: true, returnDocument: 'after' }
);
if (result.value!.merchantId !== merchantId) {
  throw new HostnameOwnershipDeniedError(merchantId, result.value!.merchantId, hostname);
}
```

### Express RFC 7807 problem detail

```typescript
class HostnameOwnershipDeniedError extends Error {
  constructor(public requestingMerchant: string, public owningMerchant: string, public hostname: string) {
    super(`hostname '${hostname}' is owned by another merchant`);
  }
}

app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  if (err instanceof HostnameOwnershipDeniedError) {
    res.status(403).json({
      type: 'about:blank',
      title: 'FORBIDDEN',
      status: 403,
      detail: 'Hostname is owned by another merchant',
      instance: req.originalUrl,
    });
    return;
  }
  next(err);
});
```

### Differences from Java

- No `@Repository` boundary; the adapter is a class injected via constructor.
- Sequelize doesn't have `@Modifying`; use `sequelize.query()` for ON CONFLICT.
- RFC 7807 in Node is hand-rolled (no `ProblemDetails.create` helper); `http-problem-details` npm package exists if you want one.
- Mongo replaces `INSERT ... ON CONFLICT` with `findOneAndUpdate` + `upsert: true`; same semantics, different SQL/NoSQL primitive.

## References

- Implementation:
- AC pinned: AC-DNS-7 (denial), AC-DNS-8 (idempotent), AC-DNS-9 (concurrency), AC-DNS-10 (case-normalize)
- RFC 7807 — Problem Details for HTTP APIs
- RFC 1034 — DNS hostnames are case-insensitive
