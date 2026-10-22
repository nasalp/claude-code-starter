---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Testing Rules

> **Shared (mutation blame, no regex-over-source, PR-owned scoring):** Read `rules-corpus/common/testing.md` on demand. Below = TS/JS-specific only.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## Test Framework

### REQUIRED: Vitest or Jest

Use Vitest (preferred) or Jest. Never mix frameworks in one project.

```typescript
// Vitest (preferred — faster, native ESM, TS support)
import { describe, it, expect } from 'vitest'

// Jest (acceptable — widely supported)
// No import needed with @types/jest
```

For plain JS:

```javascript
// @ts-check
const { describe, it, expect } = require('vitest')
```

---

## Assertions

### REQUIRED: Use Built-in Matchers Thoroughly

```typescript
// GOOD — specific, descriptive assertions
expect(result).toBe('expected')
expect(result).toEqual({ name: 'Alice', age: 30 })
expect(items).toHaveLength(3)
expect(result).toMatchObject({ status: 'pending' })
expect(() => call()).toThrow(OrderNotFoundError)
expect(value).toBeGreaterThan(0)

// BAD — weak, truthy-only assertions
expect(result).toBeTruthy()     // What IS the value?
expect(!!result).toBe(true)     // Unreadable
expect(result != null).toBe(true)  // Use .toBeDefined()
```

### CRITICAL: React Testing Library — `.toBeInTheDocument()` over `.toBeDefined()` on throwing queries

When asserting on query result from `@testing-library/react`, use
`.toBeInTheDocument()` (from `@testing-library/jest-dom`) — never
`.toBeDefined()`.

```ts
// ❌ Forbidden — silent tautology if the query is ever changed
expect(screen.getByText(/Customer Health/)).toBeDefined()
//                                          ^^^^^^^^^^^
// getByText THROWS if the element is missing, so .toBeDefined() is
// already satisfied by the time control reaches it. The assertion
// adds nothing. If a future refactor swaps getByText → queryByText
// (non-throwing), `.toBeDefined()` silently passes on `null` because
// `null != undefined`. The test goes green while the page is blank.

// ✅ Correct — explicit DOM presence check
expect(screen.getByText(/Customer Health/)).toBeInTheDocument()

// ✅ Also correct for queryBy* (non-throwing) variants
expect(screen.queryByText(/Customer Health/)).toBeInTheDocument()
expect(screen.queryByText(/Loading/)).not.toBeInTheDocument()
```

#### ESLint enforcement

Add to `eslintrc` / `eslint.config.ts`:

```js
'jest/prefer-to-be': 'error',
'jest-dom/prefer-to-be-in-the-document': 'error',   // requires eslint-plugin-jest-dom
'testing-library/prefer-presence-queries': 'error',
'testing-library/no-node-access': 'warn',
```

### RECOMMENDED: Custom Matchers for Complex Domains

```typescript
// vitest.setup.ts
expect.extend({
  toBeValidOrder(received: Order) {
    const pass = received.id != null
      && received.status != null
      && received.items.length > 0
      && received.total > 0
    return {
      pass,
      message: () => `Expected valid order but got: ${JSON.stringify(received)}`,
    }
  },
})

// Usage
expect(order).toBeValidOrder()
```

---

## BDD Convention

### REQUIRED: Given / When / Then

```typescript
it('should create order when valid request', () => {
  // given
  const request = validRequest()

  // when
  const result = service.createOrder(request)

  // then
  expect(result.status).toBe('pending')
  expect(result.items).toHaveLength(3)
})
```

### REQUIRED: Naming Convention

```
should_<expected_outcome>_when_<condition>
```

Or natural language equivalent:

```typescript
it('should reject order when amount is negative')
it('should apply discount when customer is premium')
it('should return 404 when order not found')
```

---

## Async Testing

### CRITICAL: No setTimeout / Manual Delays

```typescript
// NEVER
await new Promise(resolve => setTimeout(resolve, 5000))
await sleep(3000)

// ALWAYS — use polling or waitFor
import { waitFor } from '@testing-library/dom'  // or custom

await waitFor(() => {
  expect(element).toBeVisible()
}, { timeout: 5000, interval: 100 })

// For async operations — just await
const result = await service.processOrder(request)
expect(result.status).toBe('completed')

// For event-driven — use vi.waitFor (Vitest 1.x+)
await vi.waitFor(() => {
  expect(callback).toHaveBeenCalled()
})
```

---

## Test Isolation

### CRITICAL: No Shared Mutable State

```typescript
// NEVER — shared state between tests
let service: OrderService
const orders: Order[] = []

beforeAll(() => {
  service = new OrderService()
})

it('test 1', () => {
  orders.push(service.create())  // Leaks into test 2
})

// ALWAYS — fresh state per test
let service: OrderService

beforeEach(() => {
  service = new OrderService()
})

it('test 1', () => {
  const orders = [service.create()]  // Local to this test
})
```

### REQUIRED: Random Ports for Servers

```typescript
// NEVER — hardcoded port
const server = app.listen(3000)

// ALWAYS — random port
const server = app.listen(0)
const port = (server.address() as AddressInfo).port
```

---

## Mocking

### REQUIRED: Mock at Boundaries, Not Internals

```typescript
// GOOD — mock the external dependency
vi.mock('./payment-client', () => ({
  processPayment: vi.fn().mockResolvedValue({ status: 'paid' }),
}))

// BAD — mocking internal implementation details
vi.mock('./order-service', () => ({
  validateOrder: vi.fn(),     // Testing the mock, not the code
  calculateTotal: vi.fn(),
}))
```

### REQUIRED: Typed Mocks

```typescript
// GOOD — type-safe mock
import type { PaymentClient } from './payment-client'

const mockPayment: PaymentClient = {
  processPayment: vi.fn().mockResolvedValue({ status: 'paid' }),
  refund: vi.fn().mockResolvedValue({ status: 'refunded' }),
}

// BAD — untyped
const mockPayment = {
  processPayment: vi.fn(),
  // Forgot to mock refund — no compiler error
}
```

---

## Integration Testing

### REQUIRED: Isolation by Type

One test file = one integration type:
- Route handler tests (supertest, stubbed services)
- Repository tests (real database via testcontainers)
- HTTP client tests (MSW or nock)

### REQUIRED: Real Infrastructure for DB Tests

```typescript
import { PostgreSqlContainer } from '@testcontainers/postgresql'

let container: StartedPostgreSqlContainer

beforeAll(async () => {
  container = await new PostgreSqlContainer('postgres:16').start()
  process.env.DATABASE_URL = container.getConnectionUri()
}, 30_000)

afterAll(async () => {
  await container.stop()
})
```

### REQUIRED: MSW for External HTTP

```typescript
import { setupServer } from 'msw/node'
import { http, HttpResponse } from 'msw'

const server = setupServer(
  http.get('https://api.payment.com/charges/:id', () => {
    return HttpResponse.json({ status: 'paid', amount: 100 })
  }),
)

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
```

---

## E2E Testing

### REQUIRED: Playwright for Browser Tests

```typescript
import { test, expect } from '@playwright/test'

test('user can create an order', async ({ page }) => {
  await page.goto('/orders/new')
  await page.fill('[name="email"]', 'user@example.com')
  await page.fill('[name="amount"]', '99.99')
  await page.click('button[type="submit"]')
  await expect(page.getByText('Order created')).toBeVisible()
})
```

### REQUIRED: Supertest for API E2E

```typescript
import request from 'supertest'

it('should create order via API', async () => {
  const res = await request(app)
    .post('/api/v1/orders')
    .send({ email: 'user@test.com', amount: 99.99 })
    .expect(201)

  expect(res.body).toMatchObject({
    status: 'pending',
    email: 'user@test.com',
  })
  expect(res.headers.location).toMatch(/\/api\/v1\/orders\//)
})
```

---

## Test Execution

### CRITICAL: Tests Must Be Run

Never say "tests should pass" — run them:

```bash
# Vitest
npx vitest run

# Jest
npx jest

# With coverage
npx vitest run --coverage
```

Include output in response as proof.

---

## Property-Based Testing

### RECOMMENDED: fast-check

Use fast-check (JS equivalent of jqwik) for invariants:

```typescript
import fc from 'fast-check'

it('should accept all valid email formats', () => {
  fc.assert(
    fc.property(fc.emailAddress(), (email) => {
      const result = validateEmail(email)
      expect(result.valid).toBe(true)
    })
  )
})

it('should survive JSON roundtrip', () => {
  fc.assert(
    fc.property(fc.record({
      name: fc.string({ minLength: 1, maxLength: 128 }),
      amount: fc.double({ min: 0.01, max: 999999, noNaN: true }),
    }), (input) => {
      const json = JSON.stringify(input)
      const parsed = JSON.parse(json)
      expect(parsed).toEqual(input)
    })
  )
})
```

### Naming Convention

Property test files end with `.properties.test.ts`:

```
order-price.properties.test.ts
application-name.properties.test.ts
```

---

## Mutation Testing

### RECOMMENDED: Stryker

Use Stryker (JS equivalent of PITest) to verify tests catch bugs:

```bash
npx stryker run
```

```jsonc
// stryker.config.json
{
  "mutate": ["src/**/*.ts", "!src/**/*.test.ts"],
  "testRunner": "vitest",
  "thresholds": { "high": 80, "low": 60, "break": 60 }
}
```

Run against unit tests only — not E2E or integration tests.

---

## Quick Reference

| Rule | Priority |
|------|----------|
| No `setTimeout` / manual delays in tests | CRITICAL |
| No shared mutable state between tests | CRITICAL |
| Run tests, show output | CRITICAL |
| Vitest or Jest | REQUIRED |
| Thorough built-in matchers | REQUIRED |
| BDD naming convention | REQUIRED |
| Random ports for servers | REQUIRED |
| Mock at boundaries, not internals | REQUIRED |
| Typed mocks | REQUIRED |
| Integration isolation by type | REQUIRED |
| Testcontainers for DB | REQUIRED |
| MSW for external HTTP | REQUIRED |
| Playwright for E2E | REQUIRED |
| Property-based tests (fast-check) | RECOMMENDED |
| Mutation testing (Stryker) | RECOMMENDED |
| Custom matchers for complex domains | RECOMMENDED |

> Rationale (Why/Calibration): `docs/rule-rationale/typescript__testing.md`
