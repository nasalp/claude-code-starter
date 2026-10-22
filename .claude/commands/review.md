# Command: /review

Review current changes against project standards.

## Usage

```
/review              # Review all uncommitted changes
/review <file>       # Review specific file
/review --staged     # Review only staged changes
```

## Checklist

### Specification
- [ ] Is this a behavior change?
  - YES → Spec exists at `spec/features/<feature>/`
  - NO (build/config/refactor) → Skip spec check

### Security (CRITICAL)
- [ ] No sensitive data in logs
- [ ] No hardcoded secrets
- [ ] Input validation present
- [ ] No SQL/command injection
- [ ] Auth/authz correct

### Code Style (REQUIRED)
- [ ] Imports used (no FQNs)
- [ ] No unused code
- [ ] No unused imports
- [ ] Meaningful names
- [ ] KISS, YAGNI, DRY applied

### Code Style (SUGGESTED)
- [ ] Methods reasonably short (~10-15 lines)
- [ ] Classes reasonably short (~100-200 lines)
- [ ] Single responsibility

### Testing
- [ ] Tests exist for new behavior
- [ ] Tests are parallel-safe (no shared state)
- [ ] No `Thread.sleep()` — uses Awaitility

### Performance
- [ ] Caches bounded (`maximumSize`)
- [ ] Queues bounded (explicit capacity)
- [ ] Async uses Spring-managed executors

## Output Format

```markdown
## Review: <file or changes>

### Status: PASS / NEEDS WORK

### Issues Found

#### CRITICAL
- [ ] <issue>

#### REQUIRED
- [ ] <issue>

#### SUGGESTED
- [ ] <suggestion>

### Summary
<1-2 sentence summary>
```
