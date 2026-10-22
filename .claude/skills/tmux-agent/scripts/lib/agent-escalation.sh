#!/usr/bin/env bash
# Cheap-first escalation policy + structured-verdict validation.
# Reads escalation thresholds from config/agent-routing.yml; env overrides:
#   AGENT_CONFIDENCE_MIN, AGENT_ESCALATE_AFTER_N.
set -uo pipefail

_esc_lib_dir() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }
_esc_routing_path() {
  if [[ -n "${AGENT_ROUTING_CONFIG:-}" ]]; then printf '%s\n' "$AGENT_ROUTING_CONFIG"; return; fi
  printf '%s\n' "$(_esc_lib_dir)/../../config/agent-routing.yml"
}

# validate_watcher_verdict <json> -> 0 if it conforms to watcher.schema.json shape.
validate_watcher_verdict() {
  echo "$1" | jq -e '
    (.verdict | type == "string") and (.verdict | test("^(approve|reject|escalate)$")) and
    (.confidence | type == "number") and (.confidence >= 0 and .confidence <= 1) and
    (.reason | type == "string") and (.reason | length > 0) and
    # optional arrays, when present, must be arrays of strings
    ((has("violated_rules")   | not) or (.violated_rules   | type == "array" and (all(.[]; type == "string")))) and
    ((has("required_changes") | not) or (.required_changes | type == "array" and (all(.[]; type == "string"))))
  ' >/dev/null 2>&1
}

# validate_reviewer_verdict <json> -> 0 if it conforms to reviewer.schema.json shape,
# including the shape + enums of each blocking/non-blocking issue.
validate_reviewer_verdict() {
  echo "$1" | jq -e '
    (.verdict | type == "string") and (.verdict | test("^(approve|reject)$")) and
    (.confidence | type == "number") and (.confidence >= 0 and .confidence <= 1) and
    (.blocking_issues | type == "array") and
    (all(.blocking_issues[];
        (.rule | type == "string") and
        (.severity | type == "string") and (.severity | test("^(critical|high|normal|low)$")) and
        (.description | type == "string") and (.description | length > 0) and
        (.required_change | type == "string") and (.required_change | length > 0))) and
    ((has("non_blocking_issues") | not) or
     (.non_blocking_issues | type == "array") and
     (all(.non_blocking_issues[];
        (.description | type == "string") and (.description | length > 0) and
        ((has("severity") | not) or (.severity | test("^(critical|high|normal|low)$"))))))
  ' >/dev/null 2>&1
}

# should_escalate <verdict_json> <changed_files> <repeat_count>
# Echoes "escalate: <reason>" or "ok: <reason>". Cheap-first: only the documented
# triggers escalate to premium.
should_escalate() {
  local json="$1" changed="$2" repeat="${3:-0}"
  local conf_min n_thresh
  conf_min="${AGENT_CONFIDENCE_MIN:-$(yq -r '.escalation.confidence_min // 0.7' "$(_esc_routing_path)")}"
  n_thresh="${AGENT_ESCALATE_AFTER_N:-$(yq -r '.escalation.builder_escalate_after_n // 3' "$(_esc_routing_path)")}"

  local verdict conf
  verdict="$(echo "$json" | jq -r '.verdict // "approve"')"
  conf="$(echo "$json" | jq -r '.confidence // 1')"
  # Defensive: malformed/empty confidence values would break the awk comparison below.
  [[ "$conf"     =~ ^[0-9]+(\.[0-9]+)?$ ]] || conf=1
  [[ "$conf_min" =~ ^[0-9]+(\.[0-9]+)?$ ]] || conf_min=0.7

  if [[ "$verdict" == "escalate" ]]; then
    echo "escalate: verdict=escalate"; return 0
  fi

  # Sensitive-path trigger (any changed file matching any configured glob).
  # changed files are newline-delimited (git diff --name-only); read robustly so
  # filenames containing spaces are matched as single units.
  # `[[ == ]]` has no globstar, so a `**/foo/**` glob would miss ROOT-level
  # `foo/...` paths; derive a `**/`-stripped sub-pattern and also match it bare
  # and `*/`-prefixed so root-level sensitive files still trigger.
  local glob f sub
  while IFS= read -r glob; do
    [[ -z "$glob" ]] && continue
    sub=""
    [[ "$glob" == '**/'* ]] && sub="${glob#'**/'}"
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      # shellcheck disable=SC2053
      if [[ "$f" == $glob ]] \
         || { [[ -n "$sub" ]] && { [[ "$f" == $sub ]] || [[ "$f" == */$sub ]]; }; }; then
        echo "escalate: sensitive path $f (matches $glob)"; return 0
      fi
    done <<< "$changed"
  done < <(yq -r '.escalation.sensitive_paths[]' "$(_esc_routing_path)" 2>/dev/null)

  # Low-confidence trigger.
  if awk "BEGIN{exit !($conf < $conf_min)}"; then
    echo "escalate: confidence $conf < $conf_min"; return 0
  fi

  # Repeated-failure trigger.
  if [[ "$repeat" -ge "$n_thresh" ]]; then
    echo "escalate: repeat $repeat >= $n_thresh"; return 0
  fi

  echo "ok: no escalation trigger (verdict=$verdict conf=$conf repeat=$repeat)"
  return 0
}
