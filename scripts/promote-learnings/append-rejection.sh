#!/usr/bin/env bash
#
# scripts/promote-learnings/append-rejection.sh
#
# Append a structured entry to spec/decisions/rejected-promotions.md.
# Used by /promote-learnings (when a reviewer votes REJECT) and by
# /retract-rule (when a previously-promoted rule is being rolled back).
#
# Usage:
#   AI_RULES_REPO=/path scripts/promote-learnings/append-rejection.sh \
#     --rule '<rule-name>' \
#     --reviewer '<Adversary|Architect|Field Engineer|Operator>' \
#     --reason '<one-sentence cause>' \
#     [--reevaluation '<YYYY-MM-DD or "never">'] \
#     [--condition '<re-evaluation condition>'] \
#     [--evidence '<file:line or url>']
#
# Defaults:
#   --reevaluation: 90 days from today (YYYY-MM-DD)
#   --condition:    "(none specified)"
#   --evidence:     "(none cited)"
#
# Exit codes:
#   0 — appended successfully
#   1 — invalid arguments or missing env var

set -uo pipefail

err() { echo "[append-rejection] ERROR: $*" >&2; }

if [[ -z "${AI_RULES_REPO:-}" ]]; then
    err "AI_RULES_REPO is not set."
    exit 1
fi
if [[ ! -d "$AI_RULES_REPO/.claude/rules" ]]; then
    err "AI_RULES_REPO=$AI_RULES_REPO does not look like an ai-rules checkout."
    exit 1
fi

RULE=""
REVIEWER=""
REASON=""
REEVAL=""
CONDITION=""
EVIDENCE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rule)         RULE="$2"; shift 2 ;;
        --reviewer)     REVIEWER="$2"; shift 2 ;;
        --reason)       REASON="$2"; shift 2 ;;
        --reevaluation) REEVAL="$2"; shift 2 ;;
        --condition)    CONDITION="$2"; shift 2 ;;
        --evidence)     EVIDENCE="$2"; shift 2 ;;
        *) err "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$RULE" ]] || [[ -z "$REVIEWER" ]] || [[ -z "$REASON" ]]; then
    err "Missing required arg. --rule, --reviewer, --reason are all required."
    err "Got: rule='$RULE' reviewer='$REVIEWER' reason='$REASON'"
    exit 1
fi

# Sensible default re-evaluation date: 90 days from today (YYYY-MM-DD).
if [[ -z "$REEVAL" ]]; then
    REEVAL=$(date -u -v+90d +%Y-%m-%d 2>/dev/null \
             || date -u -d "+90 days" +%Y-%m-%d 2>/dev/null \
             || echo "(unknown — set GNU date or BSD date)")
fi
[[ -z "$CONDITION" ]] && CONDITION="(none specified)"
[[ -z "$EVIDENCE" ]]  && EVIDENCE="(none cited)"

LEDGER="$AI_RULES_REPO/spec/decisions/rejected-promotions.md"
mkdir -p "$(dirname "$LEDGER")"

# Header on first write
if [[ ! -s "$LEDGER" ]]; then
    {
        echo "# Rejected promotions ledger"
        echo
        echo "Append-only record of /promote-learnings candidates that were rejected"
        echo "or rules that were retracted, with the reasoning. Future runs of"
        echo "/promote-learnings consult this file to avoid re-proposing the same"
        echo "ideas inside the re-evaluation window."
        echo
    } > "$LEDGER"
fi

TODAY=$(date -u +%Y-%m-%d)
{
    echo
    echo "## $RULE — rejected $TODAY"
    echo
    echo "- **Reviewer:** $REVIEWER"
    echo "- **Reason:** $REASON"
    echo "- **Re-evaluation:** $REEVAL"
    echo "- **Re-evaluation condition:** $CONDITION"
    echo "- **Cited evidence:** $EVIDENCE"
} >> "$LEDGER"

echo "[append-rejection] Appended $RULE to $LEDGER" >&2
exit 0
