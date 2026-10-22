#!/usr/bin/env bash
#
# scripts/promote-learnings/check-adoption.sh
#
# Detect project-local rules that already exist upstream. The promote-
# learnings pipeline asks "what new patterns should we promote?" but the
# adversarial panel keeps rejecting candidates as "duplicate of upstream."
# That tells us the gap isn't missing rules — it's projects re-authoring
# rules locally that they could pull from `~/.claude/rules/` instead.
#
# This script flips the question: for each discovered project, find rules
# (in `.claude/rules/*.md` or `spec/learnings/*.md`) whose intent already
# lives upstream in `$AI_RULES_REPO/.claude/rules/`. Output an adoption
# report ranked by overlap strength.
#
# Detection signals (any one triggers a report entry):
#
#   1. Exact filename match against upstream (e.g. project has
#      `.claude/rules/no-custom-spring-profiles.md` AND upstream has
#      `.claude/rules/java/no-profiles.md` covering the same intent).
#      We detect this via filename slug similarity + topic field.
#   2. Same `topic:` frontmatter as an upstream rule.
#   3. Substantial content overlap — first 500 bytes of normalized
#      content share >= 40% of bigrams with the upstream file.
#
# Output is line-oriented for easy grep + diff:
#
#   <project-name>|<project-rule-path>|<upstream-rule-path>|<signal>|<score>
#
# Where <signal> is filename / topic / content and <score> is the bigram
# similarity ratio (0.00 - 1.00).
#
# Usage:
#   PROJECTS_ROOT=... AI_RULES_REPO=... scripts/promote-learnings/check-adoption.sh
#
# Flags:
#   --threshold N      override bigram similarity threshold (default 0.40)
#   --verbose          show per-file similarity scoring

set -uo pipefail
# Inner loops use grep/wc subshells whose exit codes are intentionally
# ignored when counts are zero; running under `set -e` is too brittle for
# this workload.

THRESHOLD=0.40
VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        --threshold) shift; THRESHOLD="$1"; shift ;;
        --threshold=*) THRESHOLD="${arg#*=}" ;;
        --verbose) VERBOSE=true ;;
        *) echo "[check-adoption] ERROR: unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [[ -z "${AI_RULES_REPO:-}" ]] || [[ -z "${PROJECTS_ROOT:-}" ]]; then
    echo "[check-adoption] ERROR: AI_RULES_REPO and PROJECTS_ROOT must be set." >&2
    exit 1
fi

UPSTREAM_RULES_DIR="$AI_RULES_REPO/.claude/rules"
UPSTREAM_SKILLS_DIR="$AI_RULES_REPO/.claude/skills"

# Build a list of all upstream rule files (recursive — includes subdirs like
# java/, common/, web/, etc.). Skills are also included as adoption targets
# because skills/<topic>/SKILL.md often codifies the same pattern a project
# rule re-states.
mapfile -t UPSTREAM_FILES < <(
    find "$UPSTREAM_RULES_DIR" -type f -name '*.md' 2>/dev/null
    find "$UPSTREAM_SKILLS_DIR" -type f -name 'SKILL.md' 2>/dev/null
)

if [[ "${#UPSTREAM_FILES[@]}" -eq 0 ]]; then
    echo "[check-adoption] ERROR: no upstream rules/skills found under $UPSTREAM_RULES_DIR" >&2
    exit 1
fi

# Pre-extract topic + slug metadata from each upstream file once.
declare -A UPSTREAM_TOPICS=()    # path -> topic (first one)
declare -A UPSTREAM_SLUGS=()     # path -> slug derived from filename
for u in "${UPSTREAM_FILES[@]}"; do
    topic=$(awk '/^topic:[[:space:]]/ {print $2; exit} /^[[:space:]]+-[[:space:]]/ && in_list {gsub(/^[[:space:]]+-[[:space:]]*/, ""); print; exit} /^topics:[[:space:]]*$/ {in_list=1; next} in_list {in_list=0}' "$u")
    [[ -n "$topic" ]] && UPSTREAM_TOPICS[$u]="$topic"
    base=$(basename "$u" .md)
    # Normalize SKILL.md to the parent dir name (the skill's slug)
    [[ "$base" == "SKILL" ]] && base=$(basename "$(dirname "$u")")
    UPSTREAM_SLUGS[$u]="$base"
done

# Normalize a file's body for content comparison: lowercase, strip frontmatter,
# strip non-alpha, collapse whitespace, take first 500 chars.
normalize_body() {
    local f="$1"
    awk 'BEGIN{in_fm=0; seen_fm=0} /^---$/{if(!seen_fm){in_fm=1;seen_fm=1;next}else if(in_fm){in_fm=0;next}} !in_fm{print}' "$f" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -c 'a-z0-9 \n' ' ' \
        | tr -s ' \n' '  ' \
        | head -c 500
}

# Bigram similarity ratio (Sorensen-Dice on character bigrams) using python3.
bigram_similarity() {
    local a="$1" b="$2"
    python3 - "$a" "$b" <<'PY'
import sys
a, b = sys.argv[1], sys.argv[2]
def bigrams(s):
    return set(s[i:i+2] for i in range(len(s)-1))
ga, gb = bigrams(a), bigrams(b)
if not ga or not gb:
    print("0.00")
else:
    inter = len(ga & gb)
    ratio = 2.0 * inter / (len(ga) + len(gb))
    print(f"{ratio:.2f}")
PY
}

# Walk each discovered project and compare its rules + topiced learnings
# against the upstream catalog.
shopt -s nullglob
TOTAL_HITS=0
> /tmp/adoption-raw.txt

while IFS= read -r project; do
    [[ -z "$project" ]] && continue
    proj_name=$(basename "$project")

    for f in "$project"/.claude/rules/*.md "$project"/spec/learnings/*.md; do
        [[ -e "$f" ]] || continue
        base=$(basename "$f" .md)
        [[ "$base" =~ ^(README|_template)$ ]] && continue

        # Project rule's topic + slug
        proj_topic=$(awk '/^topic:[[:space:]]/ {print $2; exit} /^[[:space:]]+-[[:space:]]/ && in_list {gsub(/^[[:space:]]+-[[:space:]]*/, ""); print; exit} /^topics:[[:space:]]*$/ {in_list=1; next} in_list {in_list=0}' "$f")
        proj_body=$(normalize_body "$f")

        for u in "${UPSTREAM_FILES[@]}"; do
            up_topic="${UPSTREAM_TOPICS[$u]:-}"
            up_slug="${UPSTREAM_SLUGS[$u]:-}"

            signals=()
            # Slug similarity by token overlap. Split slugs on `-` into tokens,
            # ignore short stopwords (no, do, is, the), and require >=2 shared
            # significant tokens. Catches "no-custom-spring-profiles" matching
            # upstream "no-profiles" (shared: profiles) only when both also
            # share a second discriminating token — but the threshold of two
            # tokens here would miss that pair, so we also flag a single-token
            # overlap if the upstream slug is entirely contained in project
            # tokens (the strict "no-profiles" → "no" + "profiles" both
            # present case).
            if [[ -n "$up_slug" && -n "$base" ]]; then
                stripped="${base#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"
                if [[ "$stripped" == "$up_slug" ]]; then
                    signals+=("filename")
                else
                    # Token sets
                    proj_tokens=$(echo "$stripped" | tr '-' '\n' | grep -vE '^(no|do|is|the|a|an|of|to|in|on|or|and)$' | sort -u)
                    up_tokens=$(echo "$up_slug" | tr '-' '\n' | grep -vE '^(no|do|is|the|a|an|of|to|in|on|or|and)$' | sort -u)
                    if [[ -n "$up_tokens" ]]; then
                        shared=$(echo "$proj_tokens" | grep -cxFf <(echo "$up_tokens") || true)
                        up_count=$(echo "$up_tokens" | wc -l | tr -d ' ')
                        if [[ "$shared" -ge 2 ]]; then
                            signals+=("filename-fuzzy")
                        elif [[ "$shared" -ge 1 ]] && [[ "$shared" -eq "$up_count" ]]; then
                            # Subsumption: every significant upstream token
                            # appears in the project slug. Catches
                            # "no-custom-spring-profiles" → "no-profiles".
                            # Content threshold is raised below to filter the
                            # false positives this rule otherwise produces.
                            signals+=("filename-subsumption")
                        fi
                    fi
                fi
            fi
            # Topic match
            if [[ -n "$proj_topic" && -n "$up_topic" && "$proj_topic" == "$up_topic" ]]; then
                signals+=("topic")
            fi

            # Cheap pre-filter: if no slug or topic hint, skip content compare
            # (otherwise we'd compute N×M bigram scores).
            [[ "${#signals[@]}" -eq 0 ]] && continue

            up_body=$(normalize_body "$u")
            score=$(bigram_similarity "$proj_body" "$up_body")
            if [[ "$VERBOSE" == "true" ]]; then
                echo "    [$proj_name/$base] vs $(basename "$u"): score=$score signals=${signals[*]}" >&2
            fi

            # Confidence-gated inclusion. Stricter for weaker signals:
            #   filename             always (exact slug match — strong intent).
            #   topic                score >= THRESHOLD               (default 0.40)
            #   filename-fuzzy       score >= THRESHOLD + 0.20         (0.60)
            #   filename-subsumption score >= THRESHOLD + 0.30         (0.70)
            include=false
            if [[ " ${signals[*]} " == *" filename "* ]]; then
                include=true
            elif [[ " ${signals[*]} " == *" filename-fuzzy "* ]]; then
                if python3 -c "import sys; sys.exit(0 if float('$score') >= float('$THRESHOLD') + 0.20 else 1)"; then
                    include=true
                fi
            elif [[ " ${signals[*]} " == *" filename-subsumption "* ]]; then
                if python3 -c "import sys; sys.exit(0 if float('$score') >= float('$THRESHOLD') + 0.30 else 1)"; then
                    include=true
                fi
            else
                if python3 -c "import sys; sys.exit(0 if float('$score') >= float('$THRESHOLD') else 1)"; then
                    include=true
                fi
            fi
            if [[ "$include" == "true" ]]; then
                signal_str=$(IFS=,; echo "${signals[*]}")
                echo "$proj_name|${f#$project/}|${u#$AI_RULES_REPO/}|$signal_str|$score" >> /tmp/adoption-raw.txt
                TOTAL_HITS=$((TOTAL_HITS + 1))
            fi
        done
    done
done < <("$AI_RULES_REPO/scripts/promote-learnings/discover-projects.sh")

# Deduplicate: a project rule can match multiple upstream rules. Keep only
# the highest-scoring upstream match per project rule.
sort -t'|' -k1,2 -k5,5 -r /tmp/adoption-raw.txt | \
    awk -F'|' '!seen[$1 "|" $2]++' | \
    sort -t'|' -k1,1 -k2,2 > /tmp/adoption-best.txt

# --- Report --------------------------------------------------------------

echo "================================================================"
echo "ADOPTION REPORT — rules re-authored locally that exist upstream"
echo "================================================================"
echo
if [[ ! -s /tmp/adoption-best.txt ]]; then
    echo "No adoption gaps detected. Either the fleet is fully aligned with"
    echo "upstream or no project rules carry topic/slug hints to compare."
    exit 0
fi

current_proj=""
hit_count=0
while IFS='|' read -r proj rule_path up_path signals score; do
    if [[ "$proj" != "$current_proj" ]]; then
        [[ -n "$current_proj" ]] && echo
        echo "## $proj"
        current_proj="$proj"
    fi
    printf "  - %s\n      -> upstream: %s\n      signals=%s score=%s\n" \
        "$rule_path" "$up_path" "$signals" "$score"
    hit_count=$((hit_count + 1))
done < /tmp/adoption-best.txt

echo
echo "================================================================"
echo "Summary: $hit_count project-rule(s) overlap with upstream."
echo "Threshold: bigram-similarity >= $THRESHOLD (filename-exact bypasses)"
echo "================================================================"
echo
echo "Next steps:"
echo "  - For each overlap, decide whether the project rule should:"
echo "    a) Be deleted and replaced with an import of upstream."
echo "    b) Stay because it adds project-specific detail not in upstream"
echo "       (in which case run propose-upstream-patch.sh to send the"
echo "       extra detail upstream as a patch)."
