---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---
# Database Rules

> Port of Java Flyway/JPA rules to JS/TS ORMs: Prisma, Drizzle, or Knex.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deploy; no exceptions |
| **REQUIRED** | Follow unless overridden |
| **RECOMMENDED** | Best practice; team adjusts |

---

## Migration Tool

### REQUIRED: Use Your ORM's Migration System

| ORM | Migration Tool | Command |
|-----|---------------|---------|
| Prisma | `prisma migrate` | `npx prisma migrate dev` |
| Drizzle | `drizzle-kit` | `npx drizzle-kit migrate` |
| Knex | built-in | `npx knex migrate:latest` |

Never modify DB schema manually in any env.

---

## Migration Rules

### CRITICAL: Migrations Are Immutable

Once deployed to any env, **NEVER** modify a migration.

```typescript
// Prisma — NEVER edit an existing migration in prisma/migrations/
// Create a new migration instead:
// npx prisma migrate dev --name add_phone_to_users

// Knex — NEVER edit a migration that has run
// Create a new one:
// npx knex migrate:make add_phone_to_users
```

### CRITICAL: Backward Compatible Migrations

Migrations MUST work with old + new app versions (zero-downtime deploys):

```sql
-- BAD — breaks old app
ALTER TABLE users DROP COLUMN legacy_field;
ALTER TABLE users RENAME COLUMN name TO full_name;

-- GOOD — backward compatible
-- Step 1: Add new column (old app ignores it)
ALTER TABLE users ADD COLUMN full_name VARCHAR(255);
UPDATE users SET full_name = name;

-- Step 2: In a LATER migration (after all instances updated)
ALTER TABLE users DROP COLUMN name;
```

### REQUIRED: One Change Per Migration

```typescript
// GOOD — separate migrations
// 001_create_orders_table.ts
// 002_add_status_to_users.ts
// 003_add_index_on_email.ts

// BAD — multiple unrelated changes in one migration
```

---

## Schema Design

### REQUIRED: Standard Columns

Every table MUST have:

```typescript
// Prisma
model Order {
  id        String   @id @default(uuid())
  // ... business columns ...
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")
  version   Int      @default(0)  // optimistic locking

  @@map("orders")
}

// Drizzle
export const orders = pgTable('orders', {
  id: uuid('id').primaryKey().defaultRandom(),
  // ... business columns ...
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  version: integer('version').notNull().default(0),
})
```

### REQUIRED: Use Appropriate Types

| Data | PostgreSQL Type | Notes |
|------|----------------|-------|
| Primary key | `uuid` | Prefer over serial/auto-increment |
| Money | `numeric(19,4)` | Never use float/double |
| Timestamps | `timestamp with time zone` | Always w/ timezone |
| Text (bounded) | `varchar(n)` | Explicit max |
| Text (unbounded) | `text` | Long content |
| Boolean | `boolean` | Not int |

```typescript
// NEVER — float for money
price: float('price')

// ALWAYS — numeric/decimal for money
price: numeric('price', { precision: 19, scale: 4 })
```

### REQUIRED: Foreign Keys

```typescript
// Prisma
model OrderItem {
  id        String  @id @default(uuid())
  orderId   String  @map("order_id")
  order     Order   @relation(fields: [orderId], references: [id], onDelete: Cascade)
  productId String  @map("product_id")
  product   Product @relation(fields: [productId], references: [id], onDelete: Restrict)
}

// Drizzle
export const orderItems = pgTable('order_items', {
  id: uuid('id').primaryKey().defaultRandom(),
  orderId: uuid('order_id').notNull().references(() => orders.id, { onDelete: 'cascade' }),
  productId: uuid('product_id').notNull().references(() => products.id, { onDelete: 'restrict' }),
})
```

---

## Indexes

### REQUIRED: Index Foreign Keys

```typescript
// Drizzle
export const orderItemsOrderIdx = index('idx_order_items_order_id').on(orderItems.orderId)

// Prisma
model OrderItem {
  orderId String @map("order_id")

  @@index([orderId])
  @@index([productId])
}
```

### REQUIRED: Index Query Patterns

```typescript
// For: SELECT * FROM orders WHERE user_id = ? ORDER BY created_at DESC
@@index([userId, createdAt(sort: Desc)])
```

---

## Testing

### REQUIRED: Testcontainers for Real DB

```typescript
import { PostgreSqlContainer } from '@testcontainers/postgresql'

let container: StartedPostgreSqlContainer

beforeAll(async () => {
  container = await new PostgreSqlContainer('postgres:16').start()
  process.env.DATABASE_URL = container.getConnectionUri()
  // Run migrations
  await migrate()
}, 30_000)

afterAll(async () => {
  await container.stop()
})
```

### REQUIRED: Never Use SQLite for Postgres-Targeted Code

```typescript
// BAD — SQLite behaves differently
// "It works in tests" then breaks in production

// GOOD — Testcontainers with real Postgres
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Never modify deployed migrations | CRITICAL |
| Backward compatible changes | CRITICAL |
| Use ORM migration system | REQUIRED |
| One change per migration | REQUIRED |
| Include id, createdAt, updatedAt, version | REQUIRED |
| Appropriate types (uuid, numeric for money) | REQUIRED |
| Index foreign keys | REQUIRED |
| Test with Testcontainers (real DB) | REQUIRED |
| Never use SQLite for Postgres code | REQUIRED |
