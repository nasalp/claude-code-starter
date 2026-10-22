#!/usr/bin/env bash
# Role -> provider routing. Reads config/agent-routing.yml via yq v4.
# Env AGENT_ROUTE_<ROLE> overrides the configured default for that role.
set -uo pipefail

routing_config_path() {
  if [[ -n "${AGENT_ROUTING_CONFIG:-}" ]]; then
    printf '%s\n' "$AGENT_ROUTING_CONFIG"; return 0
  fi
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s\n' "$lib_dir/../../config/agent-routing.yml"
}

_routing_require_yq() {
  command -v yq >/dev/null 2>&1 && return 0
  echo "agent-routing: 'yq' not found on PATH — install yq v4." >&2
  return 1
}

# Uppercase a-z -> A-Z without bash 4 ${x^^} (macOS /bin/bash is 3.2).
_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# route_role <role> -> provider. Env override wins; else routing.yml; else fail.
route_role() {
  local role="$1"
  local envvar
  envvar="AGENT_ROUTE_$(_upper "$role")"
  local override="${!envvar:-}"
  if [[ -n "$override" ]]; then printf '%s\n' "$override"; return 0; fi

  _routing_require_yq || return 1
  local p
  p="$(yq -r ".roles.${role} // \"\"" "$(routing_config_path)")"
  [[ -z "$p" || "$p" == "null" ]] && { echo "unknown role: $role" >&2; return 1; }
  printf '%s\n' "$p"
}

# watcher_fleet -> the cheap watcher providers, one per line.
# Env override: AGENT_WATCHER_FLEET="composer,gemini-flash". Falls back to routing.yml.
watcher_fleet() {
  if [[ -n "${AGENT_WATCHER_FLEET:-}" ]]; then
    printf '%s\n' "${AGENT_WATCHER_FLEET//,/$'\n'}"; return 0
  fi
  _routing_require_yq || return 1
  yq -r '.watcher_fleet[]' "$(routing_config_path)"
}

# role_effort <role> -> low|medium|high. Env AGENT_EFFORT_<ROLE> wins; else routing.yml;
# else "medium". A cost lever mapped per provider by compose_provider_cmd.
role_effort() {
  local role="$1" envvar override
  envvar="AGENT_EFFORT_$(_upper "$role")"
  override="${!envvar:-}"
  if [[ -n "$override" ]]; then printf '%s\n' "$override"; return 0; fi
  _routing_require_yq || return 1
  local e
  e="$(yq -r ".role_effort.${role} // \"\"" "$(routing_config_path)")"
  [[ -z "$e" || "$e" == "null" ]] && e="medium"
  printf '%s\n' "$e"
}

# role_tier <role> -> premium|standard|cheap
role_tier() {
  local role="$1"
  _routing_require_yq || return 1
  local t
  t="$(yq -r ".role_tier.${role} // \"\"" "$(routing_config_path)")"
  [[ -z "$t" || "$t" == "null" ]] && { echo "unknown role: $role" >&2; return 1; }
  printf '%s\n' "$t"
}
