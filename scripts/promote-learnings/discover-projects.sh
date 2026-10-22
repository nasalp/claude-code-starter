#!/usr/bin/env bash
#
# scripts/promote-learnings/discover-projects.sh
#
# Print one project repo path per line on stdout. A project repo qualifies if:
#   - It is a directory under $PROJECTS_ROOT (top-level only, depth 1).
#   - It contains a .git directory (regular checkout) or .git file (worktree).
#   - It contains either spec/learnings/ or .claude/rules/ (or both).
#
# Excludes the ai-rules checkout itself ($AI_RULES_REPO) so the harness does
# not ingest its own canonical rules as "learnings to promote."
#
# Usage:
#   PROJECTS_ROOT=/path/to/projects scripts/promote-learnings/discover-projects.sh
#
# Optional:
#   ONLY=<repo-name>   only include the named repo (basename match)

set -uo pipefail

if [[ -z "${PROJECTS_ROOT:-}" ]]; then
    echo "[discover-projects] ERROR: PROJECTS_ROOT is not set." >&2
    exit 1
fi
if [[ ! -d "$PROJECTS_ROOT" ]]; then
    echo "[discover-projects] ERROR: PROJECTS_ROOT=$PROJECTS_ROOT does not exist." >&2
    exit 1
fi

AI_RULES_ABS=""
if [[ -n "${AI_RULES_REPO:-}" ]] && [[ -d "$AI_RULES_REPO" ]]; then
    AI_RULES_ABS=$(cd "$AI_RULES_REPO" 2>/dev/null && pwd)
fi

ONLY_FILTER="${ONLY:-}"

shopt -s nullglob 2>/dev/null || true
for d in "$PROJECTS_ROOT"/*/; do
    repo=${d%/}
    base=$(basename "$repo")

    # Filter
    if [[ -n "$ONLY_FILTER" ]] && [[ "$base" != "$ONLY_FILTER" ]]; then
        continue
    fi

    # Skip ai-rules itself
    if [[ -n "$AI_RULES_ABS" ]]; then
        repo_abs=$(cd "$repo" 2>/dev/null && pwd)
        if [[ "$repo_abs" == "$AI_RULES_ABS" ]]; then
            continue
        fi
    fi

    # Must be a git repo (.git can be dir or file)
    if [[ ! -e "$repo/.git" ]]; then
        continue
    fi

    # Skip git worktrees: .git is a regular file pointing at the main repo's
    # .git/worktrees/<name>. Worktrees share history with their main checkout,
    # so counting them as independent projects would fake convergence — the
    # same learning would appear in two "projects" that are really one repo.
    # The main checkout is scanned via its own top-level entry.
    if [[ -f "$repo/.git" ]]; then
        continue
    fi

    # Must have at least one of spec/learnings/ or .claude/rules/
    if [[ -d "$repo/spec/learnings" ]] || [[ -d "$repo/.claude/rules" ]]; then
        echo "$repo"
    fi
done
