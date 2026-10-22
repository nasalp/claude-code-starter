#!/usr/bin/env bash
# mount-rules-into-worktree.sh <worktree> [rules_dir] [skills_dir]
# Stage the ai-rules tree INTO a build worktree so a CLI with no --add-dir (Cursor
# `agent`) reads the rules in-workspace. Symlinks .cursor/rules + .cursor/skills,
# points AGENTS.md at them, and excludes the symlinks via .git/info/exclude
# (never committed). Idempotent.
set -uo pipefail

wt="${1:-}"
rules="${2:-$HOME/.claude/rules}"
skills="${3:-$HOME/.claude/skills}"
[[ -n "$wt" ]] || { echo "usage: mount-rules-into-worktree.sh <worktree> [rules_dir] [skills_dir]" >&2; exit 2; }
[[ -d "$wt" ]] || { echo "mount: worktree not found: $wt" >&2; exit 2; }

mkdir -p "$wt/.cursor"
ln -sfn "$rules"  "$wt/.cursor/rules"
ln -sfn "$skills" "$wt/.cursor/skills"

# AGENTS.md managed block (idempotent via marker).
if ! grep -q "BEGIN ai-rules mount" "$wt/AGENTS.md" 2>/dev/null; then
  {
    echo "<!-- BEGIN ai-rules mount -->"
    echo "You MUST read and obey ALL rules under ./.cursor/rules/ (a symlink to the"
    echo "ai-rules tree). Skills are under ./.cursor/skills/. A cheaper model is NOT a"
    echo "weaker gate — every rule that binds the premium tier binds you."
    echo "<!-- END ai-rules mount -->"
  } >> "$wt/AGENTS.md"
fi

# Resolve the git common dir (handles both a normal repo and a `git worktree add`
# worktree, where .git is a file pointing at the real gitdir).
gitdir=""
if [[ -d "$wt/.git" ]]; then
  gitdir="$wt/.git"
elif [[ -f "$wt/.git" ]]; then
  gitdir="$(sed -n 's/^gitdir: //p' "$wt/.git" 2>/dev/null)"
  # `git worktree add` may write a relative gitdir — resolve it against the worktree.
  [[ -n "$gitdir" && "$gitdir" != /* ]] && gitdir="$wt/$gitdir"
fi

if [[ -n "$gitdir" && -d "$gitdir" ]]; then
  mkdir -p "$gitdir/info"
  ex="$gitdir/info/exclude"
  local_added=0
  for p in ".cursor/rules" ".cursor/skills"; do
    grep -qxF "$p" "$ex" 2>/dev/null || { echo "$p" >> "$ex"; local_added=1; }
  done
  [[ "$local_added" -eq 1 ]] && echo "mount: excluded .cursor symlinks in $ex" >&2
else
  echo "mount: $wt is not a git worktree — symlinks created, no .git/info/exclude written" >&2
fi

echo "mount: $wt/.cursor/{rules,skills} -> $rules / $skills"
