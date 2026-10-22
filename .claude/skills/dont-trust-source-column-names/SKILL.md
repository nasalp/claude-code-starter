---
name: dont-trust-source-column-names
description: Validate every column you query against actual prod data before shipping; column names lie (preProd means "migrated to v2", replyTime is always NULL, lastSynced is always NULL).
origin: ECC
triggers: native query review, prod data validation, column always NULL, preProd filter, replyTime, lastSynced, lastChecked, COALESCE preProd false, deletedAt IS NULL, isMerged, schema vs reality
paths:
  - "**/*.sql"
  - "**/*.java"
  - "**/*.kt"
  - "**/*.py"
---
# Don't Trust Source Column Names

## When to use

You are writing or reviewing a native SQL query that pulls from an
upstream / read-replica database whose schema was authored by a
different team for a different product. The column names look
self-explanatory (preProd, replyTime, lastSynced, isTest), so you write
the natural filter and ship.

In practice these names lie. The schema documents intent at the time of
column creation, not what the column means today, not whether anyone
populates it, and not whether the boolean's value is the inverse of
what you would guess.

## When NOT to use

- The schema you query is owned by your team, with current docs you
  trust. Read those docs.
- The query is against ephemeral test data only (CI seed). The trap is
  about prod data; CI fixtures usually match the column name's literal
  meaning.
- The column has a domain test (SELECT count(*) FROM x WHERE col IS NOT
  NULL) that already passed against prod. Trust the test.

## The pattern

Three concrete examples from the example dashboard, all
discovered after queries shipped that returned wrong numbers in prod.

### 1. Companies."preProd" does NOT mean "test account"

It means "company has been migrated to the v2 platform". The v1
dashboard returns `Company is migrated to v2` when preProd is true —
i.e. v1 filters preProd=true OUT because those companies are no longer
on v1. The v2 dashboard wants ALL real companies regardless
of migration status.

In current prod, 471 of 479 active companies have preProd = true.
A filter of `COALESCE(c."preProd", false) = false` excludes 98% of real
data:

```sql
-- WRONG — filters out 471 of 479 real companies
SELECT * FROM "Companies" c
WHERE c."deletedAt" IS NULL
  AND COALESCE(c."preProd", false) = false;

-- RIGHT — preProd is irrelevant for v2 reporting
SELECT * FROM "Companies" c
WHERE c."deletedAt" IS NULL;
```

### 2. Reviews."replyTime" is always NULL in prod

Out of 1,217,271 replied reviews (reviewReplyType NOT IN ('notReplied',
'notSpecified')), zero have a non-NULL replyTime. The column exists;
nothing writes it.

```sql
-- WRONG — silently returns 0 because replyTime is never set
SELECT count(*) FROM "Reviews"
WHERE "replyTime" IS NOT NULL
  AND "replyTime" > now() - INTERVAL '90 days';

-- RIGHT — use updatedAt as the reply timestamp proxy
SELECT count(*) FROM "Reviews"
WHERE "reviewReplyType" NOT IN ('notReplied', 'notSpecified')
  AND "updatedAt" > now() - INTERVAL '90 days';
```

Replied reviews have updatedAt populated when the reply is saved,
because the reply triggers an update. Not perfect (any update bumps
it) but the only useful column.

### 3. Locations."lastSynced" is always NULL in prod

All 2,002 non-deleted locations have lastSynced IS NULL. Use
LocationListing."lastChecked" instead:

```sql
-- WRONG — every location looks stale, returns 462 false positives
SELECT count(*) FROM "Locations" l
WHERE l."deletedAt" IS NULL
  AND (l."lastSynced" IS NULL
       OR l."lastSynced" < now() - INTERVAL '30 days');

-- RIGHT — LocationListing.lastChecked IS populated
-- (range observed in prod: 2023-09-27 to 2025-08-01)
SELECT count(*) FROM "Locations" l
JOIN "LocationListing" ll ON ll."locationId" = l."id"
WHERE l."deletedAt" IS NULL
  AND (ll."lastChecked" IS NULL
       OR ll."lastChecked" < now() - INTERVAL '30 days');
```

## Common gotchas / variants

- A column existing in the schema does not mean it has data. Run
  `SELECT count(*) FROM <table> WHERE <column> IS NOT NULL` against
  the prod dump before relying on the column.
- Filter semantics depend on which side of a migration the system is
  on. preProd=true means "migrated" because the column was added by
  a v1-era developer who treated v2 as "pre-production" from v1's
  perspective. Always check the source codebase that writes the
  column, not the one that reads it.
- deletedAt IS NULL is non-negotiable. Soft-deleted rows are invisible
  to the application UI but very visible to your COUNT(*). Every CTE
  on "Companies" includes it.
- Watch out for NULL-poisoned LEAST / GREATEST. LEAST(NULL, x, y)
  returns NULL in some SQL dialects, dropping the row from a median.
  Wrap each argument in COALESCE(arg, sentinel) if NULL is expected.
- Inconsistent enum values across queries. P4 uses status='done',
  P2/P5/P6 use status IN ('done','repeate') — same business concept,
  different filters, different numbers. Standardize at the team level
  or risk silent disagreement between metrics.
- No recency floor on text-search queries. A query for "unanswered
  reviews" without a since clause reaches back to 2006 in old data.

## Verification

Three checks, all run against the prod dump or an actual replica
snapshot:

1. Column population check: for every column the query depends on,
   run `SELECT count(*) FILTER (WHERE col IS NOT NULL) AS populated,
   count(*) AS total FROM <table>`. If populated < 1%, the column is
   functionally missing.
2. Enum / boolean distribution check: `SELECT col, count(*) FROM
   <table> GROUP BY col`. The result tells you whether your filter
   matches a sane fraction of rows.
3. Spot-check magnitude: if your query returns 0 or "all companies",
   that is almost always a column-meaning bug. Compare the query
   result with the obvious naive count
   (`SELECT count(*) FROM Companies WHERE deletedAt IS NULL`). They
   should be in the same order of magnitude unless the filter is
   genuinely narrow.

A repository-level test:

```java
@Tag("integration")
class CustomerSuccessQueryRepositoryProdShapeIT extends AbstractIntegrationTests {

    @Test
    void at_risk_query_does_not_silently_exclude_98_percent_of_companies() {
        var atRisk = repo.findAtRiskAutoRenewDisabled();
        var total  = repo.countActiveCompanies();
        assertThat(atRisk.size())
            .as("at-risk count must be a sane fraction of active companies")
            .isLessThan((int) (total * 0.5))
            .isGreaterThan(0);
    }
}
```
