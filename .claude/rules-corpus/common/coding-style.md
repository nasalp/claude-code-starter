# Coding Style

## Immutability (CRITICAL)

ALWAYS create new objects, NEVER mutate existing ones:

```
// Pseudocode
WRONG:  modify(original, field, value) → changes original in-place
CORRECT: update(original, field, value) → returns new copy with change
```

Immutable data prevents hidden side effects, eases debugging, enables safe concurrency.

## File Organization

MANY SMALL FILES > FEW LARGE FILES:
- High cohesion, low coupling
- 200-400 lines typical, 800 max
- Extract utilities from large modules
- Organize by feature/domain, not by type

## Error Handling

ALWAYS handle errors comprehensively:
- Handle errors explicitly at every level
- User-friendly error messages in UI-facing code
- Log detailed error context server-side
- Never silently swallow errors

## Input Validation

ALWAYS validate at system boundaries:
- Validate all user input before processing
- Use schema-based validation where available
- Fail fast with clear error messages
- Never trust external data (API responses, user input, file content)

## Code Quality Checklist

Before marking work complete:
- [ ] Code readable and well-named (reviewer understands intent without comments)
- [ ] Functions small (<50 lines — run `wc -l` on new functions to verify)
- [ ] Files focused (<800 lines — run `wc -l` on modified files to verify)
- [ ] No deep nesting (>4 levels — count indent levels in new code)
- [ ] Proper error handling (every external call has explicit error path)
- [ ] No hardcoded values (use constants or config)
- [ ] No mutation (immutable patterns used)

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| File exceeds 800 lines | Too many responsibilities | Extract new file per responsibility; each file one reason to change |
| Function exceeds 50 lines | Multiple abstraction levels mixed | Extract helper methods — one abstraction level per function |
| Deep nesting (>4 levels) | Nested if/for/try blocks | Early returns (guard clauses), extract inner blocks into named methods |
| Hardcoded value found in review | Magic number or string literal | Extract to `private static final` constant or `@Value("${config.key}")` property |
