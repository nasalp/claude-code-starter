<!--
Feature spec template. Copy this file into:
  spec/features/<feature-slug>/<feature-slug>.md

Conventions (canonical source: .claude/rules/core.md):
- One file per feature. Everything lives here: stories, ACs, scope, verification.
- Acceptance criteria are Gherkin scenarios, one ```gherkin block per user
  story. One Scenario = one observable promise, tagged with its AC ID.
- AC IDs use the prefix form: @AC-<PREFIX>-<N> (e.g. @AC-CANCEL-1, @AC-SNAP-3).
  Pick a SHORT, UPPER-CASE prefix that's unique across the project.
- A business person must be able to read every user story and AC.
- Scenarios describe WHAT the system does, never HOW (no class names,
  endpoints, tables, HTTP codes or UI selectors).
- The agent drafts the scenarios; a human trims and approves them before any
  test or code is written.
- Each AC maps to one or more test methods, annotated with the AC ID per the
  per-language convention (Java @Tag, TS test.describe, Python @pytest.mark.spec,
  Go function-name fragment).
-->
---
feature: <feature-slug>
status: draft
tests: []
gaps: []
---

# <Feature Name>

## Overview

<2-3 sentences: what this feature does and why it exists.>

## Primary Actors

<Who uses this feature — refer to roles, not specific people.>

## Business Rules

<The rules that govern behavior. Technology-independent. Numbered list is fine.>

## Error and Edge Cases

| Scenario | Expected behavior |
|----------|-------------------|
| <edge case> | <what happens> |

## User Stories

<Group ACs under user stories. Each story: who wants what and why,
followed by a Mermaid sequence diagram of the happy-path flow, then
the acceptance criteria as Gherkin scenarios.>

### US-<PREFIX>-1: <story title>

> As a **<role>**, I want <goal>, so that <benefit>.

```mermaid
sequenceDiagram
    actor <Actor>
    participant <System1>
    participant <System2>

    <Actor>->><System1>: <intent / action>
    <System1>->><System2>: <delegated call>
    <System2>-->><System1>: <result>
    <System1>-->><Actor>: <user-visible outcome>
```

```gherkin
# Tests: <TestClass#method> or planned
@AC-<PREFIX>-1
Scenario: <happy path, in business words>
  Given <the starting situation>
  When <the one action>
  Then <the observable outcome>

# Tests: <TestClass#method> or planned
@AC-<PREFIX>-2
Scenario: <an error or edge case>
  Given <the starting situation>
  When <the one action>
  Then <the observable outcome>
```

### US-<PREFIX>-2: <next story title>

> As a **<role>**, I want <goal>, so that <benefit>.

```mermaid
sequenceDiagram
    actor <Actor>
    participant <System>

    <Actor>->><System>: <intent>
    <System>-->><Actor>: <outcome>
```

```gherkin
# Tests: planned
@AC-<PREFIX>-3
Scenario: <observable behaviour>
  Given <the starting situation>
  When <the one action>
  Then <the observable outcome>
```

## Scope

### In scope
- <what this feature covers>

### Out of scope
- <what is explicitly excluded>

### Not changing
- <existing behavior preserved as-is>

## Access matrix (for endpoints, if applicable)

| Endpoint | Public | Authenticated | Admin | Rate Limited |
|----------|--------|---------------|-------|--------------|

## Verification

<!-- Filled by the agent after implementation. Records actual results. -->

- Test output:
- Coverage:
- Mutation kill rate:
- Reviewer approval:
