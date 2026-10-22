# Workflow: Planning and Reasoning

Structured approach for complex tasks requiring analysis and planning.

## When to Use Planning

Use structured planning for:
- New features with multiple components
- Architectural decisions
- Complex refactoring
- Tasks with unclear requirements
- Cross-cutting changes

## Planning Phases

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  ANALYZE    │ →  │  RESEARCH   │ →  │   DESIGN    │ →  │    PLAN     │ →  │   EXECUTE   │
│             │    │             │    │             │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

---

## Phase 1: Analyze

**Goal:** Understand the requirement fully.

### Questions to Answer

1. **What is being asked?**
   - Explicit requirements
   - Implicit requirements
   - Constraints

2. **What is the scope?**
   - In scope
   - Out of scope
   - Edge cases

3. **What is the success criteria?**
   - How do we know it's done?
   - How do we verify correctness?

### Output Format
```markdown
## Analysis

### Requirement
<What we're building>

### Scope
- In: <list>
- Out: <list>

### Success Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>

### Open Questions
- <question needing clarification>
```

---

## Phase 2: Research

**Goal:** Gather information about existing code and patterns.

### Steps

1. **Find relevant specs**
   ```bash
   ls spec/features/
   cat spec/features/README.md
   ```

2. **Find related code**
   - Similar features
   - Affected components
   - Shared dependencies

3. **Understand existing patterns**
   - How similar problems are solved
   - Naming conventions
   - Package structure

### Parallel Research Tasks

These can run simultaneously:
- Spec review
- Code exploration
- Dependency analysis
- Related feature review

### Output Format
```markdown
## Research Findings

### Relevant Specs
- `spec/features/x/y.md` - <summary>

### Related Code
- `src/.../FeatureService.java` - <how it relates>

### Patterns to Follow
- <pattern 1>
- <pattern 2>

### Dependencies
- Requires: <list>
- Affects: <list>
```

---

## Phase 3: Design

**Goal:** Create or update the specification.

### Steps

1. **Create/update spec**
   → Use [/feature](../commands/feature.md) command (drafts the spec with user stories + AC IDs)

2. **Define behavior**
   - Happy path
   - Edge cases
   - Error cases

3. **Define interfaces**
   - API endpoints
   - DTOs
   - Events

4. **Identify components**
   - Domain entities
   - Services
   - Repositories
   - Clients

### Output Format
```markdown
## Design

### Components
1. Domain: `Order`, `OrderStatus`
2. Service: `OrderService`
3. Repository: `OrderRepository`
4. API: `OrderController`

### Flow
1. Request → Controller → Service
2. Service → Domain logic
3. Domain → Repository (persist)
4. Return → DTO

### Interfaces
- `POST /api/orders` - Create order
- `GET /api/orders/{id}` - Get order
```

---

## Phase 4: Plan

**Goal:** Break down into executable tasks.

### Task Breakdown

```markdown
## Task List

### Phase 1: Specification
- [ ] Create spec `spec/features/orders/create-order.md`
- [ ] Update feature index

### Phase 2: Tests
- [ ] Write acceptance test `OrderAcceptanceTest`
- [ ] Write contract test (if API)

### Phase 3: Implementation
- [ ] Domain: `Order`, `OrderId`, `OrderStatus`
- [ ] Service: `OrderService`
- [ ] Repository: `OrderRepository`
- [ ] Controller: `OrderController`

### Phase 4: Verification
- [ ] Run tests
- [ ] Run SpotBugs
- [ ] Update spec status
```

### Dependency Graph

```
spec ──────────────────────────────────────┐
  │                                        │
  ▼                                        │
acceptance-test ── contract-test           │
  │                    │                   │
  ▼                    ▼                   │
domain ─────────────► service ◄────────────┘
  │                    │
  ▼                    ▼
repository ─────────► controller
  │                    │
  ▼                    ▼
tests ──────────────► verification
```

### Parallel Execution Opportunities

| Phase | Parallel Tasks |
|-------|---------------|
| Research | Spec review ║ Code exploration |
| Tests | Acceptance ║ Contract tests |
| Implementation | Domain ║ DTOs |
| Verification | Tests ║ SpotBugs ║ Checkstyle |

---

## Phase 5: Execute

**Goal:** Implement following the plan.

### Execution Order

1. **Spec first** — always
2. **Tests second** — must fail
3. **Implementation** — make tests pass
4. **Verification** — all checks pass

### Checkpoints

After each phase, verify:
- [ ] Phase deliverables complete
- [ ] Tests pass (where applicable)
- [ ] No blockers for next phase

---

## Reasoning Template

For complex decisions, use this structure:

```markdown
## Decision: <What needs to be decided>

### Context
<Background and constraints>

### Options

#### Option A: <Name>
- Pros: <list>
- Cons: <list>
- Effort: <estimate>

#### Option B: <Name>
- Pros: <list>
- Cons: <list>
- Effort: <estimate>

### Recommendation
<Chosen option and why>

### Implications
- <Impact 1>
- <Impact 2>
```

---

## Planning Checklist

Before starting execution:
- [ ] Requirements clearly understood
- [ ] Scope defined (in/out)
- [ ] Existing patterns researched
- [ ] Spec created/updated
- [ ] Tasks broken down
- [ ] Dependencies identified
- [ ] Parallel opportunities noted
- [ ] Success criteria defined

---

## Anti-Patterns

| Anti-Pattern | Better Approach |
|--------------|-----------------|
| Start coding immediately | Analyze and plan first |
| Plan everything upfront | Plan iteratively |
| Ignore existing patterns | Research before designing |
| Vague task descriptions | Specific, verifiable tasks |
| Sequential everything | Identify parallel opportunities |
| Skip checkpoints | Verify after each phase |
