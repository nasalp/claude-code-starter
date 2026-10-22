# Rationale — typescript/coding-style.md

## Why: Named Exports Only

Named exports enable auto-imports, refactoring tools, and prevent naming inconsistencies.

## Why: No Barrel Re-exports in Libraries

Causes tree-shaking issues and circular dependency risks.

**Exception:** Public API of a published package MAY use a single entry point.

## Exception: Explicit Return Types

Arrow functions in callbacks where type is obvious:

```typescript
const names = users.map(u => u.name)  // Fine — obvious from context
```
