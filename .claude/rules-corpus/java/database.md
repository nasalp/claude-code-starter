---
paths:
  - "**/*.java"
---

# Database Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## Migration Tool: Flyway

### REQUIRED: Use Flyway

All DB schema changes go through Flyway migrations.

```
src/main/resources/db/migration/
├── V1__create_users_table.sql
├── V2__create_orders_table.sql
├── V3__add_email_to_users.sql
└── V4__create_order_items_table.sql
```

### REQUIRED: Naming Convention

```
V<version>__<description>.sql

V1__create_users_table.sql
V2__add_index_on_email.sql
V3.1__add_phone_column.sql  # Sub-version for hotfix
```

**Rules:**
- Version: integer or decimal (V1, V2, V3.1)
- Double underscore separator
- Snake_case description
- `.sql` extension

---

## Migration Rules

### CRITICAL: Migrations Are Immutable

Once deployed to any env, **NEVER** modify migration.

```sql
-- V1__create_users.sql
-- ❌ NEVER edit this after it's run anywhere

-- ✅ Create new migration instead
-- V2__add_column_to_users.sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
```

### CRITICAL: Backward Compatible Migrations

Migrations must work with both old and new app versions (zero-downtime deploys).

```sql
-- ❌ BAD — breaks old app immediately
ALTER TABLE users DROP COLUMN legacy_field;
ALTER TABLE users RENAME COLUMN name TO full_name;

-- ✅ GOOD — backward compatible
-- Step 1: Add new column (old app ignores it)
ALTER TABLE users ADD COLUMN full_name VARCHAR(255);
UPDATE users SET full_name = name;

-- Step 2: (after all instances updated) Remove old column in later migration
-- V5__cleanup_legacy_name.sql
ALTER TABLE users DROP COLUMN name;
```

### REQUIRED: One Change Per Migration

```sql
-- ❌ BAD — multiple unrelated changes
CREATE TABLE orders (...);
ALTER TABLE users ADD COLUMN last_login TIMESTAMP;
CREATE INDEX idx_products_sku ON products(sku);

-- ✅ GOOD — separate migrations
-- V3__create_orders_table.sql
-- V4__add_last_login_to_users.sql
-- V5__add_index_on_products_sku.sql
```

---

## Schema Design

### REQUIRED: Always Include

```sql
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- business columns
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    version BIGINT NOT NULL DEFAULT 0  -- optimistic locking
);
```

**Standard columns:**
- `id` — primary key
- `created_at` — when created
- `updated_at` — when last modified
- `version` — optimistic locking

### REQUIRED: Use Appropriate Types

| Data | Type | Note |
|------|------|------|
| Primary key | `UUID` | Prefer over auto-increment |
| Money | `NUMERIC(19,4)` | Never use FLOAT |
| Timestamps | `TIMESTAMP WITH TIME ZONE` | Always with timezone |
| Text (bounded) | `VARCHAR(n)` | With explicit limit |
| Text (unbounded) | `TEXT` | For large content |
| Boolean | `BOOLEAN` | Not integer |

### REQUIRED: Foreign Keys

```sql
CREATE TABLE order_items (
    id UUID PRIMARY KEY,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT
);
```

**Decide on delete behavior:**
- `CASCADE` — delete children with parent
- `RESTRICT` — prevent delete if children exist
- `SET NULL` — set FK to null on parent delete

---

## Indexes

### REQUIRED: Index Foreign Keys

```sql
-- Foreign key columns need indexes
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
```

### REQUIRED: Index Query Patterns

Create indexes for common WHERE/ORDER BY columns:

```sql
-- For: SELECT * FROM orders WHERE user_id = ? ORDER BY created_at DESC
CREATE INDEX idx_orders_user_created ON orders(user_id, created_at DESC);
```

### RECOMMENDED: Partial Indexes

For queries filtering on specific values:

```sql
-- For: SELECT * FROM orders WHERE status = 'PENDING'
CREATE INDEX idx_orders_pending ON orders(status) WHERE status = 'PENDING';
```

---

## Testing Migrations

### REQUIRED: Test with Testcontainers

```java
@SpringBootTest
@Testcontainers
class MigrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");

    @Test
    void migrations_should_apply_cleanly() {
        // Flyway runs automatically on startup
        // Test that application context loads
    }
}
```

### REQUIRED: Rollback Strategy

Document rollback for each migration:

```sql
-- V3__add_email_verified.sql
ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE;

-- ROLLBACK (keep in comments or separate file):
-- ALTER TABLE users DROP COLUMN email_verified;
```

---

## Data Migrations

### REQUIRED: Separate Schema and Data

```
V3__add_status_column.sql      # Schema change
V3.1__migrate_status_data.sql  # Data migration
```

### REQUIRED: Batch Large Updates

```sql
-- ❌ BAD — locks entire table
UPDATE orders SET status = 'LEGACY' WHERE status IS NULL;

-- ✅ GOOD — batch updates
DO $$
DECLARE
    batch_size INT := 1000;
    affected INT;
BEGIN
    LOOP
        UPDATE orders
        SET status = 'LEGACY'
        WHERE id IN (
            SELECT id FROM orders
            WHERE status IS NULL
            LIMIT batch_size
        );
        GET DIAGNOSTICS affected = ROW_COUNT;
        EXIT WHEN affected = 0;
        COMMIT;
    END LOOP;
END $$;
```

---

## Configuration

### REQUIRED: Flyway Config

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: true  # For existing databases
    validate-on-migrate: true
```

### REQUIRED: Different DB Per Environment

```yaml
# application-local.yml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/myapp_dev

# application-test.yml (Testcontainers handles this)

# application-prod.yml
spring:
  datasource:
    url: ${DATABASE_URL}
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Never modify deployed migrations | CRITICAL |
| Backward compatible changes | CRITICAL |
| Use Flyway | REQUIRED |
| Naming convention (V1__desc.sql) | REQUIRED |
| One change per migration | REQUIRED |
| Include created_at, updated_at, version | REQUIRED |
| Use appropriate types (UUID, NUMERIC for money) | REQUIRED |
| Index foreign keys | REQUIRED |
| Test migrations with Testcontainers | REQUIRED |
| Document rollback strategy | REQUIRED |
| Batch large data updates | REQUIRED |
| Partial indexes | RECOMMENDED |
