#!/usr/bin/env bash
#
# scripts/promote-learnings/propose-upstream-patch.sh
#
# Reads the adoption-best results produced by check-adoption.sh and, for
# each (project-rule, upstream-rule) pair, surfaces markdown headings that
# appear ONLY in the project rule. Those sections are candidates for a
# patch PR against the upstream file — the rule already exists upstream but
# the project has accreted project-specific detail (banned profile name
# lists, env-var contract tables, migration playbooks, etc.) that other
# fleet projects would benefit from inheriting.
#
# This is intentionally a *proposal* tool, not an auto-patch tool. It tells
# you what's worth promoting; you decide what wording survives the trip
# upstream. The harness's `/promote-learnings` flow can call this in PATCH
# mode after an Architect REJECT on "duplicate of upstream X."
#
# Usage:
#   PROJECTS_ROOT=... AI_RULES_REPO=... scripts/promote-learnings/propose-upstream-patch.sh
#
# Reads /tmp/adoption-best.txt (produced by check-adoption.sh; runs that
# script if the file is missing or older than 1 hour).

set -uo pipefail

if [[ -z "${AI_RULES_REPO:-}" ]] || [[ -z "${PROJECTS_ROOT:-}" ]]; then
    echo "[propose-upstream-patch] ERROR: AI_RULES_REPO and PROJECTS_ROOT must be set." >&2
    exit 1
fi

ADOPTION_FILE=/tmp/adoption-best.txt

# Refresh if missing or stale (>1 hour). Cheap re-derivation since this is
# the second stage of a two-step pipeline.
need_refresh=false
if [[ ! -s "$ADOPTION_FILE" ]]; then
    need_refresh=true
elif [[ "$(uname)" == "Darwin" ]]; then
    mtime=$(stat -f '%m' "$ADOPTION_FILE")
    now=$(date +%s)
    (( now - mtime > 3600 )) && need_refresh=true
else
    if [[ -n "$(find "$ADOPTION_FILE" -mmin +60 2>/dev/null)" ]]; then
        need_refresh=true
    fi
fi
if [[ "$need_refresh" == "true" ]]; then
    echo "[propose-upstream-patch] refreshing adoption data..." >&2
    "$AI_RULES_REPO/scripts/promote-learnings/check-adoption.sh" >/dev/null 2>&1
fi

if [[ ! -s "$ADOPTION_FILE" ]]; then
    echo "[propose-upstream-patch] no adoption data — nothing to propose." >&2
    exit 0
fi

# Extract markdown headings (## and ###) from a file, normalizing whitespace
# and case for set membership.
extract_headings() {
    local f="$1"
    awk '
        /^##[#]?[[:space:]]/ {
            # Drop leading hashes + space
            sub(/^##[#]?[[:space:]]+/, "")
            # Drop trailing whitespace
            sub(/[[:space:]]+$/, "")
            print tolower($0)
        }
    ' "$f"
}

echo "================================================================"
echo "UPSTREAM PATCH PROPOSALS"
echo "================================================================"
echo
echo "For each adoption hit, sections present in the PROJECT rule but"
echo "missing from the UPSTREAM rule. These are candidates to patch up."
echo

current_proj=""
proposal_count=0

while IFS='|' read -r proj rule_rel up_rel signals score; do
    [[ -z "$proj" ]] && continue
    proj_path="$PROJECTS_ROOT/$proj/$rule_rel"
    up_path="$AI_RULES_REPO/$up_rel"

    if [[ ! -f "$proj_path" ]] || [[ ! -f "$up_path" ]]; then
        continue
    fi

    if [[ "$proj" != "$current_proj" ]]; then
        [[ -n "$current_proj" ]] && echo
        echo "## $proj"
        current_proj="$proj"
    fi

    proj_headings=$(extract_headings "$proj_path")
    up_headings=$(extract_headings "$up_path")

    # Sections present only in project rule
    unique=""
    if [[ -n "$proj_headings" ]]; then
        if [[ -n "$up_headings" ]]; then
            unique=$(comm -23 <(echo "$proj_headings" | sort -u) <(echo "$up_headings" | sort -u))
        else
            unique="$proj_headings"
        fi
    fi

    echo "  - $rule_rel"
    echo "      vs upstream: $up_rel (score=$score, $signals)"
    if [[ -z "$unique" ]]; then
        echo "      → No project-only sections detected at the H2/H3 level."
        echo "        Likely candidate for option (a): delete project copy,"
        echo "        rely on upstream."
    else
        echo "      → Project-only sections (candidates to patch upstream):"
        while IFS= read -r heading; do
            [[ -z "$heading" ]] && continue
            echo "          - $heading"
            proposal_count=$((proposal_count + 1))
        done <<< "$unique"
    fi
done < "$ADOPTION_FILE"

echo
echo "================================================================"
echo "Summary: $proposal_count project-only section(s) flagged as patch"
echo "candidates across $(awk -F'|' '{print $1}' "$ADOPTION_FILE" | sort -u | wc -l | tr -d ' ') project(s)."
echo "================================================================"
echo
echo "Workflow per candidate:"
echo "  1. Open the upstream file and the project file side by side."
echo "  2. Decide if the project-only section is fleet-generalizable or"
echo "     truly project-specific."
echo "  3. If fleet-generalizable, copy the section into the upstream file"
echo "     (under the most appropriate parent heading) and open a PR."
echo "  4. After the upstream PR merges, delete the project-local rule and"
echo "     it will inherit from ~/.claude/rules/ via the symlink chain."
