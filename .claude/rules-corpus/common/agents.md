# Agent Orchestration

## CRITICAL: Subagent Context Inheritance

Subagents do NOT inherit parent context, rules, memory, or conversation history. Start blank; only know what prompt tells them.

**Every subagent prompt MUST include:**

1. **Rules preamble**: `IMPORTANT: Read and follow ALL rules from ~/.claude/rules/ — especially ~/.claude/rules/core.md (SPEC → TEST → IMPLEMENT workflow).`
2. **Workflow reminder**: `Follow SPEC → TEST → IMPLEMENT. Write specs before tests. Write tests before production code. Do not skip steps.`
3. **Project context**: which repo, branch, what task is about.
4. **Specific file paths**: not "check the config" — say "read /path/to/config.ts".
5. **Expected output**: what you expect back (verdict, file list, code change).

**When subagent writes code, it MUST:**
- Create or update spec file first
- Write failing tests annotated with `@spec` IDs
- Only then write production code
- PreToolUse hooks (`spec-first-check.sh`, `require-test-first.sh`) BLOCK edits violating this — subagent cannot bypass unless `SPEC_BYPASS=true` set.

**Example subagent prompt (GOOD):**
```
IMPORTANT: Read and follow ALL rules from ~/.claude/rules/ — especially
~/.claude/rules/core.md (SPEC → TEST → IMPLEMENT workflow).

You are a Senior Developer implementing feature X in /home/user/repo.
Branch: feature/my-feature

Follow SPEC → TEST → IMPLEMENT:
1. Write spec at spec/features/my-feature.md
2. Write failing tests at src/my-feature.test.ts
3. Implement at src/my-feature.ts

Read these files first:
- /home/user/repo/spec/features/ (existing specs for context)
- /home/user/repo/src/related-module.ts (existing patterns)
```

**Example subagent prompt (BAD):**
```
Implement feature X. Make sure it works.
```

## Available Agents

Located in `~/.claude/agents/`:

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| planner | Implementation planning | Complex features, refactoring |
| architect | System design | Architectural decisions |
| tdd-guide | Test-driven development | New features, bug fixes |
| code-reviewer | Code review | After writing code |
| pr-reviewer | Pull request review | Before merging PRs |
| security-reviewer | Security analysis | Before commits |
| build-error-resolver | Fix build errors | When build fails |
| e2e-runner | E2E testing | Critical user flows |
| refactor-cleaner | Dead code cleanup | Code maintenance |
| doc-updater | Documentation | Updating docs |

## Immediate Agent Usage

No user prompt needed:
1. Complex feature requests → **planner**
2. Code just written/modified → **code-reviewer**
3. Bug fix or new feature → **tdd-guide**
4. Architectural decision → **architect**

## Parallel Task Execution

ALWAYS use parallel Task execution for independent operations:

```markdown
# GOOD: Parallel execution
Launch 3 agents in parallel:
1. Agent 1: Security analysis of auth module
2. Agent 2: Performance review of cache system
3. Agent 3: Type checking of utilities

# BAD: Sequential when unnecessary
First agent 1, then agent 2, then agent 3
```

## Multi-Perspective Analysis

Complex problems → split-role sub-agents: factual reviewer, senior engineer, security expert, consistency reviewer, redundancy checker.

## Adversarial Review Protocol

Shipping decisions → 3-agent consensus:
1. **Adversarial QA** — tries to break it (boundaries, edge cases, security)
2. **Senior Dev** — code quality, KISS/DRY, spec compliance
3. **Senior DevOps** — observability, resilience, deployability

All 3 must say SHIP IT or list specific blockers. Fix blockers and re-run until consensus.
