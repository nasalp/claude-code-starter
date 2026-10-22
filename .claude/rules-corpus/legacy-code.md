# Legacy Code Rules

How to work with existing code that doesn't follow current standards.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## Core Principle

**Don't break what works. Improve incrementally.**

Legacy code runs in production. Aggressive refactoring = risk.

---

## When to Update Legacy Code

### REQUIRED: Update When Touching

Modify file for feature/bugfix → bring touched code up to standard:

```java
// You need to add a method to this class
class OrderService {
    // Existing legacy code — DON'T touch if not related
    public void processOrder(Order o) { ... }

    // Your new code — MUST follow current standards
    Order cancelOrder(OrderId orderId) {
        // given/when/then tests
        // AssertJ assertions
        // package-private
    }
}
```

### REQUIRED: Don't Refactor Unrelated Code

```java
// ❌ BAD — changing unrelated code
class UserService {
    // You're here to fix a bug in findUser()

    // DON'T refactor this
    public void legacyMethod() { ... }

    // DON'T add tests for this
    public void otherLegacyMethod() { ... }

    // DO fix only this
    User findUser(UserId id) {
        // Your fix here
    }
}
```

### RECOMMENDED: Boy Scout Rule

Leave code slightly better — **only in area you're working**:

```java
// ✅ Good — small improvement while fixing bug
// Before: public void findUser(String id)
// After: User findUser(UserId id)  // Better type, same area

// ❌ Bad — rewriting entire class while fixing one bug
```

---

## Documenting Deviations

### REQUIRED: TODO Comments for Tech Debt

Legacy code violates rules but can't fix now:

```java
// TODO: Tech debt — this class is public but should be package-private
// Ticket: PROJ-456
// Reason: Changing visibility would break external consumers
public class LegacyOrderService { }
```

### REQUIRED: Tech Debt Tracking

Significant deviations → tracking ticket:

```markdown
## Tech Debt: PROJ-456

**Location:** com.example.orders.LegacyOrderService
**Violation:** Class is public, should be package-private
**Risk:** Low — internal use only
**Effort:** Medium — need to update 3 consumers
**Plan:** Address when refactoring order module in Q3
```

---

## Testing Legacy Code

### REQUIRED: Add Tests Before Changing

Before modifying legacy code:

```java
// Step 1: Write characterization test (captures current behavior)
@Test
void legacy_processOrder_current_behavior() {
    // Captures what it does NOW, even if "wrong"
    var result = legacyService.processOrder(order);
    assertThat(result.getStatus()).isEqualTo("PROCESSED");
}

// Step 2: Make your change

// Step 3: Verify characterization test still passes (or update if intentional)
```

### REQUIRED: Don't Add Tests for Untouched Code

Only test code you're modifying. Tests on stable legacy code waste time and may surface sleeping bugs.

---

## Refactoring Strategies

### Strangler Fig Pattern

Gradually replace legacy with new code:

```
Phase 1: New code alongside legacy
┌─────────────────────────────────────┐
│ Request → Router                    │
│              ├──→ LegacyOrderService│  (most traffic)
│              └──→ NewOrderService   │  (feature flag)
└─────────────────────────────────────┘

Phase 2: Shift traffic
┌─────────────────────────────────────┐
│ Request → Router                    │
│              ├──→ LegacyOrderService│  (feature flag)
│              └──→ NewOrderService   │  (most traffic)
└─────────────────────────────────────┘

Phase 3: Remove legacy
┌─────────────────────────────────────┐
│ Request → NewOrderService           │
└─────────────────────────────────────┘
```

### Branch by Abstraction

Introduce interface, implement twice, swap:

```java
// Step 1: Extract interface
interface OrderRepository {
    Order findById(OrderId id);
}

// Step 2: Legacy implements interface
class LegacyOrderRepository implements OrderRepository { }

// Step 3: New implementation
class JpaOrderRepository implements OrderRepository { }

// Step 4: Swap via config
@Bean
@ConditionalOnProperty(name = "feature.new-repo", havingValue = "true")
OrderRepository newRepo() { return new JpaOrderRepository(); }

@Bean
@ConditionalOnProperty(name = "feature.new-repo", havingValue = "false", matchIfMissing = true)
OrderRepository legacyRepo() { return new LegacyOrderRepository(); }
```

---

## What NOT to Do

### CRITICAL: Don't "Fix" Working Production Code

```java
// ❌ NEVER do this "while you're in there"
// - Rename variables for clarity
// - Reformat code
// - Add documentation
// - Refactor for "cleanliness"
// Unless it's directly related to your task
```

### CRITICAL: Don't Break APIs

```java
// Legacy public API
public OrderDto getOrder(String orderId) { }

// ❌ NEVER change signature of public APIs
public Order getOrder(OrderId orderId) { }  // Breaks consumers

// ✅ Add new method, deprecate old
@Deprecated
public OrderDto getOrder(String orderId) {
    return toDto(getOrderById(OrderId.of(orderId)));
}

public Order getOrderById(OrderId orderId) { }
```

### CRITICAL: Don't Mass-Refactor

```bash
# ❌ NEVER do this
find . -name "*.java" -exec sed -i 's/assertEquals/assertThat/g' {} \;
```

Changes must be intentional, tested, reviewed.

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Characterization test fails after your change | Your change altered existing behavior | Verify intent: if behavior change is deliberate, update the test and document in the spec |
| Legacy class won't compile after adding new method | Incompatible imports or Java version | Match the existing code style in that file; don't upgrade language features in untouched code |
| Strangler fig causes duplicate responses | Router sends to both old and new service | Add feature flag to route to exactly one; never fan out to both |
| New code in legacy file fails static analysis | Legacy file not excluded from new rules | Exclude the file in the tool config (e.g., SpotBugs `excludeFilterFile`), fix only your lines |
| Deprecated API removal breaks consumers | Consumers still using old API | Revert removal; deprecation requires a grace period with sunset date announced |

---

## Exceptions to Current Rules

When working with legacy code, these rules can be relaxed:

| Rule | Legacy Exception |
|------|------------------|
| AssertJ required | Existing JUnit5 tests can stay |
| Package-private classes | Existing public classes can stay |
| Custom assertions | Not required for legacy domain objects |
| Spec required | Existing undocumented features can stay |

**But:** New code you write must follow current rules.

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Don't break working production code | CRITICAL |
| Don't change public API signatures | CRITICAL |
| Don't mass-refactor | CRITICAL |
| Update when touching | REQUIRED |
| Don't refactor unrelated code | REQUIRED |
| Document deviations with TODO | REQUIRED |
| Add tests before changing legacy | REQUIRED |
| Don't test untouched code | REQUIRED |
| Boy scout rule (small improvements) | RECOMMENDED |
| Strangler fig for big replacements | RECOMMENDED |
