---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Patterns

> Extends [common/patterns.md](../common/patterns.md) w/ JS/TS patterns.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **REQUIRED** | Follow unless overridden |
| **RECOMMENDED** | Best practice; team adjusts |

---

## REQUIRED: Vertical Slice Architecture

Organize by feature, not tech layer:

```
// GOOD — by feature
src/
  orders/
    order.routes.ts        // HTTP handlers
    order.service.ts       // Business logic
    order.repository.ts    // Data access
    order.types.ts         // Types, schemas, DTOs
    order.service.test.ts  // Tests next to source
  users/
    user.routes.ts
    user.service.ts
    user.repository.ts
  shared/
    errors.ts              // Domain error base classes
    middleware.ts           // Shared middleware
    logger.ts              // Logger setup

// BAD — by technical layer
src/
  controllers/
    order.controller.ts
    user.controller.ts
  services/
    order.service.ts
    user.service.ts
  repositories/
    order.repository.ts
```

---

## REQUIRED: Repository Pattern

Encapsulate data access behind interface:

```typescript
interface OrderRepository {
  findAll(filters?: OrderFilters): Promise<Order[]>
  findById(id: OrderId): Promise<Order | null>
  create(data: CreateOrder): Promise<Order>
  update(id: OrderId, data: UpdateOrder): Promise<Order>
  delete(id: OrderId): Promise<void>
}

// Prisma implementation
function createOrderRepository(prisma: PrismaClient): OrderRepository {
  return {
    async findAll(filters) {
      return prisma.order.findMany({ where: toWhere(filters) })
    },
    async findById(id) {
      return prisma.order.findUnique({ where: { id } })
    },
    // ...
  }
}

// For testing — in-memory implementation
function createInMemoryOrderRepository(): OrderRepository {
  const orders = new Map<string, Order>()
  return {
    async findAll() { return [...orders.values()] },
    async findById(id) { return orders.get(id) ?? null },
    // ...
  }
}
```

---

## REQUIRED: Dependency Injection Without a Framework

Factory fns, not DI containers:

```typescript
// service depends on repository (interface, not implementation)
function createOrderService(deps: {
  orderRepo: OrderRepository
  paymentClient: PaymentClient
  logger: Logger
}): OrderService {
  return {
    async createOrder(request) {
      const order = await deps.orderRepo.create(request)
      await deps.paymentClient.charge(order.total)
      deps.logger.info({ orderId: order.id }, 'Order created')
      return order
    },
  }
}

// Composition root — wire everything together
function createApp() {
  const logger = createLogger()
  const prisma = new PrismaClient()
  const orderRepo = createOrderRepository(prisma)
  const paymentClient = createPaymentClient(process.env.PAYMENT_URL!)
  const orderService = createOrderService({ orderRepo, paymentClient, logger })
  const orderRoutes = createOrderRoutes(orderService)

  const app = express()
  app.use('/api/v1/orders', orderRoutes)
  return app
}
```

---

## REQUIRED: API Response Format

```typescript
// Success response
interface ApiResponse<T> {
  data: T
}

// Paginated response
interface PaginatedResponse<T> {
  content: T[]
  page: number
  size: number
  totalElements: number
  totalPages: number
}

// Error response (see error-handling.md)
interface ErrorResponse {
  code: string
  message: string
  requestId: string
  timestamp: string
  details?: Record<string, string>
}
```

---

## RECOMMENDED: Result Type for Operations That Can Fail

Expected failures -> Result, not throw:

```typescript
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E }

function ok<T>(value: T): Result<T, never> {
  return { ok: true, value }
}

function err<E>(error: E): Result<never, E> {
  return { ok: false, error }
}

// Usage
function parseOrder(input: unknown): Result<Order, ValidationError> {
  const parsed = OrderSchema.safeParse(input)
  if (!parsed.success) return err(new ValidationError(parsed.error))
  return ok(parsed.data)
}

// Caller handles both cases explicitly
const result = parseOrder(input)
if (!result.ok) {
  return badRequest(result.error)
}
processOrder(result.value)
```

---

## RECOMMENDED: React Custom Hooks (Frontend)

```typescript
function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value)

  useEffect(() => {
    const handler = setTimeout(() => setDebouncedValue(value), delay)
    return () => clearTimeout(handler)
  }, [value, delay])

  return debouncedValue
}
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Vertical slice architecture (by feature) | REQUIRED |
| Repository pattern for data access | REQUIRED |
| Factory function DI (no container) | REQUIRED |
| Consistent API response format | REQUIRED |
| Result type for expected failures | RECOMMENDED |
