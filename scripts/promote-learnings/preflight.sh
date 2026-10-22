#!/usr/bin/env bash
#
# scripts/promote-learnings/preflight.sh
#
# Cheap, fail-fast checks before the /promote-learnings command spends any
# agent tokens. Writes WARNING/ERROR lines to stderr and returns one of:
#
#   0 — proceed (preflight passed)
#   1 — abort (env var missing, missing dirs, etc.)
#   2 — no-op (kill switch active, PR already open, no changes since last run)
#
# Usage:
#   scripts/promote-learnings/preflight.sh
#   AI_RULES_REPO=/path/to/ai-rules PROJECTS_ROOT=/path/to/projects \
#     scripts/promote-learnings/preflight.sh
#
# Required env:
#   AI_RULES_REPO   absolute path to ai-rules clone
#   PROJECTS_ROOT   absolute path to folder containing sibling project repos
#
# Optional:
#   GH              path to `gh` binary (default: gh on PATH)

set -uo pipefail

err() { echo "[promote-learnings:preflight] ERROR: $*" >&2; }
note() { echo "[promote-learnings:preflight] $*" >&2; }

# 1) Env vars present
if [[ -z "${AI_RULES_REPO:-}" ]]; then
    err "AI_RULES_REPO is not set."
    err "Export it: export AI_RULES_REPO=/path/to/your/ai-rules"
    exit 1
fi
if [[ -z "${PROJECTS_ROOT:-}" ]]; then
    err "PROJECTS_ROOT is not set."
    err "Export it from the folder containing your project repos: export PROJECTS_ROOT=\$(pwd)"
    exit 1
fi
if [[ ! -d "$AI_RULES_REPO/.claude/rules" ]]; then
    err "AI_RULES_REPO=$AI_RULES_REPO does not look like an ai-rules checkout (missing .claude/rules/)."
    exit 1
fi
if [[ ! -d "$PROJECTS_ROOT" ]]; then
    err "PROJECTS_ROOT=$PROJECTS_ROOT does not exist."
    exit 1
fi

# 2) Kill switch — one-commit disable, no flag wrangling.
if [[ -f "$AI_RULES_REPO/spec/promotion-disabled" ]]; then
    note "Kill switch active: $AI_RULES_REPO/spec/promotion-disabled exists. Exiting cleanly."
    exit 2
fi

# 3) Pending PR — at most one promotion PR open at a time.
GH="${GH:-gh}"
if command -v "$GH" >/dev/null 2>&1; then
    PR_COUNT=$("$GH" -R "$(git -C "$AI_RULES_REPO" config --get remote.origin.url 2>/dev/null \
                          | sed -E 's|.*[:/]([^/]+/[^/.]+)(\.git)?$|\1|')" \
               pr list --label promotion --state open --draft --json number 2>/dev/null \
               | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null) \
              || PR_COUNT=0
    if [[ "${PR_COUNT:-0}" -gt 0 ]]; then
        note "An open draft PR with the [promotion] label already exists. Exiting cleanly."
        exit 2
    fi
fi

# 3.5) Rotate expired rejection-ledger entries before reading it. Cheap and
# idempotent; ensures the ledger's "90-day expiry" promise is enforced by
# code, not by human memory.
ROTATE_SCRIPT="$AI_RULES_REPO/scripts/promote-learnings/rotate-expired-rejections.sh"
if [[ -x "$ROTATE_SCRIPT" ]]; then
    "$ROTATE_SCRIPT" >/dev/null 2>&1 || true
fi

# 4) No-op detection — compare current per-project rule/learning SHAs to the
# last successful run logged in $AI_RULES_REPO/spec/promotion-log/<latest>.md.
LOG_DIR="$AI_RULES_REPO/spec/promotion-log"
LATEST_LOG=""
if [[ -d "$LOG_DIR" ]]; then
    LATEST_LOG=$(ls -1t "$LOG_DIR"/*.md 2>/dev/null | head -1 || echo "")
fi

# Compute a deterministic state hash across all per-project learning/rule
# directories. Uses python3 instead of `realpath --relative-to=` (GNU-only;
# silently produces empty strings on macOS, which made the no-op detection
# unreliable). Each project contributes one line of "<rel-path> <git-sha>"
# to the hash; the entries are sorted so the result is order-stable.
CURRENT_SHA=$(cd "$PROJECTS_ROOT" && python3 -c "
import os, subprocess, hashlib, sys
entries = []
for project in sorted(os.listdir('.')):
    proot = os.path.abspath(project)
    if not os.path.isdir(proot):
        continue
    if not os.path.exists(os.path.join(proot, '.git')):
        continue
    for sub in ('spec/learnings', '.claude/rules'):
        full = os.path.join(proot, sub)
        if not os.path.isdir(full):
            continue
        try:
            top = subprocess.check_output(['git', '-C', proot, 'rev-parse', '--show-toplevel'],
                                          stderr=subprocess.DEVNULL).decode().strip()
            rel = os.path.relpath(full, top)
            sha = subprocess.check_output(['git', '-C', proot, 'log', '-1', '--format=%H', '--', rel],
                                          stderr=subprocess.DEVNULL).decode().strip()
        except Exception:
            sha = ''
        entries.append(f'{project}/{sub} {sha}')
entries.sort()
h = hashlib.sha1('\n'.join(entries).encode()).hexdigest()
sys.stdout.write(h)
" 2>/dev/null)
# Empty string on failure — treat as 'unknown', do not falsely match.
[[ -z "$CURRENT_SHA" ]] && CURRENT_SHA="unknown-$(date -u +%s)"

if [[ -n "$LATEST_LOG" ]]; then
    LAST_SHA=$(grep -E '^state-sha: [a-f0-9]+' "$LATEST_LOG" 2>/dev/null | head -1 | awk '{print $2}' || echo "")
    if [[ -n "$LAST_SHA" ]] && [[ "$LAST_SHA" == "$CURRENT_SHA" ]]; then
        note "No change since last run (state-sha=$LAST_SHA). Exiting cleanly."
        exit 2
    fi
fi

# All preflight checks pass.
echo "STATE_SHA=$CURRENT_SHA"
exit 0
