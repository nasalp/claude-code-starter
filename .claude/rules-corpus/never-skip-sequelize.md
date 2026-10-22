# Never Skip Sequelize

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

Service whose data layer uses **Sequelize** → every DB read/write **MUST** go through Sequelize. No parallel data-access paths — no direct `pg.Pool`, `pg.Client`, `mysql2`, `mariadb`, `prisma`, `knex`, `node-postgres`, `pg-promise`, raw `net.Socket` to Postgres port, no shell-out to `psql`, no `child_process.exec('psql …')`. One data-access conduit per service = Sequelize.

Applies to:

- Production code (controllers, services, repositories, schedulers, workers, queue handlers, MCP tools).
- Test code (Testcontainers helpers, fixture seeders, equivalence harnesses, integration tests, golden snapshots).
- One-off scripts, migrations, seeders, admin CLIs, debugging helpers.
- Cross-language bridges where Node process talks to DB.

Sequelize not optional. It is the layer.

## What is required

### 1. Production read paths

Repositories (per `views-via-repository.md`) own all SQL. SQL **executes via** `sequelize.query(sql, { type: QueryTypes.SELECT, replacements })`. Not `pool.query`, not `client.query`, not hand-rolled `new pg.Client()`.

```js
// ✅ Good — repository uses Sequelize
async function findAccountLocations(sequelize, { filters, sort, pagination }) {
  const rows = await sequelize.query(
    `SELECT * FROM admin_v_account_location WHERE ... LIMIT :limit OFFSET :offset`,
    { type: QueryTypes.SELECT, replacements: { ...replacements } }
  );
  return rows.map(toCamelCase);
}

// ❌ Forbidden — parallel pg pool
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
async function findAccountLocations() {
  const { rows } = await pool.query('SELECT * FROM admin_v_account_location ...');
  return rows;
}
```

### 2. Production write paths

Writes via model (`Models.Location.create(...)`, `Models.Location.update(...)`) or, when raw SQL genuinely necessary (set-based update, complex CTE), via `sequelize.query(sql, { type: QueryTypes.UPDATE })`. Same connection pool, same transaction context, same hooks.

### 3. Test bootstrap

Testcontainers tests:

- Construct **one** Sequelize instance per process. Only DB handle test owns.
- Apply schema bootstrap (`pg_dump` baseline, migrations, or hand-curated DDL) via `sequelize.query(baselineSql)`. Not `new pg.Client().query(baselineSql)`, not `execSync('psql ...')`.
- Apply view DDL via `sequelize.query(viewSql)`.
- Seed fixtures via `sequelize.query(insertSql)` or `Model.create(...)`.
- Query legacy controller path AND repository path through same Sequelize instance.

### 4. Module mutation, when needed

Production `dbConfig.js` doesn't expose env-var hook test needs (e.g. no `port` on `test` profile) → patch loaded `dbConfig` exports at runtime BEFORE model singleton loads:

```js
const dbConfig = require('../../src/config/dbConfig');
dbConfig.test = { ...dbConfig.test, port: containerPort, /* etc */ };
// THEN require the model singleton — it reads from the patched dbConfig.
const models = require('../../src/models');
```

Test-only module mutation. Does NOT require parallel `pg` connection.

### 5. Schema bootstrap from baseline

Tests needing production-shaped schema → apply canonical `pg_dump --schema-only` baseline (e.g. `services/dashboard-v2/schema/baseline.sql`) via `sequelize.query(...)`. Don't replay 379 individual sequelize-cli migrations — transactional/enum-cache complications fail in isolation. Don't hand-curate parallel SQL schema unless production dump genuinely unavailable.

## What is forbidden

- `require('pg')` in production or test code, except inside Sequelize internals.
- `new Pool(...)`, `new Client(...)`, `new pg.Pool(...)`, `new pg.Client(...)`.
- `mysql2`, `mariadb`, `prisma`, `knex`, `mongoose` (SQL data path) — any second ORM/driver parallel with Sequelize on same DB.
- `execSync('psql ...')`, `child_process.exec('psql ...')`, `spawn('psql', ...)` for schema bootstrap, seeding, or queries.
- Tests building own `pg` pool to side-channel data into DB Sequelize-backed app reads.
- Tests bootstrapping schema with `node-postgres` then handing different Sequelize instance to SUT.
- Adding `pg` or `pg-promise` as direct dependency unless package.json already lists as Sequelize peer.

## What is allowed

- `pg` in `node_modules` as Sequelize transitive dependency. (Sequelize uses `pg` under hood for Postgres.)
- `sequelize.connectionManager.getConnection()` for advanced scenarios (listen/notify, explicit `SET`, session-scoped state). Connection borrowed from Sequelize pool, then released.
- `mongoose` for genuinely Mongo-backed entities (SQL via Sequelize, listing content via Mongo). Rule per-store: Sequelize = law for SQL store; Mongoose = law for Mongo store. Never raw `mongodb` driver alongside Mongoose for same collection set.
- `psql` in CI scripts OUTSIDE application process (e.g. CI prelude creating test DB before Node starts). Forbidden = shell-out from inside running app or tests.
- Direct `pg` in legacy code pre-dating rule. Mark `// TODO: remove in favor of sequelize.query` + ticket; don't silently spread anti-pattern.

## Enforcement

1. **CI gate**: `grep -rE --exclude-dir=node_modules "(require\(|from\s+|import\s+)['\"\`](pg|pg-promise)['\"\`]|new\s+(pg\.)?(Pool|Client)" services/<name>/src services/<name>/tests` MUST return zero hits (allowing Sequelize's own use). Wire in `pr-diff.yml` (or per-project equivalent).

2. **Adversarial review**: PR introducing `pg.Pool` or non-Sequelize ORM/driver = REJECT. Author must demonstrate why Sequelize can't satisfy requirement.

3. **Hooks**: PostToolUse Edit/Write on `src/` or `tests/` may emit `[WARNING] non-Sequelize DB driver detected`.

> Rationale (Why/Cross-refs/Calibration): `docs/rule-rationale/never-skip-sequelize.md`
