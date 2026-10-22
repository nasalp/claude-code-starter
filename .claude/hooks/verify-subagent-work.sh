#!/usr/bin/env bash
#
# Hook: verify-subagent-work.sh
# Trigger: SubagentStop
# Purpose: Inspect a subagent's transcript at exit and warn if production
#          source files were modified without a corresponding test edit.
#
# WARNINGS ONLY. Always exits 0. The parent agent must read stderr.
# Per the harness convention: hooks warn, never block.
#
# Schema: Claude Code SubagentStop hook input includes:
#   - transcript_path: path to the subagent's full transcript JSONL
#   - session_id: the subagent's session identifier
#   - stop_hook_active: whether stop hooks are still firing
#
# Strategy: prefer evidence from actual Write/Edit/MultiEdit tool calls
# (file_path on the tool input) over text mentions. Falls back to legacy
# `last_assistant_message` text scan only if the transcript is unavailable.
# This eliminates false positives when the assistant merely *mentions* a
# source filename in prose without actually editing it.

set -euo pipefail

INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null)

# Legacy schema (back-compat with existing tests + older Claude Code versions)
LAST_MESSAGE=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('last_assistant_message', ''))
except Exception:
    pass
" 2>/dev/null)

AGENT_TYPE=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('agent_type', ''))
except Exception:
    pass
" 2>/dev/null)

# Resolve evidence: tool calls (preferred) and text (fallback / supplement).
EDITED_FILES=""
RECENT_TEXT=""

if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
    # Extract two streams: one path-per-line (Write/Edit/MultiEdit file_path),
    # then a sentinel, then the recent text content. Sentinel is a string that
    # cannot appear in a file path or natural text.
    PARSED=$(tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null | python3 -c "
import json, sys
edited = []
text = []
for line in sys.stdin:
    try:
        msg = json.loads(line)
        if msg.get('role') != 'assistant':
            continue
        content = msg.get('content', '')
        if isinstance(content, list):
            for c in content:
                if not isinstance(c, dict):
                    continue
                if c.get('type') == 'text':
                    text.append(c.get('text', ''))
                elif c.get('type') == 'tool_use':
                    name = c.get('name', '')
                    if name in ('Write', 'Edit', 'MultiEdit'):
                        fp = (c.get('input') or {}).get('file_path', '')
                        if fp:
                            edited.append(fp)
        elif isinstance(content, str):
            text.append(content)
    except Exception:
        pass
print('\n'.join(edited))
print('---__VERIFY_SEP__---')
print('\n'.join(text[-10:]))
" 2>/dev/null || echo "")

    EDITED_FILES=$(printf '%s\n' "$PARSED" | sed -n '1,/^---__VERIFY_SEP__---$/p' | sed '$d')
    RECENT_TEXT=$(printf '%s\n' "$PARSED" | sed -n '/^---__VERIFY_SEP__---$/,$p' | sed '1d')
elif [[ -n "$LAST_MESSAGE" ]]; then
    RECENT_TEXT="$LAST_MESSAGE"
fi

# Officially-supported production source extensions.
# Java/Kotlin/Scala/Groovy + TS/TSX/JS/JSX/MJS/CJS + Python + PHP + Vue/Svelte.
SOURCE_PATH_RE='\.(java|kt|kts|scala|groovy|ts|tsx|jsx?|mjs|cjs|py|php|vue|svelte)$|/src/main/|\.github/workflows/.*\.ya?ml$|(^|/)(pom\.xml|composer\.json|package\.json)$'
TEST_PATH_RE='\.(test|spec|Test|Tests|IT|Spec|Properties)\.|_test\.(go|py)$|test_.*\.py$|/tests?/'

# Prefer explicit tool-call evidence: did the subagent actually edit production source?
HAS_SOURCE_EDIT=false
HAS_TEST_EDIT=false
if [[ -n "$EDITED_FILES" ]]; then
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if echo "$path" | grep -qE "$TEST_PATH_RE"; then
            HAS_TEST_EDIT=true
        elif echo "$path" | grep -qE "$SOURCE_PATH_RE"; then
            HAS_SOURCE_EDIT=true
        fi
    done <<< "$EDITED_FILES"
fi

# Text-only fallback (legacy LAST_MESSAGE, or when no tool calls were captured).
HAS_SOURCE_MENTION=false
HAS_TEST_MENTION=false
if [[ "$HAS_SOURCE_EDIT" == "false" ]] && [[ -n "$RECENT_TEXT" ]]; then
    if echo "$RECENT_TEXT" | grep -qiE 'src/main|\.java\b|\.kt\b|\.scala\b|\.groovy\b|\.ts\b|\.tsx\b|\.jsx?\b|\.mjs\b|\.cjs\b|\.vue\b|\.svelte\b|\.py\b|\.php\b|\.ya?ml.*workflow|workflow.*\.ya?ml|pom\.xml|composer\.json|package\.json'; then
        HAS_SOURCE_MENTION=true
    fi
    if echo "$RECENT_TEXT" | grep -qiE 'test|spec|\.bats|Test\.java|Tests\.java|test\.ts|test\.tsx'; then
        HAS_TEST_MENTION=true
    fi
fi

WARN=false
if [[ "$HAS_SOURCE_EDIT" == "true" ]] && [[ "$HAS_TEST_EDIT" == "false" ]]; then
    WARN=true
elif [[ "$HAS_SOURCE_EDIT" == "false" ]] && [[ "$HAS_SOURCE_MENTION" == "true" ]] && [[ "$HAS_TEST_MENTION" == "false" ]]; then
    WARN=true
fi

if [[ "$WARN" == "true" ]]; then
    LABEL="verify-subagent"
    if [[ -n "$AGENT_TYPE" ]]; then
        LABEL="verify-subagent:$AGENT_TYPE"
    fi
    echo "[$LABEL] WARNING: Source files were modified without a corresponding test." >&2
    echo "  Review the diff and confirm tests were written or updated." >&2
    echo "  Per harness convention, the parent agent is responsible for reading this warning." >&2
fi

# Always exit 0 — warnings only.
exit 0
