# Claude Code Hooks

Versioned hook scripts that enforce development workflow rules.

## Setup

These hooks are referenced from `~/.claude/settings.json` (global settings).
The scripts live here so they're versioned; the settings.json entry points to them.

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/spec-test-first-check.sh"
          }
        ]
      }
    ]
  }
}
```

## Available Hooks

| Script | Trigger | Purpose |
|--------|---------|---------|
| `spec-test-first-check.sh` | PreToolUse (Edit/Write) | Reminds Claude to follow SPEC -> TEST -> IMPLEMENT workflow before editing source files |

## How It Works

- When Claude tries to Edit or Write a file, the hook fires
- If the file is a production source file (not a test/spec), it prints a reminder
- The reminder text is injected into Claude's context, prompting it to check for specs/tests first
- Exit code 0 = non-blocking reminder. Change to exit code 2 to hard-block instead.

## Making It Blocking

To **hard-block** source file edits until specs/tests exist, change `exit 0` to `exit 2`
at the end of the reminder section. Exit code 2 tells Claude Code to reject the tool call.
