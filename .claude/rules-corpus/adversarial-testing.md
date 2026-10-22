# Adversarial QA Testing Rules

QA job: **find bugs**. No bugs found → not thorough enough.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |

---

## Core Mindset

### CRITICAL: Be Adversarial, Not Cooperative

Not verifying code works. **Trying to break it.**

**Think like attacker, not user.**

```
Developer mindset: "Does it work for valid input?"
QA mindset:        "What input will make it fail?"
```

### CRITICAL: Understand the Objective First

Before writing one test, answer:

1. **What does this code claim to do?** (Read spec, not just code)
2. **Invariants?** (What must ALWAYS be true?)
3. **Implicit assumptions?** (What did developer take for granted?)
4. **Trust boundaries?** (Where does external input enter?)

Can't answer these → can't test effectively.

---

## REQUIRED: Adversarial Test Categories

### 1. Boundary Attacks

Test every boundary. Off-by-one = most common bug.

```java
// If the spec says "max 128 characters"
@Test void should_accept_exactly_128_characters() { }
@Test void should_reject_129_characters() { }
@Test void should_accept_exactly_1_character() { }
@Test void should_reject_0_characters() { }

// If the spec says "positive amount"
@Test void should_reject_zero_amount() { }          // Is zero positive?
@Test void should_reject_negative_amount() { }
@Test void should_accept_smallest_positive() { }    // 0.01? 0.0001?
@Test void should_handle_max_amount() { }            // BigDecimal.MAX?
```

### 2. Null and Empty Attacks

Every nullable/empty-able input MUST be tested.

```java
@Test void should_handle_null_input() { }
@Test void should_handle_empty_string() { }
@Test void should_handle_blank_string() { }          // "   "
@Test void should_handle_empty_collection() { }
@Test void should_handle_null_nested_field() { }     // object.inner is null
```

### 3. State Attacks

Test illegal state transitions. Bug often in what SHOULDN'T be allowed.

```java
// If orders go PENDING -> CONFIRMED -> SHIPPED -> DELIVERED
@Test void should_reject_shipping_pending_order() { }
@Test void should_reject_confirming_delivered_order() { }
@Test void should_reject_cancelling_shipped_order() { }
@Test void should_reject_duplicate_confirmation() { }
```

### 4. Concurrency Attacks

Shared state exists → race it.

```java
@Test void should_not_double_charge_on_concurrent_payment() {
    // Submit same payment from two threads simultaneously
    var futures = IntStream.range(0, 10)
        .mapToObj(i -> CompletableFuture.runAsync(() ->
            paymentService.process(samePaymentId), executor))
        .toList();
    CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
    // Exactly one charge should succeed
    assertThat(chargeCount(samePaymentId)).isEqualTo(1);
}
```

### 5. Type Confusion and Format Attacks

Test inputs that look right but aren't.

```java
@Test void should_reject_email_without_domain() { }       // "user@"
@Test void should_reject_email_with_spaces() { }           // "user @example.com"
@Test void should_handle_unicode_in_name() { }             // "Ren\u00e9"
@Test void should_handle_emoji_in_input() { }              // "\uD83D\uDE00"
@Test void should_handle_very_long_input() { }             // 10MB string
@Test void should_handle_special_characters() { }          // "<script>alert(1)</script>"
@Test void should_handle_sql_in_input() { }                // "'; DROP TABLE users;--"
```

### 6. Absence and Default Attacks

What happens when optional things missing?

```java
@Test void should_handle_missing_optional_header() { }
@Test void should_handle_missing_query_param() { }
@Test void should_use_correct_default_when_config_absent() { }
@Test void should_handle_empty_response_from_external_service() { }
@Test void should_handle_timeout_from_external_service() { }
```

### 7. Ordering and Timing Attacks

```java
@Test void should_handle_events_arriving_out_of_order() { }
@Test void should_handle_duplicate_events() { }
@Test void should_handle_event_arriving_after_entity_deleted() { }
@Test void should_be_idempotent_on_retry() { }
```

---

## REQUIRED: The Bug-Finding Checklist

Before declaring testing complete, verify you tested:

- [ ] **Happy path** — obvious case works
- [ ] **Every error path** — each exception/error branch exercised
- [ ] **Boundaries** — min, max, off-by-one for every constraint
- [ ] **Nulls and empties** — every input that can be absent
- [ ] **Invalid state transitions** — what shouldn't happen but could be attempted
- [ ] **Malicious input** — injection, overflow, format abuse
- [ ] **Concurrency** — if shared mutable state exists
- [ ] **Idempotency** — calling same operation twice
- [ ] **Dependency failures** — what if DB/service/queue is down?
- [ ] **Return value correctness** — not just "no exception", the RIGHT value

### CRITICAL: Test the Output, Not Just the Absence of Failure

```java
// ❌ Weak — only tests "no crash"
@Test void should_create_order() {
    service.createOrder(request);
    // no assertion on the result!
}

// ❌ Weak — only tests type
@Test void should_create_order() {
    var result = service.createOrder(request);
    assertThat(result).isNotNull();  // So what?
}

// ✅ Strong — verifies correctness
@Test void should_create_order_with_correct_state() {
    var result = service.createOrder(request);
    assertThat(result.getStatus()).isEqualTo(PENDING);
    assertThat(result.getItems()).hasSize(3);
    assertThat(result.getTotal()).isEqualByComparingTo("99.99");
    assertThat(result.getCreatedBy()).isEqualTo(userId);
}
```

---

## REQUIRED: Escalating Thoroughness

No bugs found yet → escalate:

### Level 1: Read the Spec
- Test every stated requirement
- Test every stated constraint
- Test every error case mentioned

### Level 2: Read the Code
- Find every branch (`if`, `switch`, ternary) — test both sides
- Find every catch block — trigger each one
- Find every validation — bypass each one
- Find every default value — correct?

### Level 3: Question the Assumptions
- Types used? Can they overflow? (`int` for money?)
- Threading model? State shared?
- At scale? (1 item vs 10,000 items)
- Clock changes? (DST, leap second, time zones)
- Locale changes? (decimal separator, sort order)

### Level 4: Combine Inputs
- Combine edge cases together
- A works, B works, A+B together
- Maximum everything at once

---

## REQUIRED: Test Smells That Hide Bugs

These patterns = tests that pass but prove nothing:

| Smell | Problem |
|-------|---------|
| No assertions | Proves code doesn't crash, not that it's correct |
| Only `isNotNull()` | Doesn't verify actual value |
| Mocking the thing under test | Tests mock, not code |
| Too many mocks | Integration bugs hide between mocks |
| Single happy path | All edge cases untested |
| Copy-paste tests | Same scenario, different names, no new coverage |
| `@Disabled` tests | Something broken, nobody fixed it |
| Catching exceptions in test | Swallows failure signal |

```java
// ❌ Test smell: catching exception hides bug
@Test void should_process_order() {
    try {
        service.process(order);
    } catch (Exception e) {
        // "handle later"
    }
}

// ✅ Let it fail loudly
@Test void should_process_order() {
    service.process(order);  // Exception = test failure = bug found
}
```

---

## CRITICAL: Never Weaken a Test to Make It Pass

Test fails → **production code wrong, not test**. Investigate cause; do NOT edit assertion until test passes.

| Anti-pattern | Why it's wrong |
|--------------|----------------|
| Reduce assertion count | Removes coverage of behavior being verified |
| Replace `isEqualTo(...)` with `isNotNull()` | Hides actual value mismatch |
| Comment out an `@Test` method | Pretends failing scenario doesn't exist |
| Add `@Disabled` without a ticket | Defers a real bug indefinitely |
| Wrap the call in `try { ... } catch { ignore }` | Converts failure into silent pass |
| Increase the timeout instead of fixing the slow path | Masks a regression |
| Replace assertion with a log statement | Discards the verdict entirely |
| Change `isInstanceOf(BadException.class)` to `isInstanceOf(Exception.class)` | Loses specificity |

Contract: **failing test is a finding**. Fix code, document defect with ticket + `@Disabled("reason: PROJ-123")`, or escalate. Never re-write test until it passes.

Applies equally to your own assertions and those by other engineers / prior agents. Flaky test → fix = stable test, not deleted assertion.

---

## REQUIRED: Report Findings, Not Just Pass/Fail

Found bug (or suspicious behavior) → document:

1. **What you tested** — exact input/scenario
2. **What you expected** — based on spec or invariant
3. **What actually happened** — observed behavior
4. **Why it matters** — impact on users/system
5. **Reproduction** — minimal test case

```java
/**
 * BUG: Order total calculation ignores discount when exactly one item.
 *
 * Expected: 10% discount applied -> total = $9.00
 * Actual: total = $10.00 (discount skipped)
 * Impact: Customers with single-item orders overpay.
 * Root cause: Loop starts at index 1 instead of 0 in DiscountCalculator:42
 */
@Test void should_apply_discount_to_single_item_order() {
    var order = orderWith(singleItem(TEN_DOLLARS));
    order.applyDiscount(Discount.percentage(10));
    assertThat(order.getTotal()).isEqualByComparingTo("9.00");
}
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| All tests pass, no bugs found | Tests too cooperative (happy-path only) | Escalate to Level 2+: read code, find branches, test both sides |
| Same bug type keeps appearing | Systemic design flaw, not isolated bug | Stop testing symptom; file design issue for root cause |
| Concurrency test is flaky | Race condition timing non-deterministic | Run 100+ times (`@RepeatedTest(100)`), use `CountDownLatch` for synchronization |
| Property-based test finds failure but can't reproduce | Shrinking disabled or seed not logged | Enable jqwik shrinking, log seed with `@Property(seed = "...")` |
| Test passes locally, fails in CI | Hardcoded path, port, timezone, or locale | Use `@TempDir` for paths, `RANDOM_PORT` for ports, explicit `Locale`/`ZoneId` |

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Be adversarial, not cooperative | CRITICAL |
| Understand the objective before testing | CRITICAL |
| Test output correctness, not just no-crash | CRITICAL |
| Boundary attacks on every constraint | REQUIRED |
| Null/empty attacks on every input | REQUIRED |
| State transition attacks | REQUIRED |
| Concurrency attacks on shared state | REQUIRED |
| Escalate thoroughness until bugs found | REQUIRED |
| Watch for test smells that hide bugs | REQUIRED |
| Document findings with full context | REQUIRED |
