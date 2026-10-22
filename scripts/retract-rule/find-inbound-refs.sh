#!/usr/bin/env bash
#
# scripts/retract-rule/find-inbound-refs.sh
#
# Print one inbound reference per line in `<file>:<line>: <snippet>` format,
# given a rule or skill name that's about to be retracted. The caller should
# surface this list to the operator (e.g. in the PR body) — these references
# will go stale and may need follow-up edits.
#
# Usage:
#   AI_RULES_REPO=/path scripts/retract-rule/find-inbound-refs.sh \
#     --name '<rule-or-skill-name>'
#
# Exit codes:
#   0 — search ran (output may be empty if no references found)
#   1 — bad args or missing env

set -uo pipefail

err() { echo "[retract-rule:refs] ERROR: $*" >&2; }

NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name) NAME="$2"; shift 2 ;;
        *) err "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "${AI_RULES_REPO:-}" ]]; then
    err "AI_RULES_REPO is not set."
    exit 1
fi
if [[ -z "$NAME" ]]; then
    err "Missing --name."
    exit 1
fi

# Strip extension and any leading directory so "rules/java/foo.md", "foo.md",
# and "foo" all match the same set of references.
BASE=$(basename "$NAME" .md)

# Only search live trees — _deprecated/ is itself the destination of the
# retraction, so references inside it are expected and not actionable.
ROOTS=(
    "$AI_RULES_REPO/.claude/skills"
    "$AI_RULES_REPO/.claude/commands"
    "$AI_RULES_REPO/.claude/agents"
    "$AI_RULES_REPO/.claude/rules"
    "$AI_RULES_REPO/.claude/workflows"
    "$AI_RULES_REPO/docs"
)

for root in "${ROOTS[@]}"; do
    [[ ! -d "$root" ]] && continue
    grep -rn --include='*.md' --include='*.sh' --include='*.json' \
        --exclude-dir='_deprecated' \
        -F "$BASE" "$root" 2>/dev/null \
        | sed "s|^$AI_RULES_REPO/||"
done

exit 0
