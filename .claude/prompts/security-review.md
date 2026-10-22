# Prompt: Security Review

## Template

```
Review this code for security vulnerabilities.

Check for:
1. Injection (SQL, command, XSS, path traversal)
2. Authentication/authorization issues
3. Sensitive data exposure
4. Input validation gaps
5. Insecure configuration

Code:
<paste code or file path>

For each issue found:
- Severity: CRITICAL / HIGH / MEDIUM / LOW
- Location: file:line
- Issue: description
- Fix: recommended solution
```

## Example

```
Review this code for security vulnerabilities:

@PostMapping("/users")
public User createUser(@RequestBody UserRequest request) {
    String sql = "INSERT INTO users (name, email) VALUES ('" +
                 request.getName() + "', '" + request.getEmail() + "')";
    jdbcTemplate.execute(sql);
    return new User(request.getName(), request.getEmail());
}
```

## Expected Output

```markdown
## Security Review

### CRITICAL: SQL Injection

**Location:** UserController.java:15

**Issue:** User input directly concatenated into SQL query.

**Attack:** Attacker can inject: `'); DROP TABLE users; --`

**Fix:**
​```java
@PostMapping("/users")
public User createUser(@RequestBody @Valid UserRequest request) {
    jdbcTemplate.update(
        "INSERT INTO users (name, email) VALUES (?, ?)",
        request.getName(),
        request.getEmail()
    );
    return new User(request.getName(), request.getEmail());
}
​```

### MEDIUM: Missing Input Validation

**Location:** UserController.java:12

**Issue:** No `@Valid` annotation, input not validated.

**Fix:** Add `@Valid` and validation annotations to `UserRequest`.
```
