# Command: /security-review

Perform security review on code.

## Usage

```
/security-review              # Review uncommitted changes
/security-review <file>       # Review specific file
/security-review <directory>  # Review directory
```

## Security Checklist

### Injection (CRITICAL)
- [ ] **SQL Injection** — parameterized queries used?
- [ ] **Command Injection** — user input in shell commands?
- [ ] **XSS** — user input escaped in output?
- [ ] **Path Traversal** — user input in file paths?
- [ ] **LDAP/XML Injection** — if applicable

### Authentication & Authorization (CRITICAL)
- [ ] Endpoints protected with `@PreAuthorize` or security config?
- [ ] Permission checks before data access?
- [ ] No privilege escalation possible?
- [ ] Session handling secure?

### Sensitive Data (CRITICAL)
- [ ] No secrets in code or config files?
- [ ] No sensitive data in logs?
- [ ] No PII exposed in responses?
- [ ] Encryption for sensitive data at rest?

### Input Validation (REQUIRED)
- [ ] All external input validated?
- [ ] Size limits enforced?
- [ ] Type checking applied?
- [ ] Bean validation (`@Valid`) used?

### Dependencies (REQUIRED)
- [ ] No known CVEs?
- [ ] Dependencies from trusted sources?

### Configuration (REQUIRED)
- [ ] Actuator endpoints locked down?
- [ ] CORS configured correctly?
- [ ] CSRF protection (or justified disable)?

## Output Format

```markdown
## Security Review: <target>

### Risk Level: LOW / MEDIUM / HIGH / CRITICAL

### Findings

#### CRITICAL
- <finding with file:line>

#### HIGH
- <finding with file:line>

#### MEDIUM
- <finding with file:line>

### Recommendations
1. <recommendation>

### Approval: APPROVED / NEEDS FIXES
```

## Auto-Checks

Run static analysis:

```bash
# Maven
./mvnw spotbugs:check -Dspotbugs.plugins=com.h3xstream.findsecbugs:findsecbugs-plugin

# Gradle
./gradlew spotbugsMain
```
