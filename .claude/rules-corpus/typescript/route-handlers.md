---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Route Handler Rules

Controller-rule equivalent. Route handlers = thin layer.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deploy; no exceptions |
| **REQUIRED** | Follow unless overridden |

---

## CRITICAL: Route Handlers Are Thin Layers

Route handlers MUST only:
1. Parse/validate req (params, query, body)
2. Call service fn
3. Return HTTP response

Route handlers MUST NOT contain:
- Business logic
- Data transform beyond simple response map
- Orchestrated multi-service calls
- Business-rule conditionals
- Direct DB access

### Express

```typescript
// GOOD — thin handler
router.get('/:id', async (req, res, next) => {
  try {
    const order = await orderService.getOrder(req.params.id)
    res.json(OrderResponse.from(order))
  } catch (err) {
    next(err)
  }
})

// BAD — business logic in handler
router.get('/:id', async (req, res) => {
  const order = await db.orders.findById(req.params.id)
  if (!order) return res.status(404).json({ error: 'Not found' })
  if (order.status === 'cancelled') {
    throw new OrderCancelledException(req.params.id)
  }
  const discount = await discountService.calculate(order)
  order.total = order.total - discount
  res.json(order)
})
```

### Hono

```typescript
// GOOD — thin handler
app.get('/orders/:id', async (c) => {
  const order = await orderService.getOrder(c.req.param('id'))
  return c.json(toOrderResponse(order))
})

// BAD — orchestration in handler
app.get('/orders/:id', async (c) => {
  const order = await db.query('SELECT * FROM orders WHERE id = ?', [c.req.param('id')])
  const items = await db.query('SELECT * FROM items WHERE order_id = ?', [order.id])
  const total = items.reduce((sum, item) => sum + item.price, 0)
  return c.json({ ...order, items, total })
})
```

### Next.js Route Handlers

```typescript
// app/api/orders/[id]/route.ts

// GOOD — thin handler
export async function GET(req: Request, { params }: { params: { id: string } }) {
  const order = await orderService.getOrder(params.id)
  return Response.json(toOrderResponse(order))
}

// BAD — business logic
export async function GET(req: Request, { params }: { params: { id: string } }) {
  const order = await prisma.order.findUnique({ where: { id: params.id } })
  if (!order) return Response.json({ error: 'Not found' }, { status: 404 })
  if (isExpired(order)) {
    await prisma.order.update({ where: { id: params.id }, data: { status: 'expired' } })
  }
  return Response.json(order)
}
```

---

## CRITICAL: No Direct Auth Context Access in Handlers

Handlers get auth via middleware inject. MUST NOT use global state.

```typescript
// GOOD — auth info passed via middleware
router.get('/orders', authenticate, async (req, res) => {
  const userId = req.user.id  // Set by middleware
  const orders = await orderService.getOrdersForUser(userId)
  res.json(orders)
})

// BAD — reaching into global/static state
router.get('/orders', async (req, res) => {
  const userId = getCurrentUserId()  // Global function
  const session = getSession()       // Implicit state
})
```

### Extracting Auth in Middleware

```typescript
// Express middleware
function authenticate(req: Request, res: Response, next: NextFunction) {
  const token = req.headers.authorization?.replace('Bearer ', '')
  if (!token) return res.status(401).json({ code: 'UNAUTHORIZED' })

  const payload = verifyToken(token)
  req.user = { id: payload.sub, roles: payload.roles }
  next()
}

// Hono middleware
const auth = createMiddleware(async (c, next) => {
  const token = c.req.header('Authorization')?.replace('Bearer ', '')
  if (!token) return c.json({ code: 'UNAUTHORIZED' }, 401)

  const payload = await verifyToken(token)
  c.set('user', { id: payload.sub, roles: payload.roles })
  await next()
})
```

---

## REQUIRED: Request Validation in Handlers

Validate req data at handler before services:

```typescript
import { z } from 'zod'

const CreateOrderSchema = z.object({
  email: z.string().email(),
  amount: z.number().positive(),
  description: z.string().min(1).max(100),
})

router.post('/', async (req, res, next) => {
  try {
    const body = CreateOrderSchema.parse(req.body)
    const order = await orderService.createOrder(body)
    res.status(201)
      .location(`/api/v1/orders/${order.id}`)
      .json(toOrderResponse(order))
  } catch (err) {
    next(err)
  }
})
```

---

## REQUIRED: Response Mapping

Simple map fns or static factory methods. NO separate mapper classes.

```typescript
// GOOD — simple function
function toOrderResponse(order: Order): OrderResponse {
  return {
    id: order.id,
    status: order.status,
    total: order.total.toString(),
    createdAt: order.createdAt.toISOString(),
  }
}

// GOOD — static method on the response type
class OrderResponse {
  static from(order: Order): OrderResponse {
    return { id: order.id, status: order.status, total: order.total.toString() }
  }
}

// BAD — unnecessary mapper class
class OrderMapper {
  static toResponse(order: Order): OrderResponse { }
  static toEntity(dto: OrderDto): Order { }
  static toSummary(order: Order): OrderSummary { }
}
```

---

## REQUIRED: Route Organization

Group routes by feature, not by HTTP method:

```
// GOOD — by feature
src/
  orders/
    order.routes.ts
    order.service.ts
    order.repository.ts
  users/
    user.routes.ts
    user.service.ts

// BAD — by type
src/
  routes/
    orders.ts
    users.ts
  services/
    orders.ts
    users.ts
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Route handlers are thin layers | CRITICAL |
| No direct auth context access (use middleware) | CRITICAL |
| Request validation (Zod) in handler | REQUIRED |
| Simple response mapping (no mapper classes) | REQUIRED |
| Routes organized by feature | REQUIRED |
