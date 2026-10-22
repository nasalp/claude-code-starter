# @Transactional at Narrowest Boundary

Spring Data repos transactional by default. Don't reflexively annotate services/`@Component` with `@Transactional`. Reserve for narrowest layer where multiple persistence ops **genuinely** must commit atomically or share one read snapshot — almost always outbound persistence adapter, not application service.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## REQUIRED: Spring Data repos already transactional

Every `SimpleJpaRepository` (base for `JpaRepository`) method runs inside a transaction: writes via `@Transactional`, reads via `@Transactional(readOnly = true)`. Single repo call needs **no** wrapper. Caller annotation "to be safe" adds AOP-proxy boundary that obscures real transactional unit.

```java
// ❌ Pointless — the repository method is already transactional
@Transactional
class DefaultThingService implements ThingService {
    public Thing find(UUID id) { return repo.findById(id).map(...); } // ONE repo call
}

// ✅ No annotation needed — let the repository own its transaction
class DefaultThingService implements ThingService {
    public Thing find(UUID id) { return repo.findById(id).map(...); }
}
```

---

## REQUIRED: `@Transactional` last resort — name the invariant

Add `@Transactional` only when you can name the invariant it protects. Legitimate cases:

| Case | Why a transaction is genuinely required |
|---|---|
| Read-modify-write across **multiple** repository calls | Read and conditional write must see one consistent state (e.g. `INSERT … ON CONFLICT` then read-back then ownership check). |
| Multiple **non-idempotent** writes that must all-or-nothing | Crash between writes leaves corrupt, unrecoverable state. |
| Multiple reads with **real cross-read invariant** | Second read must see same snapshot as first (rare — usually invented). |

Can't state invariant in one sentence → don't need annotation.

---

## REQUIRED: Adapter composing calls owns tx, not service above

When transaction required, put it on layer issuing multiple persistence calls — outbound persistence adapter — not application service above.

```java
// ✅ The adapter composes INSERT + read-back + check → it owns the transaction
@Repository
class PostgresManagedSubdomainReservations implements ManagedSubdomainReservations {
    @Override @Transactional
    public ManagedSubdomainReservation reserve(ManagedSubdomainLabel label, UUID brandId) {
        jpa.tryReserve(label.value(), brandId, clock.instant());   // INSERT ... ON CONFLICT
        var row = jpa.findById(label.value()).orElseThrow(...);    // read-back
        if (!row.getBrandEntityId().equals(brandId)) throw new LabelOwnershipDeniedException(...);
        return row.toDto();
    }
}

// ✅ The application service orchestrates already-transactional, idempotent
//    port calls → NO service-level @Transactional
class DefaultManagedSubdomainService implements ManagedSubdomainService {
    public ManagedHostnameView approveGoLive(UUID brandId) {
        var label = deriveLabel(brandId, authorityLookup.findVerifiedForBrand(brandId).orElseThrow());
        reservations.reserve(label, brandId);   // idempotent (INSERT ... ON CONFLICT DO NOTHING)
        var live = reservations.goLive(label, brandId); // idempotent (COALESCE on went_live_at)
        return ManagedHostnameView.verified(label.hostname(suffix), live.phase());
    }
}
```

`reserve` and `goLive` each transactional at adapter **and idempotent**. Crash between them leaves recoverable `PREVIEW` row next call re-affirms — no corruption, nothing public served until `LIVE`. Service-level `@Transactional` protects no invariant; forbidden "to be safe" reflex.

---

## RECOMMENDED: Idempotency beats transactions for cross-aggregate sequences

Step B safely retried after step A committed → don't need A+B atomic. Make writes idempotent (`INSERT … ON CONFLICT DO NOTHING`, `UPDATE … SET x = COALESCE(x, :v)`, upserts keyed by natural id). Partial failure = no-op on retry. More robust than wide transaction — survives process death mid-tx, different node retry, at-least-once delivery.

---

## REQUIRED: `LazyInitializationException` ≠ auto-annotate

Static-analysis/review-bot: "lazy collection outside tx → add `@Transactional`." Verify type first. Domain **record** or DTO (not JPA `@Entity`) → collections already in-memory — no session, no lazy proxy, no `LazyInitializationException`.

```java
// Plain domain record — webProperties() is in-memory data, NOT a lazy JPA collection.
public record BrandEntity(UUID id, String brandName, List<WebProperty> webProperties, ...) {}
```

Annotating service because it calls `brand.webProperties()` on record = cargo-cult fix for non-problem.

---

## RECOMMENDED: Avoid `readOnly = true` on services unless needed

Each repo read already runs in own `readOnly` tx. Don't wrap several reads in service-level `@Transactional(readOnly = true)` unless you need to:
1. Disable Hibernate dirty-checking overhead on large queries.
2. Prevent connection pool thrashing under high load (single connection).
3. Ensure consistent DB snapshot across multiple queries (repeatable read).

Hot read path → prefer fewer queries over wider transaction.

---

## Anti-patterns (banned)

- `@Transactional` on service/`@Component` whose methods each make single repository call.
- `@Transactional` because linter/Gemini/SpotBugs flagged multiple DB ops without naming invariant.
- `@Transactional` to prevent `LazyInitializationException` on record/DTO with no lazy JPA collections.
- `@Transactional(readOnly = true)` on service purely to share connection across independent reads.
- Class-level `@Transactional` on large service where only one method needs it (annotate that method, or push to adapter).

## Allowed

- `@Transactional` on outbound persistence adapter method composing multiple repository calls into one atomic unit.
- Single application-service `@Transactional` when genuinely orchestrates multiple **non-idempotent** writes across **different** adapters that must all-or-nothing, and sequence can't be made idempotent.

## Quick Reference

| Rule | Priority |
|------|----------|
| Spring Data repos transactional by default — don't wrap single repo call | REQUIRED |
| `@Transactional` only when you can name the invariant it protects | REQUIRED |
| Put transaction on adapter composing calls, not service above | REQUIRED |
| Prefer idempotent + recoverable writes over wide transaction | RECOMMENDED |
| `LazyInitializationException` ≠ annotate if object is record/DTO | REQUIRED |
| No service-level `readOnly` tx just to share connection across reads | REQUIRED |

> Rationale (Cross-references): `docs/rule-rationale/java__transactional-boundaries.md`
