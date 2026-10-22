---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Observability Rules

> Port of Java Micrometer/Spring observability rules to JS/TS. Observability = first-class requirement.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deploy; no exceptions |
| **REQUIRED** | Follow unless overridden |
| **RECOMMENDED** | Best practice; team adjusts |

---

## REQUIRED: Structured Logging

### Use pino (or winston)

```typescript
import pino from 'pino'

const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  // Include request ID in all logs
  mixin: () => ({
    service: 'order-service',
  }),
})

export { logger }
```

### Log with Context

```typescript
// GOOD — structured with IDs
logger.error({ err, orderId, userId }, 'Order processing failed')
logger.warn({ validationErrors, requestId }, 'Validation failed')
logger.info({ orderId, status: 'created' }, 'Order created')

// BAD — string interpolation
logger.error(`Order processing failed for ${orderId}`)
logger.info('Order created: ' + JSON.stringify(order))
```

### Request Logging Middleware

```typescript
// Express
import pinoHttp from 'pino-http'

app.use(pinoHttp({
  logger,
  genReqId: (req) => req.headers['x-request-id'] ?? crypto.randomUUID(),
  serializers: {
    req: (req) => ({
      method: req.method,
      url: req.url,
      // DO NOT log headers (may contain auth tokens)
    }),
  },
}))
```

---

## REQUIRED: Request ID Propagation

Every req MUST have correlation ID propagating through all logs + downstream calls:

```typescript
// Middleware — generate or extract request ID
function requestId(req: Request, res: Response, next: NextFunction) {
  const id = req.headers['x-request-id'] as string ?? crypto.randomUUID()
  req.id = id
  res.setHeader('x-request-id', id)
  next()
}

// Pass to downstream services
async function callPaymentService(paymentReq: PaymentRequest, requestId: string) {
  return fetch(`${PAYMENT_URL}/charges`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Request-Id': requestId,
    },
    body: JSON.stringify(paymentReq),
  })
}
```

AsyncLocalStorage (auto propagation):

```typescript
import { AsyncLocalStorage } from 'async_hooks'

const requestContext = new AsyncLocalStorage<{ requestId: string }>()

// Middleware
app.use((req, res, next) => {
  const requestId = req.headers['x-request-id'] as string ?? crypto.randomUUID()
  requestContext.run({ requestId }, () => next())
})

// Available anywhere in the call chain
function getRequestId(): string {
  return requestContext.getStore()?.requestId ?? 'unknown'
}
```

---

## RECOMMENDED: OpenTelemetry for Tracing

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node'
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'

const sdk = new NodeSDK({
  serviceName: 'order-service',
  instrumentations: [getNodeAutoInstrumentations()],
})

sdk.start()
```

Auto-instruments:
- HTTP requests (inbound and outbound)
- Database queries (pg, mysql, prisma)
- Express/Fastify/Hono middleware

---

## REQUIRED: Health Checks

### Kubernetes Probes

```typescript
// Liveness — app is running
app.get('/health/live', (req, res) => {
  res.status(200).json({ status: 'up' })
})

// Readiness — app can serve traffic
app.get('/health/ready', async (req, res) => {
  try {
    await db.$queryRaw`SELECT 1`  // Check DB connection
    res.status(200).json({ status: 'ready' })
  } catch {
    res.status(503).json({ status: 'not ready' })
  }
})
```

### CRITICAL: Health Endpoints Must Not Expose Details

```typescript
// NEVER — leaks internals
res.json({
  database: { host: 'db.internal.com', version: '16.1' },
  redis: { host: 'redis.internal.com' },
  env: process.env,
})

// GOOD — status only
res.json({ status: 'up' })
```

---

## RECOMMENDED: Metrics

```typescript
import { Counter, Histogram, Registry } from 'prom-client'

const registry = new Registry()

const ordersProcessed = new Counter({
  name: 'orders_processed_total',
  help: 'Total orders processed',
  labelNames: ['status'],
  registers: [registry],
})

const orderDuration = new Histogram({
  name: 'order_processing_seconds',
  help: 'Order processing duration',
  registers: [registry],
})

// Usage
async function processOrder(order: Order) {
  const timer = orderDuration.startTimer()
  try {
    await doProcess(order)
    ordersProcessed.inc({ status: 'success' })
  } catch (err) {
    ordersProcessed.inc({ status: 'failure' })
    throw err
  } finally {
    timer()
  }
}

// Expose metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', registry.contentType)
  res.end(await registry.metrics())
})
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Health endpoints don't expose details | CRITICAL |
| Structured logging (pino) | REQUIRED |
| Request ID propagation | REQUIRED |
| Health check endpoints | REQUIRED |
| OpenTelemetry tracing | RECOMMENDED |
| Prometheus metrics | RECOMMENDED |
