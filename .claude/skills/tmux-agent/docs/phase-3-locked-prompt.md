# phase 3 locked prompt

# Phase 3 — the locked builder prompt

The prompt MUST contain:

1. **Override section first**: "The user has APPROVED the full scope. You do
   NOT ask for further approval. You do NOT propose 'sequenced waves' /
   're-scope' framings. You execute. `no-deferred-work.md` forbids deferring
   scope MID-PR; it does NOT forbid executing a pre-approved scope."
2. **Rules and skills the builder reads** (named, not retyped — point at the
   paths).
3. **Locked decisions** in a table (from Phase 1).
3a. **Path to the checklist** (`$RUN_DIR/checklist.md`) AND
    `$RUN_DIR/checklist-status.md` AND the explicit instruction: "after
    each phase, append `✓` or `✗` to each item AND quote the proof-command
    output back to `$RUN_DIR/checklist-status.md`. The orchestrator will
    re-run every PROOF command itself — never claim `✓` you haven't
    proven."
3b. **Run id**: `$RUN_ID` is exported in every shell so the builder also
    uses it for tmpfile naming.
4. **Data model** verbatim (schema DDL, column truth-tables) so the builder
   can't drift.
5. **Phase order with commit-per-phase** so progress is observable in
   `git log` without parsing stream-json.
6. **Banned shortcuts**: `--admin`, `--no-verify`, `@Disabled`,
   `test.skip` / `it.skip` / `describe.skip`, `continue-on-error: true`,
   multi-line comment blocks, deferring scope. Builder MUST run
   `bash .claude/skills/tmux-agent/scripts/pre-push-proof-guard.sh` before
   every `git push`; the guard rejects pushes that lack proof-tail or
   introduce skip-as-progress patterns (see
   `~/.claude/rules/no-deferred-work.md`).
7. **Final report shape** — what the agent must paste verbatim at the end.
8. **Status log requirement**: write `$RUN_DIR/status.log` every 60s
   with `[PHASE_N] msg` and `[HEARTBEAT] still on PHASE_N substep`.

Keep the prompt under 200 lines if you can. Bloat = re-typing the rules =
agent confusion when rules and prompt drift.

## Phase sizing — fewer, fatter phases

**Default formula: `phase_count = ceil(estimate_hours / 4)`** with a hard
ceiling of one phase per logical AC. Fragmenting a single AC into 8
sub-phases is the anti-pattern that bit the 217 run — each sub-phase
incurs RED→GREEN double commits + per-phase verify + watcher pass cost
+ rate-limit window crossings.

Rule of thumb:
- 1-4 hour scope → 1 phase
- 4-12 hour scope → 2-3 phases
- 12-24 hour scope → 3-6 phases
- 24+ hour scope → split into multiple PRs first; do NOT carry >6 phases in one run

If the natural AC count exceeds the phase budget, BUNDLE related ACs
(e.g. all sortable-table ACs in one phase, all link-routing fixes in
one phase). Do NOT split a single AC across phases unless RED→GREEN
forces it (two commits = one phase, not two).

## PR-body ownership — orchestrator-only (no builder edits)

The rule is explicit:

> The **builder** MUST NOT touch the PR body. The brief explicitly
> forbids this; watchers reject if the builder runs `gh pr edit`.
> The **orchestrator** is the single writer of the PR body.

An earlier revision of this doc proposed a "cost-constrained" carve-out
letting the builder run `gh pr edit` directly. The 3-reviewer consensus
on 2026-05-31 rejected that proposal because it contradicts the
proof-of-work contract and creates a corruption surface on session
crash. The orchestrator stays the single writer; cost is managed via
fewer/fatter phases (above), 5-min watcher polling, and provider-quota
isolation — NOT by handing the body to the builder.

If orchestrator cost becomes a binding constraint, the right
response is to reduce phase count or watcher count, not to weaken the
ownership contract.

