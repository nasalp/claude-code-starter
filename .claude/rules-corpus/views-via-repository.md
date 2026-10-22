# DB Views via Repository, Tested w/ Testcontainers

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

Any DB VIEW (or read-side projection in SQL) MUST be reached through **repository module**. Controllers, handlers, route adapters, GraphQL resolvers, service-layer code **MUST NOT** contain raw SQL — no `sequelize.query`, no `pool.query`, no `QueryTypes.SELECT`, no `sequelize.literal`, no `EntityManager.createNativeQuery`, no `jdbcTemplate.queryForList(...)` inlined into request-handling code.

Repository owns SQL. Repository tests use **Testcontainers** — real Postgres (or MySQL, or project DB) container per test suite — to prove SQL returns what calling layer expects. Repository tests prove equivalence with legacy code path when view replaces ORM-driven joins.

## What is required

### 1. Layer separation

```
HTTP layer (controllers, handlers)
        ↓
Service layer (optional — business orchestration)
        ↓
Repository layer  ← owns ALL SQL, owns parameter parsing for filter/sort/pagination
        ↓
Database (views + tables)
```

Repository module co-located by bounded context, not ORM model. For `admin_v_account_location` view: `src/repositories/admin/accountLocationRepository.js` (or equivalent), not `src/models/Location.js`.

### 2. Repository interface

Each repository exports plain async functions (or class w/ instance methods if project idiom prefers classes). Each function takes:

- Connection / `sequelize` / `EntityManager` handle (tests inject Testcontainers-backed one)
- Plain-object input: filters, sort, pagination, etc.

Each function returns plain object or array of plain objects in EXACT shape caller expects to emit. Repository performs snake_case → camelCase projection (or whatever shape contract caller has).

```js
// ✅ Good
async function findAccountLocations(sequelize, { filters, sort, pagination }) {
  const sortColumn = whitelistSort(sort.by);            // throws on unknown column
  const sortDirection = sort.dir === 'ASC' ? 'ASC' : 'DESC';
  const { whereSql, replacements } = buildWhere(filters);

  const rows = await sequelize.query(
    `SELECT * FROM admin_v_account_location
     ${whereSql}
     ORDER BY ${sortColumn} ${sortDirection}
     LIMIT :limit OFFSET :offset`,
    {
      type: QueryTypes.SELECT,
      replacements: { ...replacements, limit: pagination.limit, offset: pagination.offset },
    }
  );

  const [{ count }] = await sequelize.query(
    `SELECT COUNT(*)::integer AS count FROM admin_v_account_location ${whereSql}`,
    { type: QueryTypes.SELECT, replacements }
  );

  return { rows: rows.map(toCamelCase), count };
}
```

```js
// ❌ Forbidden
exports.accountManagements = async (req, res) => {
  const rows = await sequelize.query(
    'SELECT * FROM admin_v_account_location WHERE industry = :industry',
    { type: QueryTypes.SELECT, replacements: { industry: req.query.industry } }
  );
  return res.json({ data: rows });
};
```

### 3. Sort and filter whitelisting

Repository MUST whitelist sort columns + filter keys. Never interpolate `req.query.sortBy` directly into SQL string — injection vector even w/ column-quoting. Whitelist lives in repository module, exported as constant if controller needs introspection.

### 4. Tests use Testcontainers

Per repository function, Testcontainers-backed test that:

1. Starts real Postgres (or MySQL / etc.) container per test file via `testcontainers` + `@testcontainers/postgresql` (or equivalent).
2. Applies real production migrations against container DB (e.g., `umzug` for sequelize-cli, Flyway for Java, etc.).
3. Applies view DDL.
4. Seeds canonical fixture via raw `INSERT` (NOT via ORM — fixtures may need values ORM validator would reject, e.g. legacy enum typos).
5. Calls repository function.
6. Asserts return value (shape, row count, field equality).

When repository REPLACES legacy ORM include-chain, test additionally:

7. Stands up minimal Express/Spring/whatever app mounting legacy controller route.
8. Hits route via supertest (or equivalent HTTP client).
9. Asserts `deepStrictEqual(legacy.body.data, repository_result)` — equivalence proof.

### 5. No mocks of the database

Repository tests do NOT mock Sequelize, connection, or query method. Repository abstraction = SQL real + DB real. Test mocking `sequelize.query` tests mock, not SQL.

Mocking repository itself in controller tests fine — that's why layer exists. Repository OWN tests = integration tests against Testcontainers.

### 6. One repository per bounded context, one view per bounded context

Rule pairs w/ "1 bounded context = 1 view" principle. 6 superadmin bounded contexts → 6 views → 6 repository modules. Each repository has tests. Mapping 1:1:1 (context : view : repository).

Repository MAY call multiple views if bounded context read shape genuinely composes from multiple grains (rare — usually BC mis-split). Document composition in repository header comment.

## What is forbidden

- `sequelize.query(...)` anywhere outside `src/repositories/`.
- `sequelize.literal(...)`, `sequelize.fn('DISTINCT', ...)`, hand-built `Op.and`/`Op.or` trees mirroring SQL — all in repository.
- Raw SQL strings in controllers, services, route adapters, or middleware.
- Tests using shared dev DB or docker-compose started outside test process. Tests MUST own container lifecycle via Testcontainers — isolated + parallel-safe.
- Tests mocking DB connection or stubbing `sequelize.query`. Repository abstraction makes those mocks unnecessary — using them defeats point.
- "I'll add repository later" framing in PR introducing view. Repository = SAME PR as view DDL.

## Migration playbook (legacy ORM → view + repository)

Order. Each step independently committable.

1. Write view DDL (`sql/<context>_v_<name>.sql`). Commit. View unused.
2. Write indices migration. Commit. Indices unused.
3. Write repository module + Testcontainers test. Test asserts repository returns same row set legacy ORM include-chain returns (Testcontainers DB, run migrations, apply view DDL, seed fixture, hit legacy controller via supertest, call repo directly, deep-equal). Commit. Repository unused by production path; tests prove it works.
4. Refactor controller(s) to call repository instead of Sequelize include block. Repository function name + return shape matches controller needs; controller diff mechanical (delete includes, add `await repo.findX(...)`). Step 3 tests still pass — now testing controller, not repository alone. Commit.
5. Remove dead code (orphaned model associations only used by deleted include block, unused imports). Commit.

Each commit independently revertible. Risky step = 4. Reverting leaves view + repository in place, unused, ready for retry.

## Enforcement

1. **Pre-commit / CI gate** — `grep -rE --exclude-dir=repositories "sequelize\.(query|literal)|pool\.query|QueryTypes\.SELECT|createNativeQuery|queryForList" services/<x>/src` (or equivalent path) MUST return zero hits. CI step in `pr-diff.yml` (or per-project equivalent) fails build if match outside `src/repositories/`.

2. **ArchUnit / dependency-rule equivalent** for typed languages (Java): `noClasses().that().resideInAPackage("..controller..").should().dependOnClassesThat().resideInAPackage("..jdbc..")`.

3. **Code review** — PR introducing new SQL string in controller = REJECT. PR introducing repository test mocking Sequelize = REJECT.

4. **Hooks emit warnings** — `.claude/hooks/` may emit `[WARNING] raw SQL detected in controller path` when edit creates forbidden pattern.

> Rationale (Why/Cross-references/Calibration): `docs/rule-rationale/views-via-repository.md`
