---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Coding Style Rules

> Extends [common/coding-style.md](../common/coding-style.md) w/ TypeScript/JavaScript content.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **REQUIRED** | Must follow |
| **SUGGESTED** | Target to aim for, use judgment |

---

## Immutability

### REQUIRED: Never Mutate

```typescript
// NEVER — mutation
function updateUser(user: User, name: string): User {
  user.name = name  // MUTATION
  return user
}

users.push(newUser)           // MUTATION
users.sort()                  // MUTATION (in-place)
Object.assign(config, patch)  // MUTATION

// ALWAYS — new objects
function updateUser(user: User, name: string): User {
  return { ...user, name }
}

const updated = [...users, newUser]
const sorted = [...users].sort(compareFn)
const merged = { ...config, ...patch }
```

### REQUIRED: Use `const` by Default

```typescript
// ALWAYS
const name = 'Alice'
const items = [1, 2, 3]
const config = { port: 3000 }

// Only when reassignment is genuinely needed
let retries = 3
while (retries > 0) { retries-- }
```

### RECOMMENDED: `as const` for Literal Types

```typescript
const STATUSES = ['pending', 'shipped', 'delivered'] as const
type Status = typeof STATUSES[number]  // 'pending' | 'shipped' | 'delivered'

const config = {
  port: 3000,
  host: 'localhost',
} as const
```

### RECOMMENDED: `Readonly<T>` for Function Parameters

```typescript
function processOrder(order: Readonly<Order>): OrderResult {
  // order.status = 'done'  // Compile error
  return { ...order, status: 'done' }
}
```

---

## Error Handling

### REQUIRED: Async/Await with Explicit Catch

```typescript
// GOOD — explicit error handling
try {
  const result = await riskyOperation()
  return result
} catch (error: unknown) {
  if (error instanceof NetworkError) {
    return fallback()
  }
  throw error
}

// BAD — unhandled promise
riskyOperation().then(process)  // What if it rejects?
```

See [error-handling.md](./error-handling.md) for full error handling rules.

---

## Input Validation

### REQUIRED: Zod at System Boundaries

```typescript
import { z } from 'zod'

const schema = z.object({
  email: z.string().email(),
  age: z.number().int().min(0).max(150),
})

const validated = schema.parse(input)
```

For plain JS with JSDoc:

```javascript
// @ts-check
const { z } = require('zod')

const schema = z.object({
  email: z.string().email(),
  age: z.number().int().min(0).max(150),
})

/** @type {z.infer<typeof schema>} */
const validated = schema.parse(input)
```

---

## Exports

### REQUIRED: Named Exports Only

```typescript
// GOOD — named exports
export function createOrder() { }
export class OrderService { }
export type Order = { }

// BAD — default exports
export default function createOrder() { }
export default class OrderService { }
```

### REQUIRED: No Barrel Re-exports in Libraries

```typescript
// BAD — barrel file re-exports everything
// src/index.ts
export * from './orders'
export * from './users'
export * from './products'
// Causes tree-shaking issues and circular dependency risks

// GOOD — import directly from the module
import { OrderService } from './orders/order.service'
```

---

## Functions

### REQUIRED: Pure Functions by Default

```typescript
// GOOD — pure, no side effects
function calculateTotal(items: readonly Item[]): number {
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0)
}

// BAD — side effect hidden in "calculation"
function calculateTotal(items: Item[]): number {
  items.sort((a, b) => a.price - b.price)  // Surprise mutation!
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0)
}
```

### REQUIRED: Explicit Return Types for Public Functions

```typescript
// GOOD — return type is explicit contract
function getOrder(id: string): Promise<Order> { }
function calculateDiscount(order: Order): Money { }

// BAD — return type inferred (fragile contract)
function getOrder(id: string) { }  // What does this return?
```

---

## No `console.log` in Production

### REQUIRED: Use a Logger

```typescript
// NEVER in production code
console.log('Order created:', order)
console.error('Failed:', err)

// ALWAYS — structured logger
import { logger } from './logger'

logger.info({ orderId: order.id }, 'Order created')
logger.error({ err, orderId }, 'Order creation failed')
```

See hooks for automatic detection.

---

## REQUIRED: Remove Unused Code

```typescript
// NEVER — commented-out code
// function oldMethod() {
//   // old implementation
// }

// NEVER — unused imports
import { something } from './module'  // never used

// NEVER — unused variables
const unused = calculateSomething()
return otherValue
```

Version control preserves history.

---

## REQUIRED: Meaningful Names

```typescript
// BAD
const d = new Date()
function proc(o: Order) { }
const list1: User[] = []
const cb = () => { }

// GOOD
const createdAt = new Date()
function processOrder(order: Order) { }
const activeUsers: User[] = []
const onOrderCreated = () => { }
```

---

## REQUIRED: Fail Fast

```typescript
// BAD — validate late
function process(request: Request) {
  // ... lots of work ...
  if (!request.email) throw new ValidationError('email required')
}

// GOOD — validate immediately
function process(request: Request) {
  if (!request.email) throw new ValidationError('email required')
  // ... proceed with valid data ...
}
```

---

## SUGGESTED: Small Functions

Functions do one thing. Target ~10-15 lines.

```typescript
// Split large function into focused pieces
async function processOrder(request: CreateOrderRequest): Promise<Order> {
  const validated = validateRequest(request)
  const total = calculateTotal(validated.items)
  const order = await createOrder(validated.customerId, total)
  await notifyOrderCreated(order)
  return order
}
```

---

## SUGGESTED: Small Files

Target ~100-200 lines per file, 400 max.

Organize by feature:

```
orders/
  order.service.ts        // Business logic
  order.repository.ts     // Data access
  order.routes.ts         // HTTP handlers
  order.types.ts          // Types and schemas
  order.service.test.ts   // Tests
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Never mutate (spread, new objects) | REQUIRED |
| `const` by default | REQUIRED |
| Named exports only | REQUIRED |
| No barrel re-exports | REQUIRED |
| Pure functions by default | REQUIRED |
| Explicit return types (public) | REQUIRED |
| No `console.log` in production | REQUIRED |
| Remove unused code/imports | REQUIRED |
| Meaningful names | REQUIRED |
| Fail fast | REQUIRED |
| Zod at boundaries | REQUIRED |
| `as const` for literals | RECOMMENDED |
| `Readonly<T>` for params | RECOMMENDED |
| Small functions (~15 lines) | SUGGESTED |
| Small files (~200 lines) | SUGGESTED |

> Rationale (Why): `docs/rule-rationale/typescript__coding-style.md`
