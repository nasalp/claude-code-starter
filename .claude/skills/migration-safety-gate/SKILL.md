---
name: migration-safety-gate
description: PR-time gate that blocks backward-incompatible Sequelize/SQL migrations (dropColumn, renameColumn, NOT NULL tightening, raw DROP/RENAME) with auditable BACKWARD-INCOMPATIBLE override comments
origin: ECC
triggers: queryInterface.removeColumn, queryInterface.dropColumn, queryInterface.renameColumn, queryInterface.dropTable, queryInterface.changeColumn, allowNull false, ALTER TABLE DROP COLUMN, RENAME COLUMN, SET NOT NULL, BACKWARD-INCOMPATIBLE, check-migration-safety, sequelize migration
paths:
  - "**/migrations/**"
  - "**/*.sql"
---
# Migration Safety Gate

A rolling deploy with auto-rollback has one hard rule: the new migration must run safely against BOTH the new code (after deploy) AND the old code (after rollback). Drop a column, rename a column, or tighten a NOT NULL and the old code will crash on the first INSERT or SELECT. This skill is the PR-time gate that blocks those patterns at the source-control level, with an auditable override for the rare case where the team has a coordinated 2-step plan.

## When to use

- Any change to `**/migrations/*.js`, `**/src/migrations/*.js`, or `**/migrations/*.sql` in a service that uses rolling deploys.
- A new migration that delegates to `.sql` files via `fs.readFileSync(...)` — those are scanned too.
- Reviewing a Sequelize migration where the diff includes `removeColumn`, `dropColumn`, `renameColumn`, `dropTable`, `renameTable`, or `changeColumn`.

## When NOT to use

- Greenfield databases where there is no old code in rotation. The check is still safe to run; it just won't fire.
- Single-instance deploys with full downtime windows. The risk is gone; convention preserves a paper trail.

## The pattern

`scripts/check-migration-safety.js` scans changed migration files for nine pattern classes. Each is a BLOCKER unless the file carries an auditable override comment.

### Detected patterns

| Pattern | What it matches | Why it's a blocker |
|---------|-----------------|--------------------|
| `dropColumn` | `queryInterface.removeColumn(` or `dropColumn(` | Old code reading the column crashes after rollback. Use a 2-step migration: stop writing in deploy 1, drop in deploy 2. |
| `dropTable` | `queryInterface.dropTable(` or raw `DROP TABLE` | Old code querying the table crashes. Same 2-step strategy. |
| `renameColumn` | `queryInterface.renameColumn(` or `ALTER TABLE ... RENAME COLUMN` | Old code uses old name. Add new column, dual-write, drop old later. |
| `renameTable` | `queryInterface.renameTable(` | Same as renameColumn at table grain. |
| `changeColumn-notnull` | `changeColumn(...)` followed within ~400 chars by `allowNull: false` | Old code INSERTs that omit the column will fail. Two migrations: nullable add + backfill, then NOT NULL after old code is out of rotation. |
| `raw-drop-column` | `ALTER TABLE ... DROP COLUMN` (multiline) | Same hazard as the queryInterface form. |
| `raw-set-not-null` | `ALTER TABLE ... ALTER COLUMN ... SET NOT NULL` | Same hazard as `changeColumn` + `allowNull:false`. |

The regex uses the multiline-friendly `[\s\S]{0,500}?` to catch template literals and `${}`-interpolated SQL strings; raw flags use case-insensitive matching.

### Override comment

The override is a JS comment containing a ticket reference on the same line:

```javascript
// BACKWARD-INCOMPATIBLE: PROJ-1234 stop-writing already shipped in v2.18; safe to drop
```

The regex is anchored to comment prefixes (`//` or `/* */`) and requires a non-empty token after the marker, so it cannot be smuggled inside a string literal or matched by a bare keyword in user data:

```javascript
const OVERRIDE_MARKER = /(?:^|[^\S\n])\/\/\s*BACKWARD-INCOMPATIBLE:[ \t]+(\S+)|\/\*\s*BACKWARD-INCOMPATIBLE:[ \t]+(\S+)/m;
```

When an override is present, the script logs `OVERRIDE (<ticket>): <file>` and continues without failing the build — but every overridden violation is printed so reviewers can see what was waived.

### up()-only scanning

The scanner extracts the `up()` body and only scans that. The `down()` method legitimately performs drops/renames to undo the up — scanning it produces false positives. The boundary detector matches `down: ...`, `async down(...)`, `down(...)`, or `exports.down = ...` while specifically not matching identifiers that merely contain "down" (`download`, `markdown`, `breakdown`).

### Delegated SQL inlining

Migrations that delegate to `.sql` files via `fs.readFileSync(path.resolve(__dirname, ...))` cannot bypass the check. The script extracts the path string segments, resolves the file, and concatenates the SQL contents into the scan target. A migration that hides `DROP TABLE` in `sql/migrations/foo.sql` is caught the same way.

### Invocation modes

```bash
# Single file or set of files
node scripts/check-migration-safety.js services/dashboard-v2/src/migrations/20260415-x.js

# Diff-against mode for PR CI
node scripts/check-migration-safety.js --changed-against origin/main

# Full repo audit
node scripts/check-migration-safety.js --all services/dashboard-v2/src/migrations
```

The diff-against mode guards against shallow clones: it `git rev-parse --verify`s the base ref first, so `git fetch --depth=50 origin main` is a clear remediation when the ref is unreachable.

Exit codes: 0 = clean (or all overridden), 1 = violations, 2 = invalid args / setup error.

## Common gotchas / variants

- `changeColumn` is allowed when widening a type or adding a default — only `allowNull: false` flips it to BLOCKER. The 400-char heuristic in the regex catches multi-line option objects.
- Raw SQL is checked with the multiline `[\s\S]` matcher. Template literals with embedded `${}` and newlines are caught; concatenation with `+` is not — flag those in code review.
- `--changed-against` returns no files when no migrations changed; the script exits 0 with a `Skipping.` log line, so it is safe to call unconditionally in CI.
- The override comment requires a ticket-like token after the colon. `// BACKWARD-INCOMPATIBLE:` (no value) is rejected.
- A migration that calls `queryInterface.removeColumn` only inside an `if (process.env.FORCE)` branch is still flagged. The regex is syntactic, not control-flow aware. If the branch is intentional, override with the ticket.

## Verification

- Add a fixture migration with `queryInterface.removeColumn(...)` and run `node scripts/check-migration-safety.js fixture.js` — it must exit 1 with the BLOCKER reason text.
- Add `// BACKWARD-INCOMPATIBLE: TEST-1 grace-period elapsed` to the same fixture — it must exit 0 with `OVERRIDE` log.
- A unit test in `module.exports = { scanFile, PATTERNS, OVERRIDE_MARKER }` covers each pattern with positive and negative cases (e.g., `markdown` does not match the `down` boundary detector).
- Wire the script into `.github/workflows/ci.yml` as `node scripts/check-migration-safety.js --changed-against origin/${{ github.base_ref }}`.
