---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# API Design Rules

> Extends common API design w/ JS/TS patterns.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deploy; no exceptions |
| **REQUIRED** | Follow unless overridden |
| **RECOMMENDED** | Best practice; team adjusts |

---

## API Versioning

### REQUIRED: URL Path Versioning

```
/api/v1/orders
/api/v2/orders
```

### REQUIRED: Version From Day One

```typescript
// Express
const v1 = Router()
app.use('/api/v1', v1)

// Hono
const v1 = new Hono()
app.route('/api/v1', v1)

// Next.js — use folder structure
// app/api/v1/orders/route.ts
```

---

## URL Design

### REQUIRED: Resource-Based URLs

```
GET    /api/v1/orders
GET    /api/v1/orders/:id
POST   /api/v1/orders
PUT    /api/v1/orders/:id
DELETE /api/v1/orders/:id

// BAD
POST /api/v1/createOrder
GET  /api/v1/getOrders
```

### REQUIRED: Plural Resources

```
/api/v1/orders       // GOOD
/api/v1/order        // BAD
```

### REQUIRED: Nested Resources (Max 2 Deep)

```
GET /api/v1/orders/:orderId/items
GET /api/v1/orders/:orderId/items/:itemId

// BAD — too deep
/api/v1/users/:userId/orders/:orderId/items/:itemId/comments
```

### RECOMMENDED: Actions as Sub-Resources

```
POST /api/v1/orders/:id/cancel
POST /api/v1/orders/:id/ship
POST /api/v1/users/:id/verify-email
```

---

## Request/Response

### REQUIRED: Consistent JSON Format

Use `camelCase` for JSON fields:

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

```
GET /api/v1/orders?page=0&size=20&sort=createdAt:desc
```

Response:

```typescript
interface PaginatedResponse<T> {
  content: T[]
  page: number
  size: number
  totalElements: number
  totalPages: number
}
```

### REQUIRED: Filtering with Query Parameters

```
GET /api/v1/orders?status=pending&userId=123&createdAfter=2024-01-01
```

---

## HTTP Methods and Status Codes

### REQUIRED: Correct Method Usage

| Method | Purpose | Idempotent |
|--------|---------|------------|
| GET | Read | Yes |
| POST | Create | No |
| PUT | Replace | Yes |
| PATCH | Partial update | Yes |
| DELETE | Remove | Yes |

### REQUIRED: Correct Status Codes

| Status | When |
|--------|------|
| 200 OK | GET/PUT/PATCH success |
| 201 Created | POST success (+ Location header) |
| 204 No Content | DELETE success |
| 400 Bad Request | Validation fail |
| 401 Unauthorized | Unauthenticated |
| 403 Forbidden | Unauthorized |
| 404 Not Found | Resource absent |
| 409 Conflict | State conflict |
| 500 Internal Error | Unexpected server fail |

### REQUIRED: Location Header for 201

```typescript
// Express
res.status(201)
  .location(`/api/v1/orders/${order.id}`)
  .json(toOrderResponse(order))

// Hono
return c.json(toOrderResponse(order), 201, {
  Location: `/api/v1/orders/${order.id}`,
})

// Next.js
return Response.json(toOrderResponse(order), {
  status: 201,
  headers: { Location: `/api/v1/orders/${order.id}` },
})
```

---

## Request Validation

### REQUIRED: Zod Schemas for All Inputs

```typescript
import { z } from 'zod'

const CreateOrderSchema = z.object({
  email: z.string().email(),
  amount: z.number().positive(),
  description: z.string().min(1).max(100),
})

const OrderParamsSchema = z.object({
  id: z.string().uuid(),
})

const OrderQuerySchema = z.object({
  page: z.coerce.number().int().min(0).default(0),
  size: z.coerce.number().int().min(1).max(100).default(20),
  status: z.enum(['pending', 'shipped', 'delivered']).optional(),
})
```

---

## OpenAPI Documentation

### REQUIRED: Spec First

Define API contract before impl. Options:

```typescript
// Option 1: zod-to-openapi
import { extendZodWithOpenApi } from '@asteasolutions/zod-to-openapi'
extendZodWithOpenApi(z)

const CreateOrderSchema = z.object({
  email: z.string().email().openapi({ example: 'user@example.com' }),
  amount: z.number().positive().openapi({ example: 99.99 }),
}).openapi('CreateOrderRequest')

// Option 2: Manually maintained openapi.yaml in spec/contracts/
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| URL path versioning (/api/v1/) | REQUIRED |
| Version from day one | REQUIRED |
| Resource-based URLs (nouns, plural) | REQUIRED |
| Consistent camelCase JSON | REQUIRED |
| ISO 8601 dates | REQUIRED |
| Pagination for lists | REQUIRED |
| Correct HTTP methods and status codes | REQUIRED |
| Location header for 201 | REQUIRED |
| Zod schemas for all inputs | REQUIRED |
| OpenAPI documentation | REQUIRED |
| Nested resources max 2 deep | RECOMMENDED |
| Actions as sub-resources | RECOMMENDED |
