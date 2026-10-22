---
name: bounded-context-sql-views
description: CDC-friendly bounded-context PostgreSQL views — one row per grain via LATERAL LIMIT 1, GREATEST() watermarks across all child tables, safe_int casts, and Sequelize models as the test schema source...
origin: ECC
triggers: postsvsummary, reviewsvdetail, usersvcompanybilling, LEFT JOIN LATERAL, extractionwatermark, safeint, safefloat, CDC view, BigQuery dump, Sequelize globalSetup, testcontainer postgres, materialized view
paths:
  - "**/*.sql"
  - "**/*.java"
  - "**/*.kt"
---
# Bounded-Context PostgreSQL Views

A bounded-context view turns a noisy normalized schema into a CDC-friendly, one-row-per-grain projection that a warehouse (BigQuery, Snowflake, Mimir) can periodically dump. This skill encodes the nine rules adopted after adversarial review caught silent row-explosions, missing watermarks, chimera billing rows, and a single raw integer cast that crashed an entire materialized-view refresh.

## When to use

- You are exposing internal entities to a data warehouse, an ETL job, or a Debezium-style CDC consumer.
- You need a stable per-entity projection that can be cheaply re-extracted on every cron tick.
- You are converging multiple LATERAL joins or modeling a domain where parent/child tables have hasOne/hasMany associations without unique constraints.

## When NOT to use

- Operational reads that need referential integrity guarantees beyond a denormalized snapshot — use the underlying tables.
- Cases where the warehouse already gets the raw tables via Debezium and does its own joins.

## The pattern

### Rule 1 — one view per grain

Every view's grain (what one row represents) must be a single entity. The Posts domain needed two views, not one:

- `posts_v_summary` — 1 row per post (post_id grain).
- `posts_v_location_status` — 1 row per (post × location) (delivery grain).

Merging them produced a 50× row explosion. If a domain has multiple 1:many relationships, split into multiple views.

### Rule 2 — Sequelize is the test schema source of truth

Hand-written `SCHEMA_SQL` blocks in tests drift from production models. The view tests sync all Sequelize models to a testcontainer Postgres in `globalSetup.js`, then create one isolated database per test suite. Quirks to know:

- Sequelize creates `createdAt`/`updatedAt` as NOT NULL with no DEFAULT — raw SQL inserts need `ALTER COLUMN SET DEFAULT NOW()`.
- All NOT NULL constraints are dropped for testing because views don't enforce constraints anyway.
- Some models fail sync with a USING clause error; catch and ignore — the rest sync cleanly.
- View tests need their own Jest config (`jest.config.views.js`) with a `globalSetup`. Exclude them from the main config: `testPathIgnorePatterns: ['tests/sql/']`.

### Rule 3 — `LEFT JOIN LATERAL ... LIMIT 1` against any FK without UNIQUE

Tables with hasOne or hasMany associations without a unique constraint on the FK silently duplicate rows on a plain `LEFT JOIN`. Use a LATERAL with deterministic ordering and a LIMIT:

```sql
LEFT JOIN LATERAL (
    SELECT pt2.name, pt2."updatedAt"
    FROM "PostTypes" pt2
    WHERE pt2."postId" = p.id AND pt2."deletedAt" IS NULL
    ORDER BY pt2.id DESC LIMIT 1
) pt ON true
```

This is also how aggregates are added without exploding the parent grain.

### Rule 4 — `extraction_watermark` over ALL child tables

CDC consumers extract only rows where `extraction_watermark > last_seen`. The watermark must include `MAX(updatedAt)` from every table that contributes data — including child tables visited only via aggregates:

```sql
GREATEST(
    COALESCE(p."updatedAt", p."createdAt"),
    COALESCE(pt."updatedAt", p."createdAt"),
    COALESCE(ep."updatedAt", p."createdAt"),
    COALESCE(op."updatedAt", p."createdAt"),
    (SELECT MAX(pp2."updatedAt") FROM "PostPictures" pp2 WHERE pp2."postId" = p.id),
    (SELECT MAX(pl2."updatedAt") FROM "PostLocations" pl2 WHERE pl2."postId" = p.id)
) AS extraction_watermark
```

A watermark missing a contributing table means changes there are invisible to consumers — bug class: silent CDC stall.

### Rule 5 — join on the FK, not the parent entity

Joining `StripeSubscriptions` by `companyId` alone produces chimera rows where a payment plan from one subscription pairs with Stripe data from another. Always join on the explicit FK reference:

```sql
LEFT JOIN "StripeSubscriptions" s
    ON s."subscriptionId" = cpp."stripeSubscriptionId"
```

### Rule 6 — billing-era discriminator for legacy + modern

`users_v_company_billing` initially only joined `CompanyPaymentPlans` + `StripeSubscriptions`, missing 235+ paying companies still on legacy `LocationSubscriptions`. The fix was a third LATERAL with a `billing_path` discriminator and a unified `is_paying` boolean. Whenever multiple billing/auth/legacy eras coexist, a discriminator column belongs in the view.

### Rule 7 — `safe_int()` / `safe_float()`, never raw casts

Raw `::integer` casts in views crash entire `REFRESH MATERIALIZED VIEW` runs when source data is non-numeric. `reporting_v_google_insights` was the one outlier and broke a refresh until every cast was wrapped in `safe_int()` from `00_functions.sql`. Treat raw casts as a build-break-on-merge violation.

### Rule 8 — config view AND activity view per feature

Every feature that emits user-visible events needs both: a config view (what the user set up) and an activity view (what actually happened). `reporting_v_schedule` had only 21 schedule configs; the actual `ReportScheduleRecords` and `*Exports` activity tables had no view, so feature usage was unmeasurable.

### Rule 9 — denote what's NOT in Postgres

Listing content lives in MongoDB; only sync metadata is in Postgres. The view's docstring must say so explicitly so a warehouse author doesn't assume coverage. The cross-store join happens in BigQuery on `locationId`.

## Common gotchas / variants

- `'repeate'` is a known typo in the `Posts.status` ENUM — normalize it in a `CASE` to `'repeating'` rather than fixing the ENUM (a backward-incompatible migration).
- `COALESCE(p."updatedAt", p."createdAt")` keeps the watermark monotonic for rows that haven't been updated yet.
- `GREATEST` over NULLs returns NULL — coalesce every term.
- Soft deletes: include `deletedAt` in the projection (CDC consumer decides) and filter `WHERE x."deletedAt" IS NULL` inside LATERAL subqueries when joining child tables.
- Use double-quoted identifiers (`"Posts"`, `"updatedAt"`) — the codebase uses Sequelize's PascalCase casing.

## Verification

- `psql -c "SELECT COUNT(*) FROM posts_v_summary; SELECT COUNT(*) FROM \"Posts\" WHERE \"deletedAt\" IS NULL;"` — counts must match.
- Touch a child table's `updatedAt`, then `SELECT MAX(extraction_watermark) FROM posts_v_summary` — must move forward.
- `EXPLAIN (ANALYZE, BUFFERS)` for a representative WHERE clause — confirm LATERAL nodes don't degenerate to nested-loop on the parent.
- `services/dashboard-v2/tests/sql/posts_v_summary.test.js` (testcontainer) — assert one row per post even when the underlying tables have multiple PostTypes / PostPictures / PostLocations rows.
