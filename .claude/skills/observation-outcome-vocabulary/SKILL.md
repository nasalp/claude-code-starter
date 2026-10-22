---
name: observation-outcome-vocabulary
description: Canonical Micrometer Observation outcome strings (success/rejected/failure/redirect/partial/other) with rejected_<detail> sub-prefix convention so dashboards can filter outcome=~"rejected.*".
origin: ECC
triggers: Micrometer Observation, outcome tag, low cardinality key, rejected, ObservationOutcomes, Grafana outcome filter, dashboard label, observability vocabulary
paths:
  - "**/*.java"
---
# Observation Outcome Vocabulary

## When to use

You are adding a new `Observation` (or `@Observed` method) that emits an
`outcome` low-cardinality key, and you need to pick the value. Or you are
reviewing a PR that introduces a string like `"validation_error"`,
`"duplicate"`, `"timeout"`, or `"ok"` as an outcome — none of which are
canonical, all of which fragment the dashboards.

This skill applies to any Spring Boot service that ships
`micrometer-observation` and that already has a `shared/ObservationOutcomes`
constants holder (or where you are about to add one).

## When NOT to use

- The metric is **not** an `Observation` — counters/gauges/timers with
  custom labels follow their own naming policy (see Prometheus conventions).
- The key in question is high-cardinality (e.g. tenant id, user id, error
  code with many values). `outcome` is reserved for the small fixed set
  below.
- You're working in a service where dashboards already use a different
  convention; align there first instead of forking.

## The pattern

### The fixed set

| Value      | Meaning                                                            |
|------------|--------------------------------------------------------------------|
| `success`  | Happy path. HTTP 2xx, accepted job, published artifact.            |
| `rejected` | Client-side rejection. HTTP 4xx, validation failure, 409 conflict. |
| `failure`  | Server-side failure. HTTP 5xx, unhandled `RuntimeException`.       |
| `redirect` | Narrowing of `success`. HTTP 3xx.                                  |
| `partial`  | Narrowing of `success`. Some sub-units succeeded, some did not.    |
| `other`    | 1xx or unexpected status codes. The escape hatch.                  |

These six are the **only** valid `outcome` values. The constants holder:

```java
package com.example.app.shared;

/**
 * Canonical low-cardinality outcomes for Micrometer {@code Observation}
 * tagging. Adding a new bucket requires a class-javadoc justification and
 * a corresponding dashboard update. Do not invent new strings at call sites.
 */
public final class ObservationOutcomes {
    public static final String SUCCESS  = "success";
    public static final String REJECTED = "rejected";
    public static final String FAILURE  = "failure";
    public static final String REDIRECT = "redirect";
    public static final String PARTIAL  = "partial";
    public static final String OTHER    = "other";

    /** Sub-rejection prefix. Use as: REJECTED_PREFIX + "validation". */
    public static final String REJECTED_PREFIX = "rejected_";

    private ObservationOutcomes() {}
}
```

### The `rejected_<detail>` convention

Sub-rejection reasons MUST be prefixed `rejected_`:

```java
// validation failure
observation.lowCardinalityKeyValue("outcome", "rejected_validation");

// idempotency duplicate
observation.lowCardinalityKeyValue("outcome", "rejected_duplicate");

// rate limit exceeded
observation.lowCardinalityKeyValue("outcome", "rejected_rate_limit");

// stale token
observation.lowCardinalityKeyValue("outcome", "rejected_token_expired");
```

Why the prefix matters:

- Grafana queries that want **all** rejections regardless of detail use
  `outcome=~"rejected.*"`. This works only if every rejection bucket
  starts with `rejected_`.
- An exact-match `outcome="rejected"` filter does **not** match
  sub-buckets. If your dashboard uses exact match, it will silently drop
  every detailed rejection.
- The unprefixed `"rejected"` is still valid — it's the bucket for "no
  detail provided" rejections. Detail-bearing rejections are siblings,
  not narrowings.

### Call site

```java
@Service
class PublishService {

    private final ObservationRegistry registry;

    PublishingResult publish(PublishRequest request) {
        return Observation.createNotStarted("publishing.publish", registry)
            .lowCardinalityKeyValue("artifact_family",
                request.family().name())
            .observe(() -> {
                try {
                    var result = doPublish(request);
                    Observation.Scope.observation()
                        .lowCardinalityKeyValue("outcome",
                            ObservationOutcomes.SUCCESS);
                    return result;
                } catch (ValidationException e) {
                    Observation.Scope.observation()
                        .lowCardinalityKeyValue("outcome",
                            ObservationOutcomes.REJECTED_PREFIX + "validation");
                    throw e;
                } catch (DuplicateArtifactException e) {
                    Observation.Scope.observation()
                        .lowCardinalityKeyValue("outcome",
                            ObservationOutcomes.REJECTED_PREFIX + "duplicate");
                    throw e;
                }
            });
    }
}
```

### Adding a new bucket

If you genuinely need a new top-level bucket (not a `rejected_<x>` sub-bucket),
the rule is: **add it to `ObservationOutcomes` with a class-javadoc
justification first**, then ship the call site. Do not ship a string
literal at the call site and "promote it later". Promotion never happens;
the string fragments the dashboard.

## Common gotchas / variants

- **`"ok"` / `"failed"` / `"error"` are NOT canonical.** They look fine
  in code review but they fragment metric labels across services. The
  word is `success` / `rejected` / `failure`.
- **Don't put HTTP status numbers in `outcome`.** Use a separate
  `http.status_class` low-cardinality key with values `2xx`/`3xx`/`4xx`/`5xx`
  if you need the status grouping; outcome is the semantic verdict.
- **Don't put the exception class name in `outcome`.** That's high
  cardinality once new exception types are added. Use `rejected_<reason>`
  with a short fixed-vocabulary reason.
- **`partial` is not "some failed, some succeeded".** It is "the
  caller's request was satisfied with caveats" — e.g. a batch publish
  where 9 of 10 sub-artifacts published. If half the units actually
  failed, that's `failure`.
- **The Grafana panel must use a regex.** A pre-existing panel with
  `outcome="rejected"` literal will silently exclude every
  `rejected_<detail>`. Update the panel to `outcome=~"rejected.*"` when
  you add the prefix.

## Verification

A unit test pinning the rule:

```java
@Test
void no_call_site_uses_a_non_canonical_outcome() {
    JavaClasses classes = new ClassFileImporter()
        .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
        .importPackages("com.example.app");

    // Allowed literals at call sites.
    Set<String> allowed = Set.of(
        "success", "rejected", "failure", "redirect", "partial", "other");

    // Find every string literal passed as the value to
    // lowCardinalityKeyValue("outcome", X) and assert each is either
    // in `allowed` or starts with "rejected_".
    // ... (use ArchUnit's MethodCall or a simple grep CI check)
}
```

A simple CI grep is also acceptable as an inexpensive backstop:

```bash
grep -rn 'lowCardinalityKeyValue("outcome"' src/main \
  | grep -vE '"(success|rejected|failure|redirect|partial|other)"' \
  | grep -vE '"rejected_[a-z_]+"'
```

If that pipeline emits anything, the build fails.

## Node.js / TypeScript equivalent

Same outcome vocabulary applies in Node observability stacks.

### prom-client (Prometheus)

```typescript
import { Counter, Histogram } from 'prom-client';

const httpOutcomes = new Counter({
  name: 'http_request_outcomes_total',
  help: 'Outcomes of HTTP requests by canonical outcome',
  labelNames: ['route', 'outcome'],
});

const OUTCOMES = ['success', 'rejected', 'failure', 'redirect', 'partial', 'other'] as const;
type Outcome = typeof OUTCOMES[number];

httpOutcomes.inc({ route: '/api/orders', outcome: 'rejected_validation' });
httpOutcomes.inc({ route: '/api/orders', outcome: 'rejected_rate_limit' });
```

PromQL queries are identical:

```promql
sum by (route) (rate(http_request_outcomes_total{outcome=~"rejected.*"}[5m]))
```

### TypeScript type-level guard

```typescript
const OUTCOMES = ['success', 'rejected', 'failure', 'redirect', 'partial', 'other'] as const;
type CanonicalOutcome = typeof OUTCOMES[number];
type OutcomeWithSubPrefix = CanonicalOutcome | `rejected_${string}`;

function record(outcome: OutcomeWithSubPrefix) { /* ... */ }
// record('success_maybe')           // ❌ compile error
// record('rejected_validation')     // ✓
```

### OpenTelemetry-Node

Same vocabulary; record via `Counter.add()` or `Histogram.record()` with attributes `{ outcome: 'rejected_validation' }`. Avoid OTel "exemplars" or sub-namespaced attribute names that re-introduce vocabulary drift.

### Differences from Java

- prom-client labels are flat strings; no `Observation.createNotStarted()` API.
- TypeScript template-literal types catch typos at compile time — Java has no equivalent.

## References

- `~/.claude/rules/observability.md` — the global Micrometer rule that
  this skill specializes.
