---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Hooks

> Extends [common/hooks.md](../common/hooks.md) w/ JS/TS content.

## PostToolUse Hooks

Configure `~/.claude/settings.json`:

- **Prettier/Biome**: auto-format JS/TS/JSON after edit
- **TypeScript check**: `tsc --noEmit` after `.ts`/`.tsx` edit
- **ESLint**: auto-fix on save for `.ts`/`.tsx`/`.js`/`.jsx`
- **console.log warning**: warn `console.log` in edited files

## Stop Hooks

- **console.log audit**: scan modified files for `console.log` before session end
- **Type check**: `tsc --noEmit` before session end
- **Lint check**: `eslint` on modified files before session end
