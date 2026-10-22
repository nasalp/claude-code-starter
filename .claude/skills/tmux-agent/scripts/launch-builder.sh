#!/usr/bin/env bash
set -uo pipefail

_claude_cmd_prefix() {
  if [[ -n "${HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON:-}" ]]; then
    printf 'HEADROOM_MODE=token HEADROOM_TELEMETRY=off HEADROOM_LOCAL_CONTROL_GUARD_ENABLED=true %q -m headroom.cli wrap claude --port %q --no-context-tool --no-mcp --no-serena --' \
      "$HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON" "${HEADROOM_LOCAL_CLAUDE_PROXY_PORT:-8787}"
    return 0
  fi
  printf 'claude'
}

_LB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# STEER channel instruction appended to the builder brief (cooperative V1).
_steer_brief_snippet() {
  local run_dir="$1"
  cat <<EOF

## STEER channel (MANDATORY checkpoints)

before each phase and before each commit, read \`${run_dir}/STEER.md\` if it exists.
If present, course-correct per its fields and acknowledge in your output:
\`STEER_ACK phase=<p> severity=<s> action=<summary>\`
If \`${run_dir}/STEER.halt\` exists, stop the current phase until the steer is addressed.
Do **not** delete \`STEER.md\` — the watcher owns that file.
EOF
}

# Compose augmented builder prompt under RUN_DIR without mutating the source file.
_compose_augmented_prompt() {
  local source_prompt="$1" run_dir="$2" dest="$3"
  [[ -f "$source_prompt" ]] || return 1
  mkdir -p "$run_dir" || return 1
  {
    cat "$source_prompt"
    _steer_brief_snippet "$run_dir"
  } > "$dest"
}

# Resolve RUN_DIR from env or TMUX_AGENT_TMPDIR + run_id.
_resolve_run_dir() {
  local run_id="$1"
  if [[ -n "${RUN_DIR:-}" ]]; then
    printf '%s\n' "$RUN_DIR"
    return 0
  fi
  local base="${TMUX_AGENT_TMPDIR:-/tmp/tmux-agent}"
  printf '%s/%s\n' "$base" "$run_id"
}

# Compose the builder invocation for a build pass.
#
# Engine + model are env-driven (opt-in, backwards compatible):
#   BUILDER_ENGINE  claude (default) | cursor | <any provider in agent-providers.yml>
#   BUILDER_MODEL   model id; defaults to `sonnet` on the claude engine
#                   (Opus->Sonnet: the cheap stepping-stone before the cursor path),
#                   and to the provider's own default on other engines.
# The default (unset) path is the historical claude invocation, model = sonnet.
_builder_cmd() {
  local repo="$1" prompt="$2" out="$3"
  [[ -z "$prompt" ]] && return 2
  [[ -z "$repo" ]] && return 2
  [[ -z "$out" ]] && return 2

  local engine="${BUILDER_ENGINE:-claude}"
  [[ "$engine" == "cursor" ]] && engine="composer"   # alias for the Composer/Cursor provider

  if [[ "$engine" == "claude" ]]; then
    local model="${BUILDER_MODEL:-sonnet}"
    local claude_cmd
    claude_cmd=$(_claude_cmd_prefix)
    printf '%s' \
      "$claude_cmd --print --model $model --tools default" \
      " --permission-mode bypassPermissions" \
      " --output-format=stream-json --include-partial-messages --verbose" \
      " --add-dir $repo" \
      " --add-dir \$HOME/.claude/rules" \
      " --add-dir \$HOME/.claude/skills" \
      " < $prompt" \
      " > $out 2>&1"
    return 0
  fi

  # Non-claude engine: delegate to the provider registry. Empty model => provider default.
  # shellcheck source=lib/agent-providers.sh
  source "$_LB_DIR/lib/agent-providers.sh"
  compose_provider_cmd "$engine" "${BUILDER_MODEL:-}" "$repo" "$prompt" "$out"
}

# Compose tmux session name for the builder.
_session_name() {
  local run_id="$1"
  printf 'builder-%s\n' "$run_id"
}

# CLI: launch-builder <run-id> <repo> <prompt-path> <out-path>
launch_builder_main() {
  if (( $# < 4 )); then
    echo "usage: launch-builder.sh RUN_ID REPO PROMPT_PATH OUT_PATH" >&2
    return 2
  fi
  local run_id="$1" repo="$2" prompt="$3" out="$4"
  local session cmd run_dir augmented_prompt
  session=$(_session_name "$run_id")
  run_dir="$(_resolve_run_dir "$run_id")"
  augmented_prompt="${run_dir}/builder-prompt.augmented.md"
  _compose_augmented_prompt "$prompt" "$run_dir" "$augmented_prompt" || return 2
  prompt="$augmented_prompt"

  # Any non-claude engine whose provider lacks --add-dir needs the rule tree staged
  # into the worktree so the cheap builder still loads every rule (constraint C1).
  # Resolve dynamically (not a hardcoded cursor/composer list) so deepseek/qwen/etc.
  # are covered too. No-op for claude.
  local engine="${BUILDER_ENGINE:-claude}"
  [[ "$engine" == "cursor" ]] && engine="composer"
  if [[ "$engine" != "claude" ]]; then
    # shellcheck source=lib/agent-providers.sh
    source "$_LB_DIR/lib/agent-providers.sh"
    if [[ "$(provider_add_dir_supported "$engine" 2>/dev/null)" == "false" ]]; then
      bash "$_LB_DIR/mount-rules-into-worktree.sh" "$repo" >/dev/null 2>&1 || true
    fi
  fi

  cmd=$(_builder_cmd "$repo" "$prompt" "$out") || return 2
  # SKIP_AUTO_TEST=true: per ~/.claude/hooks/auto-test.sh own opt-out
  # — orchestrated builders run their own canonical verify and must
  # NOT race the post-Edit auto-test hook. Without this the hook fires
  # after every Write/Edit, blocks the builder, and stalls Phase N
  # GREEN for 15+ minutes (calibration 2026-05-31 on 227 run).
  # `env VAR=val …` rather than tmux's `-e` (tmux 3.0+) for portability.
  tmux new-session -d -s "$session" -x 220 -y 50 \
    "env SKIP_AUTO_TEST=true bash -c $(printf '%q' "$cmd")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  launch_builder_main "$@"
fi
