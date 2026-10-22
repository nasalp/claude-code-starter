#!/usr/bin/env bash
# Provider registry resolver. Reads config/agent-providers.yml via yq v4.
# Source this file; call the functions. No top-level side effects.
set -uo pipefail

# Echo the providers config path (env override wins).
providers_config_path() {
  if [[ -n "${AGENT_PROVIDERS_CONFIG:-}" ]]; then
    printf '%s\n' "$AGENT_PROVIDERS_CONFIG"; return 0
  fi
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s\n' "$lib_dir/../../config/agent-providers.yml"
}

# Fail with an install hint when yq is missing.
require_yq() {
  command -v yq >/dev/null 2>&1 && return 0
  echo "agent-providers: 'yq' not found on PATH — install yq v4 (e.g. brew install yq)." >&2
  return 1
}

# 0 if the provider key exists in the registry.
_provider_exists() {
  require_yq || return 1
  yq -e ".providers.$1" "$(providers_config_path)" >/dev/null 2>&1
}

# Echo one field of a provider; fail if the provider is unknown.
provider_field() {
  local p="$1" field="$2"
  _provider_exists "$p" || { echo "unknown provider: $p" >&2; return 1; }
  # NOT `// ""` — that collapses a boolean `false` (jq/yq treats false as empty).
  local v
  v="$(yq -r ".providers.${p}.${field}" "$(providers_config_path)")"
  [[ "$v" == "null" ]] && v=""
  printf '%s\n' "$v"
}

provider_command()          { provider_field "$1" command; }
provider_tier()             { provider_field "$1" tier; }
provider_runtime()          { provider_field "$1" runtime; }
provider_default_model()    { provider_field "$1" default_model; }
provider_prompt_delivery()  { provider_field "$1" prompt_delivery; }
provider_auth_env()         { provider_field "$1" auth_env; }
provider_add_dir_supported(){ provider_field "$1" add_dir_supported; }

# Headroom wrap prefix for the claude provider (mirrors launch-builder.sh::_claude_cmd_prefix).
# Echoes the wrapper ending in `--` so the claude args follow; empty when Headroom not exported.
_headroom_claude_prefix() {
  [[ -n "${HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON:-}" ]] || return 1
  printf 'HEADROOM_MODE=token HEADROOM_TELEMETRY=off HEADROOM_LOCAL_CONTROL_GUARD_ENABLED=true %q -m headroom.cli wrap claude --port %q --no-context-tool --no-mcp --no-serena --' \
    "$HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON" "${HEADROOM_LOCAL_CLAUDE_PROXY_PORT:-8787}"
}

# provider_reasoning <provider> <effort> -> the provider-native reasoning fragment
# (a flag string for reasoning_style=flag, or an ENV=val for reasoning_style=env).
# Empty when the provider has no reasoning support or effort is empty.
provider_reasoning() {
  local provider="$1" effort="$2"
  [[ -z "$effort" ]] && return 0
  local frag
  frag="$(yq -r ".providers.${provider}.reasoning_map.${effort} // \"\"" "$(providers_config_path)")"
  [[ "$frag" == "null" ]] && frag=""
  printf '%s' "$frag"
}

# compose_provider_cmd <provider> <model> <repo> <prompt_file> <out> [effort] [role]
# Renders the provider's invocation template. Empty model -> provider default_model.
# Optional effort (low|medium|high) maps to the provider's reasoning mechanism:
#   reasoning_style=flag -> substituted into the {effort} placeholder (e.g. codex)
#   reasoning_style=env  -> prepended as an ENV assignment (e.g. claude thinking budget)
# Optional role gates {tools}/{dirs}: cognitive roles (not builder/watcher) get read-only
# tools (Read,Glob,Grep) with repo/rules/skills mounts; builder/watcher keep default tools.
# Providers without reasoning support ignore effort (use model tier instead).
# $HOME inside templates is preserved literally (expanded by the executing shell).
compose_provider_cmd() {
  local provider="$1" model="$2" repo="$3" prompt_file="$4" out="$5" effort="${6:-}" role="${7:-}"
  _provider_exists "$provider" || { echo "unknown provider: $provider" >&2; return 1; }
  [[ -z "$model" ]] && model="$(provider_default_model "$provider")"

  # Resolve reasoning fragment (flag vs env) for the requested effort.
  local effort_flag="" effort_env="" style frag
  if [[ -n "$effort" ]]; then
    style="$(provider_field "$provider" reasoning_style 2>/dev/null)"
    frag="$(provider_reasoning "$provider" "$effort")"
    case "$style" in
      flag) effort_flag="$frag" ;;
      env)  effort_env="$frag" ;;
    esac
  fi

  local tmpl
  tmpl="$(yq -r ".providers.${provider}.invocation" "$(providers_config_path)")"
  [[ -z "$tmpl" || "$tmpl" == "null" ]] && { echo "provider $provider has no invocation template" >&2; return 1; }

  # Shell-quote substituted VALUES (not the template literals — `$HOME` in the
  # template must stay literal so the executing shell expands it). This makes
  # paths/models containing spaces or shell metacharacters safe under `bash -c`.
  local model_q repo_q pf_q out_q
  model_q="$(printf '%q' "$model")"
  repo_q="$(printf '%q' "$repo")"
  pf_q="$(printf '%q' "$prompt_file")"
  out_q="$(printf '%q' "$out")"

  local approval_mode_val="yolo"
  if [[ -n "$role" && "$role" != "builder" && "$role" != "watcher" ]]; then
    approval_mode_val="plan"
  fi

  local tools_val="default" dirs_val=""
  if [[ -n "$role" && "$role" != "builder" && "$role" != "watcher" ]]; then
    tools_val="Read,Glob,Grep"
    case "$provider" in
      claude)
        dirs_val="--add-dir $repo_q --add-dir \$HOME/.claude/rules --add-dir \$HOME/.claude/skills"
        ;;
      gemini|gemini-flash)
        dirs_val="--include-directories $repo_q,\$HOME/.claude/rules,\$HOME/.claude/skills"
        ;;
    esac
  else
    tools_val="default"
    case "$provider" in
      claude)
        dirs_val="--add-dir $repo_q --add-dir \$HOME/.claude/rules --add-dir \$HOME/.claude/skills"
        ;;
      gemini|gemini-flash)
        dirs_val="--include-directories $repo_q,\$HOME/.claude/rules,\$HOME/.claude/skills"
        ;;
    esac
  fi

  local cmd="$tmpl"
  cmd="${cmd//\{model\}/$model_q}"
  cmd="${cmd//\{repo\}/$repo_q}"
  cmd="${cmd//\{prompt_file\}/$pf_q}"
  cmd="${cmd//\{out\}/$out_q}"
  cmd="${cmd//\{effort\}/$effort_flag}"
  cmd="${cmd//\{tools\}/$tools_val}"
  cmd="${cmd//\{dirs\}/$dirs_val}"
  cmd="${cmd//\{approval_mode\}/$approval_mode_val}"
  # Collapse the double space left when {effort} renders empty.
  cmd="${cmd//  / }"

  # claude provider: prepend Headroom wrapper, replacing the leading `claude` token.
  if [[ "$provider" == "claude" ]]; then
    local prefix
    if prefix="$(_headroom_claude_prefix 2>/dev/null)"; then
      cmd="${prefix}${cmd#claude}"
    fi
  fi
  # env-style reasoning (e.g. claude thinking budget) prepends an ENV assignment.
  [[ -n "$effort_env" ]] && cmd="$effort_env $cmd"
  printf '%s\n' "$cmd"
}
