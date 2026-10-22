#!/usr/bin/env bash
# Every hook wired in settings.json.template runs and exits 0 on a sample payload
# (harness convention: hooks warn on stderr, they never break the agent).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

FAKE_HOME=$(make_tmp)
WORK=$(make_tmp)
trap 'rm -rf "$FAKE_HOME" "$WORK"' EXIT
mkdir -p "$WORK/src/main/java"

payload=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/main/java/Foo.java","command":"ls"},"cwd":"%s","session_id":"test","stop_hook_active":true}' "$WORK" "$WORK")

for h in $(grep -oE '\{\{HOOKS\}\}/[A-Za-z0-9._-]+\.sh' .claude/settings.json.template | sort -u); do
    f=".claude/hooks/${h#\{\{HOOKS\}\}/}"
    echo "$payload" | HOME="$FAKE_HOME" SKIP_VERIFY_STOP=true "$f" >/dev/null 2>&1
    assert_eq 0 "$?" "$(basename "$f") exits 0"
done

for s in $(grep -oE '\{\{SCRIPTS\}\}/[A-Za-z0-9._-]+\.js' .claude/settings.json.template | sort -u); do
    f=".claude/scripts/hooks/${s#\{\{SCRIPTS\}\}/}"
    echo "$payload" | HOME="$FAKE_HOME" node "$f" >/dev/null 2>&1
    assert_eq 0 "$?" "$(basename "$f") exits 0"
done

# require-test-first must actually warn for production code with no test.
warn=$(echo "$payload" | HOME="$FAKE_HOME" .claude/hooks/require-test-first.sh 2>&1 >/dev/null)
assert_contains "$warn" "No test file found" "require-test-first warns when a production file has no test"

finish
