# watchers-must-observe-live-tmux.md — Rationale

## Why

The original watcher pattern polled three signals:

1. SHA of the watched branch (changes when builder pushes).
2. Byte count of the builder's `stream-json` stdout file (changes when
   the builder emits more events).
3. `tmux has-session` on the builder session (alive/dead check).

A builder mid-phase that has not yet pushed AND whose `stream-json`
output goes to a file the watcher polls — but whose actual tool calls
(file reads, edits, bash invocations) are visible only on the tmux
pane — would be **invisible to the watcher** during the entire phase.
The watcher would only react after the push, by which point the
problematic edit is already committed.

Operator correction 2026-05-29:

> "the watchers are not auditing the PR, eventually they are — they
> are supposed to connect to tmux of the builder and watch the fuck
> it does on the fly".

The fix: each audit pass `tmux capture-pane -t $BUILDER_SESSION -p -S -500`
into the prompt. The auditing model now sees the same scrollback a
human attaching to the session would see.

## Cross-references

- `~/.claude/skills/tmux-agent/scripts/watcher-loop.sh` — canonical
  implementation.
- `~/.claude/skills/tmux-agent/docs/phase-4-half-watchers.md` — Phase
  4½ overview, references this rule.

## Calibration

This rule was written after an overnight build where three watchers
had been auditing the PR commit-by-commit, oblivious to live builder activity
between commits. The fix is structural: capture the pane every pass,
period.
