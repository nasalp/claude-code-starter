---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# HTTP Client Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deploy; no exceptions |
| **REQUIRED** | Follow unless overridden |
| **RECOMMENDED** | Best practice; team adjusts |

---

## REQUIRED: Use Native `fetch`

Node.js 18+ has native `fetch`. No `axios`, `node-fetch`, or `got` unless needed.

```typescript
// GOOD — native fetch
const res = await fetch(`${BASE_URL}/orders/${orderId}`)
if (!res.ok) throw new OrderNotFoundError(orderId)
const order: Order = await res.json()

// POST
const res = await fetch(`${BASE_URL}/orders`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(request),
})

// With timeout
const controller = new AbortController()
const timeout = setTimeout(() => controller.abort(), 5000)

try {
  const res = await fetch(url, { signal: controller.signal })
} finally {
  clearTimeout(timeout)
}
```

**When to use a library instead:**
- Retries with backoff → `ky` or `ofetch`
- Interceptors/middleware → `ky`
- Request cancellation patterns → `ky`

---

## REQUIRED: Always Check Response Status

```typescript
// NEVER — assumes success
const data = await fetch(url).then(r => r.json())

// ALWAYS — check status
const res = await fetch(url)
if (!res.ok) {
  throw new ExternalServiceError('payment-service', {
    status: res.status,
    body: await res.text(),
  })
}
const data: Payment = await res.json()
```

---

## REQUIRED: Typed HTTP Clients

Wrap external calls in typed client fns/classes:

```typescript
// GOOD — typed client
interface PaymentClient {
  getPayment(id: string): Promise<Payment>
  createPayment(request: CreatePaymentRequest): Promise<Payment>
}

function createPaymentClient(baseUrl: string): PaymentClient {
  return {
    async getPayment(id) {
      const res = await fetch(`${baseUrl}/payments/${id}`)
      if (!res.ok) throw new PaymentServiceError(`GET /payments/${id}`, res.status)
      return res.json()
    },

    async createPayment(request) {
      const res = await fetch(`${baseUrl}/payments`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(request),
      })
      if (!res.ok) throw new PaymentServiceError('POST /payments', res.status)
      return res.json()
    },
  }
}

// BAD — raw fetch scattered everywhere
async function getOrder(id: string) {
  const payment = await fetch(`${PAYMENT_URL}/payments/${id}`).then(r => r.json())
  const shipping = await fetch(`${SHIPPING_URL}/shipments/${id}`).then(r => r.json())
}
```

---

## REQUIRED: Validate External Responses

External APIs return anything — validate at boundary:

```typescript
import { z } from 'zod'

const PaymentResponseSchema = z.object({
  id: z.string(),
  status: z.enum(['pending', 'paid', 'failed']),
  amount: z.number(),
})

async function getPayment(id: string): Promise<Payment> {
  const res = await fetch(`${BASE_URL}/payments/${id}`)
  if (!res.ok) throw new PaymentServiceError('GET', res.status)
  const data = await res.json()
  return PaymentResponseSchema.parse(data)  // Validate shape
}
```

---

## REQUIRED: Timeouts on All External Calls

```typescript
// ALWAYS set a timeout
const TIMEOUT_MS = 5_000

async function fetchWithTimeout(url: string, options?: RequestInit): Promise<Response> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS)

  try {
    return await fetch(url, { ...options, signal: controller.signal })
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw new ExternalServiceError('timeout', url)
    }
    throw err
  } finally {
    clearTimeout(timeout)
  }
}
```

---

## RECOMMENDED: Retry with Backoff

Unreliable external services:

```typescript
async function fetchWithRetry(
  url: string,
  options?: RequestInit,
  retries = 3,
): Promise<Response> {
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const res = await fetchWithTimeout(url, options)
      if (res.status >= 500 && attempt < retries) {
        await delay(Math.pow(2, attempt) * 100)  // Exponential backoff
        continue
      }
      return res
    } catch (err) {
      if (attempt === retries) throw err
      await delay(Math.pow(2, attempt) * 100)
    }
  }
  throw new Error('Unreachable')
}

// Or use ky which has built-in retry
import ky from 'ky'

const api = ky.create({
  prefixUrl: BASE_URL,
  retry: { limit: 3, methods: ['get'] },
  timeout: 5000,
})
```

---

## Testing HTTP Clients

### REQUIRED: MSW for Mocking External Services

```typescript
import { setupServer } from 'msw/node'
import { http, HttpResponse } from 'msw'

const server = setupServer(
  http.get('https://api.payment.com/payments/:id', ({ params }) => {
    return HttpResponse.json({ id: params.id, status: 'paid', amount: 100 })
  }),
)

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

// Test error scenarios
it('should throw on payment service error', async () => {
  server.use(
    http.get('https://api.payment.com/payments/:id', () => {
      return new HttpResponse(null, { status: 503 })
    }),
  )

  await expect(paymentClient.getPayment('123'))
    .rejects.toThrow(PaymentServiceError)
})
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Use native `fetch` (Node 18+) | REQUIRED |
| Always check response status | REQUIRED |
| Typed client functions/classes | REQUIRED |
| Validate external responses (Zod) | REQUIRED |
| Timeouts on all external calls | REQUIRED |
| MSW for testing HTTP clients | REQUIRED |
| Retry with backoff for unreliable services | RECOMMENDED |
