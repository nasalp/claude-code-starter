# Rationale — event-driven-orchestrator-observation.md

## Relationship to the continuous-watcher rules

`watchers-must-observe-live-tmux.md` governs the
**dedicated watcher agents** (when a build runs them): those persistently read the live
pane and emit verdicts. This rule governs the **orchestrator's own attention cadence**:
event-driven, not poll-driven. A build may run with full live watchers, OR (cheaper) with
the orchestrator's event-driven observation + a Phase-5 assessor-consensus gate as the
catch point. Calibration data so far is that the event-driven +
assessor-consensus model caught 100% of defects at completion (blank-screenshot proof,
static-presented-as-real data, broken-main static-analysis, arch-boundary breach,
entity-id-codec 404, a behavior regression) with no continuous live-pane polling — at a
fraction of the token cost.

## Cross-references

- `~/.claude/skills/tmux-agent/SKILL.md` — Phase 4 audit cadence; this rule is the
  orchestrator-attention model for it.
- `~/.claude/rules/watchers-must-observe-live-tmux.md` — live-pane watchers; this rule is
  why the *orchestrator* need not also tail panes.
- `~/.claude/rules/parallel-cli-sessions.md` — spawning the units this rule observes.
- `~/.claude/rules/common/proof-of-work.md` — the "verify durable state, not the EXIT
  claim" clause is proof-of-work applied to completion signals.
