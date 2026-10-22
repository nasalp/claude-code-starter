#!/usr/bin/env bash
# Deterministic unattended driver for tmux-agent work units.
# FSM: INIT -> BUILD -> AUDIT -> ... -> ASSESS -> SHIP (draft PR only).
set -uo pipefail

_NL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/issue-mirror.sh
source "$_NL_DIR/lib/issue-mirror.sh"
# shellcheck source=lib/agent-escalation.sh
source "$_NL_DIR/lib/agent-escalation.sh"

NL_PHASE_INIT="INIT"
NL_PHASE_BUILD="BUILD"
NL_PHASE_AUDIT="AUDIT"
NL_PHASE_ASSESS="ASSESS"
NL_PHASE_SHIP="SHIP"

_nl_usage() {
  echo "usage: night-loop.sh run --repo PATH [--run-id ID] [--issue N]" >&2
  echo "       night-loop.sh resume --issue N [--repo PATH]" >&2
  echo "       night-loop.sh advance-phase --run-dir DIR --verdict-dir DIR" >&2
  exit 2
}

_nl_run_dir_from_id() {
  local run_id="$1"
  local base="${TMUX_AGENT_TMPDIR:-/tmp/tmux-agent}"
  printf '%s/%s\n' "$base" "$run_id"
}

_nl_state_path() {
  printf '%s/orchestrator-state.md\n' "$1"
}

_nl_read_state_key() {
  local run_dir="$1" key="$2"
  local state
  state=$(_nl_state_path "$run_dir")
  [[ -f "$state" ]] || return 1
  awk -F':[[:space:]]*' -v k="$key" '$1 == k { print $2; exit }' "$state"
}

_nl_set_phase() {
  local run_dir="$1" phase="$2"
  local state tmp content
  state=$(_nl_state_path "$run_dir")
  [[ -f "$state" ]] || return 1
  tmp="${state}.tmp.$$"
  content="$(awk -v p="$phase" '
    BEGIN { found=0 }
    /^phase:/ { print "phase: " p; found=1; next }
    { print }
    END { if (!found) print "phase: " p }
  ' "$state")"
  _state_write "$run_dir" "$content"
}

_nl_log() {
  local run_dir="$1"
  shift
  local log="$run_dir/night-loop.log"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$log"
}

_nl_safe_import_kv() {
  local line key val
  while IFS= read -r line; do
    case "$line" in
      RUN_ID=*)
        val="${line#RUN_ID=}"
        [[ "$val" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
        RUN_ID="$val"
        export RUN_ID
        ;;
      RUN_DIR=*)
        val="${line#RUN_DIR=}"
        [[ -n "$val" && "$val" != *$'\n'* && "$val" != *$';'* ]] || return 1
        RUN_DIR="$val"
        export RUN_DIR
        ;;
    esac
  done
}

_nl_builder_packet() {
  local run_dir="$1"
  local packet="${NIGHT_LOOP_BUILDER_PACKET:-}"
  if [[ -z "$packet" ]]; then
    packet="$run_dir/builder-packet.md"
  fi
  printf '%s\n' "$packet"
}

_nl_cmd() {
  local name="$1"
  shift
  if [[ -n "${NIGHT_LOOP_STUB_DIR:-}" && -x "${NIGHT_LOOP_STUB_DIR}/${name}" ]]; then
    "${NIGHT_LOOP_STUB_DIR}/${name}" "$@"
    return $?
  fi
  command -v "$name" >/dev/null 2>&1 || return 127
  "$name" "$@"
}

_nl_wait_builder_terminal() {
  local out="$1" task_id="$2"
  local pattern="${task_id} EXIT|BUILD SUCCESS|BUILD FAILURE"
  if [[ -n "${NIGHT_LOOP_TEST_MODE:-}" ]]; then
    [[ -f "${out}.terminal" ]] && return 0
    return 1
  fi
  local sleep_sec="${NIGHT_LOOP_MONITOR_SLEEP:-40}"
  local max_sec="${NIGHT_LOOP_BUILDER_WAIT_SEC:-7200}"
  local elapsed=0
  until grep -qE "$pattern" "$out" 2>/dev/null; do
    sleep "$sleep_sec"
    elapsed=$((elapsed + sleep_sec))
    if (( elapsed >= max_sec )); then
      echo "ERROR: builder wait timed out after ${max_sec}s (no terminal marker in $out)" >&2
      return 1
    fi
  done
}

_nl_any_reject() {
  local run_dir="$1"
  local f json verdict
  shopt -s nullglob
  for f in "$run_dir"/watcher-verdict-*.json "$run_dir"/verdict-watcher-*.json; do
    [[ -f "$f" ]] || continue
    json="$(cat "$f")"
    if ! validate_watcher_verdict "$json"; then
      return 2
    fi
    verdict="$(printf '%s' "$json" | jq -r '.verdict')"
    if [[ "$verdict" == "reject" ]]; then
      return 1
    fi
  done
  return 0
}

_nl_run_audit_cycle() {
  local repo="$1" run_id="$2"
  if [[ -n "${NIGHT_LOOP_STUB_DIR:-}" && -x "${NIGHT_LOOP_STUB_DIR}/audit-cycle.sh" ]]; then
    bash "${NIGHT_LOOP_STUB_DIR}/audit-cycle.sh" --repo "$repo" "$run_id"
    return $?
  fi
  bash "$_NL_DIR/audit-cycle.sh" --repo "$repo" "$run_id"
}

_nl_run_check_watchers() {
  local run_id="$1"
  shift
  bash "$_NL_DIR/check-watchers.sh" "$run_id" "$@"
}

_nl_run_pre_merge_gate() {
  local pr="$1" run_dir="$2"
  shift 2
  if [[ -n "${NIGHT_LOOP_STUB_DIR:-}" && -x "${NIGHT_LOOP_STUB_DIR}/pre-admin-merge-gate.sh" ]]; then
    bash "${NIGHT_LOOP_STUB_DIR}/pre-admin-merge-gate.sh" "$pr" "$run_dir" "$@"
    return $?
  fi
  bash "$_NL_DIR/orchestration/pre-admin-merge-gate.sh" "$pr" "$run_dir" "$@"
}

_nl_spawn_builder() {
  local wt="$1" packet="$2" run_id="$3"
  export RUN_ID="$run_id"
  _nl_cmd agent-spawn.sh builder auto "$wt" "$packet"
}

_nl_advance_phase() {
  local run_dir="$1"
  local phase
  phase=$(_nl_read_state_key "$run_dir" "phase")
  case "$phase" in
    "$NL_PHASE_INIT"|INIT|PLAN) _nl_set_phase "$run_dir" "$NL_PHASE_BUILD" ;;
    "$NL_PHASE_BUILD"|BUILD*)   _nl_set_phase "$run_dir" "$NL_PHASE_AUDIT" ;;
    "$NL_PHASE_AUDIT"|AUDIT*)   _nl_set_phase "$run_dir" "$NL_PHASE_ASSESS" ;;
    "$NL_PHASE_ASSESS"|ASSESS*) _nl_set_phase "$run_dir" "$NL_PHASE_SHIP" ;;
    *) return 1 ;;
  esac
}

_nl_gate_after_audit() {
  local run_dir="$1" repo="$2" run_id="$3"
  local rc=0

  _nl_log "$run_dir" "audit-cycle start"
  _nl_run_audit_cycle "$repo" "$run_id" || rc=$?

  if [[ -n "${NIGHT_LOOP_SKIP_WATCHERS:-}" ]]; then
    _nl_any_reject "$run_dir" || rc=$?
    return "$rc"
  fi

  _nl_log "$run_dir" "check-watchers start"
  _nl_run_check_watchers "$run_id" composer gemini-flash || rc=$?

  _nl_any_reject "$run_dir"
  case $? in
    0) ;;
    1) _nl_log "$run_dir" "REJECT blocks advance"; return 1 ;;
    2) _nl_log "$run_dir" "BLIND/empty verdict blocks advance"; return 1 ;;
  esac

  return "$rc"
}

_nl_ship() {
  local run_dir="$1" run_id="$2" repo="$3"
  local pr_body pr_url pr

  pr_body="$(cat <<EOF
## Night-loop ship

- Locked decisions: see GH issue trail
- Production checklist: mirrored on orchestration issue
- Orchestration log: \$RUN_DIR/night-loop.log

issue_number: $(_nl_read_state_key "$run_dir" "issue_number")
consensus plan-of-work: see orchestration issue #$(_nl_read_state_key "$run_dir" "issue_number")
production-readiness checklist: see orchestration issue #$(_nl_read_state_key "$run_dir" "issue_number")
EOF
)"

  if [[ -n "${NIGHT_LOOP_TEST_MODE:-}" ]]; then
    printf '%s\n' "$pr_body" > "$run_dir/draft-pr-body.md"
    _nl_log "$run_dir" "draft-pr-body written (test mode)"
    pr="99" # test mode pr number
  else
    pr_url=$(_nl_cmd gh pr create --draft --title "feat(tmux-agent): night-loop assembly" --body "$pr_body") || return 1
    _nl_log "$run_dir" "draft PR: $pr_url"
    pr="$(printf '%s' "$pr_url" | grep -oE '[0-9]+$' || true)"
    [[ -n "$pr" ]] && printf '%s\n' "$pr" > "$run_dir/pr-number"
  fi

  if [[ -z "$pr" ]]; then
    _nl_log "$run_dir" "SHIP blocked: no PR number"
    return 1
  fi

  _nl_log "$run_dir" "pre-admin-merge-gate pr=${pr:-0}"
  _nl_run_pre_merge_gate "$pr" "$run_dir" || return 1

  if [[ -z "${NIGHT_LOOP_SKIP_TEARDOWN:-}" ]]; then
    if [[ -n "${NIGHT_LOOP_STUB_DIR:-}" && -x "${NIGHT_LOOP_STUB_DIR}/teardown-run.sh" ]]; then
      bash "${NIGHT_LOOP_STUB_DIR}/teardown-run.sh" --repo "$repo" ${pr:+--pr "$pr"} "$run_id"
    else
      bash "$_NL_DIR/teardown-run.sh" --repo "$repo" ${pr:+--pr "$pr"} "$run_id"
    fi
  fi
}

_nl_build_once() {
  local run_dir="$1" repo="$2" run_id="$3" wt="$4" packet="$5" task_id="$6"
  local out="$run_dir/agent-builder-${task_id}.out"

  _nl_set_phase "$run_dir" "${NL_PHASE_BUILD}_${task_id}"
  _nl_log "$run_dir" "spawn builder task=$task_id"

  if [[ -n "${NIGHT_LOOP_TEST_MODE:-}" ]]; then
    : > "$out"
  else
    _nl_spawn_builder "$wt" "$packet" "$run_id" || return 1
    out="$run_dir/agent-builder-composer.out"
  fi

  _nl_wait_builder_terminal "$out" "$task_id" || return 1
  _nl_set_phase "$run_dir" "${NL_PHASE_AUDIT}_${task_id}"
  _nl_gate_after_audit "$run_dir" "$repo" "$run_id"
}

_nl_advance_phase_cmd() {
  local run_dir="$1"
  local repo run_id
  repo=$(_nl_read_state_key "$run_dir" "repo")
  run_id=$(_nl_read_state_key "$run_dir" "run_id")
  [[ -z "$run_id" ]] && run_id="$(basename "$run_dir")"

  _nl_gate_after_audit "$run_dir" "$repo" "$run_id" || return 1
  _nl_advance_phase "$run_dir" || return 1
  _nl_log "$run_dir" "advanced to phase=$(_nl_read_state_key "$run_dir" phase)"
  _issue_mirror "$run_dir" "Phase advanced to $(_nl_read_state_key "$run_dir" phase)"
}

_nl_resume_main() {
  local issue="$1"
  local out
  out=$(_issue_resume "$issue") || return 1
  printf '%s\n' "$out"
}

_nl_run_main() {
  local repo="" run_id="" issue=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)  repo="$2"; shift 2 ;;
      --run-id) run_id="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -n "$repo" && -d "$repo" ]] || { echo "night-loop: --repo required" >&2; return 2; }

  local run_dir
  if [[ -n "$run_id" ]]; then
    run_dir=$(_nl_run_dir_from_id "$run_id")
  elif [[ -n "$issue" ]]; then
    _nl_safe_import_kv < <(_issue_resume "$issue") || return 1
    run_dir="$RUN_DIR"
    run_id="$RUN_ID"
  else
    _nl_safe_import_kv < <(bash "$_NL_DIR/init-run.sh" night-loop) || return 1
    run_id="$RUN_ID"
    run_dir="$RUN_DIR"
  fi

  mkdir -p "$run_dir"
  export RUN_ID="$run_id" RUN_DIR="$run_dir"

  if [[ ! -f "$(_nl_state_path "$run_dir")" ]]; then
    _state_write "$run_dir" "$(cat <<EOF
repo: $repo
run_id: $run_id
branch: $(git -C "$repo" branch --show-current 2>/dev/null || echo unknown)
phase: $NL_PHASE_INIT
issue_number: ${issue:-}
EOF
)"
  fi

  _nl_set_phase "$run_dir" "$NL_PHASE_BUILD"
  _nl_log "$run_dir" "night-loop run start repo=$repo"

  local packet wt task_id
  packet=$(_nl_builder_packet "$run_dir")
  wt="${NIGHT_LOOP_BUILDER_WT:-$repo}"
  task_id="${NIGHT_LOOP_BUILD_TASK_ID:-build}"
  if [[ -n "${NIGHT_LOOP_TEST_MODE:-}" ]]; then
    packet="/dev/null"
  elif [[ ! -f "$packet" ]]; then
    echo "night-loop: builder packet missing: $packet" >&2
    return 2
  fi
  _nl_build_once "$run_dir" "$repo" "$run_id" "$wt" "$packet" "$task_id" || return 1

  _nl_set_phase "$run_dir" "$NL_PHASE_ASSESS"
  _nl_gate_after_audit "$run_dir" "$repo" "$run_id" || return 1

  _nl_set_phase "$run_dir" "$NL_PHASE_SHIP"
  _nl_ship "$run_dir" "$run_id" "$repo"
}

night_loop_main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    run)            _nl_run_main "$@" ;;
    resume)         [[ "${1:-}" == "--issue" && -n "${2:-}" ]] || _nl_usage; _nl_resume_main "$2" ;;
    advance-phase)  [[ "${1:-}" == "--run-dir" && -n "${2:-}" ]] || _nl_usage; _nl_advance_phase_cmd "$2" ;;
    *)              _nl_usage ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  night_loop_main "$@"
fi
