# Workflow: Feature Development

Complete workflow for implementing a new feature from specification to deployment.

## Overview

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   SPEC      │ →  │   TEST      │ →  │ IMPLEMENT   │ →  │  VERIFY     │ →  │  COMPLETE   │
│   FIRST     │    │   FIRST     │    │             │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

---

## Phase 1: Specification

**Goal:** Document what we're building before writing any code.

### Steps

1. **Check existing specs**
   ```bash
   ls spec/features/
   cat spec/features/README.md
   ```

2. **Create feature directory**
   ```bash
   mkdir -p spec/features/<feature-name>
   ```

3. **Write specification**
   → Use [/feature](../commands/feature.md) command (drafts the spec with user stories + AC IDs)

4. **Update feature index**
   → Add to `spec/features/README.md`

5. **Review spec completeness**
   - [ ] What does it do?
   - [ ] Who uses it?
   - [ ] Inputs and outputs?
   - [ ] Error cases?
   - [ ] Edge cases?
   - [ ] Dependencies?

### Deliverables
- `spec/features/<feature-name>/<feature>.md`
- Updated `spec/features/README.md`

### Parallel Tasks
During spec writing, can also:
- Read existing codebase
- Identify affected areas
- Review related features

---

## Phase 2: Test First

**Goal:** Write failing acceptance tests that define done.

### Steps

1. **Read the spec thoroughly**

2. **Write acceptance test**
   → Use [/test](../commands/test.md) command — write the failing acceptance test first

3. **Verify test fails**
   ```bash
   ./mvnw test -Dtest=FeatureAcceptanceTest
   # Should FAIL (no implementation yet)
   ```

4. **Write contract tests** (if HTTP/messaging API)
   → Use [/test](../commands/test.md) — add the contract test

### Deliverables
- `src/test/java/.../acceptance/FeatureAcceptanceTest.java`
- Contract definitions (if applicable)

### Parallel Tasks
Can work in parallel:
- Acceptance tests
- Contract definitions
- Test data fixtures

---

## Phase 3: Implementation

**Goal:** Write minimal code to make tests pass.

### Steps

1. **Implement domain layer**
   - Entities (package-private)
   - Value objects
   - Domain services

2. **Implement application layer**
   - Use cases
   - Application services

3. **Implement infrastructure**
   - Repositories
   - HTTP clients
   - Message handlers

4. **Implement API layer**
   - Controllers
   - DTOs
   - Validation

5. **Run acceptance test**
   ```bash
   ./mvnw test -Dtest=FeatureAcceptanceTest
   # Should PASS now
   ```

### Implementation Checklist
- [ ] Classes package-private by default
- [ ] Entities never public
- [ ] Caches bounded (`maximumSize`)
- [ ] Queues bounded (explicit capacity)
- [ ] Async uses Spring-managed executors

### Deliverables
- Domain classes
- Application services
- Infrastructure adapters
- API controllers

---

## Phase 4: Unit Tests & Edge Cases

**Goal:** Cover edge cases and ensure robustness.

### Steps

1. **Identify edge cases from spec**

2. **Write unit tests**
   → Use [/test](../commands/test.md) — unit tests

3. **Create custom assertions**
   → Use [/test](../commands/test.md) — custom assertions

4. **Test custom assertions**
   - Positive case
   - Negative case

### Deliverables
- Unit tests for all services
- Custom assertions for domain objects
- Custom assertion tests

---

## Phase 5: Verification

**Goal:** Ensure everything passes quality gates.

### Steps

1. **Run full test suite**
   ```bash
   ./mvnw test
   ```

2. **Run static analysis**
   ```bash
   ./mvnw spotbugs:check
   ./mvnw checkstyle:check
   ```

3. **Run full verification**
   ```bash
   ./mvnw verify
   ```

4. **Review code**
   → Use [/code-review](../commands/code-review.md) command

### Verification Checklist
- [ ] All tests pass
- [ ] SpotBugs clean
- [ ] Checkstyle clean
- [ ] BUILD SUCCESS

### Parallel Tasks
Can run in parallel:
- Test execution
- SpotBugs
- Checkstyle

---

## Phase 6: Documentation & Completion

**Goal:** Update spec status and finalize.

### Steps

1. **Update spec status**
   ```markdown
   ## Status
   - [x] Spec complete
   - [x] Backend implemented
   - [ ] Frontend implemented
   - [x] Tests passing
   ```

2. **Update feature index**
   ```markdown
   | Feature | Spec | Backend | Frontend | Status |
   |---------|------|---------|----------|--------|
   | Name | [spec](path) | ✅ | ❌ | Backend Complete |
   ```

3. **Final verification**
   ```bash
   ./mvnw clean verify
   ```

### Deliverables
- Updated spec with status
- Updated feature index
- Passing build

---

## Quick Reference

```
Phase 1: /feature <description>      → drafts spec with AC IDs
Phase 2: /test                       → write failing acceptance test
Phase 3: /tdd                        → implement with TDD inner loop
Phase 4: /test                       → unit + custom-assertion tests
Phase 5: /test (full suite) + /code-review
Phase 6: Update specs and index
```

---

## Parallel Execution Map

```
┌──────────────────────────────────────────────────────────┐
│ SEQUENTIAL (dependencies)                                │
│                                                          │
│  Spec → Acceptance Test → Implementation → Verification  │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│ PARALLEL WITHIN PHASES                                   │
│                                                          │
│  Phase 2: acceptance tests ║ contract tests              │
│  Phase 4: unit tests ║ custom assertions                 │
│  Phase 5: tests ║ spotbugs ║ checkstyle                  │
└──────────────────────────────────────────────────────────┘
```
