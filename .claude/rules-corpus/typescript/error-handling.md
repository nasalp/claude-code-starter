---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Error Handling Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deploy; no exceptions |
| **REQUIRED** | Follow unless overridden |
| **RECOMMENDED** | Best practice; team adjusts |

---

## Domain Errors

### REQUIRED: Custom Error Classes

Domain-specific errors — not generic:

```typescript
// GOOD — specific domain errors
class OrderNotFoundError extends Error {
  readonly code = 'ORDER_NOT_FOUND' as const
  constructor(readonly orderId: string) {
    super(`Order not found: ${orderId}`)
    this.name = 'OrderNotFoundError'
  }
}

class OrderAlreadyCancelledError extends Error {
  readonly code = 'ORDER_ALREADY_CANCELLED' as const
  constructor(readonly orderId: string) {
    super(`Order already cancelled: ${orderId}`)
    this.name = 'OrderAlreadyCancelledError'
  }
}

class InsufficientInventoryError extends Error {
  readonly code = 'INSUFFICIENT_INVENTORY' as const
  constructor(readonly productId: string, readonly requested: number, readonly available: number) {
    super(`Insufficient inventory for ${productId}: requested ${requested}, available ${available}`)
    this.name = 'InsufficientInventoryError'
  }
}

// BAD — generic
throw new Error('Order not found')
throw new Error('Something went wrong')
```

Plain JS:

```javascript
class OrderNotFoundError extends Error {
  /** @param {string} orderId */
  constructor(orderId) {
    super(`Order not found: ${orderId}`)
    this.name = 'OrderNotFoundError'
    this.code = 'ORDER_NOT_FOUND'
    this.orderId = orderId
  }
}
```

### RECOMMENDED: Error Hierarchy

```
AppError (abstract base)
+-- NotFoundError
|   +-- OrderNotFoundError
|   +-- UserNotFoundError
+-- ValidationError
|   +-- InvalidOrderStateError
|   +-- InvalidAmountError
+-- ConflictError
|   +-- OrderAlreadyCancelledError
|   +-- DuplicateEmailError
+-- ExternalServiceError
    +-- PaymentServiceError
    +-- NotificationServiceError
```

```typescript
abstract class AppError extends Error {
  abstract readonly code: string
  abstract readonly statusCode: number
}

abstract class NotFoundError extends AppError {
  readonly statusCode = 404
}

abstract class ValidationError extends AppError {
  readonly statusCode = 400
}

abstract class ConflictError extends AppError {
  readonly statusCode = 409
}
```

---

## HTTP Error Responses

### REQUIRED: Consistent Error Format

```typescript
interface ErrorResponse {
  code: string           // Machine-readable: "ORDER_NOT_FOUND"
  message: string        // Human-readable: "Order not found"
  requestId: string      // For debugging: correlation ID
  timestamp: string      // ISO 8601
  details?: Record<string, string>  // Field-level validation errors
}
```

### REQUIRED: Centralized Error Handler

#### Express

```typescript
import type { ErrorRequestHandler } from 'express'

const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  if (err instanceof NotFoundError) {
    return res.status(404).json({
      code: err.code,
      message: err.message,
      requestId: req.id,
      timestamp: new Date().toISOString(),
    })
  }

  if (err instanceof ValidationError) {
    return res.status(400).json({
      code: 'VALIDATION_ERROR',
      message: err.message,
      requestId: req.id,
      timestamp: new Date().toISOString(),
      details: err.fieldErrors,
    })
  }

  // Unexpected error — log full stack, don't expose details
  logger.error({ err, requestId: req.id }, 'Unexpected error')
  return res.status(500).json({
    code: 'INTERNAL_ERROR',
    message: 'An unexpected error occurred',
    requestId: req.id,
    timestamp: new Date().toISOString(),
  })
}

app.use(errorHandler)
```

#### Next.js / Hono

```typescript
// Hono error handler
app.onError((err, c) => {
  if (err instanceof AppError) {
    return c.json({
      code: err.code,
      message: err.message,
      requestId: c.get('requestId'),
      timestamp: new Date().toISOString(),
    }, err.statusCode)
  }

  logger.error({ err }, 'Unexpected error')
  return c.json({
    code: 'INTERNAL_ERROR',
    message: 'An unexpected error occurred',
  }, 500)
})
```

### REQUIRED: HTTP Status Mapping

| Error Type | HTTP Status | When |
|------------|-------------|------|
| `NotFoundError` | 404 | Resource absent |
| `ValidationError` | 400 | Bad input |
| `ConflictError` | 409 | State conflict (exists, cancelled) |
| `UnauthorizedError` | 401 | Unauthenticated |
| `ForbiddenError` | 403 | Unauthorized |
| Unexpected | 500 | Unhandled |

---

## Validation Errors

### REQUIRED: Field-Level Details

```json
{
  "code": "VALIDATION_ERROR",
  "message": "Invalid request",
  "requestId": "abc-123",
  "timestamp": "2024-01-15T10:30:00Z",
  "details": {
    "email": "Invalid email format",
    "amount": "Must be greater than 0"
  }
}
```

### REQUIRED: Use Zod at Boundaries

```typescript
import { z } from 'zod'

const CreateOrderSchema = z.object({
  email: z.string().email(),
  amount: z.number().positive(),
  description: z.string().min(1).max(100),
})

// In handler — parse and throw structured error
try {
  const body = CreateOrderSchema.parse(req.body)
} catch (err) {
  if (err instanceof z.ZodError) {
    const details = Object.fromEntries(
      err.issues.map(issue => [issue.path.join('.'), issue.message])
    )
    throw new ValidationError('Invalid request', details)
  }
}
```

---

## Logging Errors

### CRITICAL: No Sensitive Data in Logs

```typescript
// NEVER
logger.error(`Login failed for password: ${password}`)
logger.info(`User data: ${JSON.stringify(userWithPII)}`)
logger.debug(`Token: ${authToken}`)

// ALWAYS
logger.error({ userId }, 'Login failed')
logger.info({ userId }, 'User logged in')
```

**Prohibited in logs:**
- Passwords, API keys, tokens, secrets
- PII (email, phone, SSN, address)
- Credit card numbers
- Session identifiers
- Full request/response bodies with sensitive fields

### REQUIRED: Structured Logging

```typescript
import pino from 'pino'

const logger = pino({ level: process.env.LOG_LEVEL ?? 'info' })

// ALWAYS — structured with context
logger.error({ err, orderId, userId }, 'Order processing failed')
logger.warn({ validationErrors }, 'Validation failed for order creation')
logger.info({ orderId, status: 'created' }, 'Order created')
```

### REQUIRED: Appropriate Log Levels

| Level | When |
|-------|------|
| `error` | Unexpected failures; need attention |
| `warn` | Expected failures (validation, not-found) |
| `info` | Business events |
| `debug` | Troubleshoot detail |

---

## External Service Errors

### REQUIRED: Wrap External Errors

```typescript
class ExternalServiceError extends AppError {
  readonly code = 'EXTERNAL_SERVICE_ERROR'
  readonly statusCode = 502

  constructor(
    readonly serviceName: string,
    readonly cause: unknown,
  ) {
    super(`External service error: ${serviceName}`)
    this.name = 'ExternalServiceError'
  }
}

// In HTTP client
async function fetchPayment(id: string): Promise<Payment> {
  try {
    const res = await fetch(`${PAYMENT_URL}/payments/${id}`)
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return await res.json()
  } catch (cause) {
    throw new ExternalServiceError('payment-service', cause)
  }
}
```

---

## Anti-Patterns

### CRITICAL: Don't Swallow Errors

```typescript
// NEVER — silently swallowing
try {
  await process()
} catch (e) {
  // nothing
}

// NEVER — log and ignore
try {
  await process()
} catch (e) {
  console.error('Error', e)  // Then what?
}

// GOOD — handle or propagate
try {
  await process()
} catch (e) {
  if (e instanceof RetryableError) return fallback()
  throw e
}
```

### CRITICAL: Don't Catch Generic and Continue

```typescript
// NEVER — catch-all hides bugs
try {
  await processOrder(order)
} catch (e) {
  return { status: 'failed' }  // Which error? All of them??
}

// GOOD — catch specific errors
try {
  await processOrder(order)
} catch (e) {
  if (e instanceof OrderNotFoundError) return notFound(e.orderId)
  if (e instanceof ValidationError) return badRequest(e.fieldErrors)
  throw e  // Unknown errors propagate
}
```

### CRITICAL: No Unhandled Promise Rejections

```typescript
// NEVER — fire and forget async
processOrder(order)  // Unhandled rejection if it throws

// ALWAYS — await or attach error handler
await processOrder(order)

// If intentionally fire-and-forget, handle errors explicitly
processOrder(order).catch(err => {
  logger.error({ err, orderId: order.id }, 'Background order processing failed')
})
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| No sensitive data in logs | CRITICAL |
| Don't swallow errors | CRITICAL |
| Don't catch-all and continue | CRITICAL |
| No unhandled promise rejections | CRITICAL |
| Domain-specific error classes | REQUIRED |
| Consistent error response format | REQUIRED |
| Centralized error handler | REQUIRED |
| HTTP status mapping | REQUIRED |
| Field-level validation details (Zod) | REQUIRED |
| Structured logging (pino) | REQUIRED |
| Appropriate log levels | REQUIRED |
| Wrap external service errors | REQUIRED |
| Error class hierarchy | RECOMMENDED |
