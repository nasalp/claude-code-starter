#!/usr/bin/env bash
# verify-ac-tests.sh + generate-features-index.py read Gherkin acceptance criteria:
# scenario tags count, comments / @removed scenarios / non-gherkin code blocks don't.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

P=$(make_tmp)
trap 'rm -rf "$P"' EXIT
mkdir -p "$P/spec/features/order-cancellation" "$P/src/test/java/orders"

cat > "$P/spec/features/order-cancellation/order-cancellation.md" <<'SPEC'
---
feature: order-cancellation
status: in-progress
tests: []
gaps: []
---
# Order Cancellation

## User Stories

### US-CANCEL-1: Cancel a pending order

```gherkin
# Tests: OrderCancelAcceptanceTest#should_cancel_pending_order
@AC-CANCEL-1
Scenario: A pending order cancelled inside the window
  Given a pending order placed less than 24 hours ago
  When the customer cancels it
  Then the order is cancelled

# Tests: planned (AC-CANCEL-9 mentioned only in a comment)
@AC-CANCEL-2
Scenario: A shipped order cannot be cancelled
  Given an order that has already shipped
  When the customer tries to cancel it
  Then the cancellation is rejected

@AC-CANCEL-3 @removed
Scenario: A retired promise
  Given something old
  When it happens
  Then nothing
```

```java
// AC-CANCEL-8 appears only in a non-gherkin code example
```
SPEC

cat > "$P/src/test/java/orders/OrderCancelAcceptanceTest.java" <<'JAVA'
class OrderCancelAcceptanceTest {
  @Tag("AC-CANCEL-1") void should_cancel_pending_order() {}
}
JAVA

out=$(cd "$P" && bash "$REPO_ROOT/scripts/verify-ac-tests.sh" 2>&1); rc=$?
assert_eq 1 "$rc" "verify-ac-tests fails when a scenario has no test"
assert_contains "$out" "2 AC ID(s)" "counts exactly the two live scenario tags"
assert_contains "$out" "no test annotation for AC-CANCEL-2" "reports the untested scenario"
[[ "$out" != *"AC-CANCEL-3"* ]] && pass "ignores @removed scenarios" || fail "ignores @removed scenarios"
[[ "$out" != *"AC-CANCEL-8"* && "$out" != *"AC-CANCEL-9"* ]] && pass "ignores IDs in comments and non-gherkin code" || fail "ignores IDs in comments and non-gherkin code"

cat >> "$P/src/test/java/orders/OrderCancelAcceptanceTest.java" <<'JAVA'
class OrderCancelRejectTest { @Tag("AC-CANCEL-2") void should_reject_shipped_order() {} }
JAVA
(cd "$P" && bash "$REPO_ROOT/scripts/verify-ac-tests.sh" >/dev/null 2>&1)
assert_eq 0 "$?" "verify-ac-tests passes once every scenario has a test"

(cd "$P" && python3 -I "$REPO_ROOT/scripts/generate-features-index.py" --spec-dir spec/features >/dev/null 2>&1)
row=$(grep 'order-cancellation' "$P/spec/features/README.md" | head -1)
assert_contains "$row" "| 1 | 2 |" "features index counts 1 story and 2 acceptance criteria"

finish
