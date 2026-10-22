# Workflow: Bug Fix

Complete workflow for fixing bugs with proper testing and spec updates.

## Overview

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  REPRODUCE  │ →  │ UPDATE SPEC │ →  │ WRITE TEST  │ →  │    FIX      │ →  │   VERIFY    │
│             │    │             │    │ (fails)     │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

---

## Phase 1: Reproduce

**Goal:** Understand and reproduce the bug.

### Steps

1. **Gather information**
   - Error messages
   - Stack traces
   - Steps to reproduce
   - Expected vs actual behavior

2. **Find relevant spec**
   ```bash
   ls spec/features/
   cat spec/features/<feature>/<relevant>.md
   ```

3. **Identify the gap**
   - Is this a spec bug (missing case)?
   - Is this an implementation bug (code doesn't match spec)?
   - Is this an edge case not considered?

### Questions to Answer
- [ ] What is the expected behavior per spec?
- [ ] What is the actual behavior?
- [ ] What conditions trigger the bug?
- [ ] Which component is at fault?

---

## Phase 2: Update Specification

**Goal:** Ensure spec covers this case.

### If Spec is Missing the Case

1. **Update the spec** with the edge case or error case

   ```markdown
   ### Edge Cases
   - What happens when <bug condition>? → <correct behavior>
   ```

2. **Update feature index** if behavior changes significantly

### If Spec is Correct

The bug is in implementation. Skip to Phase 3.

### Deliverables
- Updated spec (if needed)
- Clear understanding of correct behavior

---

## Phase 3: Write Failing Test

**Goal:** Write a test that reproduces the bug.

### Steps

1. **Write test that exposes the bug**

   ```java
   @Test
   void should_handle_edge_case_correctly() {
       // given - setup that triggers the bug
       var input = triggerBugCondition();

       // when
       var result = service.process(input);

       // then - expected correct behavior
       assertThat(result).isEqualTo(expectedCorrectBehavior);
   }
   ```

2. **Run test — MUST FAIL**
   ```bash
   ./mvnw test -Dtest=ServiceTest#should_handle_edge_case_correctly
   # Should FAIL (bug still present)
   ```

3. **If test passes, your test is wrong!**
   - Re-examine the bug
   - Verify reproduction steps
   - Update test

### Deliverables
- Failing test that reproduces the bug

---

## Phase 4: Fix

**Goal:** Implement the minimal fix.

### Steps

1. **Implement the fix**
   - Change minimal code
   - Don't refactor unrelated areas
   - Don't "improve" surrounding code

2. **Run the failing test**
   ```bash
   ./mvnw test -Dtest=ServiceTest#should_handle_edge_case_correctly
   # Should PASS now
   ```

3. **Run related tests**
   ```bash
   ./mvnw test -Dtest="*ServiceTest"
   ```

### Fix Checklist
- [ ] Minimal change
- [ ] No unrelated changes
- [ ] Test passes
- [ ] Related tests still pass

---

## Phase 5: Verification

**Goal:** Ensure fix doesn't break anything.

### Steps

1. **Run full test suite**
   ```bash
   ./mvnw test
   ```

2. **Run static analysis**
   ```bash
   ./mvnw spotbugs:check
   ```

3. **Run verification**
   ```bash
   ./mvnw verify
   ```

4. **Review the fix**
   - Is it minimal?
   - Does it match the spec?
   - Any side effects?

### Parallel Tasks
Can run in parallel:
- Full test suite
- SpotBugs
- Checkstyle

### Verification Checklist
- [ ] Bug reproduction test passes
- [ ] All other tests pass
- [ ] SpotBugs clean
- [ ] BUILD SUCCESS

---

## Phase 6: Documentation

**Goal:** Document the fix.

### Steps

1. **Update spec if behavior clarified**

2. **Add test documentation**
   ```java
   /**
    * Regression test for BUG-123.
    * Previously, when X happened, system did Y.
    * Now correctly does Z per spec.
    */
   @Test
   void should_handle_edge_case_correctly() {
   ```

3. **Commit with clear message**
   ```
   Fix: Handle edge case when <condition>

   Previously, when <condition>, the system would <wrong behavior>.
   Now correctly <expected behavior> per spec.

   Adds regression test to prevent recurrence.
   ```

---

## Quick Reference

```
1. Reproduce → understand the bug
2. Check spec → is this case covered?
3. Update spec → if case was missing
4. Write test → must fail initially
5. Fix → minimal change only
6. Verify → run all tests
7. Document → update spec, commit message
```

---

## Common Mistakes

| Mistake | Correct Approach |
|---------|------------------|
| Fix before test | Write failing test FIRST |
| Big refactor with fix | Minimal fix only |
| Test passes immediately | Your test is wrong |
| Skip spec check | Always verify against spec |
| Skip full test suite | Always run all tests |
| Vague commit message | Explain what and why |

---

## Bug Categories

### Spec Bug
Spec doesn't cover this case.
→ Update spec first, then write test, then fix.

### Implementation Bug
Code doesn't match spec.
→ Write test from spec, then fix.

### Environment Bug
Works locally, fails in production.
→ Reproduce in similar environment, then fix.

### Edge Case Bug
Unusual input causes failure.
→ Add edge case to spec, write test, fix.
