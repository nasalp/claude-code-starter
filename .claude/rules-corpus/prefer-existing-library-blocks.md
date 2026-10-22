# Prefer Existing Library Building Blocks

## Rule

**Before custom code, search for existing library, repo module, or pre-installed wiring that already solves problem.** Exists and works → use it. Do NOT write custom equivalent because spec said slightly different one.

## What is required

### 1. Inventory before implementing

Before new dependency or non-trivial class, inventory in order:

1. **The repo itself.** `find … -name '*Foo*'`, `grep -r '@Bean' src/main/java | grep -i foo`. Wiring already exist? Added by earlier ADR?
2. **Maven Central artifact families relevant to problem.** ShedLock → `shedlock-provider-*`. Spring Modulith → `spring-modulith-*`. Micrometer → `micrometer-*`. List ALL, not just names matching guess.
3. **Sibling repos.** a shared infra repo, a shared Spring Boot library, or a sibling with same concern wiring → copy pattern, don't reinvent.
4. **Library class index.** Open JAR, list public classes (`jar -tvf` or `unzip -l`) — class may exist under different name than spec anticipated.

Only after all four fail → "write custom block" becomes candidate.

### 2. When spec asks for X but X doesn't exist

Spec says "use `PostgresAdvisoryLockJdbcTemplateLockProvider`" and class genuinely missing in available library version → NOT "write custom one." Instead:

1. Find closest equivalent that DOES exist (here: `JdbcTemplateLockProvider` with `shedlock` table).
2. Use it. Update spec to reflect what was actually used.
3. File learning if non-obvious gotcha (e.g. "ShedLock 7.7.0 doesn't ship Postgres-advisory-lock provider; use standard `JdbcTemplateLockProvider`; table migration one Flyway statement").

### 3. When repo already has wiring

Existing `@Bean LockProvider`, `@Bean ObjectMapper`, `@Bean RestTemplate`, etc. in `@Configuration` → DO NOT add second. Either:

- Reuse existing bean directly (autowire where needed), OR
- Update existing configuration to add new behavior (new `@Bean` method in same `@Configuration`, NOT sibling class wiring alternative).

Two competing `@Bean LockProvider`s in same context = startup failure or non-deterministic injection. Framework picks one, breaks other subtly.

### 4. Inventory commands (paste into shell first)

```bash
# Does the repo already have what I'm about to add?
grep -rE "@Bean\s+\w*\s*(LockProvider|ObjectMapper|RestTemplate|TaskExecutor|Clock|...)" \
  src/main/java --include='*.java'

# Does ANY Flyway migration already create the table I'm about to add?
grep -ri "<table-name>" src/main/resources/db/migration/

# Does the library family ship the variant I want?
curl -s "https://repo1.maven.org/maven2/<group-path>/" | grep -oE '<artifact-name-prefix>[a-z-]+' | sort -u

# What's actually inside the version I'm using?
jar tf ~/.m2/repository/<group>/<artifact>/<version>/<artifact>-<version>.jar | grep -i <class-fragment>
```

## What is forbidden

- Custom block whose name suggests "reimplementing X from library Y" (e.g. `PostgresAdvisoryLockProvider` mirroring ShedLock API).
- Second `@Bean` of type that already has `@Primary`-eligible bean in same context.
- Reimplementing Flyway migration that already exists under different version number (e.g. `V12__create_shedlock_table.sql` alongside existing `V1__create_shedlock_table.sql`).
- Citing "spec said X" as reason for custom code when X doesn't exist in available library version — escalate spec mismatch to user, don't paper over with custom code.
- Re-implementing business math in sibling service or external dependency WITHOUT parity test gated in CI proving two implementations agree on representative input matrix. Parity test lands BEFORE second implementation, not follow-up.

## What is allowed

- Custom block when library genuinely doesn't address use case (e.g. custom `LockProvider` wrapping two underlying providers for failover — not in any library).
- Thin adapter (single delegating class) bridging library API to project-specific port type. Wiring, not custom implementation.
- Fork and patch library when upstream unresponsive and patch small. Document fork reason in learning file; target next library release for removal.

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/prefer-existing-library-blocks.md`
