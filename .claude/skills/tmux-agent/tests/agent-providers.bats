#!/usr/bin/env bats

setup() {
  LIB="${BATS_TEST_DIRNAME}/../scripts/lib/agent-providers.sh"
  # Hermetic: the Headroom wrapper is opt-in; clear any ambient export so the
  # "bare claude" assertions are deterministic. The Headroom test re-exports it.
  unset HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON HEADROOM_LOCAL_CLAUDE_PROXY_PORT
}

@test "provider_command returns the binary for a known provider" {
  run bash -c "source '$LIB'; provider_command composer"
  [ "$status" -eq 0 ]
  [ "$output" = "agent" ]
}

@test "provider_command fails for an unknown provider" {
  run bash -c "source '$LIB'; provider_command nope-not-real"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown provider"* ]]
}

@test "provider_tier maps composer->cheap, claude->premium, gemini->premium" {
  run bash -c "source '$LIB'; provider_tier composer"; [ "$output" = "cheap" ]
  run bash -c "source '$LIB'; provider_tier claude";   [ "$output" = "premium" ]
  run bash -c "source '$LIB'; provider_tier gemini";   [ "$output" = "premium" ]
}

@test "provider_default_model returns the configured default" {
  run bash -c "source '$LIB'; provider_default_model claude"
  [ "$output" = "sonnet" ]
}

@test "compose_provider_cmd claude renders the builder contract with the given model" {
  run bash -c "source '$LIB'; compose_provider_cmd claude sonnet /repo /p.md /o.out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude --print --model sonnet"* ]]
  [[ "$output" == *"--tools default"* ]]
  [[ "$output" == *"--permission-mode bypassPermissions"* ]]
  [[ "$output" == *"--add-dir /repo"* ]]
  [[ "$output" == *'--add-dir $HOME/.claude/rules'* ]]
  [[ "$output" == *"< /p.md"* ]]
  [[ "$output" == *"> /o.out"* ]]
}

@test "compose_provider_cmd claude uses default_model when model arg empty" {
  run bash -c "source '$LIB'; compose_provider_cmd claude '' /repo /p.md /o.out"
  [[ "$output" == *"--model sonnet"* ]]
}

@test "compose_provider_cmd claude prepends Headroom wrapper when exported" {
  run bash -c "export HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON='/tmp/hp' HEADROOM_LOCAL_CLAUDE_PROXY_PORT=9912; source '$LIB'; compose_provider_cmd claude sonnet /repo /p.md /o.out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HEADROOM_MODE=token"* ]]
  [[ "$output" == *"headroom.cli wrap claude"* ]]
  [[ "$output" == *"--port 9912"* ]]
  [[ "$output" == *"--no-context-tool --no-mcp --no-serena -- --print"* ]]
}

@test "compose_provider_cmd composer renders the cursor agent invocation" {
  run bash -c "source '$LIB'; compose_provider_cmd composer composer-2.5-fast /wt /p.md /o.out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent --print --force --trust --model composer-2.5-fast"* ]]
  [[ "$output" == *"--output-format stream-json"* ]]
  [[ "$output" == *"--workspace /wt"* ]]
  [[ "$output" == *"< /p.md"* ]]
  [[ "$output" == *"> /o.out"* ]]
}

@test "compose_provider_cmd gemini mounts rules via --include-directories" {
  run bash -c "source '$LIB'; compose_provider_cmd gemini gemini-2.5-pro /repo /p.md /o.out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini --model gemini-2.5-pro"* ]]
  [[ "$output" == *"--approval-mode yolo"* ]]
  [[ "$output" == *"--include-directories /repo,"* ]]
  [[ "$output" == *'$HOME/.claude/rules'* ]]
}

@test "gemini-flash is a cheap provider using the gemini CLI + flash model" {
  run bash -c "source '$LIB'; provider_tier gemini-flash";          [ "$output" = "cheap" ]
  run bash -c "source '$LIB'; provider_command gemini-flash";       [ "$output" = "gemini" ]
  run bash -c "source '$LIB'; provider_default_model gemini-flash"; [ "$output" = "gemini-2.5-flash" ]
}

@test "codex is premium (NOT a cheap watcher)" {
  run bash -c "source '$LIB'; provider_tier codex"
  [ "$output" = "premium" ]
}

@test "compose_provider_cmd gemini-flash mounts rules + uses flash default model" {
  run bash -c "source '$LIB'; compose_provider_cmd gemini-flash '' /repo /p.md /o.out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini --model gemini-2.5-flash"* ]]
  [[ "$output" == *"--approval-mode yolo"* ]]
  [[ "$output" == *"--include-directories /repo,"* ]]
}

@test "provider_add_dir_supported is false for composer, true for gemini" {
  run bash -c "source '$LIB'; provider_add_dir_supported composer"; [ "$output" = "false" ]
  run bash -c "source '$LIB'; provider_add_dir_supported gemini";   [ "$output" = "true" ]
}

@test "compose_provider_cmd shell-escapes values with spaces / metacharacters" {
  run bash -c "source '$LIB'; compose_provider_cmd composer composer-2.5-fast '/tmp/my repo;rm -rf' '/p file.md' '/o.out'"
  [ "$status" -eq 0 ]
  # the dangerous value must be quoted/escaped, never appear raw+unquoted
  [[ "$output" != *"/tmp/my repo;rm -rf"* ]]
  # and the rendered command must be safe to evaluate (no stray command execution)
  run bash -c "source '$LIB'; cmd=\$(compose_provider_cmd composer m '/tmp/a b' '/p q.md' '/o o.out'); printf '%s' \"\$cmd\" | grep -q 'workspace' && echo SAFE"
  [[ "$output" == *"SAFE"* ]]
}

@test "compose_provider_cmd leaves plain paths unchanged (no spurious escaping)" {
  run bash -c "source '$LIB'; compose_provider_cmd composer composer-2.5-fast /wt /p.md /o.out"
  [[ "$output" == *"--workspace /wt"* ]]
  [[ "$output" == *"< /p.md"* ]]
}

@test "compose_provider_cmd codex injects the reasoning-effort flag (flag style)" {
  run bash -c "source '$LIB'; compose_provider_cmd codex '' /repo /p.md /o.out high"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex exec -c model_reasoning_effort=high"* ]]
}

@test "compose_provider_cmd codex without effort emits no reasoning flag" {
  run bash -c "source '$LIB'; compose_provider_cmd codex '' /repo /p.md /o.out"
  [ "$status" -eq 0 ]
  [[ "$output" != *"model_reasoning_effort"* ]]
  [[ "$output" == *"codex exec --skip-git-repo-check"* ]]
}

@test "compose_provider_cmd claude prepends thinking-budget env (env style)" {
  run bash -c "source '$LIB'; compose_provider_cmd claude sonnet /repo /p.md /o.out high"
  [ "$status" -eq 0 ]
  [[ "$output" == MAX_THINKING_TOKENS=24000* ]]
  [[ "$output" == *"claude --print --model sonnet"* ]]
}

@test "compose_provider_cmd ignores effort for a provider without reasoning support" {
  run bash -c "source '$LIB'; compose_provider_cmd gemini-flash '' /repo /p.md /o.out high"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MAX_THINKING_TOKENS"* ]]
  [[ "$output" != *"model_reasoning_effort"* ]]
  [[ "$output" == *"gemini --model gemini-2.5-flash"* ]]
}

@test "compose_provider_cmd cognitive role gets read-only tools and dirs for claude" {
  run bash -c "source '$LIB'; compose_provider_cmd claude sonnet /repo /p.md /o.out medium planner"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--tools Read,Glob,Grep"* ]]
  [[ "$output" != *"--tools default"* ]]
  [[ "$output" == *"--add-dir /repo"* ]]
  [[ "$output" == *'--add-dir $HOME/.claude/rules'* ]]
  [[ "$output" == *'--add-dir $HOME/.claude/skills'* ]]
}

@test "compose_provider_cmd cognitive role gets read-only tools and dirs for gemini" {
  run bash -c "source '$LIB'; compose_provider_cmd gemini gemini-2.5-pro /repo /p.md /o.out '' reviewer"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--approval-mode plan"* ]]
  [[ "$output" == *"--include-directories /repo,"* ]]
  [[ "$output" == *'$HOME/.claude/rules'* ]]
  [[ "$output" == *'$HOME/.claude/skills'* ]]
}

@test "compose_provider_cmd builder role keeps tools and dirs for claude" {
  run bash -c "source '$LIB'; compose_provider_cmd claude sonnet /repo /p.md /o.out '' builder"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--tools default"* ]]
  [[ "$output" == *"--add-dir /repo"* ]]
}

@test "compose_provider_cmd watcher role keeps dirs for gemini-flash" {
  run bash -c "source '$LIB'; compose_provider_cmd gemini-flash '' /repo /p.md /o.out '' watcher"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--approval-mode yolo"* ]]
  [[ "$output" == *"--include-directories /repo,"* ]]
}

@test "compose_provider_cmd gemini builder role uses yolo approval mode" {
  run bash -c "source '$LIB'; compose_provider_cmd gemini gemini-2.5-pro /repo /p.md /o.out '' builder"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--approval-mode yolo"* ]]
  [[ "$output" == *"--include-directories /repo,"* ]]
}

@test "require_yq errors clearly when yq is absent" {
  # Shadow PATH so yq cannot be found.
  run bash -c "PATH=/nonexistent; source '$LIB'; require_yq"
  [ "$status" -ne 0 ]
  [[ "$output" == *"yq"* ]]
}
