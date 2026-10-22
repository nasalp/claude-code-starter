---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python Hooks

> Extends [common/hooks.md](../common/hooks.md) w/ Python content.

## PostToolUse Hooks

Configure `~/.claude/settings.json`:

- **black/ruff**: auto-format `.py` after edit
- **mypy/pyright**: type-check after `.py` edit

## Warnings

- Warn `print()` in edited files — use `logging`
