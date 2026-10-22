# phase 2 plan consensus

# Phase 2 — plan-consensus (3 fresh agents, 2 codex + 1 claude)

Spawn 3 independent CLI agents. **Each gets the SAME briefing** (mission,
clarified decisions, rules + skills to read). Each produces an
independent plan (phase order, file list, test list, risks). The
orchestrator picks the consensus plan, or surfaces disagreement to the
USER.

## Composition: 2 codex + 1 claude (REQUIRED when codex is available)

| # | Engine | Model | Why |
|---|---|---|---|
| 1 | `codex exec` (OpenAI) | default | Non-Anthropic perspective; cheaper than Opus at comparable plan quality |
| 2 | `codex exec` (OpenAI) | default | Independence — same engine, fresh process, no shared scratchpad |
| 3 | `claude --print` | opus | Catches subtler architecture / rule-violation drift that codex underweights |

**Why 2 codex + 1 claude (not 3 claude):**

- The orchestrator IS already a claude. Adding three more claude voices
  in Phase 2 amplifies single-family blindness — they share training
  data, biases, and idiom preferences.
- Codex (OpenAI) is materially cheaper per plan-generation pass than
  Opus at equivalent plan quality on hexagonal-architecture +
  test-strategy work.
- One Opus is retained because Opus catches subtler architecture and
  rule-violation drift that codex consistently underweights (esp.
  hexagonal boundaries, package-private defaults, deferred-as-done
  framing). Dropping it to 0 has measurably hurt plan quality in past
  runs.

This mirrors the Phase 4½ watcher split documented in
`.claude/rules/watchers-must-observe-live-tmux.md` — the same
reasoning applies to plan generation.

## Codex availability check (REQUIRED before spawn)

Before launching any agents, verify codex is installed. Use the
canonical script (BATS-covered, shellcheck-clean):

```bash
if scripts/check-codex-available.sh; then
  CODEX_AVAILABLE=1
else
  CODEX_AVAILABLE=0
fi
```

The script prints two lines to stdout:

```
AVAILABLE codex on PATH at /opt/homebrew/bin/codex
ACTION spawn 2 codex + 1 claude opus for Phase 2 plan-consensus
```

or:

```
MISSING codex CLI not installed
ACTION fallback to 3 claude opus with sharply different brief framings; install codex: https://github.com/openai/codex-cli
```

Exit code 0 = available, 1 = missing. See
`scripts/check-codex-available.sh` and `tests/check-codex-available.bats`.

**If codex IS available** (`CODEX_AVAILABLE=1`): spawn 2 codex + 1 claude
as in the table above.

**If codex is NOT available** (`CODEX_AVAILABLE=0`): fall back to 3
claude opus with **sharply different brief framings** (otherwise they
converge). The framings:

- **planner-1**: "Plan as if you must minimize PR surface area."
- **planner-2**: "Plan as if you must minimize test coverage gaps."
- **planner-3**: "Plan as if you must minimize risk of breaking main."

Do NOT fall back silently. Tell the user codex was missing and you ran
3-claude. Mention plan-diversity is degraded.

## Spawn flags

Use `parallel-cli-sessions` skill conventions:

### claude --print

```bash
# The variadic --tools eats the first positional arg, so pipe the prompt
# via stdin (cleanest) instead of passing it as a positional.
unset GH_TOKEN
printf '%s\n' "$PROMPT" | claude --print \
  --model opus \
  --tools default \
  --permission-mode bypassPermissions \
  --add-dir "$REPO" \
  --add-dir "$HOME/.claude" \
  > "$PLAN_OUT" 2>&1
```

### codex exec

```bash
unset GH_TOKEN
printf '%s\n' "$PROMPT" | codex exec \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  -C "$REPO" \
  --add-dir "$HOME/.claude" \
  - > "$PLAN_OUT" 2>&1
```

The trailing `-` tells codex to read the prompt from stdin.

## Smoke test ONE agent first

Before launching all three, smoke-test the FIRST agent end-to-end:

1. Spawn agent #1 with the real briefing.
2. Wait for completion (or 10-min timeout).
3. Inspect the plan output for: (a) non-empty, (b) addresses the
   clarified decisions, (c) cites file paths from the actual repo.

If the smoke test fails (empty output, plan ignores the briefing, plan
talks about files that don't exist), fix the briefing or flag mismatch
BEFORE burning budget on 2 more agents.

This catches the common failure modes early:
- Flag misordering (`--tools default` eating the positional prompt).
- Stale `GH_TOKEN` env var causing auth errors.
- Wrong `--add-dir` path so the agent can't read project rules.
- The agent timing out because the briefing is too vague.

## Comparing the three plans

Compare on these axes:

| Axis | Agreement = consensus | Disagreement = surface to USER |
|---|---|---|
| Phase order | Same N phases in same order | Different phase decomposition |
| Test layering | Same test pyramid (unit/IT/E2E ratios) | One says "all IT", others say "mostly unit" |
| File list | Overlapping ~80%+ on files touched | Wildly different scope |
| Public surface | Same proposed public API | Different boundaries |
| Risk register | Same top-3 risks | Different fundamental concerns |

**If they agree on phase order AND test layering**, that's your locked
plan — pick the one with the most file-level detail and use it.

**If they disagree on something structural** (e.g. "one PR" vs "three
PRs", or "WebMVC" vs "WebFlux"), surface the disagreement to the USER
with the trade-offs and let the USER pick.

## Do NOT have the orchestrator write the "third plan"

The orchestrator shares biases with the conversation context (it
already knows the user's preferred file structure, idioms, prior
decisions). Its plan would converge with whichever agent it sympathizes
with. The agents must be FRESH (`--print` mode = fresh context per run).

## When to re-run Phase 2 — per work unit, not per session

Phase 2 is NOT a once-per-session event. It runs at the start of
**every work unit** the orchestrator handles. See
`~/.claude/rules/consensus-plan-per-work-unit.md` for the full
definition.

Triggers that REQUIRE a fresh Phase 2:

- A new feature kickoff in the same tmux session ("now let's build
  X", "next chunk: Y").
- A new branch cut from main for a different feature than the one
  in flight.
- A new PR scope (different AC IDs, different bounded context) even
  if the previous chunk's PR is still open.
- A scope expansion of an in-flight PR beyond the originally-planned
  file set.
- A scope re-orientation triggered by a discovered constraint
.
- The session resumes after reboot / context-compact / multi-hour
  gap — the in-memory plan is gone; re-plan from PR body + git
  state.

Each Phase 2 run produces a fresh plan-of-work doc committed at
`docs/plans/<YYYY-MM-DD>-<work-unit-slug>.md`. That file is the PR
body's source of truth and the session-resume substrate. The
orchestrator's response that opens the work unit MUST explicitly
either (a) say "starting Phase 2 for work unit <name>" or (b) cite
the existing plan-of-work this work falls under.

A FAN-OUT analysis ("5 parallel agents map the AC → test landscape")
is a legitimate INPUT to Phase 2 — it's a deep Phase 1, not Phase 2
itself. Phase 2 is specifically 3 fresh agents producing independent
END-TO-END plans, with the orchestrator picking consensus or
surfacing disagreement.
