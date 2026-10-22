#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export TMP
  LIB="${BATS_TEST_DIRNAME}/../scripts/init-run.sh"
}

teardown() {
  if [[ -n "${TMP:-}" && -d "$TMP" ]]; then
    find "$TMP" -name '.monitor.pid' -print0 2>/dev/null | while IFS= read -r -d '' pidfile; do
      pid="$(cat "$pidfile" 2>/dev/null || true)"
      [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null || true
    done
  fi
  rm -rf "$TMP"
}

@test "_compose_run_id joins slug + epoch" {
  run bash -c "source '$LIB'; _compose_run_id myfeature 1779976800"
  [ "$status" -eq 0 ]
  [ "$output" = "myfeature-1779976800" ]
}

@test "_compose_run_id rejects empty slug" {
  run bash -c "source '$LIB'; _compose_run_id '' 1779976800"
  [ "$status" -ne 0 ]
}

@test "_compose_run_id rejects non-numeric epoch" {
  run bash -c "source '$LIB'; _compose_run_id slug notanumber"
  [ "$status" -ne 0 ]
}

@test "_run_dir_path returns /tmp/tmux-agent/<id>" {
  run bash -c "source '$LIB'; _run_dir_path myfeature-42"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/tmux-agent/myfeature-42" ]
}

@test "_run_dir_path honours TMUX_AGENT_TMPDIR override" {
  # Env-var prefix on `source` does NOT carry into the next ;-chained
  # command — export before sourcing so _run_dir_path reads the override.
  run bash -c "export TMUX_AGENT_TMPDIR='$TMP'; source '$LIB'; _run_dir_path foo-1"
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/foo-1" ]
}

@test "init_run main creates run dir and echoes id+path" {
  run bash -c "TMUX_AGENT_TMPDIR='$TMP' bash '$LIB' myfeature 1779976800"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RUN_ID=myfeature-1779976800"* ]]
  [[ "$output" == *"RUN_DIR=$TMP/myfeature-1779976800"* ]]
  [ -d "$TMP/myfeature-1779976800" ]
}

@test "init_run main spawns monitor pid file with live process" {
  run bash -c "TMUX_AGENT_TMPDIR='$TMP' TMUX_AGENT_MONITOR_INTERVAL=300 bash '$LIB' monitored 1779976800"
  [ "$status" -eq 0 ]
  pidfile="$TMP/monitored-1779976800/.monitor.pid"
  [ -f "$pidfile" ]
  pid="$(cat "$pidfile")"
  kill -0 "$pid"
  kill "$pid" 2>/dev/null || true
}

@test "init_run main fails on missing slug" {
  run bash -c "bash '$LIB'"
  [ "$status" -ne 0 ]
}
