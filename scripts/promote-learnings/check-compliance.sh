#!/usr/bin/env bash
#
# scripts/promote-learnings/check-compliance.sh
#
# Lightweight fleet-wide trend signal for the meta-harness heartbeat log.
# One grep-based pass per rule that has a `.compliance.regex` sidecar:
#
#   .compliance.regex — forbidden literals in production source
#                       (src/main/, lib/, top-level src/ minus test/).
#                       Hits = violation.
#
# Real enforcement lives in the consumer project's build (ArchUnit,
# ESLint, Spotless, etc.). This runner does NOT duplicate that — it
# tracks whether forbidden literals are creeping back in despite those
# build-time gates.
#
# Adoption tracking via grep was tried and removed. Multi-line wraps,
# Kotlin/Java imports, custom matchers, and reformatting all break a
# grep-based "is the ArchUnit test wired" check. The right adoption
# signal is consumer CI status (read via `gh run list`), not regex.
#
# Usage:
#   AI_RULES_REPO=/path PROJECTS_ROOT=/path \
#     scripts/promote-learnings/check-compliance.sh \
#     [--rule <rule-relative-path>]    # check just this rule
#     [--dry-run]                      # print, don't append to heartbeat log
#
# Exit codes:
#   0 — completed (summary on stdout)
#   1 — bad env / missing dirs

set -uo pipefail

err()  { echo "[check-compliance] ERROR: $*" >&2; }
note() { echo "[check-compliance] $*" >&2; }

if [[ -z "${AI_RULES_REPO:-}" ]]; then
    err "AI_RULES_REPO is not set."
    exit 1
fi
if [[ -z "${PROJECTS_ROOT:-}" ]]; then
    err "PROJECTS_ROOT is not set."
    exit 1
fi
if [[ ! -d "$AI_RULES_REPO/.claude/rules" ]]; then
    err "Not an ai-rules checkout: $AI_RULES_REPO"
    exit 1
fi
if [[ ! -d "$PROJECTS_ROOT" ]]; then
    err "Projects root does not exist: $PROJECTS_ROOT"
    exit 1
fi

DRY_RUN=false
ONLY_RULE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --rule)    ONLY_RULE="$2"; shift 2 ;;
        *) err "Unknown argument: $1"; exit 1 ;;
    esac
done

rules_checked=0
rules_passing=0
rules_violated=0
violations=""

# Collect production-source roots per project. Restricting to src/main/,
# lib/, and a top-level src/ (minus any test subdirs) keeps test fixtures
# with intentional placeholder secrets or Thread.sleep in setup from
# producing false positives.
production_roots() {
    local proj="$1"
    local roots=()
    [[ -d "$proj/src/main" ]] && roots+=("$proj/src/main")
    [[ -d "$proj/lib" ]] && roots+=("$proj/lib")
    if [[ -d "$proj/src" ]] && [[ ! -d "$proj/src/main" ]]; then
        # Some Node/PHP projects keep production code at src/ directly with
        # tests under src/test or tests/ — include src/ but tell grep to
        # exclude any nested test directories.
        roots+=("$proj/src")
    fi
    printf '%s\n' "${roots[@]}"
}

run_compliance_for_rule() {
    local rule="$1" rel="$2"
    local re_check="${rule%.md}.compliance.regex"
    [[ ! -f "$re_check" ]] && return 0

    rules_checked=$((rules_checked + 1))
    local violation_found=false

    # Walk every project under PROJECTS_ROOT that has at least one
    # production-source root.
    shopt -s nullglob 2>/dev/null || true
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        [[ "$pattern" =~ ^# ]] && continue

        for project in "$PROJECTS_ROOT"/*/; do
            local proj=${project%/}
            # Skip ai-rules itself.
            if [[ -n "${AI_RULES_REPO:-}" ]]; then
                local proj_abs ai_abs
                proj_abs=$(cd "$proj" 2>/dev/null && pwd)
                ai_abs=$(cd "$AI_RULES_REPO" 2>/dev/null && pwd)
                [[ "$proj_abs" == "$ai_abs" ]] && continue
            fi

            while IFS= read -r root; do
                [[ -z "$root" ]] && continue
                if grep -rE \
                    --include='*.java' --include='*.kt' --include='*.scala' \
                    --include='*.groovy' --include='*.ts' --include='*.tsx' \
                    --include='*.js' --include='*.jsx' --include='*.mjs' \
                    --include='*.cjs' --include='*.py' --include='*.php' \
                    --include='*.yml' --include='*.yaml' \
                    --include='*.properties' \
                    --exclude-dir='target' --exclude-dir='build' \
                    --exclude-dir='node_modules' --exclude-dir='__pycache__' \
                    --exclude-dir='_deprecated' --exclude-dir='generated' \
                    --exclude-dir='dist' --exclude-dir='out' \
                    --exclude-dir='test' --exclude-dir='tests' \
                    --exclude-dir='__tests__' \
                    "$pattern" "$root" >/dev/null 2>&1; then
                    violation_found=true
                    break 3
                fi
            done < <(production_roots "$proj")
        done
    done < "$re_check"
    shopt -u nullglob 2>/dev/null || true

    if [[ "$violation_found" == "true" ]]; then
        rules_violated=$((rules_violated + 1))
        violations="${violations}${rel}\n"
    else
        rules_passing=$((rules_passing + 1))
    fi
}

# Iterate over all live rules. The find excludes _deprecated/ and _proposed/
# directories; the basename guard below skips any _-prefixed file under rules/.
# (compliance-regex-howto.md was relocated to docs/, so it is outside the find
# root and naturally excluded — and being no longer _-prefixed, the guard would
# not catch it anyway.)
while IFS= read -r rule; do
    rel="${rule#$AI_RULES_REPO/}"
    [[ "$(basename "$rule")" == _* ]] && continue
    if [[ -n "$ONLY_RULE" ]] && [[ "$rel" != "$ONLY_RULE" ]]; then
        continue
    fi
    run_compliance_for_rule "$rule" "$rel"
done < <(find "$AI_RULES_REPO/.claude/rules" -type f -name '*.md' \
            ! -path '*/_deprecated/*' ! -path '*/_proposed/*' 2>/dev/null)

# Print structured summary on stdout.
echo "rules-checked: $rules_checked"
echo "rules-passing: $rules_passing"
echo "rules-violated: $rules_violated"
if [[ -n "$violations" ]]; then
    echo "violations:"
    printf "%b" "$violations" | sed 's/^/  - /'
fi

# Append to heartbeat log unless --dry-run.
if [[ "$DRY_RUN" == "false" ]]; then
    LOG_DIR="$AI_RULES_REPO/spec/promotion-log"
    mkdir -p "$LOG_DIR"
    TODAY=$(date -u +%Y-%m-%d)
    NOW=$(date -u +'%Y-%m-%d %H:%M UTC')
    echo "$NOW | compliance: $rules_checked rules / $rules_passing clean / $rules_violated violated" \
        >> "$LOG_DIR/$TODAY.md"
fi

exit 0
