# Security Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## CRITICAL: Security Review Every Change

**Every code change MUST be analyzed for security flaws before completion.**

### Mandatory Security Checklist

Before completing any task, verify:

- [ ] **No injection vulnerabilities**
  - SQL injection (use parameterized queries)
  - Command injection (validate/sanitize inputs)
  - XSS (escape output, use safe templates)

- [ ] **No sensitive data exposure**
  - No secrets in code or logs
  - No PII in logs
  - No tokens/passwords in responses

- [ ] **Authentication/Authorization correct**
  - Endpoints protected appropriately
  - Permission checks in place
  - No privilege escalation possible

- [ ] **Input validation**
  - All external input validated
  - Size limits enforced
  - Type checking applied

- [ ] **No insecure dependencies**
  - No known CVEs in dependencies
  - Dependencies from trusted sources

### Security Review Process

```
1. WRITE CODE
   ↓
2. SELF-REVIEW for security
   - Check OWASP Top 10
   - Review input handling
   - Check auth/authz
   ↓
3. IF security issue found
   - Fix immediately
   - Do not proceed until fixed
   ↓
4. COMPLETE task
```

### Common Vulnerabilities to Check

| Vulnerability | Check For |
|---------------|-----------|
| SQL Injection | String concatenation in queries |
| XSS | Unescaped user input in HTML |
| CSRF | State-changing GET requests, missing tokens |
| Auth Bypass | Missing `@PreAuthorize`, unchecked permissions |
| Path Traversal | User input in file paths |
| SSRF | User-controlled URLs in server requests |
| Mass Assignment | Binding request directly to entities |
| Sensitive Data | Secrets in logs, responses, or code |

---

## CRITICAL: No Sensitive Data in Logs

```java
// ❌ NEVER
log.info("Login attempt with password: {}", password);
log.debug("Token: {}", authToken);
log.info("User data: {}", userWithPII);

// ✅ ALWAYS
log.info("Login attempt for user: {}", userId);
log.debug("Authentication successful");
log.info("User {} logged in", userId);
```

**Prohibited in logs:**
- Passwords, API keys, tokens, secrets
- PII (email, phone, SSN, address)
- Credit card numbers
- Session identifiers
- Full request/response bodies with sensitive fields

---

## CRITICAL: No Hardcoded Secrets

```java
// ❌ NEVER
private static final String API_KEY = "sk-abc123...";
private static final String DB_PASSWORD = "secret";

// ✅ ALWAYS
@Value("${external.api.key}")
private String apiKey;
```

```yaml
# ❌ NEVER in config files
api:
  key: sk-abc123...

# ✅ ALWAYS use environment variables
api:
  key: ${API_KEY}
```

---

## REQUIRED: Actuator Endpoints Locked Down

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health
  endpoint:
    health:
      show-details: never
      probes:
        enabled: true
```

**Allowed:** `/actuator/health`, `/actuator/health/readiness`, `/actuator/health/liveness`

**Never expose:** `/actuator/env`, `/actuator/configprops`, `/actuator/beans`

---

## REQUIRED: Input Validation

```java
@PostMapping("/orders")
ResponseEntity<Order> create(@Valid @RequestBody CreateOrderRequest request) {
    // @Valid triggers bean validation
}

record CreateOrderRequest(
    @NotNull @Email String email,
    @NotNull @Positive BigDecimal amount,
    @NotBlank @Size(max = 100) String description
) {}
```

---

## REQUIRED: Parameterized Queries

```java
// ❌ NEVER — SQL injection
String query = "SELECT * FROM users WHERE id = '" + userId + "'";

// ✅ ALWAYS — parameterized
@Query("SELECT u FROM User u WHERE u.id = :id")
Optional<User> findById(@Param("id") String id);
```

---

## REQUIRED: Authentication & Authorization

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/public/**").permitAll()
                .requestMatchers("/api/admin/**").hasRole("ADMIN")
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .build();
    }
}

// Method-level security
@PreAuthorize("hasRole('ADMIN') or @authService.isOwner(#orderId, principal)")
public Order getOrder(String orderId) { }
```

---

## REQUIRED: Dependency Security

```bash
# Check for vulnerable dependencies
./mvnw org.owasp:dependency-check-maven:check

# Or with Gradle
./gradlew dependencyCheckAnalyze
```

Keep dependencies updated. Monitor CVEs.

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Security review every change | CRITICAL |
| No sensitive data in logs | CRITICAL |
| No hardcoded secrets | CRITICAL |
| Actuator endpoints locked | REQUIRED |
| Input validation | REQUIRED |
| Parameterized queries | REQUIRED |
| Auth/authz configured | REQUIRED |
| Dependency security checks | REQUIRED |
