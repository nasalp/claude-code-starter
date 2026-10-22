# Code Review Standards

When and how to conduct code reviews before merge.

## When to Review

**MANDATORY review triggers:**

- After writing or modifying code
- Before any commit to shared branches
- When security-sensitive code changes (auth, payments, user data)
- When architectural changes made
- Before merging pull requests

**Pre-Review Requirements** (before requesting review):

- All automated checks (CI/CD) passing
- Merge conflicts resolved
- Branch up to date with target branch
- Senior review gates passed when review is for a code owner or senior reviewer

## Review Checklist

Before marking code complete:

- [ ] Code readable and well-named
- [ ] Functions focused (<50 lines)
- [ ] Files cohesive (<800 lines)
- [ ] No deep nesting (>4 levels)
- [ ] Errors handled explicitly
- [ ] No hardcoded secrets or credentials
- [ ] No console.log or debug statements
- [ ] Tests exist for new functionality
- [ ] Test coverage meets 80% minimum

## Security Review Triggers

**STOP and use security-reviewer agent when:** authentication/authorization code, user input handling, DB queries, file system operations, external API calls, cryptographic operations, payment or financial code.

## Review Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| CRITICAL | Security vulnerability or data loss risk | **BLOCK** - Must fix before merge |
| HIGH | Bug or significant quality issue | **WARN** - Should fix before merge |
| MEDIUM | Maintainability concern | **INFO** - Consider fixing |
| LOW | Style or minor suggestion | **NOTE** - Optional |

## Agent Usage

| Agent | Purpose |
|-------|---------|
| **code-reviewer** | General code quality, patterns, best practices |
| **security-reviewer** | Security vulnerabilities, OWASP Top 10 |
| **typescript-reviewer** | TypeScript/JavaScript specific issues |
| **python-reviewer** | Python specific issues |
| **go-reviewer** | Go specific issues |
| **rust-reviewer** | Rust specific issues |

## Review Workflow

```
1. Run git diff to understand changes
2. Check security checklist first
3. Review code quality checklist
4. Run relevant tests
5. Verify coverage >= 80%
6. Use appropriate agent for detailed review
```

## Common Issues to Catch

### Security

- Hardcoded credentials (API keys, passwords, tokens)
- SQL injection (string concatenation in queries)
- XSS (unescaped user input)
- Path traversal (unsanitized file paths)
- CSRF protection missing
- Authentication bypasses

### Code Quality

- Large functions (>50 lines) → split
- Large files (>800 lines) → extract modules
- Deep nesting (>4 levels) → early returns
- Missing error handling → handle explicitly
- Mutation patterns → prefer immutable
- Missing tests → add coverage

### Performance

- N+1 queries → JOINs or batching
- Missing pagination → add LIMIT
- Unbounded queries → add constraints
- Missing caching → cache expensive operations

## Approval Criteria

- **Approve**: No CRITICAL or HIGH issues
- **Warning**: Only HIGH issues (merge with caution)
- **Block**: CRITICAL issues found

## Integration with Other Rules

- [testing.md](testing.md) — test coverage requirements
- [security.md](security.md) — security checklist
- [git-workflow.md](git-workflow.md) — commit standards
- [agents.md](agents.md) — agent delegation
