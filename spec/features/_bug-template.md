<!--
Bug-fix spec template. Copy into:
  spec/features/<bug-slug>/<bug-slug>.md

A bug fix has a different shape than a forward feature: instead of "what
should this do?" the spec captures (a) what the system did wrong, (b) what
it should do, and (c) how we make sure the bug never returns. Each is a
separate AC with its own test. The PREFIX should be a short UPPER-CASE
token derived from the bug slug (e.g. BUG-CANCEL-RACE for a slug
`cancel-race-condition`).
-->
---
feature: <bug-slug>
status: draft
type: bug-fix
tests: []
gaps: []
---

# <Bug Title>

## Bug summary

<2-3 sentences: what's broken from the user's perspective. Avoid
implementation language — describe the symptom, not the suspected cause.>

## Severity and impact

| Severity | Affected users | First seen | Reported by |
|----------|----------------|------------|-------------|
| <SEV-1..4> | <scope> | <date / build / commit> | <reporter> |

## Reproduction

Step-by-step, in plain language:

1. Given <precondition>
2. When <action>
3. Then **observed**: <wrong behavior>
4. **Expected**: <correct behavior>

## Suspected root cause (optional)

<If you have a hypothesis at filing time, put it here. Otherwise omit.>

## User Stories and Acceptance Criteria

<Bug fixes have THREE story shapes. Each gets its own AC — a Gherkin
scenario tagged with its AC ID — and its own test. They are not optional — a fix without a regression-prevention AC
is one merge away from being broken again. Bug specs show TWO Mermaid
diagrams: the buggy flow (under US-1) and the fixed flow (under US-2),
side-by-side so reviewers can see exactly what changed.>

### US-<PREFIX>-1: Reproduce the bug

> As an **engineer**, I want a failing test that reproduces this bug,
> so that I can prove the fix works and detect regressions.

```mermaid
sequenceDiagram
    actor <Actor>
    participant <System>

    Note over <Actor>,<System>: Buggy flow — what the system does today
    <Actor>->><System>: <action that triggers the bug>
    <System>-->><Actor>: <observed wrong outcome>
```

```gherkin
# Tests: <TestClass#should_reproduce_<bug-slug>> or planned
# This test MUST fail BEFORE the fix is applied. (RED-first ATDD.)
@AC-<PREFIX>-1
Scenario: <the bug, as the user experiences it>
  Given <reproduction context>
  When <action>
  Then <the observed wrong outcome happens>
```

### US-<PREFIX>-2: Fix the bug

> As a **<affected role>**, I want <correct behavior>, so that <benefit>.

```mermaid
sequenceDiagram
    actor <Actor>
    participant <System>

    Note over <Actor>,<System>: Fixed flow — what the system should do
    <Actor>->><System>: <same triggering action>
    <System>-->><Actor>: <correct outcome>
```

```gherkin
# Tests: <TestClass#should_<expected_outcome>> or planned
# The reproduction test from AC-<PREFIX>-1 must now pass.
@AC-<PREFIX>-2
Scenario: <the correct behaviour>
  Given <the same reproduction context>
  When <the same action>
  Then <the expected outcome>
```

### US-<PREFIX>-3: Prevent regression

> As an **engineer**, I want a guard that fails the build if this bug
> ever returns, so that we don't fix the same thing twice.

```gherkin
# Tests: <RegressionTest#guard_<bug-slug>> or planned
# The regression test SHOULD outlive the immediate fix. If you refactor
# the fix later, this test must still catch the bug.
@AC-<PREFIX>-3
Scenario: The bug cannot come back
  Given the conditions that originally triggered the bug
  When <the regression scenario runs in CI>
  Then the build fails if the bug returns
```

## Scope

### In scope
- <code paths the fix touches>

### Out of scope
- <related-but-separate issues — file as separate bug specs>

### Not changing
- <existing behavior preserved>

## Verification

<!-- Filled by the agent after implementation. -->

- Reproduction test (AC-<PREFIX>-1) was RED before fix:
- Fix test (AC-<PREFIX>-2) was GREEN after fix:
- Regression guard (AC-<PREFIX>-3) is wired into CI:
- Mutation kill rate on touched code:
- Reviewer approval:
