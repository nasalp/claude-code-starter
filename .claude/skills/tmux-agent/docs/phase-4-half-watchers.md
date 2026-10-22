# phase 4 half watchers

## Phase 4½ — 3-watcher adversarial consensus (MANDATORY)

The parent orchestrator MUST spawn **three independent watcher agents**
alongside the builder. This is NOT optional. A single cohost can
hallucinate, miss things, or share the parent's biases. THREE
independent watchers with two different model families catch what one
misses.

**Why mandatory, not optional:**

Earlier versions of this skill made the cohost optional. In practice
the parent orchestrator kept forgetting to spawn it on multi-item
builds, and shipped PRs that the cohost would have caught (PITest gate
miss, dropped frontend tests, "fixed it forward" workarounds passed
off as done). The user's correction was direct: *"we need 3 adversarial
tmux watchers, 2 codex and 1 claude — because you're so stupid that
you forget to do this. When it's written in a skill most probably you
will do it."*

So this is now the default. The parent does NOT decide per-run whether
to spawn watchers. The parent spawns them. The only exception is
single-file one-line fixes (then skip the whole skill).

**Composition (3 watchers):**

| Watcher | Model | tmux session | Audit file |
|---|---|---|---|
| `watcher-1` | `codex exec` (OpenAI) | `watch1-$RUN_ID` | `$RUN_DIR/watch1.md` |
| `watcher-2` | `codex exec` (OpenAI) — DIFFERENT brief framing | `watch2-$RUN_ID` | `$RUN_DIR/watch2.md` |
| `watcher-3` | `claude --print` fresh context (Anthropic) | `watch3-$RUN_ID` | `$RUN_DIR/watch3.md` |

Two codex + one claude on purpose: the parent IS already a claude, so
adding two non-Anthropic voices gives the most independent perspective.
If codex isn't installed, fall back to `gemini exec` or another
`claude --print` (with a sharply different brief framing).

**Each watcher gets a DIFFERENT brief framing** so they don't
all-converge on the same false positive / false negative:

- **watcher-1: spec-conformance auditor.** "Did the builder do EXACTLY
  what the plan/checklist says? Item by item. Status: DONE / PARTIAL /
  NOT_STARTED / WRONG. Quote file:line evidence per item."
- **watcher-2: anti-pattern detective.** "Look for shortcuts: dropped
  tests, weakened assertions, raised caps, @Disabled, @SuppressWarnings,
  continue-on-error, deleted files that were RED before. Flag every one
  with file:line."
- **watcher-3: scope-creep & rules-compliance.** "Did the builder add
  any public type beyond the approved list? Add any new dependency?
  Touch unrelated files? Modify CI workflows? Add @SuppressFBWarnings?
  Quote evidence per finding."

All three are PASSIVE: read-only mode (`--sandbox read-only` for
codex), no writes to the worktree, no talking to the builder, no
running mvn/npm. They produce structured verdicts to their
respective files.

**Cadence:**

- **Watchers**: every 5 minutes (default; pass `300` as 8th positional
  arg to `watcher-loop.sh` or set `WATCHER_POLL_SECONDS=300`). Each
  watcher pass costs ~$0.05 of LLM call; 5-min cadence is the sweet
  spot for cost vs detection latency.
- **Parent**: every 1 minute, reads the 3 verdict files. Reading local
  files is a **zero-cost** operation (no LLM call), so the parent
  doesn't need to wait for the watcher cadence — it picks up new
  verdicts within ≤1 min of the watcher writing them. This also
  eliminates the race window where the parent could check immediately
  before the watchers write.

Earlier defaults of 1-3 minutes for watchers were calibrated for
fast-iteration phases; in practice most passes return identical
"REJECT, build in flight" verdicts because the builder is mid-edit
between commits. 300s keeps detection latency aligned with phase
commit boundaries (a phase commit per ~5-15 min) while cutting watcher
API cost ~5× and freeing the shared org quota for the builder.

Why a 1-min parent poll:
parent polling 5-min would have created up-to-5-min race delays AND
detection latency for verdicts written by watchers near the start of
the parent's window. Zero-cost file reads should run at whatever
cadence the parent finds useful; the LLM-call cost only applies to
the watcher pass.

**Cache-guard (watcher-side, since 2026-05-31):** even at 5-min poll,
the watcher's `_should_audit` cache-guard now SKIPS the LLM call when
`branch_sha` is unchanged AND `builder.out` grew by <2KiB since last
audit AND <15min has passed since last audit. The result: builder
typing slowly between commits no longer triggers an audit every 5min;
the audit fires on commit boundaries (always) or after meaningful
activity. Tunable via `WATCHER_MIN_DELTA_BYTES` and
`WATCHER_MAX_QUIET_SECONDS`.

If a particular phase is genuinely fast-iteration (e.g. a rename refactor
where 6 commits land in 3 min), drop to `WATCHER_POLL_SECONDS=120` for
that run only. Do NOT make it the default.

## Watcher count — 1 default, 3 for high-stakes audit (2026-05-31)

The 3-watcher fleet above is the **opt-in mode** for high-stakes
audit runs (production-readiness, security review, compliance
backlog closure). For routine multi-phase feature work the default
is **ONE combined watcher** running the merged
`spec-conformance + anti-pattern + scope-creep` brief.

The 2026-05-31 3-reviewer consensus (codex-1, codex-2, claude-opus)
unanimously flagged the mandatory 3-watcher fleet as overcooked for
small finding lists: most passes return identical "REJECT, build in
flight" verdicts and the consensus tabulation overhead doesn't pay
back below ~5 finding-class items.

Heuristic:

| Run shape | Watcher count |
|---|---|
| Single-PR feature with <5 ACs | 1 (combined brief) |
| Multi-phase feature with 5-15 ACs | 1 (combined brief) |
| Audit backlog closure / production-readiness | 3 (split briefs above) |
| Compliance / security review with >15 findings | 3 (split briefs above) |
| Single-line bug fix | 0 (skip skill entirely) |

The 3-watcher block above remains the canonical pattern for
audit-shaped runs. For other shapes, spawn ONE watcher with the
combined brief (`templates/watcher-brief-combined.md`).

## CRITICAL: watchers MUST be wrapped in a persistent shell loop

`claude --print` and `codex exec` are ONE-SHOT processes. They run
once, write their verdict, and exit. If the parent orchestrator
spawns them inside a `tmux new-session "claude --print ..."` and
walks away, the watcher dies after the FIRST baseline pass and
silently misses every subsequent commit. The parent then thinks the
watcher is "watching" when in fact it's a dead session producing
nothing.

Failure mode this prevents: rules-auditor approved
the baseline commit `0511c8d`, exited, and was never re-launched.
The builder pushed three more commits (sidebar submenu, combobox,
backend extension) — all unaudited until the operator caught it.

**The fix is structural, not a reminder.** Every watcher tmux
session MUST run a shell loop that:

1. Polls every 60s for new builder activity (new commits on the
   branch, OR new bytes appended to `$RUN_DIR/builder.out`).
2. When new activity is detected, fires a fresh Headroom-wrapped Claude
   pass when setup exported the wrapper env (or `codex exec`) with the
   current branch state.
3. Writes the verdict to the watcher's verdict file.
4. Posts the verdict as a PR review comment if a PR exists.
5. Loops forever, or until the builder process exits AND there has
   been no new activity for ≥ 5 minutes (drain window).

**Canonical wrapper:** `scripts/watcher-loop.sh` in this skill —
function-decomposed, `shellcheck -x -P SCRIPTDIR` clean, covered by
BATS at `tests/watcher-loop.bats`. Do NOT hand-roll an inline variant;
use this one.

Spawn pattern: see `examples/spawn-watcher.sh`. It launches one
`watcher-loop.sh` inside `tmux new-session -d -s watch-<TAG>-<RUN_ID>`
and explicitly passes the Headroom wrapper env into the tmux command
when available. Repeat per watcher tag (scroll, rules, fe-parity,
be-parity, …).

Positional arguments:

| # | Name | Meaning |
|---|---|---|
| 1 | `REPO` | path to the worktree the watcher reads (no writes) |
| 2 | `BRANCH` | branch under audit |
| 3 | `PR_REPO` | `owner/repo` for `gh` PR comment posting |
| 4 | `BUILDER_OUT` | path to the builder's `stream-json` output file |
| 5 | `BRIEF` | the watcher brief (passed as stdin to `claude --print`) |
| 6 | `VERDICT_DIR` | directory; each pass writes `pass-<UTC>.md` |
| 7 | `INTERVAL` | optional poll seconds, default 60 |

Drain threshold: `WATCHER_DRAIN_SECONDS` env, default 300s.

Function shape (see the script for full source):

- `_now_ts` — compact UTC stamp.
- `_resolve_branch_sha REF` — `git fetch` + `git rev-parse`; empty on fail.
- `_file_size PATH` — byte count; 0 if missing; macOS + Linux portable.
- `_activity_detected SHA LAST_SHA SIZE LAST_SIZE` — fires on commit OR growth.
- `_builder_alive BRANCH` — `pgrep` for builder process.
- `_drain_elapsed QUIET_SINCE THRESHOLD` — true when builder gone for long enough.
- `_run_audit_pass REPO BRIEF VERDICT` — one Headroom-wrapped Claude
  execution when available, else raw `claude --print`.
- `_post_pr_comment PR_REPO BRANCH VERDICT` — no-op if no PR yet.
- `watcher_loop_main` — composes the above into the polling loop.

**Anti-patterns specifically banned:**

- `tmux new-session -d -s watch "claude --print ... < brief.md"`
  with no loop. This is the dead-watcher pattern. NEVER spawn a
  watcher this way.
- Briefs that include a `while true; do … done` block expecting
  the agent to loop. The agent will read the loop as instructions
  but cannot actually loop; it processes the brief once and exits.
  The loop MUST be in the shell wrapper, not in the prompt.
- Parent `ScheduleWakeup` on a 4-minute cadence to "remind itself"
  to re-spawn watchers. That couples the watcher cadence to the
  parent's attention, which is exactly the failure mode this rule
  exists to prevent.
- A single `Monitor` armed to "watch the watcher" without
  re-spawning logic. Monitor surfaces events; it does not re-launch
  dead processes.

The parent orchestrator MUST follow this.

**Parent's consensus role:**

On every parent audit cycle:

1. Read all three watcher files.
2. Compute consensus per item:
   - **3/3 agree** → that's the verdict. Report to user.
   - **2/3 agree** → that's the consensus verdict; note the minority
     view as a watch-item.
   - **1/3 finding** → a SINGLE watcher flagging something is worth
     investigating but not automatically blocking. Spend one audit
     cycle verifying yourself. If you confirm, escalate to user. If
     you can't reproduce, downgrade to "watch" with the watcher name
     attached.
   - **All 3 disagree on the same row** → surface ALL three views to
     user with the conflict, let user decide.
3. The PARENT is the synthesizer. Watchers don't talk to each other;
   they talk to the parent's report file.

**Watchers are NEVER the tiebreaker by themselves. The USER is.**
Watchers prevent single-model blindness; the user decides scope.

**Communication direction:**

```
USER
 │
 ▼
PARENT ORCHESTRATOR ─── reads ──► watch1.md (codex spec)
 │                       reads ──► watch2.md (codex anti-pattern)
 │                       reads ──► watch3.md (claude rules)
 │
 │ launches all four
 │
 ▼
 BUILDER ─── stream-json ──► all three watchers read independently
```

Watchers read the same `$RUN_DIR/builder.out`, `$RUN_DIR/status.log`,
and `$RUN_DIR/checklist-status.md` that the parent reads. None of
them write to the builder's pane.

**Lifecycle:**

- Spawn watchers AFTER builder is confirmed running (avoids watchers
  starting against an empty stream).
- Parent terminates ALL watchers when build completes (single pkill on
  the `watch*-$RUN_ID` tmux sessions) OR when parent decides the
  audit value isn't worth the spend (e.g. final 5 min are cosmetic
  cleanup).

**Why three, not two or five:**

- Two adversarial watchers + parent = 3 voices total. If 2 voices
  share a model family (parent + one watcher both Claude), single-
  family blindness still kills you.
- Five+ watchers don't add proportional value — diminishing returns,
  cost goes up linearly, consensus tabulation gets unwieldy.
- Three with two different model families is the empirical sweet spot.

## When the builder hits a wall

The builder's status log will heartbeat the same phase repeatedly with no
file changes. Three possible causes:

1. **Real blocker** — a build failure the agent can't resolve. Read the
   error from the build output, propose a fix, kill+restart the builder
   with an additional decision locked in.
2. **Agent confusion** — the agent is re-reading rules and arguing with
   itself. Look at the last 2000 chars of text-deltas. If it's stuck in
   "should I do X or Y" prose, send a sharper override prompt in a new
   builder spawn.
3. **Genuine wall** — the agent literally cannot proceed (missing
   credentials, missing artifact, unreachable repo). Escalate to the USER
   with the exact blocker.
