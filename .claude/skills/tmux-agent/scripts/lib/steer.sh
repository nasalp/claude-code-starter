#!/usr/bin/env bash
# Cooperative STEER channel: structured drift signals from watcher to builder.
set -uo pipefail

# Stable dedup key from steer payload fields.
_steer_hash() {
  local severity="$1" wrong="$2" required="$3" rule_ref="$4"
  printf '%s|%s|%s|%s' "$severity" "$wrong" "$required" "$rule_ref" | cksum | awk '{print $1}'
}

# Resolve phase identity: phase.current, else last known SHA, else unknown.
_steer_phase() {
  local run_dir="$1"
  local phase_file="${run_dir}/steer/phase.current"
  if [[ -f "$phase_file" ]]; then
    cat "$phase_file"
    return 0
  fi
  local last_sha_file="${run_dir}/steer/state/last_sha"
  if [[ -f "$last_sha_file" ]]; then
    cat "$last_sha_file"
    return 0
  fi
  echo "unknown"
}

# Append one JSON row to the steer orchestration trail.
_steer_trail_append() {
  local run_dir="$1" json="$2"
  mkdir -p "${run_dir}/steer"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' "$json" | sed "s/\"ts\":null/\"ts\":\"${ts}\"/" >> "${run_dir}/steer/trail.ndjson"
}

# Read integer count from state file; 0 when missing.
_steer_read_count() {
  local count_file="$1"
  if [[ ! -f "$count_file" ]]; then
    echo 0
    return 0
  fi
  local n
  n="$(cat "$count_file" 2>/dev/null || echo 0)"
  if [[ -z "$n" || ! "$n" =~ ^[0-9]+$ ]]; then
    echo 0
    return 0
  fi
  echo "$n"
}

# Reset per-phase steer state when phase identity changes.
_steer_reset_phase_if_needed() {
  local run_dir="$1" phase="$2"
  local state_dir="${run_dir}/steer/state"
  local phase_file="${state_dir}/phase"
  local count_file="${state_dir}/count"
  local hashes_dir="${state_dir}/hashes"
  local prev=""

  mkdir -p "$state_dir" "$hashes_dir"
  if [[ -f "$phase_file" ]]; then
    prev="$(cat "$phase_file")"
  fi
  if [[ "$prev" == "$phase" ]]; then
    return 0
  fi

  echo "0" > "$count_file"
  rm -f "${hashes_dir}/"*
  rm -f "${run_dir}/STEER.halt"
  echo "$phase" > "$phase_file"
  _steer_trail_append "$run_dir" \
    "{\"event\":\"phase_reset\",\"prev\":\"${prev}\",\"phase\":\"${phase}\",\"ts\":null}"
}

# Strip watcher diagnostic header; emit audit body only.
_steer_verdict_body() {
  local verdict_file="$1"
  [[ -f "$verdict_file" ]] || return 0
  awk '
    /^=== WATCHER DIAGNOSTIC ===/ { skip=1; next }
    /^=== END DIAGNOSTIC ===/     { skip=0; next }
    !skip                          { print }
  ' "$verdict_file" | sed -e '/./,$!d'
}

# Extract parseable JSON object from verdict body (flat, pretty-printed, or fenced).
_steer_json_from_verdict() {
  local verdict_file="$1"
  local body fenced json
  body="$(_steer_verdict_body "$verdict_file")"
  [[ -n "$body" ]] || return 1

  fenced="$(printf '%s\n' "$body" | awk '
    /^```json[[:space:]]*$/ { capture=1; next }
    /^```json/              { capture=1; next }
    /^```[[:space:]]*$/ && capture { capture=0; next }
    /^```/ && capture        { capture=0; next }
    capture                  { print }
  ')"
  if [[ -n "$fenced" ]]; then
    json="$fenced"
  else
    json="$body"
  fi

  command -v jq >/dev/null 2>&1 || return 1
  printf '%s' "$json" | jq -e . >/dev/null 2>&1 || return 1
  printf '%s' "$json"
}

# Parse verdict severity: reject|escalate|warn|none.
_steer_severity_from_verdict() {
  local verdict_file="$1"
  [[ -f "$verdict_file" ]] || { echo "none"; return 0; }

  local json verdict raw
  json="$(_steer_json_from_verdict "$verdict_file" 2>/dev/null || echo "")"
  if [[ -n "$json" ]]; then
    verdict="$(printf '%s' "$json" | jq -r '.verdict // empty' 2>/dev/null || echo "")"
    case "$verdict" in
      reject)   echo "reject"; return 0 ;;
      escalate) echo "escalate"; return 0 ;;
      warn)     echo "warn"; return 0 ;;
      approve)  echo "none"; return 0 ;;
    esac
  fi

  raw="$(cat "$verdict_file" 2>/dev/null || echo "")"
  if printf '%s' "$raw" | grep -qiE 'verdict:[[:space:]]*reject'; then
    echo "reject"
    return 0
  fi
  if printf '%s' "$raw" | grep -q 'REJECT'; then
    echo "reject"
    return 0
  fi
  if printf '%s' "$raw" | grep -qiE 'verdict:[[:space:]]*escalate'; then
    echo "escalate"
    return 0
  fi

  echo "none"
}

# First forbidden marker across one or more files, or empty (secondary backstop only).
_steer_detect_forbidden() {
  local file line
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    line="$(grep -n -E 'TODO|FIXME|@Disabled|\|\|[[:space:]]*true|continue-on-error|SuppressWarnings|(^|[^[:alnum:]_])skip([^[:alnum:]_]|$)|xfail|archunit_ignore' \
      "$file" 2>/dev/null | head -1 || echo "")"
    if [[ -n "$line" ]]; then
      echo "$line"
      return 0
    fi
  done
  echo ""
}

# Extract sha_resolved from watcher diagnostic header in a verdict file.
_steer_sha_from_verdict() {
  local verdict_file="$1"
  [[ -f "$verdict_file" ]] || return 0
  awk '/^sha_resolved: / { print $2; exit }' "$verdict_file" 2>/dev/null
}

# Pull steer fields from structured verdict JSON; empty on failure.
# Optional extra args are additional files scanned for forbidden markers (warn backstop).
_steer_fields_from_verdict() {
  local verdict_file="$1" severity="$2"
  shift 2
  local raw json wrong="" required="" rule_ref="" forbidden
  raw="$(cat "$verdict_file" 2>/dev/null || echo "")"
  json="$(_steer_json_from_verdict "$verdict_file" 2>/dev/null || echo "")"

  if [[ -n "$json" ]] && command -v jq >/dev/null 2>&1; then
    wrong="$(printf '%s' "$json" | jq -r '.reason // empty' 2>/dev/null || echo "")"
    required="$(printf '%s' "$json" | jq -r '(.required_changes // []) | join("; ")' 2>/dev/null || echo "")"
    rule_ref="$(printf '%s' "$json" | jq -r '(.violated_rules // []) | join(", ")' 2>/dev/null || echo "")"
  fi

  if [[ -z "$wrong" ]]; then
    wrong="$(printf '%s' "$raw" | grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  fi
  if [[ -z "$wrong" ]]; then
    wrong="$(printf '%s' "$raw" | grep -i 'reason:' | head -1 | sed 's/^[^:]*:[[:space:]]*//')"
  fi
  if [[ -z "$required" ]]; then
    required="$(printf '%s' "$raw" | grep -i 'required_change' | head -1 | sed 's/^[^:]*:[[:space:]]*//')"
  fi
  if [[ -z "$rule_ref" ]]; then
    rule_ref="$(printf '%s' "$raw" | grep -i 'violated_rule' | head -1 | sed 's/^[^:]*:[[:space:]]*//')"
  fi

  if [[ "$severity" == "warn" ]]; then
    forbidden="$(_steer_detect_forbidden "$verdict_file" "$@")"
    if [[ -n "$forbidden" ]]; then
      wrong="forbidden pattern: ${forbidden}"
      [[ -z "$required" ]] && required="remove or justify the forbidden marker"
      [[ -z "$rule_ref" ]] && rule_ref="no-deferred-work.md"
    fi
  fi

  if [[ -z "$wrong" || -z "$required" ]]; then
    return 1
  fi
  [[ -z "$rule_ref" ]] && rule_ref="unknown"
  wrong="$(printf '%s' "$wrong" | tr '\n' ' ')"
  required="$(printf '%s' "$required" | tr '\n' ' ')"
  rule_ref="$(printf '%s' "$rule_ref" | tr '\n' ' ')"
  printf '%s\n%s\n%s' "$wrong" "$required" "$rule_ref"
}

# Atomic write of STEER.md with dedup, cap, and halt marker on reject.
_steer_write() {
  local run_dir="$1" severity="$2" wrong="$3" required="$4" rule_ref="$5"
  local state_dir="${run_dir}/steer/state"
  local count_file="${state_dir}/count"
  local hashes_dir="${state_dir}/hashes"
  local hash max count phase ts tmp dest

  if [[ -z "$run_dir" || ! -d "$run_dir" || ! -w "$run_dir" ]]; then
    return 1
  fi

  mkdir -p "$state_dir" "$hashes_dir"
  hash="$(_steer_hash "$severity" "$wrong" "$required" "$rule_ref")"
  if [[ -f "${hashes_dir}/${hash}" ]]; then
    _steer_trail_append "$run_dir" \
      "{\"event\":\"dedup_suppressed\",\"severity\":\"${severity}\",\"hash\":\"${hash}\",\"ts\":null}"
    return 2
  fi

  max="${STEER_MAX_PER_PHASE:-3}"
  count="$(_steer_read_count "$count_file")"
  if (( count >= max )); then
    _steer_trail_append "$run_dir" \
      "{\"event\":\"cap_suppressed\",\"severity\":\"${severity}\",\"count\":${count},\"max\":${max},\"ts\":null}"
    return 3
  fi

  phase="$(_steer_phase "$run_dir")"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  dest="${run_dir}/STEER.md"
  tmp="$(mktemp "${run_dir}/.STEER.md.XXXXXX")" || return 1
  [[ -n "$tmp" ]] || return 1
  {
    printf 'severity: %s\n' "$severity"
    printf 'whats_wrong: %s\n' "$wrong"
    printf 'required_change: %s\n' "$required"
    printf 'rule_ref: %s\n' "$rule_ref"
    printf 'phase: %s\n' "$phase"
    printf 'ts: %s\n' "$ts"
  } > "$tmp"
  mv "$tmp" "$dest"

  count=$((count + 1))
  echo "$count" > "$count_file"
  touch "${hashes_dir}/${hash}"
  _steer_trail_append "$run_dir" \
    "{\"event\":\"written\",\"severity\":\"${severity}\",\"phase\":\"${phase}\",\"hash\":\"${hash}\",\"ts\":null}"

  if [[ "$severity" == "reject" ]]; then
    touch "${run_dir}/STEER.halt"
    _steer_trail_append "$run_dir" \
      "{\"event\":\"halt_written\",\"severity\":\"reject\",\"phase\":\"${phase}\",\"ts\":null}"
  fi

  return 0
}

# Main entry: verdict-primary drift detection with forbidden backstop.
# Optional 3rd arg: live pane / builder_out snapshot file for secondary backstop.
_steer_process_verdict() {
  local run_dir="$1" verdict_file="$2" pane_file="${3:-}"
  local phase severity wrong required rule_ref fields sha forbidden

  if [[ -z "$run_dir" || ! -d "$run_dir" || ! -w "$run_dir" ]]; then
    return 1
  fi
  [[ -f "$verdict_file" ]] || return 1

  sha="$(_steer_sha_from_verdict "$verdict_file")"
  if [[ -n "$sha" && "$sha" != "NONE" ]]; then
    mkdir -p "${run_dir}/steer/state"
    echo "$sha" > "${run_dir}/steer/state/last_sha"
  fi

  phase="$(_steer_phase "$run_dir")"
  _steer_reset_phase_if_needed "$run_dir" "$phase"

  severity="$(_steer_severity_from_verdict "$verdict_file")"
  if [[ "$severity" == "none" ]]; then
    if [[ -n "$pane_file" ]]; then
      forbidden="$(_steer_detect_forbidden "$verdict_file" "$pane_file")"
    else
      forbidden="$(_steer_detect_forbidden "$verdict_file")"
    fi
    if [[ -n "$forbidden" ]]; then
      severity="warn"
    else
      return 1
    fi
  fi

  if [[ -n "$pane_file" ]]; then
    fields="$(_steer_fields_from_verdict "$verdict_file" "$severity" "$pane_file")" || return 4
  else
    fields="$(_steer_fields_from_verdict "$verdict_file" "$severity")" || return 4
  fi
  wrong="$(printf '%s' "$fields" | sed -n '1p')"
  required="$(printf '%s' "$fields" | sed -n '2p')"
  rule_ref="$(printf '%s' "$fields" | sed -n '3p')"
  wrong="$(printf '%s' "$wrong" | tr '\n' ' ')"
  required="$(printf '%s' "$required" | tr '\n' ' ')"
  rule_ref="$(printf '%s' "$rule_ref" | tr '\n' ' ')"

  _steer_write "$run_dir" "$severity" "$wrong" "$required" "$rule_ref"
}
