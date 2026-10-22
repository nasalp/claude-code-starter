# Command: /build

Run full build with all checks.

## Usage

```
/build              # Full build with all 5 static analysis tools
/build fast         # Skip static analysis (local dev)
/build check        # Only run static analysis checks
/build mutations    # Run mutation testing (PITest)
/build properties   # Run property-based tests only (jqwik)
/build all          # Full build + mutation testing
```

## Commands

### Full Build (5 Static Analysis Tools)

Runs: Spring Java Format, Checkstyle, Error Prone + NullAway, SpotBugs + FindSecBugs, PMD

```bash
# Maven (prefer daemon)
mvnd verify -T 1C 2>/dev/null || ./mvnw verify -T 1C

# Gradle
./gradlew build --parallel
```

### Fast Build (Skip Checks)

```bash
# Maven
mvnd test -T 1C -DskipTests=false -Dcheckstyle.skip=true -Dspotbugs.skip=true -Dpmd.skip=true 2>/dev/null || \
./mvnw test -T 1C -Dcheckstyle.skip=true -Dspotbugs.skip=true -Dpmd.skip=true

# Gradle
./gradlew test --parallel -x checkstyleMain -x checkstyleTest -x spotbugsMain -x spotbugsTest -x pmdMain
```

### Checks Only

```bash
# Maven — all 5 static analysis tools
./mvnw spring-javaformat:validate checkstyle:check spotbugs:check pmd:check -T 1C

# Gradle
./gradlew checkstyleMain spotbugsMain pmdMain
```

### Mutation Testing (PITest)

Verifies tests actually catch bugs. Requires 80% mutation kill rate.

```bash
./mvnw org.pitest:pitest-maven:mutationCoverage
```

### Property-Based Tests Only (jqwik)

```bash
./mvnw test -Dtest="*Properties" -T 1C
```

### Full Build + Mutations

```bash
(mvnd verify -T 1C 2>/dev/null || ./mvnw verify -T 1C) && \
./mvnw org.pitest:pitest-maven:mutationCoverage
```

## All 7 Tools

| # | Tool | Run During | What It Catches |
|---|------|-----------|-----------------|
| 1 | Spring Java Format | `verify` (initialize + process-sources) | Formatting violations |
| 2 | Checkstyle | `verify` (validate) | Style violations |
| 3 | Error Prone + NullAway | `verify` (compile) | Compile-time bugs, null safety |
| 4 | SpotBugs + FindSecBugs | `verify` | Bytecode bugs, security issues |
| 5 | PMD | `verify` | Complexity, dead code |
| 6 | PITest | on-demand | Tests that don't verify behavior |
| 7 | jqwik | `test` | Invariant violations across all inputs |

## Expected Output

```
BUILD SUCCESS
```

## On Failure

1. Identify which phase/tool failed (format, compile, test, checkstyle, spotbugs, pmd, pitest)
2. Show relevant errors
3. Suggest fixes

See `.claude/checklists/toolchain-setup.md` for full plugin configuration.
