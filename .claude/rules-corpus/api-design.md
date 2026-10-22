# API Design Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## API Versioning

### REQUIRED: URL Path Versioning

```
/api/v1/orders
/api/v2/orders
```

Why: explicit/visible; easy LB routing; clear in logs/docs; simple to test.

### REQUIRED: Version From Day One

Even v1 includes version:

```java
@RestController
@RequestMapping("/api/v1/orders")
class OrderController { }
```

### REQUIRED: Maintain Previous Version

Releasing v2 → keep v1 working:

```java
@RestController
@RequestMapping("/api/v1/orders")
class OrderControllerV1 { }

@RestController
@RequestMapping("/api/v2/orders")
class OrderControllerV2 { }
```

Deprecation timeline:
1. Release v2
2. Mark v1 deprecated (response header)
3. Announce sunset date
4. Remove v1 after grace period

---

## Breaking vs Non-Breaking Changes

### Non-Breaking (No Version Bump)

- Add new optional response fields
- Add new endpoints
- Add new optional query params
- Add new enum values (if client handles unknown)

### Breaking (Requires New Version)

- Remove response fields
- Change field types
- Rename fields
- Change URL structure
- Change required params
- Change error response format

---

## URL Design

### REQUIRED: Resource-Based URLs

```
# ✅ Good — nouns, resources
GET    /api/v1/orders
GET    /api/v1/orders/{id}
POST   /api/v1/orders
PUT    /api/v1/orders/{id}
DELETE /api/v1/orders/{id}

# ❌ Bad — verbs, actions
POST /api/v1/createOrder
GET  /api/v1/getOrders
POST /api/v1/order/delete
```

### REQUIRED: Consistent Pluralization

Plural for collections:

```
/api/v1/orders      # ✅ Plural
/api/v1/users       # ✅ Plural
/api/v1/order       # ❌ Singular
```

### REQUIRED: Nested Resources

Parent-child:

```
GET /api/v1/orders/{orderId}/items
GET /api/v1/orders/{orderId}/items/{itemId}
POST /api/v1/orders/{orderId}/items
```

Limit nesting depth to 2:
```
# ✅ Good
/api/v1/orders/{orderId}/items

# ❌ Too deep
/api/v1/users/{userId}/orders/{orderId}/items/{itemId}/comments
```

### RECOMMENDED: Actions as Sub-Resources

Actions not mapping to CRUD:

```
POST /api/v1/orders/{id}/cancel
POST /api/v1/orders/{id}/ship
POST /api/v1/users/{id}/verify-email
```

---

## Request/Response

### REQUIRED: Use JSON

```java
@PostMapping(
    consumes = MediaType.APPLICATION_JSON_VALUE,
    produces = MediaType.APPLICATION_JSON_VALUE
)
```

### REQUIRED: Consistent Field Naming

`camelCase` for JSON fields:

```json
{
    "orderId": "123",
    "createdAt": "2024-01-15T10:30:00Z",
    "totalAmount": 99.99
}
```

### REQUIRED: ISO 8601 Dates

```json
{
    "createdAt": "2024-01-15T10:30:00Z",
    "expiresAt": "2024-01-16T10:30:00Z"
}
```

### REQUIRED: Pagination

List endpoints:

```
GET /api/v1/orders?page=0&size=20&sort=createdAt,desc
```

Response:
```json
{
    "content": [...],
    "page": 0,
    "size": 20,
    "totalElements": 100,
    "totalPages": 5
}
```

### REQUIRED: Filtering

Query params:

```
GET /api/v1/orders?status=PENDING&userId=123&createdAfter=2024-01-01
```

---

## HTTP Methods

### REQUIRED: Correct Method Usage

| Method | Purpose | Idempotent | Safe |
|--------|---------|------------|------|
| GET | Read resource | Yes | Yes |
| POST | Create resource | No | No |
| PUT | Replace resource | Yes | No |
| PATCH | Partial update | Yes | No |
| DELETE | Remove resource | Yes | No |

### REQUIRED: Idempotency

PUT and DELETE must be idempotent:

```java
// PUT — same result if called multiple times
@PutMapping("/{id}")
Order replaceOrder(@PathVariable UUID id, @RequestBody OrderRequest request) {
    return orderService.replace(id, request);  // Always same result
}

// DELETE — succeeds even if already deleted
@DeleteMapping("/{id}")
ResponseEntity<Void> deleteOrder(@PathVariable UUID id) {
    orderService.delete(id);  // No error if not found
    return ResponseEntity.noContent().build();
}
```

---

## HTTP Status Codes

### REQUIRED: Correct Status Codes

| Status | When |
|--------|------|
| 200 OK | Successful GET, PUT, PATCH |
| 201 Created | Successful POST (with Location header) |
| 204 No Content | Successful DELETE |
| 400 Bad Request | Validation error |
| 401 Unauthorized | Not authenticated |
| 403 Forbidden | Not authorized |
| 404 Not Found | Resource doesn't exist |
| 409 Conflict | State conflict |
| 500 Internal Error | Unexpected server error |

### REQUIRED: Location Header for Created

```java
@PostMapping
ResponseEntity<Order> createOrder(@RequestBody CreateOrderRequest request) {
    Order order = orderService.create(request);
    return ResponseEntity
        .created(URI.create("/api/v1/orders/" + order.getId()))
        .body(order);
}
```

---

## Documentation

### REQUIRED: OpenAPI Specification

Document all endpoints:

```java
@Operation(summary = "Create a new order")
@ApiResponses({
    @ApiResponse(responseCode = "201", description = "Order created"),
    @ApiResponse(responseCode = "400", description = "Invalid request")
})
@PostMapping
ResponseEntity<Order> createOrder(@RequestBody CreateOrderRequest request) { }
```

### REQUIRED: Spec First

Define API in `spec/contracts/openapi.yaml` before implementation.

---

## Quick Reference

| Rule | Priority |
|------|----------|
| URL path versioning (/api/v1/) | REQUIRED |
| Version from day one | REQUIRED |
| Maintain previous versions | REQUIRED |
| Resource-based URLs (nouns) | REQUIRED |
| Plural resources | REQUIRED |
| Consistent camelCase | REQUIRED |
| ISO 8601 dates | REQUIRED |
| Pagination for lists | REQUIRED |
| Correct HTTP methods | REQUIRED |
| Correct status codes | REQUIRED |
| Location header for 201 | REQUIRED |
| OpenAPI documentation | REQUIRED |
| Nested resources max 2 deep | RECOMMENDED |
| Actions as sub-resources | RECOMMENDED |
