#!/usr/bin/env bash
#
# scripts/retract-rule/preflight.sh
#
# Cheap, fail-fast checks before /retract-rule does anything destructive.
#
# Exit codes:
#   0 — all checks passed; the resolved rule path is printed on stdout.
#   1 — abort (missing env, missing reason, ambiguous match, dirty tree).
#   2 — idempotent no-op (file already deprecated).
#
# Usage:
#   AI_RULES_REPO=/path/to/ai-rules \
#     scripts/retract-rule/preflight.sh \
#     --target '<rule-path-or-name>' \
#     --reason '<one-sentence cause>'

set -uo pipefail

err()  { echo "[retract-rule:preflight] ERROR: $*" >&2; }
info() { echo "[retract-rule:preflight] $*" >&2; }

TARGET=""
REASON=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        *) err "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "${AI_RULES_REPO:-}" ]]; then
    err "AI_RULES_REPO is not set."
    err "Export it: export AI_RULES_REPO=/path/to/your/ai-rules"
    exit 1
fi
if [[ ! -d "$AI_RULES_REPO/.claude/rules" ]]; then
    err "AI_RULES_REPO=$AI_RULES_REPO does not look like an ai-rules checkout."
    exit 1
fi
if [[ -z "$TARGET" ]]; then
    err "Missing --target. Provide a rule path or name."
    exit 1
fi
if [[ -z "$REASON" ]]; then
    err "Missing --reason. The rejection ledger requires evidence, not just a removal."
    exit 1
fi

# Resolve the target to an existing rule or skill file.
resolve_target() {
    local t="$1"
    # 1) Direct relative path under AI_RULES_REPO
    if [[ -f "$AI_RULES_REPO/$t" ]]; then
        echo "$t"
        return 0
    fi
    # 2) Bare path under .claude/rules/
    if [[ -f "$AI_RULES_REPO/.claude/rules/$t" ]]; then
        echo ".claude/rules/$t"
        return 0
    fi
    # 3) Filename match anywhere under .claude/rules/ (with or without .md)
    local q="$t"
    [[ "$q" != *.md ]] && q="${q}.md"
    local matches
    matches=$(find "$AI_RULES_REPO/.claude/rules" -type f -name "$(basename "$q")" 2>/dev/null | head -10)
    local count
    count=$(echo -n "$matches" | grep -c .)
    if [[ "$count" -eq 1 ]]; then
        echo "${matches#$AI_RULES_REPO/}"
        return 0
    fi
    if [[ "$count" -gt 1 ]]; then
        err "Ambiguous --target '$t'. Matches:"
        while IFS= read -r m; do err "  ${m#$AI_RULES_REPO/}"; done <<< "$matches"
        err "Specify a relative path under .claude/rules/ to disambiguate."
        return 1
    fi
    # 4) Skill directory match under .claude/skills/
    if [[ -d "$AI_RULES_REPO/.claude/skills/$t" ]]; then
        echo ".claude/skills/$t/SKILL.md"
        return 0
    fi
    err "No rule or skill matches '$t'."
    err "Looked under .claude/rules/ and .claude/skills/."
    return 1
}

REL_PATH=$(resolve_target "$TARGET") || exit 1

# Idempotent no-op: already in _deprecated/.
if echo "$REL_PATH" | grep -q '/_deprecated/'; then
    info "Already deprecated: $REL_PATH. No-op."
    exit 2
fi

# Refuse to run with uncommitted changes.
if [[ -d "$AI_RULES_REPO/.git" ]]; then
    DIRTY=$(git -C "$AI_RULES_REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${DIRTY:-0}" -gt 0 ]]; then
        err "$AI_RULES_REPO has uncommitted changes ($DIRTY entries)."
        err "The retraction trail must land in a single PR. Commit or stash first."
        exit 1
    fi
fi

# Print the resolved path on stdout for the caller.
echo "$REL_PATH"
exit 0
