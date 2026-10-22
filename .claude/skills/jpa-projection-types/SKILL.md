---
name: jpa-projection-types
description: Type mapping for Spring Data JPA interface projections — map SQL column types (TIMESTAMPTZ, NUMERIC, JSONB, etc.) to the correct Java return type to prevent runtime ClassCastException. Use when aut...
origin: ECC
triggers: jpa-projection-types, You're declaring an interface projection (interface Foo { X, java.sql.Timestamp, ClassCastException, TIMESTAMPTZ, String, LocalDateTime, Instant, OffsetDateTime, TIMESTAMP, DATE, LocalDate
paths:
  - "**/*.java"
---
# JPA Interface Projection Types

Spring Data JPA interface projections look harmless:

```java
interface OrderSummary {
    UUID getId();
    String getCreatedAt();   // ❌ TIMESTAMPTZ column → runtime ClassCastException
}
```

There's no compile error. There's no warning. The first time the projection runs, Hibernate hands back a `java.sql.Timestamp` and the proxy throws `ClassCastException` at the call site. The class loads, the test compiles, the bug ships.

## When to use

- You're declaring an interface projection (`interface Foo { X getY(); }`).
- The query is a native `@Query("SELECT ... FROM ...", nativeQuery = true)` or a JPQL/HQL projection.
- The columns include any non-trivial type: timestamps, numerics, JSON, arrays, enums.

## The type-mapping table (PostgreSQL → Java)

| SQL type | Wrong | Correct |
|----------|-------|---------|
| `TIMESTAMPTZ` / `TIMESTAMP WITH TIME ZONE` | `String`, `LocalDateTime` | `Instant` or `OffsetDateTime` |
| `TIMESTAMP` / `TIMESTAMP WITHOUT TIME ZONE` | `String`, `Instant` | `LocalDateTime` |
| `DATE` | `String` | `LocalDate` |
| `TIME` | `String` | `LocalTime` |
| `NUMERIC(p,s)` / `DECIMAL` | `Double`, `Float` | `BigDecimal` |
| `BIGINT` | `Integer` | `Long` |
| `INTEGER` | `Long` (works but wastes 4 bytes) | `Integer` |
| `SMALLINT` | `Integer` (works) | `Short` |
| `UUID` | `String` | `UUID` |
| `JSONB` / `JSON` | `String` (works on read; loses structure) | Custom type-handler returning a Jackson `JsonNode` or your DTO |
| `TEXT[]` (array) | `String` | `List<String>` (with proper Hibernate array handler) or fetch via `unnest()` and aggregate |
| `BYTEA` | `String` | `byte[]` |
| `BOOLEAN` | `String`, `Integer` | `Boolean` |
| `INET` / `CIDR` | hibernate types vary | `String` (typed wrapper if precision matters) |
| `INTERVAL` | `String` | `java.time.Duration` (with proper handler) |
| `enum` (PG enum) | `String` (works) | Java `enum` with `@JdbcType` or `@Enumerated` configured |
| `TO_CHAR(...)` derived column | `Instant` | `String` — `TO_CHAR` returns text |
| `COUNT(*)` / `SUM(...)` | int when the column is COUNT (returns BIGINT) | `Long` |
| `EXTRACT(EPOCH FROM ...)` | `Long` | `Double` (epoch in seconds with fractional part) |

## Common gotchas

### `getCreatedAt()` returns `Timestamp`, not `Instant`

The JDBC default for `TIMESTAMPTZ` is `java.sql.Timestamp`. Hibernate's projection proxy passes through what the JDBC driver gives it. Use `Instant getCreatedAt()` and Hibernate will convert.

### Aggregate columns are typed by the DB, not your wish

`SELECT COUNT(*) FROM orders` returns `BIGINT` in PostgreSQL. Use `Long`, not `Integer`. Same for `SUM(integer_col)` (returns `BIGINT`).

### `TO_CHAR(timestamp_col, 'YYYY-MM-DD')` returns `text`, not a date

If you `TO_CHAR` for display formatting, the projection method must return `String`. If you wanted a date, drop `TO_CHAR` and let Java format it.

### `NUMERIC` without scale loses precision

`getPrice()` typed as `Double` will silently round on a `NUMERIC(19,4)` column. Always `BigDecimal` for money or any value where precision matters.

### Nullable columns vs primitives

`int getQuantity()` on a NULLable column throws `NullPointerException` at projection time. Use `Integer`, or make the column `NOT NULL` at the DB level.

## Verifying you got it right

```java
@Test
void projection_returns_expected_types() {
    OrderSummary summary = repository.findSummaryById(orderId);

    assertThat(summary.getCreatedAt()).isInstanceOf(Instant.class);
    assertThat(summary.getTotal()).isInstanceOf(BigDecimal.class);
    assertThat(summary.getCount()).isInstanceOf(Long.class);
}
```

Pair with [annotation-drift-testing](../annotation-drift-testing/SKILL.md) if your projection is described by a custom doc annotation that references column types.

## Generalization

The pattern is universal: any ORM with type inference between SQL and Java has projection-type traps. The fix is the same — know the SQL type, look up the canonical Java mapping, write a smoke test that verifies the runtime type matches the declared one.
