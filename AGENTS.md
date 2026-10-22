# AGENTS.md

> Place this file in your home directory (`~/.agents.md` or `~/AGENTS.md`).
> AI coding agents will read this to understand your preferences and workflow.

---

## Workflow Orchestration

### 1. Plan Mode Default

- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy

- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop

- After ANY correction from the user: update [`spec/learnings/`](spec/learnings/) with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review learnings at session start for relevant project
- See [learnings rules](.claude/rules/learnings.md) for format and process

### 4. Verification Before Done

- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)

- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing

- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

---

## Task Management

1. **Plan First:** Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan:** Check in before starting implementation
3. **Track Progress:** Mark items complete as you go
4. **Explain Changes:** High-level summary at each step
5. **Document Results:** Add review section to `tasks/todo.md`
6. **Capture Learnings:** Update [`spec/learnings/`](spec/learnings/) after corrections — see [template](spec/learnings/_template.md)

---

## Core Principles

- **Simplicity First:** Make every change as simple as possible. Impact minimal code.
- **No Laziness:** Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact:** Changes should only touch what's necessary. Avoid introducing bugs.

---

## Rules Reference

| Category | Files |
|----------|-------|
| Core | [Spec-first](.claude/rules/core.md), [Senior review gates](.claude/rules-corpus/senior-review-gates.md), [Exceptions](.claude/rules/exceptions.md), [Learnings](.claude/rules/learnings.md) |
| Every Change | [Security](.claude/rules/security.md), [Performance](.claude/rules/common/performance.md), [Code Style](.claude/rules/common/coding-style.md) |
| Development | [Java/Spring](.claude/rules/java/java-spring.md), [Testing](.claude/rules/testing.md), [Database](.claude/rules/java/database.md) |

## Specs & Knowledge

| Directory | Purpose |
|-----------|---------|
| [`spec/features/`](spec/features/) | Feature specifications (behavior) |
| [`spec/learnings/`](spec/learnings/) | Key findings about the codebase — always keep current |
| [`spec/decisions/`](spec/decisions/) | Architecture Decision Records |
| [`spec/contracts/`](spec/contracts/) | API contracts (OpenAPI) |

## Setup

```bash
./.claude/init/setup.sh
```
