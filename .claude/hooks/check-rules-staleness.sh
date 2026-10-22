#!/usr/bin/env bash
#
# Hook: check-rules-staleness.sh
# Trigger: SessionStart
# Purpose: At session start, surface a one-line warning if the canonical
#          ai-rules `.claude/rules/` directory has not been updated in
#          STALENESS_DAYS (default 14). Without this signal, consumer
#          repos linked via symlink can silently drift behind the
#          canonical harness for weeks.
#
# WARNINGS ONLY. Always exits 0. The agent reads stderr and surfaces it
# to the user as a "consider running git pull on ai-rules" nudge.
#
# Per the harness convention all hooks warn, never block.
#
# Configuration (all optional — sensible defaults computed at runtime):
#   AI_RULES_REPO       — path to the ai-rules checkout. If unset, the hook
#                         tries (in order): ${CLAUDE_PLUGIN_ROOT}, the directory
#                         two levels above this script, then $HOME/.claude.
#                         If none look like an ai-rules checkout, the hook
#                         exits silently (no false warning on machines that
#                         haven't installed ai-rules yet).
#   STALENESS_DAYS      — threshold in days before warning (default: 14).
#   SKIP_STALENESS      — set to "true" to silence the warning entirely.

set -uo pipefail

# Resolve ai-rules location without baking in any single user's layout.
resolve_ai_rules_repo() {
    if [[ -n "${AI_RULES_REPO:-}" ]] && [[ -d "$AI_RULES_REPO/.claude/rules" ]]; then
        echo "$AI_RULES_REPO"
        return
    fi
    # Try the Claude Code plugin root variable.
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && [[ -d "$CLAUDE_PLUGIN_ROOT/.claude/rules" ]]; then
        echo "$CLAUDE_PLUGIN_ROOT"
        return
    fi
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && [[ -d "$CLAUDE_PLUGIN_ROOT/rules" ]]; then
        # Plugin layout where the plugin root IS the .claude tree.
        echo "$(dirname "$CLAUDE_PLUGIN_ROOT")"
        return
    fi
    # Try the directory two levels above this script (typical when this hook
    # lives at <repo>/.claude/hooks/check-rules-staleness.sh).
    local self
    self=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || self=""
    if [[ -n "$self" ]] && [[ -d "$self/../../.claude/rules" ]]; then
        ( cd "$self/../.." && pwd )
        return
    fi
    # User-level Claude Code home as a last resort.
    if [[ -d "$HOME/.claude/rules" ]]; then
        echo "$HOME/.claude"
        return
    fi
    echo ""
}

AI_RULES_REPO=$(resolve_ai_rules_repo)
STALENESS_DAYS="${STALENESS_DAYS:-14}"

# Read JSON input but do not require any fields — the hook makes its own
# decisions. Always pass-through stdout untouched.
INPUT=$(cat 2>/dev/null || echo "{}")

# Escape hatch
if [[ "${SKIP_STALENESS:-false}" == "true" ]]; then
    echo "$INPUT"
    exit 0
fi

# If we couldn't find an ai-rules checkout at all, silently no-op.
if [[ -z "$AI_RULES_REPO" ]]; then
    echo "$INPUT"
    exit 0
fi

# An ai-rules checkout may be either a full git repo or a directly-installed
# .claude tree. Probe both layouts.
RULES_DIR=""
if [[ -d "$AI_RULES_REPO/.claude/rules" ]]; then
    RULES_DIR="$AI_RULES_REPO/.claude/rules"
elif [[ -d "$AI_RULES_REPO/rules" ]]; then
    RULES_DIR="$AI_RULES_REPO/rules"
fi

if [[ -z "$RULES_DIR" ]]; then
    echo "$INPUT"
    exit 0
fi

# Last-touched timestamp of any tracked file under .claude/rules/, in seconds
# since epoch. Falls back to mtime if git is unavailable.
LAST_TOUCH=""
if command -v git >/dev/null 2>&1 && [[ -d "$AI_RULES_REPO/.git" ]]; then
    # Use whichever rules path was probed above (relative to repo root).
    REL_RULES_DIR="${RULES_DIR#$AI_RULES_REPO/}"
    LAST_TOUCH=$(git -C "$AI_RULES_REPO" log -1 --format='%ct' -- "$REL_RULES_DIR" 2>/dev/null || echo "")
fi

if [[ -z "$LAST_TOUCH" ]]; then
    # Fallback: most-recent mtime of any *.md under rules/. `stat -f '%m'`
    # is BSD-only — on GNU systems `-f` is "show filesystem info" which
    # returns multi-line text including an `Inodes:` line that breaks
    # downstream arithmetic. Detect platform to pick the right form.
    case "$(uname -s)" in
        Darwin|*BSD)
            LAST_TOUCH=$(find "$RULES_DIR" -type f -name '*.md' -exec stat -f '%m' {} \; 2>/dev/null \
                         | sort -nr | head -1)
            ;;
        *)
            LAST_TOUCH=$(find "$RULES_DIR" -type f -name '*.md' -printf '%T@\n' 2>/dev/null \
                         | sort -nr | head -1 | cut -d. -f1)
            ;;
    esac
fi

# Validate LAST_TOUCH is a non-empty integer before arithmetic. If the
# fallback emitted anything non-numeric (different `stat` flavor, a
# locale-dependent output, etc.) the downstream `$(( ))` would explode
# under `set -u`. Treat non-numeric as "unknown — silent no-op".
if [[ -z "$LAST_TOUCH" ]] || ! [[ "$LAST_TOUCH" =~ ^[0-9]+$ ]]; then
    echo "$INPUT"
    exit 0
fi

NOW=$(date +%s)
AGE_SEC=$(( NOW - LAST_TOUCH ))
AGE_DAYS=$(( AGE_SEC / 86400 ))

if [[ $AGE_DAYS -gt $STALENESS_DAYS ]]; then
    {
        echo "[rules-staleness] WARNING: $RULES_DIR last changed $AGE_DAYS days ago (threshold: $STALENESS_DAYS)."
        echo "  If this machine has not pulled the ai-rules harness recently, it may be drifted."
        echo "  Run:  ( cd \"$AI_RULES_REPO\" && git pull )"
        echo "  Override:  AI_RULES_REPO=/path/to/your/ai-rules to point at a different checkout."
        echo "  Silence:   set SKIP_STALENESS=true to suppress this warning."
    } >&2
fi

# Always exit 0 — warnings only.
echo "$INPUT"
exit 0
