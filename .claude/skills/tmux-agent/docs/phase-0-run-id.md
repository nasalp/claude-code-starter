# phase 0 run id

# Phase 0 — pick a run id (multi-tenant safety)

Multiple `tmux-agent` runs can be in flight at once (different features,
different branches). EVERY file the orchestrator and builder write goes
under a per-run directory keyed by a unique id you pick now:

Run `scripts/init-run.sh <feature-slug>`; it emits `RUN_ID` and
`RUN_DIR` to stdout and `mkdir -p`s the directory. Covered by
`tests/init-run.bats`. Override the base dir with
`TMUX_AGENT_TMPDIR=…`.

Every path the rest of this skill references — `checklist.md`,
`checklist-status.md`, `status.log`, `builder.out`, `audit-builder.sh`,
the tmux session name — is namespaced under `$RUN_DIR` or suffixed with
`$RUN_ID` (e.g. tmux session `builder-$RUN_ID`).

This means:
- Two concurrent feature builds NEVER touch each other's files.
- `pkill -f builder-prompt` is a hammer that kills ALL runs; prefer
  `pkill -f "builder-prompt-$RUN_ID"` or kill by PID.
- Status reports show `[RUN $RUN_ID]` so the user knows which build they
  apply to.

When the user asks for status across multiple in-flight runs, list each
`$RUN_ID` and its phase. Don't conflate them.

## Phase 0 prereqs (run these BEFORE Phase 1 on the dispatch target)

The orchestrator MUST verify the following on the host that will run the
builder + watchers (not necessarily its own host — `tmux-agent` can dispatch
to a remote machine):

1. **`tmux -V`** — tmux 3.0+ installed.
2. **`claude --version`** AND **`echo hello | claude --print --model haiku
   --dangerously-skip-permissions`** completes within 60s. If it hangs, fix
   tooling before spawning N agents (per `parallel-cli-sessions.md`).
3. **`gh auth status`** — green for the repo owner. Watcher PR-comment
   posting is gated on this; the wrapper `|| true`'s a broken gh and posts
   silently no-op. If broken, the orchestrator MUST open the PR from a host
   with valid auth before spawning watchers.
4. **`git worktree`** support and a clean filesystem location for each
   agent's worktree (`/tmp/builder-wt`, `/tmp/watcher-wt-<role>`).

## Phase 0 worktree setup (MANDATORY — partner with `tmux-agent-worktree-isolation.md`)

Per [`~/.claude/rules/tmux-agent-worktree-isolation.md`](../../../rules/tmux-agent-worktree-isolation.md),
every agent gets its OWN worktree. Create them now, in Phase 0, before any
agent is spawned:

```bash
cd <project-root>                                 # NON-bare main checkout
BUILD_BRANCH=<build-branch>                       # e.g. feat/prod-readiness
RUN_ID=$(date -u +%Y%m%d-%H%M%S)
PARENT=~/work/agents-${RUN_ID}                    # NOT /tmp — see worktree-isolation rule
mkdir -p "$PARENT"

# Preflight 1: fetch so origin/<branch> exists locally before any `worktree add`.
git fetch origin "$BUILD_BRANCH"

# Preflight 2: if the main repo has <build-branch> currently checked out,
# `git worktree add <path> <build-branch>` will fail with "already checked out".
# Switch the main repo to a side branch first.
if [ "$(git symbolic-ref --short HEAD 2>/dev/null)" = "$BUILD_BRANCH" ]; then
  git checkout main   # or any branch that is NOT the build branch
fi

# Builder worktree — checked out to the build branch (writes + commits + pushes here)
git worktree add "$PARENT/builder-wt" "$BUILD_BRANCH"

# Watcher worktrees — DETACHED, tracking origin/<build-branch>
for role in <role-1> <role-2> <role-3>; do
  git worktree add --detach "$PARENT/watcher-wt-${role}" "origin/${BUILD_BRANCH}"
done

git worktree list   # verify the 4 new entries
```

Builder brief MUST cite `$PARENT/builder-wt` as its working dir and
forbid touching the main checkout. Each watcher brief MUST cite its own
`$PARENT/watcher-wt-<role>` and use `git fetch origin && git reset --hard
origin/<branch> && git clean -fdx` (NEVER `git checkout`) to refresh per
pass. The `git clean -fdx` ensures untracked artifacts from a prior pass
don't poison the next one.

## Phase 0 pre-spawn smoke (MANDATORY)

Before spawning the full builder + N watchers fleet, run ONE watcher pass
against ONE worktree and verify:

1. The watcher's verdict file at `$RUN_DIR/verdicts-<role>/pass-*.md` is
   non-empty (proves claude + tools work).
2. `git -C /tmp/builder-wt reflog -10` shows NO `reset:` or `checkout:`
   lines triggered by the smoke watcher.
3. The builder's working tree on the build branch is byte-unchanged.

If any of (1)-(3) fails, fix the dispatch (most likely a worktree-collision
bug) BEFORE spawning the full set. Catching a worktree-isolation bug here
costs ~3 minutes; catching it after spawning 4 agents costs 30+ minutes of
corrupted commits + a full kill-and-respawn cycle.

## Phase 0 pre-flight verify-like-ci (MANDATORY HARD BARRIER)

Before spawning Phase 4 builder, run the project's canonical local
verification gate (`scripts/verify-like-ci.sh` or equivalent) against the
**baseline branch** the build will fork from (typically `main`). If it
fails, the builder inherits a red baseline and burns multiple phases
chasing failures the operator could have surfaced in minutes.

**Hard barrier — Phase 4 launch is FORBIDDEN until preflight has exited
0 with the success marker captured in `$RUN_DIR/preflight-verify.log`.**
You may run preflight in parallel with Phase 2 plan-consensus to amortise
wall-clock, but the orchestrator MUST `wait` on the PID before spawning
builder/watchers.

```bash
cd "$PARENT/builder-wt"
bash scripts/verify-like-ci.sh > "$RUN_DIR/preflight-verify.log" 2>&1 &
PREFLIGHT_PID=$!

# … run Phase 2 plan-consensus while preflight runs …

# Phase 4 barrier — block until preflight exits AND succeeds
wait "$PREFLIGHT_PID"
PREFLIGHT_RC=$?
if [[ $PREFLIGHT_RC -ne 0 ]]; then
  echo "PREFLIGHT FAILED rc=$PREFLIGHT_RC — see $RUN_DIR/preflight-verify.log" >&2
  exit 1
fi
grep -qE "BUILD SUCCESS|Tests run: [0-9]+, Failures: 0|Test Files .* passed" \
  "$RUN_DIR/preflight-verify.log" || {
    echo "PREFLIGHT log lacks canonical success marker — see $RUN_DIR/preflight-verify.log" >&2
    exit 1
  }
```

If pre-flight FAILS:
- Stop the run.
- Open a separate PR fixing `main` first.
- Restart this run from Phase 0 once the baseline is green.

The hard-barrier wording (was previously `nohup … &` advice without the
`wait`) was tightened 2026-05-31 per the 3-reviewer consensus: a
background process the orchestrator never joins is the same defect class
as the D8 "didn't run verify before pushing" gap this section closes.

