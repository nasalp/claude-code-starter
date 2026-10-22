---
name: tmux-agent
description: |
  Orchestrator pattern for feature work. (1) Clarify decisions with the user
  and emit a CHECKLIST. (2) Build a plan in 3-agent consensus mode. (3) Hand
  the locked plan + checklist to ONE builder agent running Claude through
  Headroom when setup exported it, otherwise `claude --print
  --output-format=stream-json`, inside a tmux session. (4)
  The builder ticks the checklist as it goes AND attaches PROOF per item;
  the orchestrator audits the same checklist + the live work every N
  minutes against plan, global rules, project rules — runs the red-flag
  scan, reasons over content with its own judgment, gates phase commits on
  proof. (5) Post-build, 3-agent assessor consensus must APPROVE before
  merge — verifying every checklist item's proof. Use whenever the user
  says build / implement / do / create / rework / add and the scope is more
  than a one-liner.
origin: ECC
triggers:
  - "build"
  - "implement"
  - "do this"
  - "create the feature"
  - "rework"
  - "add the page"
  - "ship this feature"
  - "babysit the agent"
  - "watch the builder"
  - "tmux build with audit"
  - "consensus plan then build"
  - "1 builder + 3 reviewers"
---

# tmux-agent

A six-phase orchestration pattern for shipping a feature when:

- The scope is too big to one-shot but too small to fragment into separate PRs.
- Spec → test → impl discipline must hold (no defer-as-done).
- The orchestrator must see what's happening, not wait for a black-box result.
- Final shape must be reviewed by independent eyes before ship.

## Pattern at a glance

```
┌──────────────────────┐
│ PHASE 1 — clarify     │  Orchestrator + USER → lock data-model + UX decisions
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ PHASE 2 — plan-consensus  │  3 fresh CLI agents → 2 codex + 1 claude (when codex
└──────────┬───────────┘     available); orchestrator picks consensus plan or
           │                 surfaces disagreement to USER
           ▼
┌──────────────────────┐
│ PHASE 3 — locked prompt  │  Orchestrator writes the builder prompt with:
└──────────┬───────────┘     - rules + skills the builder reads
           │                 - locked decisions (do NOT re-decide)
           │                 - phase order (commit per phase)
           │                 - banned shortcuts + final-report shape
           ▼
┌──────────────────────┐
│ PHASE 4 — tmux build    │  ONE builder agent, Headroom-wrapped Claude
└──────────┬───────────┘     inside a tmux session named `builder`
           │
           ├─► every 5 min: ORCHESTRATOR AUDIT
           │     - check process alive (`ps`)
           │     - count commits + tail commit messages
           │     - read spec / tests / code being written
           │     - run red-flag scan (stupid-shit detectors)
           │     - reason content vs rules with own judgment
           │     - flag concerns to USER + answer USER questions
           ▼
┌──────────────────────┐
│ PHASE 5 — assessor-consensus │  3 fresh CLI agents review the PR independently.
└──────────┬───────────┘        All three must APPROVE.
           ▼
┌──────────────────────┐
│ PHASE 6 — ship + babysit deploy │  Address EVERY gemini-code-assist finding
└──────────────────────┘            (HARD pre-merge gate), then squash-merge, watch CI on
                                    main, handle approval gate (env-protection OR
                                    trstringer issue), confirm PROD_LIVE to USER.
```

## When to use

Use this skill when the task has ALL of:

- ≥ 5 sub-deliverables (spec, multiple tests, multiple impl files, frontend + backend, etc.).
- A clear "spec → test → impl" path the builder must follow.
- Real risk of an under-supervised agent (a) refusing to start because it sees scope as too big OR (b) shipping the easy 70% with a TODO for the rest.
- The orchestrator session can stay alive for the build's duration (the builder is a child of the orchestrator).

Do NOT use when:

- The task is a one-line fix / typo / config tweak (use direct edit).
- The task is exploratory / "what could we do about X" (use a Plan agent).
- The build must outlive the orchestrator session (use the `schedule` skill + a
  cloud agent instead).

## Files that MUST NEVER be committed

The checklist, the checklist-status, the orchestrator's audit script, the
builder's stream-json output, and the status log are ORCHESTRATION
METADATA. They live OUTSIDE the repo at `/tmp/tmux-agent/$RUN_ID/` and
must never end up in `git add` / `git status` / a commit / a PR.

If you ever feel the urge to write any of these inside the repo:
- DON'T. Use `$RUN_DIR` under `/tmp/tmux-agent/$RUN_ID/`.
- If a previous orchestrator did write them inside the repo, scrub them
  before the build phase starts (`git rm --cached`) AND add to
  `.gitignore` if a future agent might recreate them.
- `git add -A` and `git add .` are BANNED in the builder prompt for this
  reason — the builder commits specific files by name.

## Phase reference

Each phase is its own focused doc under `docs/` (kept small so loading
one phase costs little context). Read the phase doc when you're in that
phase; the index here is the navigation.

| Phase | Doc | One-line |
|---|---|---|
| 0 | [docs/phase-0-run-id.md](docs/phase-0-run-id.md) | Pick `RUN_ID`, create `$RUN_DIR`, spawn audit-cycle backstop Monitor |
| 1 | [docs/phase-1-clarify.md](docs/phase-1-clarify.md) | Lock decisions with the user + emit the CHECKLIST |
| 2 | [docs/phase-2-plan-consensus.md](docs/phase-2-plan-consensus.md) | 3-agent plan consensus — 2 codex + 1 claude (when codex available) before any code. **Runs per work unit, not per session** — see `~/.claude/rules/consensus-plan-per-work-unit.md` |
| 3 | [docs/phase-3-locked-prompt.md](docs/phase-3-locked-prompt.md) | Write the builder prompt with locked decisions |
| 4 | [docs/phase-4-build-audit.md](docs/phase-4-build-audit.md) | tmux build + orchestrator audit every N min |
| 4½ | [docs/phase-4-half-watchers.md](docs/phase-4-half-watchers.md) | 3-watcher adversarial consensus (MANDATORY) + persistent-loop invariant + WARN prepend |
| 5 | [docs/phase-5-assessor-consensus.md](docs/phase-5-assessor-consensus.md) | 3 assessors verify every checklist proof |
| 6 | [docs/phase-6-ship-deploy.md](docs/phase-6-ship-deploy.md) | Address gemini findings (HARD gate) → draft PR / merge → deploy babysit → teardown |
| — | [docs/status-and-anti-patterns.md](docs/status-and-anti-patterns.md) | User status reports + skill-wide anti-patterns |

## Canonical scripts (used across phases)

- `scripts/init-run.sh` — Phase 0 RUN_ID + RUN_DIR + audit-cycle backstop Monitor. Tests: `tests/init-run.bats`.
- `scripts/audit-cycle.sh` — Deterministic per-cycle audit; emits `WARN <category>: <detail>`. Tests: `tests/audit-cycle.bats`.
- `scripts/night-loop.sh` — Unattended FSM driver (issue → build → audit → draft PR). Tests: `tests/night-loop.bats`.
- `scripts/teardown-run.sh` — Kill Monitor, archive `$RUN_DIR`, cleanup worktrees. Tests: `tests/teardown-run.bats`.
- `scripts/orchestration/pre-admin-merge-gate.sh` — Fail-closed pre-merge gate. Tests: `tests/pre-admin-merge-gate.bats`.
- `scripts/launch-builder.sh` — Phase 4 builder launch under tmux. Tests: `tests/launch-builder.bats`.
- `scripts/watcher-loop.sh` — Phase 4½ persistent watcher loop. Tests: `tests/watcher-loop.bats`.
- `docs/phase-watcher-steer.md` — Cooperative STEER channel (V1): `$RUN_DIR/STEER.md`, loop-guard, builder brief. Tests: `tests/watcher-steer.bats`.
- `scripts/check-watchers.sh` — Parent's per-cycle watcher liveness check. Tests: `tests/check-watchers.bats`.
- `scripts/check-codex-available.sh` — Phase 2 codex-CLI probe (2-codex+1-claude vs 3-claude fallback). Tests: `tests/check-codex-available.bats`.
- `scripts/list-gemini-findings.sh` — Phase 6 gemini-code-assist enumeration (inline + PR-level, TSV out, exit 0=found / 1=clean / 2=error). Tests: `tests/list-gemini-findings.bats`.
- `examples/spawn-watcher.sh` — Runnable example of one watcher spawn.

### Mixed-model role-based orchestration (opt-in, backwards compatible)

Claude stays orchestrator/planner/arbitrator; cheaper models (Composer via Cursor
`agent`, Gemini) do building / cheap-watching / reviewing. Config-driven and extensible.
Full guide: `docs/mixed-model-agents.md`; builder tiers: `docs/phase-4-builder-tiers.md`.

- `config/agent-providers.yml` — provider registry (claude, codex, gemini, composer; deepseek/qwen parked). Tests: `tests/agent-providers.bats`.
- `config/agent-routing.yml` — role→provider, consensus, escalation, budget defaults. Tests: `tests/agent-routing.bats`.
- `config/verdict-schemas/{watcher,reviewer}.schema.json` — structured verdict shapes.
- `scripts/agent-spawn.sh` — `agent_spawn <role> <provider|auto> <worktree> <prompt_file>`. Tests: `tests/agent-spawn.bats`.
- `scripts/select-rules.sh` / `scripts/gen-packet.sh` — role-scoped rule selection + packets (rules-block-first cache discipline). Tests: `tests/select-rules.bats`, `tests/gen-packet.bats`.
- `scripts/lib/{agent-providers,agent-routing,agent-budget,cost-ledger,agent-escalation}.sh` — resolver, routing, budget caps, cost ledger, escalation. Tests: matching `tests/*.bats`.
- `scripts/mount-rules-into-worktree.sh` — stage `~/.claude/rules` into a worktree for no-`add-dir` CLIs. Tests: `tests/mount-rules-into-worktree.bats`.
- `scripts/check-cursor-available.sh` / `scripts/install-agent-clis.sh` — Cursor probe + worker-CLI installer. Tests: matching `tests/*.bats`.

Default builder model is now **sonnet** (was opus); `BUILDER_ENGINE`/`BUILDER_MODEL` and
`WATCHER_ENGINE`/`WATCHER_MODEL` opt into other providers. Unset env = historical behavior.

Audit-warning child checks live under `scripts/checks/` (one BATS file each). Per
`~/.claude/rules/audit-warning-loop.md`, they emit WARN lines; non-zero exits are
runtime errors only. Orchestration determinism + GH issue trail:
`~/.claude/rules/orchestration-determinism-and-issue-trail.md`. Event-driven observation
(Monitor per unit + one backstop tick): `~/.claude/rules/event-driven-orchestrator-observation.md`.

All scripts: shellcheck clean (`-x -P SCRIPTDIR`). All tests passing locally.

Headroom note: `setup.sh` exports `HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON` and
`HEADROOM_LOCAL_CLAUDE_PROXY_PORT` through the shell rc wrapper block. The
builder and Claude watcher scripts call that wrapper directly when those
variables are present, so non-interactive tmux commands still route Claude
traffic through Headroom even if `.zshrc`/`.bashrc` functions are not loaded.

## Related skills

- `parallel-cli-sessions` — covers `claude --print` flag ordering, silent
  hangs, smoke testing, lock-files.
- `santa-method` — adversarial verification pattern reusable in Phase 5.
- `gan-style-harness` — Generator/Evaluator pattern (different shape; use
  when there's a continuous critique loop rather than a single sign-off).
- `agent-harness-construction` — agent action-space design.
- `tdd-workflow` — what each phase's tests should look like.
- `pre-ship-checklist` (rules) — the 15-class verdict required at PR time.
- `senior-review-gates` (rules) — the hard reject gates before senior review.
