#!/usr/bin/env bash
#
# scripts/promote-learnings/check-proposed-expiry.sh
#
# Audit .claude/rules-proposed/*.md against the grace-period date each
# file declares. The Tier-1/2 convention is: a rule sits in rules-proposed/
# (visible, NOT auto-loaded — it lives OUTSIDE .claude/rules/ so the
# session loader never injects it) for a grace period; if no second fleet
# project independently surfaces the same pattern before the deadline,
# the rule either promotes to canonical or expires.
#
# Without this audit the directory rots: stale rules accumulate, the
# grace-period contract becomes a lie, and the heartbeat counter loses
# meaning.
#
# Usage:
#   AI_RULES_REPO=/path scripts/promote-learnings/check-proposed-expiry.sh \
#     [--prune-expired]      # delete files past grace (default: report only)
#     [--warn-days N]        # mark files within N days as DUE_SOON (default: 7)
#     [--today YYYY-MM-DD]   # override "today" (for tests)
#     [--quiet]              # suppress per-file output, summary only
#
# Output (one line per file):
#   OK         <file>  grace=<YYYY-MM-DD>  in <N>d
#   DUE_SOON   <file>  grace=<YYYY-MM-DD>  in <N>d   (<= warn-days)
#   EXPIRED    <file>  grace=<YYYY-MM-DD>  by <N>d
#   NO_GRACE   <file>  (no grace-period date found — manual review)
#
# Exit codes:
#   0 — no EXPIRED entries
#   1 — at least one EXPIRED entry (or --prune-expired triggered a delete)
#   2 — bad env / missing dir

set -uo pipefail

err() { echo "[check-proposed-expiry] ERROR: $*" >&2; }

PRUNE=0
WARN_DAYS=7
TODAY=""
QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prune-expired) PRUNE=1; shift ;;
    --warn-days)     WARN_DAYS="$2"; shift 2 ;;
    --today)         TODAY="$2"; shift 2 ;;
    --quiet)         QUIET=1; shift ;;
    -h|--help)
      sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//;/^set -uo/d'
      exit 0 ;;
    *) err "unknown arg: $1"; exit 2 ;;
  esac
done

if [[ -z "${AI_RULES_REPO:-}" ]]; then
  err "AI_RULES_REPO is not set."
  exit 2
fi
PROP_DIR="$AI_RULES_REPO/.claude/rules-proposed"
if [[ ! -d "$PROP_DIR" ]]; then
  err "$PROP_DIR does not exist."
  exit 2
fi
if [[ -z "$TODAY" ]]; then
  TODAY=$(date -u +%Y-%m-%d)
fi
if ! [[ "$TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  err "--today must be YYYY-MM-DD (got: $TODAY)"
  exit 2
fi

# Portable YYYY-MM-DD → epoch-days, since `date -d` and `date -j` differ
# between GNU and BSD. Pure bash, no externals.
_to_days() {
  local d="$1"
  local y=${d:0:4} m=${d:5:2} mday=${d:8:2}
  y=$((10#$y)); m=$((10#$m)); mday=$((10#$mday))
  if (( m < 3 )); then m=$((m+12)); y=$((y-1)); fi
  # Zeller-derived day count, anchored at 0000-03-01.
  echo $(( y*365 + y/4 - y/100 + y/400 + (153*(m-3)+2)/5 + mday - 1 ))
}

_extract_grace() {
  # Heuristic: on a line that mentions "grace" / "expire" / "ends",
  # the grace date is the LAST YYYY-MM-DD on that line (English phrasing
  # is "promoted-from <date1> ... grace ends <date2>"). Falls back to
  # the second YYYY-MM-DD in the file when no grace-keyword line exists
  # (same rationale — the first date is typically promoted-from).
  # Returns empty on no match.
  local f="$1"
  local hit
  hit=$(grep -iE '(grace|expire|ends)' "$f" 2>/dev/null \
        | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' | tail -1)
  if [[ -z "$hit" ]]; then
    local n
    n=$(grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$n" -ge 2 ]]; then
      hit=$(grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$f" | sed -n 2p)
    fi
  fi
  printf '%s\n' "$hit"
}

today_d=$(_to_days "$TODAY")
ok_n=0
soon_n=0
exp_n=0
none_n=0
deleted_n=0
expired_files=()

shopt -s nullglob
for f in "$PROP_DIR"/*.md; do
  base=$(basename "$f")
  grace=$(_extract_grace "$f")
  if [[ -z "$grace" ]]; then
    none_n=$((none_n+1))
    (( QUIET )) || printf 'NO_GRACE   %s  (no grace-period date found — manual review)\n' "$base"
    continue
  fi
  if ! [[ "$grace" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    none_n=$((none_n+1))
    (( QUIET )) || printf 'NO_GRACE   %s  (malformed grace date: %s)\n' "$base" "$grace"
    continue
  fi
  grace_d=$(_to_days "$grace")
  delta=$(( grace_d - today_d ))
  if (( delta < 0 )); then
    exp_n=$((exp_n+1))
    expired_files+=("$f")
    (( QUIET )) || printf 'EXPIRED    %s  grace=%s  by %dd\n' "$base" "$grace" "$(( -delta ))"
  elif (( delta <= WARN_DAYS )); then
    soon_n=$((soon_n+1))
    (( QUIET )) || printf 'DUE_SOON   %s  grace=%s  in %dd\n' "$base" "$grace" "$delta"
  else
    ok_n=$((ok_n+1))
    (( QUIET )) || printf 'OK         %s  grace=%s  in %dd\n' "$base" "$grace" "$delta"
  fi
done

if (( PRUNE )) && (( exp_n > 0 )); then
  for f in "${expired_files[@]}"; do
    rm -- "$f"
    deleted_n=$((deleted_n+1))
    (( QUIET )) || printf 'DELETED    %s\n' "$(basename "$f")"
  done
fi

printf 'summary: ok=%d due_soon=%d expired=%d no_grace=%d deleted=%d (today=%s)\n' \
  "$ok_n" "$soon_n" "$exp_n" "$none_n" "$deleted_n" "$TODAY"

(( exp_n == 0 )) && exit 0 || exit 1
