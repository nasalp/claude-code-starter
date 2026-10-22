---
name: webflux-test-isolation
description: Spring WebFlux + Reactor + BlockHound test-isolation pattern — emit reactive outcomes on dedicated schedulers (never the caller thread), assert scheduler choice in tests, isolate BlockHound install per JVM to avoid global pollution.
paths:
  - "**/*.java"
---

# WebFlux test isolation

## When to use

Use this skill when you're building, reviewing, or debugging Spring
WebFlux / Reactor code where:

- A tool / endpoint / scheduler emits an **outcome** (an audit event, a
  metric, a notification) that downstream code consumes on a different
  thread than the caller.
- `BlockHound` is wired in (or considered) to detect blocking calls in
  non-blocking threads.
- Tests claim "no blocking on event loop" but never assert which
  scheduler the emit landed on.

The canonical failure mode this skill prevents: an outcome emitted on
the caller's thread (e.g. an HTTP request thread, or the upstream
signal scheduler) interleaves with the next request's processing,
producing intermittent ordering bugs that don't reproduce under load
testing because the timing is wall-clock-dependent.

## The four-rule pattern

### Rule 1: Outcomes emit on a dedicated scheduler, NEVER on the caller thread

```java
// ❌ Forbidden — outcome emitted on whatever thread the upstream signal arrives on
upstream
    .flatMap(this::callTool)
    .doOnNext(result -> auditSink.append(result));  // runs on upstream's thread!

// ✅ Required — outcome emit explicitly offloaded
upstream
    .flatMap(this::callTool)
    .publishOn(Schedulers.boundedElastic())     // or a named tool-outcome scheduler
    .doOnNext(result -> auditSink.append(result));
```

The scheduler can be `boundedElastic()` for I/O-bound emit work, a
named scheduler for traceability, or — if the emit is genuinely
non-blocking — `parallel()`. The point is: **explicit choice**, not
"whatever thread the upstream happens to be on".

### Rule 2: Tests must assert the scheduler the outcome lands on

```java
@Test
void destructiveToolOutcomeRunsOffUpstreamSignalScheduler() {
    var auditThread = new AtomicReference<Thread>();
    var audit = (AuditSink) event -> auditThread.set(Thread.currentThread());

    var bridge = new McpToolBridge(audit);
    StepVerifier.create(bridge.invoke(destructiveTool, args))
        .expectNextCount(1)
        .verifyComplete();

    Thread thread = auditThread.get();
    assertThat(thread)
        .as("audit event must have been emitted at all")
        .isNotNull();
    assertThat(thread.getName())
        .as("audit event must NOT land on upstream signal thread")
        .doesNotStartWith("upstream-signal-");
    assertThat(thread.getName())
        .as("audit event must land on the named tool-outcome scheduler")
        .startsWith("tool-outcome-");
}
```

Without this assertion, the test is "the tool returns a result" — not
"the emit happens on the right thread." The former passes when the
latter is broken.

### Rule 3: BlockHound install is once-per-JVM and lives behind a profile flag

`BlockHound.install()` is process-wide and not idempotent across
configurations. If two test classes both `BlockHound.install()` in
`@BeforeAll`, the second one is a no-op, but if they install with
different ignore-lists, the FIRST one's list silently wins.

```java
// ✅ Centralized installer — runs once, gated on env var
@TestConfiguration
class BlockHoundTestConfig {
    @Bean
    static BlockHoundInitializer blockHoundInitializer() {
        return new BlockHoundInitializer();
    }
}

class BlockHoundInitializer {
    @Value("${app.block-detect.enabled:false}")
    private boolean enabled;

    @PostConstruct
    void install() {
        if (!enabled) {
            return;
        }
        BlockHound.builder()
            .allowBlockingCallsInside(...)  // documented one-off allows
            .install();
    }
}
```

Test classes that need BlockHound depend on the centralized config;
nothing else calls `BlockHound.install()` directly.

### Rule 4: BlockHound needs a proof-test, or it's effectively disabled

`BlockHound.install()` does nothing detectable until a blocking call
actually runs on a non-blocking thread. Ship a focused proof test:

```java
@Test
@EnabledIfEnvironmentVariable(named = "BLOCK_DETECT_ENABLED", matches = "true")
void blockHoundDetectsBlockingCallOnReactorParallelScheduler() {
    Mono<Void> blocking = Mono.fromRunnable(() -> {
        try { Thread.sleep(10); } catch (InterruptedException ignored) {}
    }).subscribeOn(Schedulers.parallel()).then();

    StepVerifier.create(blocking)
        .expectError(BlockingOperationError.class)
        .verify();
}

@Test
@EnabledIfEnvironmentVariable(named = "BLOCK_DETECT_ENABLED", matches = "true")
void blockHoundAllowsNonBlockingCallOnReactorParallelScheduler() {
    Mono<Integer> nonBlocking = Mono.fromCallable(() -> 42)
        .subscribeOn(Schedulers.parallel());
    StepVerifier.create(nonBlocking)
        .expectNext(42)
        .verifyComplete();
}
```

`StepVerifier` is the standard Reactor test API and is non-blocking;
`.block()` blocks the test thread and is generally discouraged in
reactive tests. `@EnabledIfEnvironmentVariable` (JUnit 5) replaces the
imperative `assumeTrue(...)` with a declarative gate that integrates
with the test runner.

Without both tests, you have no evidence BlockHound is actually
detecting what you think it's detecting.

## Why this skill exists

A tmux-agent run on a Java MCP server found two production-class bugs
in its reactive layer:

1. **Audit event on upstream-signal thread** — `McpToolBridge` emitted
   destructive-tool audit events on whatever thread the upstream
   provider's response arrived on. When two destructive tools were
   in-flight, their audit events could interleave with each other's
   completion, producing audit-log ordering bugs under load.
   Caught by writing `destructiveToolOutcomeRunsOffUpstreamSignalScheduler`
   asserting `auditThread.getName()` does not start with `upstream-signal-`.

2. **JWKS refresh rate-limit race** — concurrent distinct unknown-`kid`
   verifications could each trigger a refresh fetch, defeating the
   rate-limit cache. Caught by writing
   `concurrentDistinctUnknownKidsAreRefreshRateLimitedWhileJwksCacheIsFresh`
   asserting at most N refreshes occurred for M > N distinct unknown
   `kid` values within the rate-limit window.

Both bugs are the same shape: **the test that would catch them is a
test about which thread did what, not about what the function returned**.
Standard "the tool returns the right output" testing misses them
entirely.

This skill packages the four-rule pattern so the next reactive Java
build (or migration) catches the same class of bug structurally.

## Anti-patterns specifically banned

- `doOnNext(...)` / `doOnSuccess(...)` / `doOnError(...)` on an outcome
  emit, without a preceding `publishOn(...)` to choose the scheduler
  explicitly.
- Tests that assert the Mono completed without also asserting which
  thread the side-effect ran on.
- `BlockHound.install()` called directly inside test code outside the
  centralized initializer.
- A repo that wires `BlockHound` but ships no proof-test asserting
  blocking is actually detected.
- Marking BlockHound as "enabled" in CI when the proof-test is `@Disabled`
  or doesn't exist.

## Cross-references

- `.claude/rules/common/testing.md` — broader behavioral-testing
  discipline; this skill is the WebFlux specialization.
- `.claude/rules/adversarial-testing.md` — concurrency-attack
  category; the scheduler-isolation assertions implement that
  category for reactive code.
- `.claude/skills/agentic-engineering` — model selection for
  reactive correctness audits.
