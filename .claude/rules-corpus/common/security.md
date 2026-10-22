# Security Guidelines

## Mandatory Security Checks

Before ANY commit, verify each item:

- [ ] No hardcoded secrets — `grep -rn "password\|api_key\|secret\|token" --include="*.java" --include="*.yml" --include="*.properties" src/` → zero matches outside test fixtures
- [ ] All user inputs validated — every `@RequestBody` has `@Valid`, every `@PathVariable`/`@RequestParam` has type constraints
- [ ] SQL injection prevention — `grep -rn "\" +" --include="*.java" src/` on repository classes → zero string concatenation in queries
- [ ] XSS prevention — no raw user input in HTML; template engine auto-escaping
- [ ] CSRF protection — `SecurityFilterChain` must not call `csrf().disable()` (except stateless JWT APIs)
- [ ] Authentication/authorization — every controller class or method has `@PreAuthorize` or is under authenticated URL pattern
- [ ] Rate limiting — rate limit filter or annotation on public-facing endpoints
- [ ] Error messages don't leak sensitive data — `grep -rn "getMessage\|stackTrace\|printStackTrace" --include="*.java" src/main/` → none reach HTTP responses

## Secret Management

- NEVER hardcode secrets in source
- ALWAYS use env vars or secret manager
- Validate required secrets at startup (fail fast if `${VAR}` unresolved)
- Rotate any secrets that may have been exposed

## Security Response Protocol

Security issue found:
1. STOP immediately
2. Use **security-reviewer** agent
3. Fix CRITICAL issues before continuing
4. Rotate any exposed secrets
5. Review entire codebase for similar issues

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `grep` finds secret-like string in test fixture | Test uses dummy credentials | Verify values clearly fake (e.g., `test-api-key`); if real, rotate immediately and replace with env var |
| CSRF disabled but shouldn't be | Copied config from stateless API to session-based app | Remove `csrf().disable()`, add CSRF token to forms |
| `@PreAuthorize` not evaluated | `@EnableMethodSecurity` missing on security config class | Add `@EnableMethodSecurity` annotation |
| Dependency check reports CVE | Vulnerable transitive dependency | Run `./mvnw dependency:tree` (Maven) or `./gradlew dependencies` (Gradle) to find parent, then override version or exclude + replace |
