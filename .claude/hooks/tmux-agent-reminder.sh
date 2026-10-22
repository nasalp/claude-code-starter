#!/usr/bin/env bash
# SessionStart hook — remind the agent to read rules + the tmux-agent skill
# fully whenever the user asks for build/implement/do/create/rework/add work.
# Output goes to stderr per Claude Code hook convention.

cat >&2 <<'MSG'
[tmux-agent reminder] At session start, fully read:
  1. ALL files under ~/.claude/rules/  (global)
  2. ALL files under <project>/.claude/rules/ + <project>/CLAUDE.md (project)
  3. ~/.claude/skills/tmux-agent/SKILL.md — the canonical pattern for
     ANY user message containing "build" / "implement" / "do" / "create" /
     "rework" / "add" / "ship this feature".
On any such request, route through the tmux-agent skill UNLESS the scope
is a one-line fix. Do not shortcut to direct edits for multi-file work.
The skill is FASTER end-to-end than going it alone — the audit loop catches
gaps within minutes instead of at PR review.
MSG
exit 0
