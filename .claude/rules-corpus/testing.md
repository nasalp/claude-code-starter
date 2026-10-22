---
roles: [builder, watcher, reviewer]
severity: critical
model_tiers: [premium, standard, cheap]
applies_to:
  task_types: [implementation, test, review]
---

# Testing Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## Assertions

### REQUIRED: Use AssertJ

```java
// ✅ AssertJ
assertThat(actual).isEqualTo("expected");
assertThat(condition).isTrue();
assertThatThrownBy(() -> call()).isInstanceOf(Exception.class);

// ❌ JUnit5 — avoid
assertEquals("expected", actual);
assertTrue(condition);
```

---

## BDD Convention

### REQUIRED: Given / When / Then

```java
@Test
void should_create_order_when_valid_request() {
    // given
    var request = validRequest();

    // when
    var result = service.createOrder(request);

    // then
    assertThat(result.getStatus()).isEqualTo(PENDING);
}
```

### REQUIRED: Naming Convention

```
should_<expected_outcome>_when_<condition>
```

---

## Behavioral Test Quality

### CRITICAL: Tests Must Prove Behavior

Passing test useful only when it would fail if product behavior were wrong.

Reject tests that:

- Mirror implementation logic instead of exercising behavior
- Grep YAML, JSON, or shell text when real script/workflow decision can execute
- Assert only value exists without checking correctness
- Assert on mocks instead of system boundary/output
- Use broad snapshots without targeted behavioral assertions
- Cover only happy path when code has branches

### REQUIRED: Input/Output Matrix

Per changed behavior, list meaningful input/output cases + cover with tests.

Minimum matrix:

| Case | Required |
|---|---|
| Happy path | Yes |
| Invalid input | Yes |
| Missing input | Yes, when input optional or external |
| Boundary value | Yes, when limits exist |
| Negative path | Yes |
| Compatibility case | Yes, when callers, routes, contracts, events, or CI outputs exist |
| Side effect | Yes, when DB writes, messages, HTTP calls, files, cache, or deploy decisions occur |

Matrix row with no test + no explicit reason → not ready for senior review.

---

## Async Testing

### CRITICAL: No Thread.sleep()

```java
// ❌ NEVER
Thread.sleep(5000);

// ✅ ALWAYS use Awaitility
await()
    .atMost(Duration.ofSeconds(5))
    .pollInterval(Duration.ofMillis(100))
    .untilAsserted(() ->
        assertThat(result).isPresent()
    );
```

---

## Custom Assertions

### RECOMMENDED: For Complex Domain Objects

Create custom assertions for domain objects with complex validation logic.

```java
public class OrderAssert extends AbstractAssert<OrderAssert, Order> {
    public static OrderAssert assertThat(Order actual) {
        return new OrderAssert(actual);
    }

    public OrderAssert isPending() {
        isNotNull();
        if (actual.getStatus() != PENDING) {
            failWithMessage("Expected PENDING but was %s", actual.getStatus());
        }
        return this;
    }
}
```

### RECOMMENDED: Test Custom Assertions

If you create custom assertions, test them:
- One positive test (passes)
- One negative test (fails with correct message)

---

## Integration Testing

### REQUIRED: Isolation by Type

One test class = one integration type:
- Controller tests (MockMvc, stubbed services)
- Repository tests (Testcontainers)
- HTTP client tests (WireMock)

### REQUIRED: Real Infrastructure

```java
// ✅ Testcontainers with real database
@Container
static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");

// ❌ Don't use H2 for Postgres-targeted code
```

### CRITICAL: Singleton Container for Parallel ITs

**Use static initializer block, not `@Container`:**

```java
// ✅ REQUIRED — singleton, started once per JVM
abstract class AbstractIntegrationTest {

    static final PostgreSQLContainer<?> POSTGRES;

    static {
        POSTGRES = new PostgreSQLContainer<>("postgres:15")
            .withReuse(true);
        POSTGRES.start();   // Started once. JVM shuts it down on exit.
    }

    @DynamicPropertySource
    static void registerProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url",      POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }
}

// ❌ NEVER — JUnit lifecycle interleaves with parallel execution
@Testcontainers
class MyIT {
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");
}
```

### CRITICAL: Per-Test Data Isolation, Not `deleteAll`

**Isolate by data, not lifecycle:**

```java
// ✅ REQUIRED — UUID prefix per test, no truncation
@Test void should_create_order() {
    var tenantId = "test-" + UUID.randomUUID();
    var order = orderService.create(tenantId, request);
    assertThat(orderRepository.findByTenant(tenantId)).hasSize(1);
}

// ❌ NEVER in parallel-IT mode
@BeforeEach void clean() { orderRepository.deleteAll(); }
```

Schema isolation: unique schema name per test, migrate in, drop in `@AfterEach`. Row isolation: prefix every insert with per-test UUID, query by prefix.

---

## Contract Testing

### REQUIRED: For Public APIs

If service exposes HTTP/messaging APIs consumed by other teams/services:
- Define Spring Cloud Contract
- Publish stubs
- Consumer tests use Stub Runner

### RECOMMENDED: For Internal APIs

Internal APIs within same team — contract tests optional but beneficial.

---

## Test Execution

### REQUIRED: Tests Must Be Run

Never say "tests should pass" — run them:

```bash
./mvnw test
# Verify: BUILD SUCCESS, Failures: 0
```

Include output in response as proof.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Awaitility condition not met within 5s` | Async operation slower than expected | Increase `atMost()` duration, or check if the async executor is Spring-managed |
| Tests pass alone but fail in parallel | Shared mutable state between tests | Remove static fields, use `@TestInstance(PER_METHOD)`, check for hardcoded ports |
| `No Container annotation found` | Testcontainers not started | Add `@Testcontainers` to class and `@Container` to container field |
| Testcontainer connection refused | Container not mapped to dynamic properties | Add `@DynamicPropertySource` to wire container port into Spring config |
| `AssertionError: expected PENDING but was null` | Test reads before async write completes | Wrap assertion in `await().untilAsserted()` |
| MockMvc returns 403 on all requests | Spring Security active in test slice | Add `@AutoConfigureMockMvc(addFilters = false)` or configure test security |

---

## Quick Reference

| Rule | Priority |
|------|----------|
| No `Thread.sleep()` | CRITICAL |
| Run tests, show output | REQUIRED |
| Use AssertJ | REQUIRED |
| BDD naming convention | REQUIRED |
| Integration isolation | REQUIRED |
| Testcontainers for DB | REQUIRED |
| Contract tests (public APIs) | REQUIRED |
| Custom assertions | RECOMMENDED |
| Contract tests (internal) | RECOMMENDED |

> Rationale (Why/Calibration): `docs/rule-rationale/testing.md`
