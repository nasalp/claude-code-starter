#!/usr/bin/env bash
#
# scripts/promote-learnings/rotate-expired-rejections.sh
#
# Maintenance for the rejection ledger. Move ledger entries whose
# `Re-evaluation:` date is in the past into an "## Expired" section so
# convergence detection on the active list stays cheap and `/promote-learnings`
# is allowed to re-propose them.
#
# Idempotent. Safe to run on every preflight invocation.
#
# Usage:
#   AI_RULES_REPO=/path scripts/promote-learnings/rotate-expired-rejections.sh
#   [TODAY=YYYY-MM-DD]   override "today" for tests
#
# Exit codes:
#   0 — completed (rotated 0 or more entries; count printed on stdout)
#   1 — bad env / missing ledger file

set -uo pipefail

err()  { echo "[rotate-expired] ERROR: $*" >&2; }
note() { echo "[rotate-expired] $*" >&2; }

if [[ -z "${AI_RULES_REPO:-}" ]]; then
    err "AI_RULES_REPO is not set."
    exit 1
fi

LEDGER="$AI_RULES_REPO/spec/decisions/rejected-promotions.md"
if [[ ! -f "$LEDGER" ]]; then
    note "No ledger at $LEDGER — nothing to rotate."
    echo "0"
    exit 0
fi

TODAY="${TODAY:-$(date -u +%Y-%m-%d)}"

ROTATED=$(python3 -c "
import re
import sys
from datetime import date

today_str = '$TODAY'
y, m, d = (int(p) for p in today_str.split('-'))
today = date(y, m, d)

with open('$LEDGER') as f:
    text = f.read()

# Split on '## ' headers but keep the preamble. Then partition: everything
# before the '## Expired' header is "active" candidate space; everything from
# '## Expired' onward is the already-rotated bucket and is left untouched.
sections = re.split(r'(?m)^(?=## )', text)
preamble = sections[0]
entries = sections[1:]

active_entries = []
expired_bucket_chunks = []
seen_expired = False
for s in entries:
    if s.startswith('## Expired'):
        seen_expired = True
    if seen_expired:
        expired_bucket_chunks.append(s)
    else:
        active_entries.append(s)

active = []
to_expire = []
for s in active_entries:
    m = re.search(r'\\*\\*Re-evaluation:\\*\\*\\s*([\\d-]+|never)', s)
    if not m:
        active.append(s)
        continue
    val = m.group(1).strip()
    if val == 'never':
        active.append(s)
        continue
    try:
        py, pm, pd = (int(p) for p in val.split('-'))
        if date(py, pm, pd) <= today:
            to_expire.append(s)
        else:
            active.append(s)
    except Exception:
        active.append(s)

if not to_expire:
    sys.stdout.write('0')
    sys.exit(0)

# Build the new ledger: preamble + remaining active + bucket + newly rotated.
if expired_bucket_chunks:
    bucket_blob = ''.join(expired_bucket_chunks)
else:
    bucket_blob = '## Expired\n\nLedger entries whose re-evaluation window has elapsed. Re-propose freely.\n\n'
new_text = preamble + ''.join(active) + bucket_blob + ''.join(to_expire)
with open('$LEDGER', 'w') as f:
    f.write(new_text)
sys.stdout.write(str(len(to_expire)))
" 2>/dev/null) || { err "rotation script failed"; exit 1; }

note "Rotated $ROTATED entries to Expired section (today=$TODAY)."
echo "$ROTATED"
exit 0
