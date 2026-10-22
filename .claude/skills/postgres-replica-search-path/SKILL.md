---
name: postgres-replica-search-path
description: Use ?currentSchema= on the JDBC URL when prod tables live in public but local dev keeps them in a separate schema; hibernate.default_schema does NOT cover native queries.
origin: ECC
triggers: replica datasource, currentSchema, searchpath, hibernate.defaultschema, native query schema, relation does not exist, dual datasource Postgres, Whole Brain replica
paths:
  - "**/*.java"
  - "**/*.kt"
  - "**/*.sql"
---
# Postgres Replica Schema via `?currentSchema=`

## When to use

You have a Spring Boot service with a **read-replica datasource** whose
native SQL queries reference unqualified table names like
`SELECT ... FROM "Companies"` and `JOIN "CompanyPaymentPlans"`. In
production, those tables live in the `public` schema of an upstream
read replica. In local development, you do not have access to the
upstream cluster, so the same tables live in a separate schema (e.g.
`replica`) inside your local Postgres container, side-by-side with the
service's own primary schema.

When you boot the service locally, every native query against the
replica datasource fails with
`relation "Companies" does not exist` because the connection's
`search_path` defaults to the local primary schema.

## When NOT to use

- The service is single-datasource and tables already live in `public`
  (or `$user`). Postgres' default `search_path = "$user", public`
  resolves them.
- The service uses **only JPQL/HQL** — Hibernate respects
  `hibernate.default_schema` for those, and you do not need this fix.
- You are not on Postgres. This is a Postgres-specific feature.
- You can run identical schemas in dev and prod (e.g. `public` in both).
  Prefer that — no fix needed.

## The pattern

Add `?currentSchema=<schema>` to the **JDBC URL** of the affected
datasource. PostgreSQL's JDBC driver reads `currentSchema` and runs
`SET search_path TO <schema>` on every new connection in the pool, so
unqualified table names resolve in the right schema for every query —
JPQL **and** native SQL.

### `application.yml`

```yaml
spring:
  replica:
    datasource:
      hikari:
        # DB_SCHEMA defaults to "replica" for local dev; production
        # sets DB_SCHEMA=public via env var.
        jdbc-url: jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME:app}?currentSchema=${DB_SCHEMA:replica}
        username: ${DB_USER:app}
        password: ${DB_PASSWORD:app}
        maximum-pool-size: ${REPLICA_HIKARI_MAX_POOL_SIZE:10}
```

### Local seed (creates the replica-shaped schema in dev)

```sql
-- infra/local-init/02-create-replica-tables.sql
CREATE SCHEMA IF NOT EXISTS replica;

CREATE TABLE IF NOT EXISTS replica."Companies" (
    "id"          UUID PRIMARY KEY,
    "name"        TEXT,
    "deletedAt"   TIMESTAMPTZ,
    "preProd"     BOOLEAN DEFAULT FALSE,
    "isMerged"    BOOLEAN DEFAULT FALSE,
    -- ...
);
```

In production, the upstream replica already has `public."Companies"`,
and the service is configured with `DB_SCHEMA=public`.

### `ReplicaDataSourceConfig`

```java
@Configuration(proxyBeanMethods = false)
@EnableJpaRepositories(
    basePackages = { "com.example.dashboard.customersuccess",
                     "com.example.dashboard.sales",
                     "com.example.dashboard.finance",
                     "com.example.dashboard.product",
                     "com.example.dashboard.technical" },
    entityManagerFactoryRef = "replicaEntityManagerFactory",
    transactionManagerRef   = "replicaTransactionManager")
class ReplicaDataSourceConfig {

    @Bean
    @ConfigurationProperties("spring.replica.datasource.hikari")
    DataSource replicaDataSource() {
        return new HikariDataSource();
    }
    // EMF + tx manager beans omitted for brevity
}
```

The `@ConfigurationProperties` binding picks up the JDBC URL with
`currentSchema` directly; no further wiring is required.

## Common gotchas / variants

- **`hibernate.default_schema` does NOT work for native queries.** It
  qualifies JPQL/HQL only. Native `@Query(nativeQuery = true, value = ...)`
  bypasses Hibernate's schema rewriting and goes straight to the JDBC
  driver, which uses the connection's `search_path`. This is the
  trap that motivates the rule.
- **`HikariCP.connectionInitSql: SET search_path TO replica` works**,
  but binds awkwardly with `@ConfigurationProperties` — the SQL string
  has to survive YAML escaping and HikariCP's binding. Just use
  `?currentSchema=` in the JDBC URL.
- **Quote camelCase identifiers.** Postgres folds unquoted identifiers
  to lowercase, so `Companies` and `companies` are different tables.
  Upstream replicas authored from a Sequelize/JS app commonly use
  camelCase; you must quote them: `"Companies"`, `"deletedAt"`.
- **`search_path` is per-connection.** A pool that recycles connections
  across requests is fine — every connection inherits the URL's
  `currentSchema`. Don't be tempted to `SET search_path` from app code
  per request; that is a footgun if the connection is reused.
- **Two datasources, two URLs.** The primary datasource (where Flyway
  manages your own schema) does NOT need `currentSchema`. Only the
  replica does.
- **In test code,** `@DynamicPropertySource` sets the same env var so
  Testcontainers seed scripts can create the `replica` schema and the
  app reads from it.

## Verification

1. Boot the service locally with the replica datasource pointed at the
   Compose Postgres. Hit any endpoint that runs a native query against
   the replica.
2. Inspect the running connection: `psql ... -c "SHOW search_path;"`
   Expected: `replica, "$user", public`.
3. Repository test (Testcontainers + seed migration):

```java
@Tag("integration")
class ReplicaSchemaIT extends AbstractIntegrationTests {

    @Autowired CustomerSuccessQueryRepository repo;

    @Test
    void native_query_resolves_companies_in_replica_schema() {
        var rows = repo.findAtRiskAutoRenewDisabled();
        assertThat(rows).isNotNull();   // would throw if "Companies"
                                         // could not be resolved
    }
}
```

4. Production: `DB_SCHEMA=public` is set via ECS task env vars; the
   same query runs against `public."Companies"` on the upstream replica
   without code changes.

## Node.js / TypeScript equivalent

### Sequelize: `dialectOptions.options`

```typescript
import { Sequelize } from 'sequelize';

const sequelize = new Sequelize(process.env.DATABASE_URL!, {
  dialect: 'postgres',
  dialectOptions: {
    options: '-c search_path=replica',   // equivalent of ?currentSchema=replica
  },
});
```

Or via the URL directly:
```
postgres://user:pass@host:5432/db?options=-c%20search_path%3Dreplica
```

### Raw `pg`

```typescript
import { Client } from 'pg';

const client = new Client({
  connectionString: process.env.DATABASE_URL,
  options: '-c search_path=replica',
});
```

### Don't use per-query `SET search_path`

`SET search_path` is sticky to whichever pooled connection executed it; subsequent queries on different connections see the wrong path. Set it at pool config level so every connection starts correctly.

### Multi-replica routing

```typescript
const sequelize = new Sequelize('mydb', 'user', 'pass', {
  dialect: 'postgres',
  replication: {
    read: [
      { host: 'replica-1.internal', dialectOptions: { options: '-c search_path=replica' } },
    ],
    write: { host: 'primary.internal' },   // primary uses default public schema
  },
});
```

### Differences from Java

- `dialectOptions.options` is the connection-string equivalent of JDBC `?currentSchema=`.
- Raw queries via `sequelize.query()` honor the search path (same as JDBC).
- No `default_schema` analogue that ignores search_path — only one mechanism.

### When NOT to use the Node variant

- Postgres-only — MySQL/Oracle have completely different mechanisms.

## References

- PostgreSQL JDBC driver:
  https://jdbc.postgresql.org/documentation/use/#connection-parameters
  (`currentSchema` parameter).
