# Watchers MUST Observe Builder's Live tmux Pane

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

Watcher in tmux-agent run MUST consume builder's **live tmux pane** (`tmux capture-pane -t <builder-session> -p -S -500`) every audit pass, not just builder stdout file + pushed git SHA. Watcher only reacting to commit pushes audits past, not present.

Applies to every watcher spawn pattern in fleet:

- Canonical `~/.claude/skills/tmux-agent/scripts/watcher-loop.sh` loop (`_run_audit_pass` MUST capture pane + include in audit `claude --print` prompt).
- Any hand-rolled wrapper w/ different schedule (still MUST `tmux capture-pane` per pass).
- Any watcher brief — MUST instruct auditing model: "live pane snapshot appended below; treat as authoritative view of what builder doing right now".

## Default engine split: 2 codex + 1 claude per 3-watcher run

tmux-agent build spawning 3 watchers → operator calibrated default **2 codex + 1 claude opus**:

- **Codex (OpenAI)** cheaper per audit pass than Claude Opus at equivalent quality on diff-review + rule-compliance audits. Two codex watchers cover scope + style + diff shape at low cost.
- **Claude Opus** retained for one watcher (typically "rules" watcher) — catches subtler architecture + rule-violation drift codex underweights (hexagonal boundaries, package-private defaults, "deferred-as-done" framing in commit messages).

Configure via `WATCHER_ENGINE` env var per watcher:

```bash
# rules watcher (Claude Opus — keep this one on Opus)
WATCHER_ENGINE=claude WATCHER_MODEL=opus \
  bash scripts/watcher-loop.sh ... &

# scope + fe-parity watchers (codex)
WATCHER_ENGINE=codex \
  bash scripts/watcher-loop.sh ... &

WATCHER_ENGINE=codex \
  bash scripts/watcher-loop.sh ... &
```

Non-standard split (1 codex + 2 claude, all-codex, all-claude) → orchestrator MUST document split in PR body orchestration log so resuming session knows what was running.

## What is required

### 1. `watcher-loop.sh` `_run_audit_pass` captures pane

Function MUST:

1. Read `BUILDER_SESSION` from environment.
2. If session capturable, append fenced code block tagged `LIVE BUILDER TMUX PANE (last 500 lines)` to brief content.
3. Pass combined content to `claude --print` via stdin.
4. Always clean up temp file holding combined prompt.

When session gone (drain phase), block MUST explicitly say "tmux session not capturable" so auditor knows reasoning from committed state alone.

### 2. Watcher briefs reference live pane

Every watcher brief MUST include one paragraph:

> "The LIVE BUILDER TMUX PANE block at the end of this brief is the
> authoritative view of what the builder is doing right now. Read it
> alongside the latest pushed commit. If the pane shows the builder
> about to do something forbidden (write a TODO, add a suppression,
> touch an out-of-scope file), reject NOW rather than waiting for the
> commit."

### 3. Orchestrator MUST NOT skip pane capture for cost

`tmux capture-pane` local-only + free. Audit pass cost dominated by `claude --print` input tokens; 500-line pane snapshot adds at most ~1 KB to prompt. Cost difference nil; visibility difference = entire point of watcher.

## What is forbidden

| Pattern | Why |
|---|---|
| Watcher loop only polling SHA + file size | Misses everything between commits |
| `_run_audit_pass` not capturing pane | Same |
| Watcher brief saying "audit the diff" without pointing to pane block | Auditor has no view of in-flight work |
| Disabling pane capture "to save tokens" | Tokens not bottleneck; visibility is |

## Enforcement

- `tests/watcher-loop.bats` in tmux-agent skill MUST include test asserting `_run_audit_pass` either reads `BUILDER_SESSION` + attempts `tmux capture-pane`, or fails build. (Added same change introducing this rule.)
- Code review on `tmux-agent` skill changes rejects any `_run_audit_pass` bypassing pane capture.
- Any new watcher script outside canonical pattern MUST reference this rule in header comment + demonstrate pane-capture step.

> Rationale (Why/Cross-references/Calibration): `docs/rule-rationale/watchers-must-observe-live-tmux.md`
