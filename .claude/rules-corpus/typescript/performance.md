---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Performance Rules

Fast build/test/deploy.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deploy; no exceptions |
| **REQUIRED** | Follow unless overridden |
| **RECOMMENDED** | Best practice; team adjusts |

---

## REQUIRED: Parallel Test Execution

Tests MUST run in parallel by default.

### Vitest (Parallel by Default)

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    pool: 'forks',          // or 'threads'
    poolOptions: {
      forks: {
        minForks: 2,
        maxForks: undefined,  // Use all CPUs
      },
    },
  },
})
```

### Jest

```javascript
// jest.config.js
module.exports = {
  maxWorkers: '50%',  // Half of available CPUs
}
```

```bash
# Run in parallel
npx jest --maxWorkers=50%
npx vitest run
```

---

## REQUIRED: Test Isolation

Tests MUST isolate for parallel runs.

- [ ] No shared mutable state between tests
- [ ] No hardcoded ports — use random ports (`:0`)
- [ ] No shared files — use temp directories
- [ ] No test order dependencies
- [ ] No shared database state — reset between tests

```typescript
// BAD — shared state
let service: OrderService
const orders: Order[] = []

// GOOD — fresh per test
beforeEach(() => {
  service = new OrderService()
})
```

### Random Ports

```typescript
// NEVER
const server = app.listen(3000)

// ALWAYS
const server = app.listen(0)
const { port } = server.address() as AddressInfo
```

---

## REQUIRED: Bounded Caches

```typescript
// NEVER — unbounded cache
const cache = new Map<string, User>()

// ALWAYS — bounded with eviction
import { LRUCache } from 'lru-cache'

const cache = new LRUCache<string, User>({
  max: 10_000,
  ttl: 5 * 60 * 1000,  // 5 min TTL
})
```

---

## REQUIRED: Bounded Queues and Concurrency

```typescript
// NEVER — unbounded concurrency
const promises = items.map(item => processItem(item))
await Promise.all(promises)  // 10,000 concurrent requests

// ALWAYS — bounded concurrency
import pLimit from 'p-limit'

const limit = pLimit(10)  // Max 10 concurrent
const results = await Promise.all(
  items.map(item => limit(() => processItem(item)))
)
```

---

## REQUIRED: Stream Large Data

```typescript
// NEVER — load entire file into memory
const data = await fs.readFile('large-file.csv', 'utf-8')
const lines = data.split('\n')

// ALWAYS — stream
import { createReadStream } from 'fs'
import { createInterface } from 'readline'

const rl = createInterface({
  input: createReadStream('large-file.csv'),
})

for await (const line of rl) {
  await processLine(line)
}
```

### Streaming HTTP Responses

```typescript
// For large JSON arrays
app.get('/orders/export', async (req, res) => {
  res.setHeader('Content-Type', 'application/json')
  res.write('[')

  let first = true
  for await (const order of orderStream()) {
    if (!first) res.write(',')
    res.write(JSON.stringify(order))
    first = false
  }

  res.write(']')
  res.end()
})
```

---

## RECOMMENDED: Database Query Optimization

```typescript
// NEVER — N+1 queries
const orders = await prisma.order.findMany()
for (const order of orders) {
  order.items = await prisma.orderItem.findMany({
    where: { orderId: order.id },
  })
}

// ALWAYS — include relations
const orders = await prisma.order.findMany({
  include: { items: true },
})

// Or use explicit joins in Drizzle
const orders = await db
  .select()
  .from(ordersTable)
  .leftJoin(itemsTable, eq(ordersTable.id, itemsTable.orderId))
```

---

## RECOMMENDED: Bundle Size (Frontend)

```bash
# Analyze bundle
npx vite-bundle-visualizer
npx next-bundle-analyzer

# Tree-shake — use named imports
import { map, filter } from 'lodash-es'  // GOOD — tree-shakeable
import _ from 'lodash'                     // BAD — imports everything
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Tests run in parallel | REQUIRED |
| Tests are isolated | REQUIRED |
| Bounded caches (LRU) | REQUIRED |
| Bounded concurrency (p-limit) | REQUIRED |
| Stream large data | REQUIRED |
| N+1 query prevention | RECOMMENDED |
| Bundle size optimization | RECOMMENDED |
