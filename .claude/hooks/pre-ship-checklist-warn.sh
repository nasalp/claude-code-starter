#!/usr/bin/env bash
# Stub for the pre-ship-checklist warn hook (referenced from ~/.claude/settings.json:107).
# The original implementation was never committed; this no-op keeps the PreToolUse:Bash
# hook chain from erroring on every Bash call.
#
# If the original intent (per ~/.claude/rules/pre-ship-checklist.md) needs to be enforced,
# replace this stub with a real check that reads the hook payload from stdin
# (`{"tool_input": {"command": "..."}}`) and prints WARN lines to stderr for risky commands.
#
# Exit 0 always — per ai-rules convention, hooks warn (stderr) and never block.
exit 0
