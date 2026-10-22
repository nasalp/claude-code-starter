#!/usr/bin/env bash
#
# scripts/promote-learnings/write-heartbeat.sh
#
# Append a one-line heartbeat to $AI_RULES_REPO/spec/promotion-log/<YYYY-MM-DD>.md
# so consumers can verify the loop is alive. If no entry has appeared in the
# last 14 days, the meta-harness is broken — that's the signal to investigate.
#
# Usage:
#   AI_RULES_REPO=/path scripts/promote-learnings/write-heartbeat.sh \
#     --projects-scanned <N> \
#     --learnings-seen   <N> \
#     --candidates       <N> \
#     --prs-drafted      <N> \
#     --cost-usd         <FLOAT> \
#     [--state-sha       <hex>]
#
# Exit codes:
#   0 — appended successfully
#   1 — bad args or env

set -uo pipefail

err() { echo "[write-heartbeat] ERROR: $*" >&2; }

if [[ -z "${AI_RULES_REPO:-}" ]]; then
    err "AI_RULES_REPO is not set."
    exit 1
fi
if [[ ! -d "$AI_RULES_REPO/.claude/rules" ]]; then
    err "AI_RULES_REPO=$AI_RULES_REPO does not look like an ai-rules checkout."
    exit 1
fi

PROJECTS=""
LEARNINGS=""
CANDIDATES=""
PRS=""
COST=""
STATE_SHA=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --projects-scanned) PROJECTS="$2"; shift 2 ;;
        --learnings-seen)   LEARNINGS="$2"; shift 2 ;;
        --candidates)       CANDIDATES="$2"; shift 2 ;;
        --prs-drafted)      PRS="$2"; shift 2 ;;
        --cost-usd)         COST="$2"; shift 2 ;;
        --state-sha)        STATE_SHA="$2"; shift 2 ;;
        *) err "Unknown argument: $1"; exit 1 ;;
    esac
done

for arg_name in PROJECTS LEARNINGS CANDIDATES PRS COST; do
    eval "v=\${$arg_name}"
    if [[ -z "$v" ]]; then
        # `tr` instead of bash 4+ ${var,,} so the script runs on macOS's
        # default /bin/bash 3.2 (which CI uses).
        arg_lower=$(echo "$arg_name" | tr '[:upper:]' '[:lower:]')
        err "Missing required arg corresponding to --${arg_lower}"
        exit 1
    fi
    if ! echo "$v" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
        err "Argument for $arg_name must be numeric, got: '$v'"
        exit 1
    fi
done

LOG_DIR="$AI_RULES_REPO/spec/promotion-log"
mkdir -p "$LOG_DIR"
TODAY=$(date -u +%Y-%m-%d)
NOW=$(date -u +'%Y-%m-%d %H:%M UTC')
FILE="$LOG_DIR/$TODAY.md"

# Header on first write of the day.
if [[ ! -s "$FILE" ]]; then
    {
        echo "# Promotion-log: $TODAY"
        echo
        echo "Heartbeat entries — one line per /promote-learnings invocation."
        echo "If you don't see an entry from the past 14 days, the loop is broken."
        echo
    } > "$FILE"
fi

ENTRY="$NOW | scanned $PROJECTS projects | $LEARNINGS learnings | $CANDIDATES candidates | $PRS PRs drafted | \$$COST"
if [[ -n "$STATE_SHA" ]]; then
    ENTRY="$ENTRY | state-sha: $STATE_SHA"
fi
echo "$ENTRY" >> "$FILE"

# Also write the state-sha as a parseable line so preflight.sh can read it.
if [[ -n "$STATE_SHA" ]]; then
    echo "state-sha: $STATE_SHA" >> "$FILE"
fi

echo "[write-heartbeat] Appended heartbeat to $FILE" >&2
exit 0
