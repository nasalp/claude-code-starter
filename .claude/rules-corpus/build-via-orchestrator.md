# Build via orchestrator

User says "build", "implement", "do", "create", "add", "rework", "fix across N files", "ship this feature", or equivalent non-trivial code work → **agent MUST route through `tmux-agent` skill** unless scope genuinely one-line fix.

**Per-work-unit, not per-session.** Phase 2 plan-consensus runs at start of EVERY new work unit, not just session's first. Long-lived orchestrator ran Phase 2 once and ad-hoc-planned every chunk thereafter = failure mode `consensus-plan-per-work-unit.md` names. In doubt — new feature kickoff, new branch, new PR scope, scope expansion, session resume after compaction — re-run Phase 2.

## What counts as build-shaped

Use skill when request triggers ANY of:

- ≥ 5 sub-deliverables (spec, multiple tests, multiple impl files, frontend + backend, etc.).
- ≥ 2 layers touched (backend + frontend, or DB migration + service + controller).
- New bounded context, new migration, new public API surface, or new user-visible page.
- Entity / column / view refactor across more than one BC.
- Feature needing Spring Cloud Contract + stub-driven tests.
- User-visible deployable change with multiple ACs.

Use skill even when user impatient and says "just do it" — FASTER end-to-end because audit loop catches gaps within minutes instead of at PR review.

## What does NOT need the skill

- Single-line bug fix.
- Typo / copy edit / comment removal.
- Single-config-value change.
- One-method addition with one test where entire diff < 30 LOC.
- Exploratory questions ("what could we do about X?") — answer with plan in conversation, do not spawn agents.

In doubt: use the skill.

## How the agent applies this rule

Every user message: scan for trigger verbs. If matched:

1. Confirm scope clarification questions (Phase 1 of skill).
2. Invoke `tmux-agent` via Skill tool, passing user's original request as `args`.
3. Follow skill's six phases through to PROD_LIVE.

Do NOT write code directly in orchestrator session for multi-file feature. Orchestrator job = clarify, plan, hand off, audit, review — NOT type code.

## Enforcing delegation (mixed-model)

Instruction ≠ enforcement. Three escalating levels keep Claude managing, not implementing:

1. **Rule** (this file) — Claude delegates; relies on model obeying.
2. **Hook** — set `AGENT_ROLE=orchestrator`. `.claude/hooks/orchestrator-no-direct-impl.sh` (PreToolUse Edit|Write) warns when orchestrator edits production source instead of spawning builder. Inert in normal/builder sessions; warn-only.
3. **Structural (strongest)** — deny `Edit`/`Write` for source paths in orchestrator's `.claude/settings.json` → can't implement, only plan, `agent_spawn`, audit. Builders edit in own worktrees.

Ship #2 now; tighten to #3 once trusted. See `docs/mixed-model-agents.md`.

## When the user explicitly opts out

User may say "just do it inline, no agents". Honor it. Document as user override per `~/.claude/rules/exceptions.md`; proceed without audit loop. Override applies to current task only.

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/build-via-orchestrator.md`
