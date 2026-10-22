# Rationale — Never Skip Sequelize

## Why

1. **Connection pool integrity.** Sequelize maintains a pool sized to the service's expected load. Introducing a parallel `pg.Pool` doubles the pool budget, hides connections from Sequelize's health checks, and silently exhausts the DB's `max_connections` under stress.

2. **Transaction boundaries.** A Sequelize transaction (`sequelize.transaction()`) is a coordinated `BEGIN`/`COMMIT` over Sequelize's connection. A raw `pg` query in the middle of the same logical work runs on a different connection — it sees a different snapshot, can deadlock against the Sequelize transaction, and produces correctness bugs that look like flakes.

3. **Observability.** Sequelize's hooks (`beforeQuery`, `afterQuery`), logging, and timing instrumentation cover everything that flows through it. A parallel `pg` path is invisible to dashboards, slow-query logs, and the test-time SQL-count assertions that prove N+1 fixes.

4. **Type and validator coverage.** Sequelize's model definitions enforce column shapes, soft-delete semantics (`paranoid: true`), and lifecycle hooks. A parallel `pg` insert that bypasses the model writes rows that the model would reject — corrupting invariants the rest of the code assumes.

5. **Audit and history.** This codebase's `ModelLogs` wrapper (and equivalents in other services) intercepts Sequelize lifecycle events to write `*Histories` rows. A direct `pg` write skips this and breaks the audit trail.

6. **Schema bootstrap consistency.** When tests apply a `pg_dump --schema-only` baseline via Sequelize (`sequelize.query(baselineSql)`), the connection that creates the schema is the same connection pool the tests then query. Side-channelling through `pg` to bootstrap produces a schema on connection X that the Sequelize connection on connection Y might not see (in some pool configurations) until the next round-trip.

## Cross-references

- `.claude/rules/views-via-repository.md` — the partner rule. Repositories own all SQL; this rule says how that SQL executes.
- `.claude/rules/common/testing.md` — test discipline; integration tests use Testcontainers + Sequelize, not parallel `pg`.
- `.claude/rules/legacy-code.md` — when migrating legacy raw-`pg` code, do it in the same PR that adds the repository; never leave both paths live in production at once.

## Calibration

This rule was written 2026-05-21 after a Testcontainers test infrastructure attempt was about to introduce a parallel `pg` connection for "convenience" — bootstrapping schema with raw `pg` while the system under test used Sequelize. The operator's correction was explicit: "Work with sequelize." Both halves matter: stay on Sequelize for production paths AND for test paths. There is one conduit. Cite this rule when reviewing any data-layer code; the conduit is non-negotiable.
