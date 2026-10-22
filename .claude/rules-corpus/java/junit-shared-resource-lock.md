# `@ResourceLock` for shared singletons under parallel class execution

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

When a JUnit 5 test suite enables parallel class execution
(`junit.jupiter.execution.parallel.mode.classes.default=concurrent`)
**AND** multiple test classes share a process-wide singleton resource —
typically a Testcontainers container, an embedded broker, a temp
directory, or any `static final` field initialised once per JVM — every
class that touches that resource MUST carry
`@ResourceLock("<resource-name>")`. JUnit then serialises **only** those
classes against each other; everything else stays fully parallel.

FORBIDDEN to "fix" the resulting races by globally switching
`mode.classes.default=same_thread`. That destroys parallelism for
thousands of cheap unit tests with no shared state, doubling wall-clock
for no good reason. The right fix is the targeted lock.

The races concurrent class execution + a shared singleton produces (each
looks like a fresh bug per CI run): Class A inserts a row keyed by
`accounts.primary_email = "x@y"` while Class B's `@BeforeEach` truncates the
table; Class A commits on connection X while Class B's `findAll` on
connection Y misses it due to Postgres MVCC visibility lag; `ON DELETE
CASCADE` from a parent table wipes a sibling class's child rows mid-test.
Per-test Awaitility, per-test UUIDs, and removing `@BeforeEach
deleteAll()` treat symptoms. Root cause: concurrent class execution
against a singleton with no session boundary between classes. `@ResourceLock`
addresses the root.

## What is required

### 1. Choose a stable lock name per shared resource

Name the resource, not the test:

```java
@ResourceLock("SharedPostgres")
@ResourceLock("SharedKafka")
@ResourceLock("SharedTempDir")
@ResourceLock("nurture-prospects")  // a logical sub-resource of the DB
```

`@ResourceLock` is **repeatable** (Java 8+ annotation repetition) —
a class participating in a sub-resource lock AND the broader singleton
lock stacks them:

```java
@ResourceLock("nurture-prospects")
@ResourceLock("SharedPostgres")
class NurtureWhatsAppDeliveryIT { ... }
```

### 2. Apply to every class that touches the resource

Every `@SpringBootTest` (or equivalent) class whose context wires into
`SharedPostgres.INSTANCE`, `SharedKafka.INSTANCE`, etc., carries the lock.
Abstract base classes with no `class` declaration (e.g. `@interface`
meta-annotations, `@TestConfiguration` records) don't need it directly;
the concrete classes that USE them do.

Mechanical roll-out for a large suite:

```bash
# Find every test that touches the singleton.
grep -rl 'SharedPostgres\.INSTANCE' src/test/java | while read f; do
  # Add the import + annotation if missing.
  ...
done
```

A first roll-out can touch dozens of classes in one PR.
Land it as one focused commit; reviewers sanity-check by grepping for the
singleton's symbol and the annotation in the same files.

### 3. Keep classes-concurrent ON

Parallel class execution stays enabled. Canonical
`junit-platform.properties` shape after this rule:

```properties
junit.jupiter.execution.parallel.enabled=true
# Methods within a class run sequentially (safe for shared Spring context).
junit.jupiter.execution.parallel.mode.default=same_thread
# Classes run in parallel. Classes that share a JVM-wide singleton carry
# @ResourceLock("<name>") so they serialise against each other; unit tests
# and other non-singleton classes remain fully parallel.
junit.jupiter.execution.parallel.mode.classes.default=concurrent
junit.jupiter.execution.parallel.config.strategy=dynamic
junit.jupiter.execution.parallel.config.dynamic.factor=1
```

`forkCount=1C reuseForks=true` (Surefire) is the matching JVM-side shape:
one fork per core, each fork shares its own JVM with multiple test classes.

**Resource-contention warning.** Combining `forkCount=1C` (Surefire-level
JVM forks per core) with `parallel.config.dynamic.factor=1` (JUnit
engine-level threads per fork at full core count) on an N-core host yields
N × N = N² concurrent test threads. On CI runners this saturates CPU and
produces flakes that look like timing bugs but are actually
thread-starvation. Pick ONE parallelism layer at full intensity:

- Multiple modules / heterogeneous test types (slow ITs + fast units) →
  `forkCount=1C` + `parallel.config.dynamic.factor=0.5` (half as many
  threads per fork — N × N/2 = N²/2 total).
- Single module / mostly-uniform test runtimes → `forkCount=1` (single
  fork) + `parallel.config.dynamic.factor=1` (full engine parallelism).
- Hostile CI environment (shared runner, GitHub Actions) → `forkCount=2`
  + `parallel.config.dynamic.factor=0.5` regardless of core count — pin a
  predictable upper bound.

The numbers assume CPU-bound tests; IO-bound tests (Testcontainers, HTTP,
DB) can tolerate higher concurrency per fork, but the N² ceiling still
applies if all tests block on the same DB pool.

## What is forbidden

| Anti-pattern | Why |
|---|---|
| `mode.classes.default=same_thread` to "fix the flakes" | Serialises every class, including unit tests with no shared state; ~2× wall-clock for no benefit |
| Per-test `Awaitility` wraps as the sole defence against cross-class races | Symptom whack-a-mole; the next test that touches the same singleton flakes anyway |
| `@BeforeEach deleteAll()` on a shared singleton DB | Truncates rows a sibling parallel class just inserted (banned by `~/.claude/rules/common/testing.md`) |
| `@DirtiesContext` sprinkled to "force isolation" | Rebuilds the Spring context per test — minutes of extra wall-clock for what `@ResourceLock` resolves in nanoseconds |
| Disabling parallel execution entirely (`parallel.enabled=false`) | Same blunt-tool problem at the next level up |
| One lock name per class | The lock name names the **resource**, not the class — different names don't serialise |

## What is allowed

- Multiple `@ResourceLock` annotations on one class (the annotation is
  repeatable).
- Method-level `@ResourceLock` for a narrow sub-section of a class that
  holds the lock for a longer scope at the class level.
- `@ResourceLock(value = "...", mode = ResourceAccessMode.READ)` for
  classes that only read the shared resource — JUnit allows multiple
  readers concurrently and serialises writers against them.
- A separate Awaitility wrap as a defensive belt-and-suspenders when the
  underlying race could surface from non-test code (e.g. async event
  handlers committing on background threads). Keep it; the ResourceLock is
  the structural fix, not a license to delete the Awaitility.

## Enforcement

1. **ArchUnit / convention test.** Each project using a shared
   Testcontainers singleton should ship a test that fails if a class
   references the singleton without the matching `@ResourceLock`:

   ```java
   @ArchTest
   static final ArchRule classes_using_SharedPostgres_must_carry_lock =
       classes()
           .that().areAnnotatedWith(SpringBootTest.class)
           .and().areAssignableTo(SharedPostgresAware.class) // marker iface, or grep-by-import
           .should(new ArchCondition<JavaClass>("be annotated with @ResourceLock or @ResourceLocks") {
               @Override
               public void check(JavaClass clazz, ConditionEvents events) {
                   // @ResourceLock is @Repeatable — when a class declares >1, the
                   // compiler wraps them in a synthetic @ResourceLocks container.
                   // Checking only @ResourceLock would miss those classes.
                   boolean hasLock = clazz.isAnnotatedWith(ResourceLock.class)
                                  || clazz.isAnnotatedWith(ResourceLocks.class);
                   if (!hasLock) {
                       events.add(SimpleConditionEvent.violated(clazz,
                           clazz.getName() + " references SharedPostgres but has no @ResourceLock / @ResourceLocks"));
                   }
               }
           })
           .because("see .claude/rules/java/junit-shared-resource-lock.md");
   ```

2. **CI sanity check.** A grep step in the project's PR pipeline:

   ```bash
   # The lock-detection regex matches @ResourceLock("SharedPostgres") AND
   # @ResourceLock(value = "SharedPostgres") AND mode-qualified variants
   # like @ResourceLock(value = "SharedPostgres", mode = READ_WRITE) AND
   # the repeatable @ResourceLocks({ ... }) container form.
   missing=$(comm -23 \
     <(grep -rlE 'SharedPostgres\.INSTANCE' src/test/java | sort -u) \
     <(grep -rlE '@ResourceLocks?\([^)]*"SharedPostgres"' src/test/java | sort -u))
   if [ -n "$missing" ]; then
     echo "ERROR: SharedPostgres usages without @ResourceLock:"; echo "$missing"; exit 1
   fi
   ```

3. **Code review.** Reject any PR that introduces a new `@SpringBootTest`
   referencing the singleton without the lock, or that "fixes a flake" by
   editing `junit-platform.properties` to `mode.classes.default=same_thread`.

> Rationale (Why/Calibration/Cross-refs): docs/rule-rationale/java__junit-shared-resource-lock.md
