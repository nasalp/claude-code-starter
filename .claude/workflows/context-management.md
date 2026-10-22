# Context Management

How to manage conversation context effectively during long tasks.

---

## Why Context Matters

AI assistants have limited context windows. Long conversations can:
- Lose early details
- Repeat information unnecessarily
- Slow down responses
- Miss important constraints

---

## Strategies

### 1. Reference by Path, Don't Repeat

```
# ❌ Bad — repeating content
"The spec says users should be able to cancel orders within 24 hours.
The spec also mentions that cancelled orders should refund automatically.
The spec requires email notification on cancellation..."

# ✅ Good — reference by path
"Implementing per spec at `spec/features/orders/cancel-order.md`.
Key requirements: 24h window, auto-refund, email notification."
```

### 2. Summarize Completed Work

After completing a phase, summarize:

```
## Completed: Phase 1 (Specification)

Created:
- `spec/features/orders/cancel-order.md`
- Updated `spec/features/README.md`

Key decisions:
- 24h cancellation window
- Automatic refund via payment service
- Email notification required

Moving to: Phase 2 (Tests)
```

### 3. Use Task Lists

For multi-step work:

```
## Order Cancellation Feature

### Done
- [x] Create spec
- [x] Write acceptance test
- [x] Implement domain logic

### In Progress
- [ ] Implement controller

### Pending
- [ ] Add unit tests
- [ ] Run verification
```

### 4. Checkpoint at Phase Boundaries

Before starting a new phase:

```
## Checkpoint: Ready for Implementation

Spec: `spec/features/orders/cancel-order.md` ✓
Test: `CancelOrderAcceptanceTest.java` ✓ (fails as expected)

Proceeding with implementation...
```

---

## Long Conversation Patterns

### Starting Fresh

When beginning a complex task:

```
## Task: Implement Order Cancellation

References:
- Spec: `spec/features/orders/cancel-order.md`
- Related: `src/.../OrderService.java`

Approach:
1. Spec (done)
2. Test
3. Implement
4. Verify

Starting with acceptance test...
```

### Mid-Task Summary

When context is getting long:

```
## Progress Summary

### Completed
- Spec at `spec/features/orders/cancel-order.md`
- Acceptance test (failing, as expected)
- Domain: `Order.cancel()`, `CancellationPolicy`
- Service: `OrderService.cancelOrder()`

### Current
Implementing `OrderController.cancelOrder()`

### Remaining
- Unit tests for edge cases
- Integration test
- Verification
```

### Resuming After Break

If conversation continues after pause:

```
## Resuming: Order Cancellation

Last state:
- Spec: ✓
- Tests: ✓
- Implementation: In progress (controller remaining)

Files modified so far:
- `Order.java` — added cancel()
- `OrderService.java` — added cancelOrder()
- `CancelOrderAcceptanceTest.java`

Continuing with controller...
```

---

## What to Keep in Context

### Always Reference
- Spec location
- Test file locations
- Key decisions made
- Current phase/step

### Summarize, Don't Repeat
- Full file contents → path + summary
- Detailed requirements → key points
- Long discussions → decisions made

### Drop When Done
- Implementation details of completed phases
- Failed approaches
- Exploratory reading

---

## Agent Behavior

### After Reading a File
```
# ❌ Bad
"The file contains 200 lines. Let me quote all of it..."

# ✅ Good
"Read `OrderService.java` (45 lines). Key method: `createOrder()` at line 23.
Relevant to our task: uses `OrderRepository` for persistence."
```

### After Completing a Phase
```
# ❌ Bad
Continue without acknowledgment

# ✅ Good
"## Phase 1 Complete

Created spec at `spec/features/orders/cancel-order.md`.
Key behavior defined: 24h window, auto-refund, notification.

Moving to Phase 2: Writing acceptance test..."
```

### When Context is Long
```
# ✅ Proactive summary
"## Context Summary (conversation is long)

Task: Order cancellation feature
Progress: Spec ✓, Test ✓, Implementation 80%
Remaining: Controller endpoint, verification

Current file: `OrderController.java`
Adding: `cancelOrder()` endpoint per spec."
```

---

## Parallel Agent Context

When multiple agents work in parallel:

### Shared State
```
## Shared Context

Spec: `spec/features/orders/cancel-order.md`
Branch: `feature/PROJ-123-cancel-order`

Agent 1: Writing acceptance tests
Agent 2: Writing contract tests
Agent 3: Running static analysis on existing code
```

### Handoff Between Agents
```
## Handoff: Test → Implementation

Completed by Test Agent:
- `CancelOrderAcceptanceTest.java` — 3 test cases
- `CancelOrderContractTest.java` — producer contract

Implementation Agent should:
- Make tests pass
- Follow patterns in existing `OrderService`
- Domain logic in `Order.cancel()`
```

---

## Quick Reference

| Situation | Action |
|-----------|--------|
| Reading file | Summarize, reference path |
| Completing phase | Write summary checkpoint |
| Long conversation | Proactive context summary |
| Resuming work | State last position |
| Multiple agents | Document shared state |
| Key decision | Record decision and rationale |
