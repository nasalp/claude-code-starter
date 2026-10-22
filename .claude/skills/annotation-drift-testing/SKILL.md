---
name: annotation-drift-testing
description: Build-time drift tests for annotations that mirror external state. When a custom annotation (like @MetricDoc, @ApiContract, @TableMapping) claims to describe a SQL table, an OpenAPI shape, a metric...
origin: ECC
triggers: @MetricDoc, @ApiContract, @TableMapping, annotation drift test, build-time drift detection, scanAnnotations, pg_tables, OpenAPI annotation drift, Sets.difference, drift assertion, annotation source of truth, scanAnnotations test
paths:
  - "**/*.java"
---
# Annotation Drift Testing

Annotations are convenient places to hang documentation: `@MetricDoc(sources = "orders")`, `@ApiResponseExample(json = "...")`, `@TableMapping("user_account")`. The convenience is a trap — the annotation value lives next to the code that interprets it, but it's a string. Strings drift.

This skill describes how to ship a build-time test that catches the drift before it ships.

## When to use

- A custom annotation declares a fact about external state (table name, metric source, SQL interval, OpenAPI example, cache key).
- The annotation value would be wrong/misleading if the underlying state changed.
- You want the build to fail when they diverge, not silently lie at runtime.

## When NOT to use

- The annotation value is purely descriptive (e.g., `@author "Alice"`).
- The annotation already validates at compile time (e.g., a `Class<?>` reference).
- The "source of truth" is the annotation itself (then there's nothing to drift against).

## The core pattern

```java
class MetricDocDriftTests {

    @Test
    void all_documented_sources_match_actual_sql_tables() {
        // 1. Find every annotation site
        var documented = scanAnnotations(MetricDoc.class)
            .map(MetricDoc::sources)
            .flatMap(Arrays::stream)
            .collect(toSet());

        // 2. Read the source of truth
        var actualTables = jdbcTemplate.queryForList(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
            String.class).stream().collect(toSet());

        // 3. Diff and fail with a useful message
        var missing = Sets.difference(documented, actualTables);
        var orphan  = Sets.difference(actualTables, documented);

        assertThat(missing)
            .as("@MetricDoc.sources references tables that don't exist")
            .isEmpty();
        assertThat(orphan)
            .as("Tables exist with no @MetricDoc — either document or exclude")
            .isEmpty();
    }
}
```

## Variants

### Time-interval drift

`@MetricDoc(description = "rolling 90-day window")` paired with SQL `INTERVAL '90 days'`. Parse the description, parse the SQL, fail if they disagree.

### OpenAPI example drift

`@ApiResponseExample(json = "...")` should round-trip through the response DTO without errors. Test deserializes the example and re-serializes it, asserting equality.

### Cache key drift

`@CacheEvict(key = "#user.id")` should reference a method parameter that exists. Test scans `@Cacheable`/`@CacheEvict` SpEL expressions and binds them against the method signature.

### Feature-flag drift

`@FeatureFlag("experimental_x")` should match a key declared in the flag-store config. Test loads both, compares.

## Implementation notes

- **Run in the unit test phase, not integration.** Mutation testing reruns these; they must be fast.
- **Use `ClassPath.from(loader).getAllClasses()` (Guava) or Reflections** to scan. Don't hand-roll classpath walking.
- **Fail with both sets visible.** "missing X, orphan Y" beats "drift detected" because it tells the engineer exactly what to fix.
- **Don't snapshot — diff.** A snapshot test ("the documented set equals this checked-in file") just moves the drift problem; the file itself can drift.

## Generalization beyond Spring

The pattern applies anywhere an annotation captures non-self-validating state:

- TypeScript decorators referencing API endpoints
- Python decorators referencing database columns
- Go struct tags referencing JSON shapes
- Any IDL-generated code where the annotation is the IDL projection

The build-time drift test is the universal escape from "the annotation is wrong now and nobody noticed."

## Why this matters

The cost of a wrong annotation is paid at runtime — usually as silent zero-result queries, missing metric panels, or 500s when an example doesn't match the schema. The cost of catching it at build time is one unit test. The asymmetry is huge.
