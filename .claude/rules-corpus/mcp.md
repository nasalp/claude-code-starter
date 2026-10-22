# MCP Server Rules (Optional)

> **Note:** Only if building MCP (Model Context Protocol) servers. Skip if not applicable.

## Quick Reference

| Rule | Priority |
|------|----------|
| All endpoints require JWT | CRITICAL |
| Identity from token (not params) | CRITICAL |
| No flat RBAC | CRITICAL |
| Validate inputs | REQUIRED |
| Limit output size | REQUIRED |
| Configure timeouts | REQUIRED |
| Audit all actions | REQUIRED |
| Contract tests | REQUIRED |

---

## Essential Patterns

### 1. Defensive Tool Design
- **Validate all inputs** before processing
- **Limit output size** (max 10-100 results, paginate)
- **Configure timeouts** on all operations
- **Return structured errors** for LLM understanding

### 2. Stateless Execution
- No server-side session state
- Pass all context in each request
- Idempotent where possible

---

## Security Essentials

### CRITICAL: Authentication

Every request must have valid JWT:
```java
@PreAuthorize("hasAuthority('SCOPE_resource:read')")
public Response execute(Request request, @AuthenticationPrincipal Jwt jwt) {
    String userId = jwt.getSubject();  // ✅ From token
    // NOT from request.getUserId()    // ❌ Never trust request
}
```

### CRITICAL: Authorization Hierarchy

No flat RBAC. Implement:
1. **Tenant isolation** — strict data separation
2. **Resource-level roles** — project owner, team member
3. **Object-level permissions** — per-item access

### CRITICAL: Verify BOTH App AND User

Delegated auth:
```java
// Check app is allowed
if (!authService.canAppAccess(clientId, resourceId)) { throw ... }
// AND check user is allowed
if (!authService.canUserAccess(userId, resourceId)) { throw ... }
```

---

## Tool Implementation

```java
@Tool("get_orders")
@PreAuthorize("hasAuthority('SCOPE_orders:read')")
public OrdersResponse getOrders(GetOrdersRequest request, Jwt jwt) {
    // 1. Identity from token
    String userId = jwt.getSubject();

    // 2. Permission check
    if (!authService.canAccess(userId, request.projectId())) {
        throw new AccessDeniedException("Not authorized");
    }

    // 3. Execute with timeout
    var results = executeWithTimeout(() -> orderService.find(request), Duration.ofSeconds(30));

    // 4. Limit output
    return new OrdersResponse(
        results.stream().limit(MAX_RESULTS).toList(),
        results.size() > MAX_RESULTS ? nextCursor(results) : null
    );

    // 5. Audit (happens in aspect/filter)
}
```

---

## Security Checklist

- [ ] All endpoints require valid JWT
- [ ] Token signature, `aud`, and `exp` validated
- [ ] Identity extracted from token claims
- [ ] Multi-tenant data isolation
- [ ] Fine-grained authorization (not flat RBAC)
- [ ] Human-in-the-loop for destructive ops
- [ ] All actions audited
- [ ] Contract tests exist

> Rationale (Extended Documentation): `docs/rule-rationale/mcp.md`
