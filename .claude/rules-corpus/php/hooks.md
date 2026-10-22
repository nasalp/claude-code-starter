---
paths:
  - "**/*.php"
  - "**/composer.json"
  - "**/phpstan.neon"
  - "**/phpstan.neon.dist"
  - "**/psalm.xml"
---
# PHP Hooks

> Extends [common/hooks.md](../common/hooks.md) with PHP content.

## PostToolUse Hooks

Config in `~/.claude/settings.json`:

- **Pint / PHP-CS-Fixer**: auto-format edited `.php` files.
- **PHPStan / Psalm**: static analysis after PHP edits in typed codebases.
- **PHPUnit / Pest**: targeted tests for touched files/modules when edits affect behavior.

## Warnings

- Warn on `var_dump`, `dd`, `dump`, `die()` left in edited files.
- Warn when edited PHP files add raw SQL or disable CSRF/session protections.
