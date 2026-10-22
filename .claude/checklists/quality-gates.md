# Quality Gates

---

## Priority Levels

| Priority | Meaning | Override |
|----------|---------|----------|
| **CRITICAL** | Blocks deployment | Never |
| **REQUIRED** | Must pass | User can override |
| **SUGGESTED** | Target to aim for | Use judgment |

---

## CRITICAL (Never Skip)

### Security
- [ ] Security review completed
- [ ] No sensitive data in logs
- [ ] No hardcoded secrets
- [ ] No injection vulnerabilities

### Stability
- [ ] Bounded caches — `maximumSize` set
- [ ] Bounded queues — explicit capacity
- [ ] Tests actually executed

### Performance
- [ ] Tests run in parallel
- [ ] Tests are isolated — no shared state

---

## REQUIRED — Specification

*Skip for: trivial changes, build/infrastructure, config, refactoring*

- [ ] Spec exists for behavior changes
- [ ] Spec is high-level (no implementation details)
- [ ] Feature indexed in `spec/features/README.md`

**Not needed for:** Dockerfile, CI/CD, dependency updates, typo fixes, property changes

---

## REQUIRED — Code Quality

- [ ] Imports used (no FQNs)
- [ ] No unused code
- [ ] No unused imports
- [ ] Meaningful names
- [ ] Fail fast (validate early)
- [ ] KISS, YAGNI, DRY applied

---

## REQUIRED — Testing

- [ ] Tests executed: `./mvnw test -T 1C`
- [ ] Output: `BUILD SUCCESS`, Failures: 0
- [ ] AssertJ assertions (not JUnit5)
- [ ] No `Thread.sleep()` — use Awaitility

---

## REQUIRED — Build (All 7 Tools)

- [ ] `./mvnw verify -T 1C` passes (or `mvnd` if available)
- [ ] Spring Java Format: auto-applied and validated
- [ ] Checkstyle: spring-javaformat rules pass
- [ ] Error Prone + NullAway: no compile-time bugs, null safety enforced
- [ ] SpotBugs + FindSecBugs: no bugs at any threshold
- [ ] PMD: no complexity violations
- [ ] PITest: mutation kill rate >= 80% (`./mvnw org.pitest:pitest-maven:mutationCoverage`)
- [ ] jqwik property tests: `*Properties.java` classes included by Surefire

See [toolchain-setup.md](toolchain-setup.md) for full configuration.

---

## SUGGESTED — Code Style

*Targets to aim for, not hard rules:*

- [ ] Methods ~10-15 lines
- [ ] Classes ~100-200 lines
- [ ] Single responsibility
- [ ] Minimal blank lines in methods

---

## Quick Verification

```bash
# With Maven Daemon (fastest)
mvnd verify -T 1C

# Standard Maven
./mvnw verify -T 1C

# Gradle
./gradlew build --parallel
```

---

## When Specs Are NOT Needed

| Change Type | Spec Required? |
|-------------|----------------|
| New feature | Yes |
| Behavior change | Yes |
| Bug fix (behavior) | Yes |
| Dockerfile | No |
| CI/CD pipeline | No |
| Dependency update | No |
| Config/properties | No |
| Refactoring (same behavior) | No |
| Typo/log message | No |

---

## What Blocks Completion

| Blocker | Fix |
|---------|-----|
| Security issue | Fix immediately |
| FQN in code | Use imports |
| Unused code/imports | Delete them |
| Tests not parallel | Remove shared state |
| Unbounded cache/queue | Add limits |
