---
name: metric-cache-warmup-runner
description: Pre-populate Spring @Cacheable caches on application startup using @EventListener(ApplicationReadyEvent) + @Async with a per-metric safeCall wrapper that swallows individual failures
origin: ECC
triggers: cache warmup, ApplicationReadyEvent, @Cacheable warmup, first-request slow, dashboard cold start, metric cache, CacheWarmupRunner, @Async cache prefill
paths:
  - "**/*.java"
---
# Metric Cache Warmup Runner

Pattern for executive/metric dashboards where the first request after deploy is unacceptably slow because every `@Cacheable` repository method is cold. A `@Component` listens for `ApplicationReadyEvent` and `@Async`-fires every cached service method once. Failures of individual metrics are swallowed (they'd block warmup and produce noisy stack traces), but logged with a newline-stripped message so the line stays single-line in CloudWatch / structured log search.

## When to use

- Your service exposes a dashboard/report where one HTTP request triggers 20–60 expensive queries (each `@Cacheable`, TTL 5–15 min).
- The 99th-percentile cold first-request latency is unacceptable (e.g. >30 s) but the warm latency is fine (sub-second).
- Cache misses can be re-driven from inside the JVM at boot — i.e. the queries don't need a request-scoped principal, tenant, or HTTP context.
- You're behind a load balancer with a readiness probe; warmup happens after `ApplicationReadyEvent` (the probe will start succeeding, but the first user-facing request hits warm caches a few seconds later).

## When NOT to use

- Cached values are per-user/per-tenant. Warming "all of them" is unbounded — use lazy-on-first-touch with a per-tenant lock instead.
- The expensive queries write side effects (audit log, metric increment, downstream API call). Warmup will multiply those side effects.
- Boot needs to be fast (serverless, scale-to-zero). `@Async` makes the warmup non-blocking, but the queries still consume DB connections — a cold replica can't tolerate 30+ parallel queries on boot.
- The cache is L1-only (no shared Redis/Hazelcast). On a 3-node cluster, every node warms independently, multiplying replica load by 3×.

## The pattern

### Component

```java
@Component
class CacheWarmupRunner {

    private static final Logger log = LoggerFactory.getLogger(CacheWarmupRunner.class);

    private final FinanceService financeService;
    private final SalesService salesService;
    private final CustomerSuccessService customerSuccessService;

    CacheWarmupRunner(FinanceService financeService, SalesService salesService,
            CustomerSuccessService customerSuccessService) {
        this.financeService = financeService;
        this.salesService = salesService;
        this.customerSuccessService = customerSuccessService;
    }

    @Async
    @EventListener(ApplicationReadyEvent.class)
    void warmCaches() {
        log.info("Cache warmup starting — loading all department metrics");
        warmFinance();
        warmSales();
        warmCustomerSuccess();
        log.info("Cache warmup complete");
    }

    private void warmFinance() {
        log.info("Warming finance caches (F1-F4 + trials, MRR, CLV)");
        safeCall("F1", () -> this.financeService.getConversionRate());
        safeCall("F2", () -> this.financeService.getRevenueByPlanTier());
        safeCall("F3", () -> this.financeService.getChurnRateByPeriod());
        safeCall("F4", () -> this.financeService.getCustomerLifetime());
        // ... ~30 more metrics
    }

    @SuppressWarnings("PMD.AvoidCatchingGenericException")
    private void safeCall(String metric, Runnable call) {
        try {
            call.run();
        }
        catch (Exception ex) {
            String msg = (ex.getMessage() != null)
                ? ex.getMessage().replaceAll("[\\r\\n]", " ")
                : "unknown";
            log.warn("Cache warmup failed for {}: {}", metric, msg);
        }
    }
}
```

### Why these specific choices

- **`@EventListener(ApplicationReadyEvent.class)`** fires AFTER `CommandLineRunner` and AFTER the embedded server is bound to the port. The actuator readiness probe is already up, so K8s/ALB starts routing traffic — but `@Async` means the first user request still beats the warmup if it lands in the first ~100 ms. Tradeoff: bind-then-warm > warm-then-bind, because health checks have a strict timeout.
- **`@Async`** decouples warmup duration from boot time. The thread pool is the framework default unless `@EnableAsync` configures one — for a 30-method warmup that runs every 10–15 minutes (TTL refresh) you want a dedicated bounded executor (`taskExecutor` with `corePoolSize=2`, `queueCapacity=64`).
- **`safeCall(name, Runnable)`** is the lynchpin. A single bad query (DB schema drift, replica lag, NPE in a row mapper) would otherwise abort the whole warmup. The catch block is intentionally `Exception` (PMD-suppressed). The `replaceAll("[\\r\\n]", " ")` on the message keeps the warning to one log line — critical for log aggregators that key on line breaks. The metric name (`"F1"`, `"M3a"`) appears at the front of every line so a dashboard can count failures-per-metric.
- **One `Runnable` per cached method**, not a stream over a `List<Runnable>`. The verbose form gives you a cheap way to comment-out a metric during incident response without touching collection mechanics, and it lets you reorder by criticality.

### Cache-key convention pairing

Services annotate every cached method with `@Cacheable(cacheNames = "metrics", key = "'finance:f1'")`, etc. The warmup names (`"F1"`) intentionally match the second half of the key so a `grep "Cache warmup failed for F1"` and a `cache.miss.metrics.finance:f1` Micrometer counter line up.

## Common gotchas / variants

- **Forgetting `@EnableAsync`.** Without it, `@Async` is a no-op and warmup runs synchronously on the boot thread, blocking the readiness probe. Symptom: K8s rolling deploy times out after 30s.
- **Catching `Throwable` instead of `Exception`.** Swallowing `OutOfMemoryError` or `StackOverflowError` masks real cluster problems. Stick to `Exception`.
- **Logging `ex` (the whole exception).** Stack traces during warmup are noise — the actual fix happens when a user hits the metric and gets a 500. Log the message only; let the request handler log the stack.
- **Newlines in the log line.** Hibernate's `ConstraintViolationException.getMessage()` is multi-line. The CloudWatch JSON appender treats `\n` as a record separator and you lose half the message. The `replaceAll("[\\r\\n]", " ")` is mandatory.
- **Warmup running on every node in a multi-node cluster.** For shared caches (Redis), wrap with `@SchedulerLock` (ShedLock) so only one node warms. For local caches (Caffeine), each node warms its own — accept the 3× DB load.
- **Order matters when methods depend on each other.** If `getMrrByPlanMonthly()` internally calls `getActiveTrials()` and both are cached, warm the dependency first to avoid a cache miss inside a "warm" call.
- **Variant: scheduled re-warm.** Add `@Scheduled(fixedDelay = 5 * 60 * 1000)` on a similar method to re-warm BEFORE TTL expiry. This eliminates the first-request-after-TTL penalty for active metrics.
- **Don't make warmup transactional.** A `@Transactional` warmup holds one connection for its entire duration — 30+ seconds — starving the pool. Service methods open their own short transactions.

## Verification

- Boot the app, observe `Cache warmup starting`, then `Cache warmup complete` in logs ~5–15 s later.
- The first dashboard request returns in <500 ms (vs. 20+ s without warmup).
- Inject a deliberate failure (rename a column the F1 query depends on) and verify only F1 warns, F2–F4 still warm.
- Confirm `@Async` is in effect: time between "Started Application" and "Cache warmup complete" should be ~hundreds of ms for the former, seconds for the latter.
- `actuator/health` returns UP within boot timeout (warmup does not block readiness).

## References

- `.claude/rules/project.md` — `{dept}:{metric-id}` cache-key convention and 5/15-minute TTLs.
- Spring Boot reference: `org.springframework.boot.context.event.ApplicationReadyEvent`.
- ShedLock for cluster-aware variant: `net.javacrumbs.shedlock`.
