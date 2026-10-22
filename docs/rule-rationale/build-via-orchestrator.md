# Rationale — build-via-orchestrator.md

## Why this rule exists

Single-agent "I'll just implement it" invocations on multi-file features
produce two recurring failure modes:

1. The agent ships the easy 70% and labels the rest a follow-up — exactly
   what `no-deferred-work.md` forbids, but routinely happens when the
   orchestrator hands off blind.
2. The agent stops mid-PR to ask "should I split this into waves?" — the
   exact failure mode `no-deferred-work.md` warns about in reverse: not
   shipping prose instead of code.

The `tmux-agent` skill encodes the operator's correction:
clarify decisions, plan in consensus, hand off to ONE builder in tmux, audit
the live work against rules every 5 minutes, gate ship on assessor-consensus.
Routing all build-shaped requests through it makes the discipline default.

The audit loop is cheap; an unattended half-built PR is expensive.

## Related

- `~/.claude/skills/tmux-agent/SKILL.md` — the canonical pattern.
- `~/.claude/skills/parallel-cli-sessions` — `claude --print` flag
  ordering and silent-hang prevention used by the skill.
- `~/.claude/rules/no-deferred-work.md` — the rule the pattern enforces.
- `~/.claude/rules/senior-review-gates.md` — what the assessor agents
  check against.
- `~/.claude/rules/pre-ship-checklist.md` — the 15-class verdict required
  before merge in Phase 5.
- `~/.claude/rules/consensus-plan-per-work-unit.md` — the per-work-unit
  Phase 2 refinement.
