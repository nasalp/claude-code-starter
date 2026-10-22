# MCP Security Checklist

Complete security checklist for MCP (Model Context Protocol) server development.

Reference: https://auth0.com/blog/api-authorization-hierarchy-needs/

---

## Authentication

### Token Validation

- [ ] **All MCP endpoints require valid JWT/OAuth token**
- [ ] **Token signature validated** against auth server public keys
- [ ] **Token `aud` claim validated** (must match MCP server)
- [ ] **Token `exp` enforced** (reject expired tokens)
- [ ] **Identity extracted from token** (never from request params)

### Token Requirements

| Claim | Purpose | Validation |
|-------|---------|------------|
| `sub` | User/Service ID | Must exist |
| `azp`/`client_id` | Application ID | Must exist |
| `scope` | Granted permissions | Check required scopes |
| `aud` | Audience | Must match MCP server |
| `exp` | Expiration | Must be future |

---

## Authorization Levels

### Level 1: Application Authorization

- [ ] **Multi-tenant data isolation** implemented and tested
- [ ] **Hierarchical roles** defined (not flat RBAC):
  - Tenant-level roles
  - Resource-level roles
  - Object-level roles
- [ ] **Resource hierarchy** permissions inherit correctly

### Level 2: Service Accounts (M2M)

- [ ] **OAuth Client Credentials** or secure API keys used
- [ ] Service accounts **scoped to single tenant**
- [ ] Permissions **explicitly configured per tenant**
- [ ] All service account actions **audited**

### Level 3: Delegated Authorization

- [ ] **BOTH app AND user permissions verified**:
  - Grant: Did user authorize this app?
  - Permission: Does user currently have access?
- [ ] **Fine-grained scopes** used (e.g., `create:ticket:project_A`)
- [ ] **OAuth delegation flows** implemented

### Level 4: AI Agent Security

- [ ] **Data leakage prevention**:
  - Enforce read AND write permissions
  - Validate output destinations
- [ ] **RAG filtering by permissions**:
  - Pre-filter OR post-filter results
- [ ] **Intent-based restrictions**:
  - Scope to specific intent, not full user permissions
- [ ] **Human-in-the-loop** for destructive actions
- [ ] **Comprehensive auditing** of all agent actions

---

## Agent-Specific Risks

| Risk | Mitigation | Verified |
|------|------------|----------|
| Data Leakage | Validate read AND write permissions | [ ] |
| Unauthorized RAG | Filter by user permissions | [ ] |
| Orchestration Failure | Restrict agent scope | [ ] |
| Privilege Escalation | Never trust agent context | [ ] |

---

## Tool Security

### Input Validation

- [ ] **All inputs validated** before processing
- [ ] **Type checking** on all parameters
- [ ] **Bounds checking** on numeric values
- [ ] **Size limits** on string/array inputs

### Output Security

- [ ] **Output size limited** (max 10-100 results)
- [ ] **Pagination** for large result sets
- [ ] **Sensitive data filtered** from responses
- [ ] **No internal errors leaked** to clients

### Execution Security

- [ ] **Timeouts configured** on all operations
- [ ] **Rate limiting** applied
- [ ] **Resource bounds** enforced
- [ ] **Stateless execution** (no server-side session)

---

## Destructive Operations

For operations that modify/delete data:

- [ ] **Explicit confirmation required**
- [ ] **Human approval** for bulk operations
- [ ] **Clear warning messages** returned
- [ ] **Audit trail** with before/after state
- [ ] **Rollback capability** where possible

---

## Audit Requirements

All MCP tool invocations MUST log:

- [ ] **Timestamp**
- [ ] **Client ID** (which app)
- [ ] **User ID** (on whose behalf)
- [ ] **Tool name**
- [ ] **Input parameters** (sanitized)
- [ ] **Resources accessed**
- [ ] **Outcome** (success/failure)
- [ ] **Error details** (if failed)

---

## Contract Testing

### Producer (MCP Server)

- [ ] **Spring Cloud Contract** for all tools
- [ ] **Contracts define schemas** and behaviors
- [ ] **Stubs published** for consumers
- [ ] **Contract tests in CI**

### Consumer (MCP Client)

- [ ] **Stub Runner** for all tests
- [ ] **Tests against stubs** (not real server)
- [ ] **Compatibility verified** before deploy

---

## Configuration Checklist

### Spring Security

```java
@Bean
public SecurityFilterChain mcpSecurity(HttpSecurity http) {
    return http
        .securityMatcher("/mcp/**")
        .authorizeHttpRequests(auth -> auth
            .anyRequest().authenticated()    // ✓ All authenticated
        )
        .oauth2ResourceServer(oauth2 -> oauth2
            .jwt(jwt -> jwt
                .jwtAuthenticationConverter(converter())  // ✓ Scope mapping
            )
        )
        .sessionManagement(s -> s
            .sessionCreationPolicy(STATELESS)  // ✓ Stateless
        )
        .csrf(csrf -> csrf.disable())  // ✓ OK for stateless API
        .build();
}
```

### Method Security

```java
@Tool("get_data")
@PreAuthorize("hasAuthority('SCOPE_data:read')")  // ✓ Scope check
public DataResponse getData(Request request, Jwt jwt) {
    String userId = jwt.getSubject();  // ✓ From token
    // ✓ User permission check
    if (!authService.canAccess(userId, request.resourceId())) {
        throw new AccessDeniedException("Not authorized");
    }
}
```

---

## Pre-Deployment Checklist

### Must Pass

- [ ] All authentication checks implemented
- [ ] All authorization levels verified
- [ ] RAG filtering tested
- [ ] Human-in-the-loop for destructive ops
- [ ] Audit logging complete
- [ ] Contract tests passing
- [ ] Security review completed

### Red Flags (Block Deployment)

- ❌ Any endpoint without authentication
- ❌ User ID from request parameters
- ❌ Flat RBAC without hierarchy
- ❌ No RAG filtering
- ❌ Destructive ops without confirmation
- ❌ Missing audit logs
- ❌ Cross-tenant data access possible

---

## Quick Verification Commands

```bash
# Run security tests
./mvnw test -Dtest="*Security*"

# Run contract tests
./mvnw test -Dtest="*Contract*"

# Check for security bugs
./mvnw spotbugs:check

# Review security configuration
grep -r "@PreAuthorize" src/
grep -r "getSubject()" src/
```
