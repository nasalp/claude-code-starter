#!/usr/bin/env bash
set -uo pipefail

_WL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/steer.sh
source "$_WL_DIR/lib/steer.sh"

# Poll interval: WATCHER_POLL_SECONDS overrides; cheap engines default lower.
_watcher_poll_seconds() {
  if [[ -n "${WATCHER_POLL_SECONDS:-}" ]]; then
    printf '%s\n' "$WATCHER_POLL_SECONDS"
    return 0
  fi
  local engine="${WATCHER_ENGINE:-claude}"
  case "$engine" in
    composer|gemini-flash)
      printf '%s\n' "${STEER_POLL_SECONDS:-45}"
      ;;
    *)
      printf '%s\n' "300"
      ;;
  esac
}

# Resolve RUN_DIR for steer writes from env or verdict_dir parent.
_watcher_run_dir() {
  local verdict_dir="$1"
  if [[ -n "${RUN_DIR:-}" ]]; then
    printf '%s\n' "$RUN_DIR"
    return 0
  fi
  dirname "$verdict_dir"
}

# Compact UTC timestamp, sortable, no separators.
_now_ts() {
  date -u +%Y%m%dT%H%M%SZ
}

# Echo the SHA of a ref after `git fetch`; empty on failure.
_resolve_branch_sha() {
  local ref="$1"
  git fetch origin >/dev/null 2>&1 || true
  git rev-parse "$ref" 2>/dev/null || echo ""
}

# Byte count of a file; 0 if missing.
_file_size() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo 0
    return 0
  fi
  if stat -f%z "$path" 2>/dev/null; then
    return 0
  fi
  stat -c%s "$path" 2>/dev/null || echo 0
}

# 0 (true) if either sha or output bytes advanced since last pass.
_activity_detected() {
  local sha="$1" last_sha="$2" size="$3" last_size="$4"
  [[ -z "$sha" ]] && return 1
  [[ "$sha" != "$last_sha" ]] && return 0
  (( size > last_size )) && return 0
  return 1
}

# 0 (true) if we should fire an LLM audit pass.
#
# Cache-guard logic (resolves the $9/hr → $2/hr cost issue flagged by the
# 3-reviewer consensus on 2026-05-31):
#   - Commit boundary (sha change) → ALWAYS audit. Most important signal.
#   - Size delta ≥ MIN_DELTA_BYTES → audit. Real activity worth re-reading.
#   - Heartbeat — quiet stretch ≥ MAX_QUIET_SECONDS → audit even when
#     nothing changed (keeps watcher visible to the orchestrator).
#   - Otherwise SKIP — saves the LLM call on builder.out growing by a
#     few bytes per minute (typing into one file).
#
# Args: SHA LAST_SHA SIZE LAST_SIZE LAST_AUDIT_TS MIN_DELTA MAX_QUIET
_should_audit() {
  local sha="$1" last_sha="$2" size="$3" last_size="$4"
  local last_audit_ts="$5" min_delta="$6" max_quiet="$7"
  [[ -z "$sha" ]] && return 1
  [[ "$sha" != "$last_sha" ]] && return 0
  # Size decreased (truncation / log rotation) → audit immediately so the
  # baseline resets. Without this, a negative delta stays below MIN_DELTA
  # forever and the size-based trigger locks off until the file grows past
  # the old size.
  (( size < last_size )) && return 0
  local delta=$(( size - last_size ))
  (( delta >= min_delta )) && return 0
  local now age
  now=$(date +%s)
  (( last_audit_ts > 0 )) || return 1
  age=$(( now - last_audit_ts ))
  (( age >= max_quiet )) && return 0
  return 1
}

# 0 (true) if the builder tmux session is alive.
# Caller passes the session name (typically `builder-$RUN_ID`).
# pgrep on the branch name doesn't work — the builder command line
# does not contain it.
_builder_alive() {
  local session="$1"
  tmux has-session -t "$session" 2>/dev/null
}

_run_claude_print() {
  if [[ -n "${HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON:-}" ]]; then
    HEADROOM_MODE=token \
    HEADROOM_TELEMETRY=off \
    HEADROOM_LOCAL_CONTROL_GUARD_ENABLED=true \
      "${HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON}" -m headroom.cli wrap claude \
        --port "${HEADROOM_LOCAL_CLAUDE_PROXY_PORT:-8787}" \
        --no-context-tool --no-mcp --no-serena -- "$@"
    return $?
  fi
  claude "$@"
}

_run_dir_path() {
  local run_id="$1"
  local base="${TMUX_AGENT_TMPDIR:-/tmp/tmux-agent}"
  printf '%s/%s\n' "$base" "$run_id"
}

_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

_write_audit_warnings_prepend() {
  local run_id="${RUN_ID:-}"
  [[ -n "$run_id" ]] || return 0
  local run_dir
  run_dir=$(_run_dir_path "$run_id")
  [[ -d "$run_dir" ]] || return 0

  local audit_script="${AUDIT_CYCLE_SCRIPT:-$(_script_dir)/audit-cycle.sh}"
  [[ -f "$audit_script" ]] || return 0

  local warnings_file="$run_dir/warnings-prepend.txt"
  local output
  output=$(bash "$audit_script" "$run_id" 2>&1)
  printf '%s\n' "$output" | awk '/^WARN / { print }' > "$warnings_file"
}

# 0 (true) if quiet_since is non-zero AND elapsed >= threshold seconds.
_drain_elapsed() {
  local quiet_since="$1" threshold="$2"
  (( quiet_since == 0 )) && return 1
  local now elapsed
  now=$(date +%s)
  elapsed=$(( now - quiet_since ))
  (( elapsed >= threshold ))
}

# Emit the structured WATCHER DIAGNOSTIC header.
# Args: PASS_NUM BRANCH REF SHA SHA_UNCHANGED_PASSES BUILDER_OUT BUILDER_OUT_SIZE [LEARNINGS_FILE]
# When SHA is empty, reports NONE + BLIND so the orchestrator notices.
# When LEARNINGS_FILE provided, advertises path so meta-harness can collect.
_diagnostic_header() {
  local pass="$1" branch="$2" ref="$3" sha="$4" unchanged="$5"
  local out="$6" size="$7" learnings="${8:-}"
  local sha_field="$sha"
  local blind_line=""
  if [[ -z "$sha" ]]; then
    sha_field="NONE"
    blind_line=$'BLIND: branch not on origin yet (or ref misconfigured)\n'
  fi
  local learn_line=""
  [[ -n "$learnings" ]] && learn_line="learnings_file: $learnings"$'\n'
  cat <<EOF
=== WATCHER DIAGNOSTIC ===
pass_number: $pass
watching_branch: $branch
ref_requested: $ref
sha_resolved: $sha_field
sha_unchanged_since_pass: $unchanged
file_being_audited: $out
file_size_bytes: $size
last_activity_ts: $(date -u +%Y-%m-%dT%H:%M:%SZ)
${learn_line}${blind_line}=== END DIAGNOSTIC ===
EOF
}

# Pull the === LEARNING CANDIDATES === block from a verdict file. Empty if absent.
_extract_learnings() {
  local verdict="$1"
  [[ -f "$verdict" ]] || return 0
  awk '
    /^=== LEARNING CANDIDATES ===/ { capture=1; next }
    /^=== END LEARNINGS ===/       { capture=0 }
    capture                        { print }
  ' "$verdict"
}

# Append a watcher pass'\''s LEARNING CANDIDATES (with a dated header) to a learnings file.
# Args: VERDICT_FILE PASS_NUM SHA LEARNINGS_FILE
_append_learnings() {
  local verdict="$1" pass="$2" sha="$3" learnings_file="$4"
  local body
  body=$(_extract_learnings "$verdict")
  [[ -z "$body" ]] && return 0
  mkdir -p "$(dirname "$learnings_file")"
  {
    echo
    echo "## pass=$pass sha=$sha ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "$body"
  } >> "$learnings_file"
}

# Write a structured BLIND verdict when the watcher can't resolve its ref.
# Args: PASS_NUM BRANCH REF VERDICT_PATH
_write_blind_verdict() {
  local pass="$1" branch="$2" ref="$3" path="$4"
  {
    _diagnostic_header "$pass" "$branch" "$ref" "" "$pass" "n/a" 0
    echo
    echo "BLIND: cannot resolve $ref — branch not yet visible. Skipping audit."
    echo "Action for the orchestrator: push the branch, or correct the ref."
  } > "$path"
}

# Fire one audit pass; write stdout to verdict file.
#
# Engine selection: WATCHER_ENGINE env var picks the model harness.
#   - claude (default)  → Headroom wrapper when installed, else claude --print
#   - codex             → codex exec --skip-git-repo-check
#
# Operator's recommended split for a 3-watcher run: 2 codex + 1 claude.
# Codex is cheaper at comparable review quality on file-diff audits.
# Claude Opus catches subtler architecture / rule-violation drift; keep one.
# See ~/.claude/rules/watchers-must-observe-live-tmux.md.
_run_audit_pass() {
  local repo="$1" brief="$2" verdict="$3"
  local session="${BUILDER_SESSION:-}"
  local engine="${WATCHER_ENGINE:-claude}"
  local pane_snapshot=""
  if [[ -n "$session" ]] && tmux has-session -t "$session" 2>/dev/null; then
    pane_snapshot=$(tmux capture-pane -t "$session" -p -S -500 2>/dev/null || echo "")
  fi
  _write_audit_warnings_prepend
  local warnings_file=""
  if [[ -n "${RUN_ID:-}" ]]; then
    warnings_file="$(_run_dir_path "$RUN_ID")/warnings-prepend.txt"
  fi
  local combined
  combined=$(mktemp)
  {
    if [[ -n "$warnings_file" && -s "$warnings_file" ]]; then
      echo "## AUDIT WARNINGS"
      echo
      cat "$warnings_file"
      echo
    fi
    cat "$brief"
    echo
    echo "## LIVE BUILDER TMUX PANE (last 500 lines)"
    echo
    echo '```'
    if [[ -n "$pane_snapshot" ]]; then
      printf '%s\n' "$pane_snapshot"
    else
      echo "(tmux session '$session' not capturable — no live pane available)"
    fi
    echo '```'
    echo
    echo "Use the pane snapshot above to audit what the builder is doing RIGHT NOW, in addition to what's already committed."
  } > "$combined"
  case "$engine" in
    codex)
      codex exec \
        --skip-git-repo-check \
        --dangerously-bypass-approvals-and-sandbox \
        -C "$repo" \
        --add-dir "$HOME/.claude" \
        - \
        < "$combined" > "$verdict" 2>&1
      ;;
    claude)
      local model="${WATCHER_MODEL:-opus}"
      _run_claude_print --print \
        --model "$model" \
        --tools default \
        --permission-mode bypassPermissions \
        --add-dir "$repo" \
        --add-dir "$HOME/.claude" \
        < "$combined" > "$verdict" 2>&1
      ;;
    *)
      # Any other engine (composer/cursor/gemini/…) routes through the provider
      # registry. Backwards compatible: WATCHER_ENGINE unset -> "claude" above.
      local _wl_dir gcmd
      _wl_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      # shellcheck source=lib/agent-providers.sh
      source "$_wl_dir/lib/agent-providers.sh"
      gcmd="$(compose_provider_cmd "$engine" "${WATCHER_MODEL:-}" "$repo" "$combined" "$verdict")" \
        && bash -c "$gcmd" \
        || echo "watcher: provider '$engine' failed to compose/run" > "$verdict"
      ;;
  esac
  rm -f "$combined"
}

# Strip the WATCHER DIAGNOSTIC header from a verdict; emit only the audit body.
# The diagnostic block belongs in on-disk verdict files for the orchestrator,
# not in every PR comment — posting it per pass spams the PR.
_strip_diagnostic_header() {
  local verdict="$1"
  awk '
    /^=== WATCHER DIAGNOSTIC ===/ { skip=1; next }
    /^=== END DIAGNOSTIC ===/     { skip=0; next }
    !skip                          { print }
  ' "$verdict" | sed -e '/./,$!d' -e ':a;/^\n*$/{$d;N;ba;}'
}

# Post verdict file as a PR comment when a PR exists; no-op otherwise.
# Skips posting when the audit body is empty (diagnostic-only pass) or
# identical to the previously posted body (deduplication).
_post_pr_comment() {
  local pr_repo="$1" branch="$2" verdict="$3"
  local pr
  pr=$(gh pr list --repo "$pr_repo" --head "$branch" \
                  --state open --json number \
                  --jq '.[0].number' 2>/dev/null)
  if [[ -z "$pr" ]]; then
    echo "no PR open for $branch"
    return 0
  fi
  local body_tmp last_posted
  body_tmp=$(mktemp)
  _strip_diagnostic_header "$verdict" > "$body_tmp"
  if [[ ! -s "$body_tmp" ]]; then
    rm -f "$body_tmp"
    echo "SKIP empty body pr=$pr"
    return 0
  fi
  last_posted="$(dirname "$verdict")/.last-posted-body.md"
  if [[ -f "$last_posted" ]] && cmp -s "$body_tmp" "$last_posted"; then
    rm -f "$body_tmp"
    echo "SKIP duplicate pr=$pr"
    return 0
  fi
  gh pr comment "$pr" --repo "$pr_repo" --body-file "$body_tmp" >/dev/null 2>&1
  mv "$body_tmp" "$last_posted"
  echo "POSTED $pr"
}

# Persistent watcher loop. Polls; runs an audit pass on each activity tick.
# Exits when builder session is gone AND drain window has elapsed.
#
# BRANCH_REF is the git ref to watch — pass `origin/foo` to track pushes,
# or just `foo` to track local commits in a worktree (origin-only misses local builder commits).
# BUILDER_SESSION is the tmux session name (typically `builder-$RUN_ID`).
watcher_loop_main() {
  if (( $# < 7 )); then
    echo "usage: watcher_loop_main REPO BRANCH_REF PR_REPO BUILDER_OUT BRIEF VERDICT_DIR BUILDER_SESSION [INTERVAL]" >&2
    return 2
  fi
  local repo="$1" branch_ref="$2" pr_repo="$3"
  local builder_out="$4" brief="$5" verdict_dir="$6" builder_session="$7"
  # Default poll interval: 300s for premium engines; 45s for cheap engines.
  # Override via 8th arg, WATCHER_POLL_SECONDS, or STEER_POLL_SECONDS (cheap only).
  local interval="${8:-$(_watcher_poll_seconds)}"
  local drain="${WATCHER_DRAIN_SECONDS:-300}"
  # Cache-guard thresholds. Override via env.
  #   MIN_DELTA: skip LLM audit unless builder.out grew by at least this
  #     many bytes since last audit (default 2 KiB). Filters out
  #     "builder typing slowly" noise.
  #   MAX_QUIET: force a heartbeat audit after this many seconds of
  #     no-meaningful-change (default 900 = 15 min) so the watcher stays
  #     visible to the orchestrator.
  local min_delta="${WATCHER_MIN_DELTA_BYTES:-2048}"
  local max_quiet="${WATCHER_MAX_QUIET_SECONDS:-900}"

  mkdir -p "$verdict_dir"

  cd "$repo" || return 1

  # PR-comment posting uses the branch leaf name (strip optional `origin/`).
  local branch_leaf="${branch_ref#origin/}"

  local last_sha="" last_size=0 quiet_since=0 pass=0 unchanged=0
  local last_audit_ts=0 skipped=0
  while true; do
    local sha size
    sha=$(_resolve_branch_sha "$branch_ref")
    size=$(_file_size "$builder_out")
    pass=$((pass + 1))

    # BLIND state: ref doesn't resolve. Write a BLIND verdict and continue.
    if [[ -z "$sha" ]]; then
      local stamp verdict
      stamp=$(_now_ts)
      verdict="${verdict_dir}/pass-${stamp}.md"
      _write_blind_verdict "$pass" "$branch_leaf" "$branch_ref" "$verdict"
      echo "[$stamp] BLIND pass=$pass ref=$branch_ref"
      sleep "$interval"
      continue
    fi

    if [[ "$sha" == "$last_sha" ]]; then
      unchanged=$((unchanged + 1))
    else
      unchanged=0
    fi

    if _should_audit "$sha" "$last_sha" "$size" "$last_size" \
                     "$last_audit_ts" "$min_delta" "$max_quiet"; then
      quiet_since=0
      local stamp verdict learnings_file
      stamp=$(_now_ts)
      verdict="${verdict_dir}/pass-${stamp}.md"
      learnings_file="${verdict_dir}/learnings.md"
      echo "[$stamp] pass=$pass starting sha=$sha bytes=$size"
      {
        _diagnostic_header "$pass" "$branch_leaf" "$branch_ref" "$sha" "$unchanged" "$builder_out" "$size" "$learnings_file"
        echo
      } > "$verdict"
      BUILDER_SESSION="$builder_session" _run_audit_pass "$repo" "$brief" "${verdict}.body"
      cat "${verdict}.body" >> "$verdict"
      rm -f "${verdict}.body"
      _append_learnings "$verdict" "$pass" "$sha" "$learnings_file"
      local run_dir
      run_dir="$(_watcher_run_dir "$verdict_dir")"
      _steer_process_verdict "$run_dir" "$verdict" "$builder_out" || true
      _post_pr_comment "$pr_repo" "$branch_leaf" "$verdict" || true
      last_sha="$sha"
      last_size="$size"
      last_audit_ts=$(date +%s)
      skipped=0
    else
      skipped=$((skipped + 1))
      echo "[$(_now_ts)] pass=$pass skipped (cache-guard; skipped_in_row=$skipped sha=$sha bytes=$size)"
      if (( quiet_since == 0 )); then
        quiet_since=$(date +%s)
      fi
      if ! _builder_alive "$builder_session" && _drain_elapsed "$quiet_since" "$drain"; then
        echo "[$(_now_ts)] drain window elapsed; watcher exiting"
        return 0
      fi
    fi
    sleep "$interval"
  done
}

# Allow direct invocation: `bash watcher-loop.sh <args>` runs the main loop.
# Allow sourcing: `source watcher-loop.sh` exposes functions for tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  watcher_loop_main "$@"
fi
