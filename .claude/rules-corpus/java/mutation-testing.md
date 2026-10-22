---
paths:
  - "**/*.java"
---

# Mutation Testing Rules

Mutation testing catches tests that don't actually verify behavior.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## REQUIRED: PITest for Mutation Testing

Use PITest (pitest-maven) to verify tests actually catch bugs.

### Maven Configuration

```xml
<plugin>
    <groupId>org.pitest</groupId>
    <artifactId>pitest-maven</artifactId>
    <version>${pitest-maven.version}</version>
    <dependencies>
        <dependency>
            <groupId>org.pitest</groupId>
            <artifactId>pitest-junit5-plugin</artifactId>
            <version>${pitest-junit5-plugin.version}</version>
        </dependency>
    </dependencies>
    <configuration>
        <targetClasses>
            <param>com.example.*</param>
        </targetClasses>
        <targetTests>
            <param>com.example.**.*Test</param>
            <param>com.example.**.*Properties</param>
        </targetTests>
        <excludedTestClasses>
            <param>**.*E2ETest</param>
            <param>**.*RepositoryTest</param>
            <param>**.*ContractTest</param>
        </excludedTestClasses>
        <mutators>
            <mutator>STRONGER</mutator>
        </mutators>
        <mutationThreshold>80</mutationThreshold>
        <timestampedReports>false</timestampedReports>
    </configuration>
</plugin>
```

### Run

```bash
./mvnw org.pitest:pitest-maven:mutationCoverage
```

---

## REQUIRED: Unit Tests Only

Mutation testing runs against **unit tests only** — not integration, E2E, or contract tests.

**Excluded patterns:**
- `**/*E2ETest.java` — full stack tests
- `**/*RepositoryTest.java` — database slice tests
- `**/*ContractTest.java` — contract verification tests

**Included patterns:**
- `**/*Test.java` — unit tests
- `**/*Properties.java` — property-based tests (jqwik)

---

## REQUIRED: STRONGER Mutators

Use `STRONGER` mutator set (not `DEFAULT`). It includes:
- Conditional boundary mutations
- Negate conditionals
- Math mutations
- Increment/decrement
- Invert negatives
- Return value mutations
- Void method call removal
- Empty return mutations

---

## REQUIRED: 80% Mutation Kill Threshold

Build fails if mutation kill rate drops below **80%**.

```xml
<mutationThreshold>80</mutationThreshold>
```

If a test doesn't kill a mutant, either:
1. The test doesn't actually verify the behavior (fix the test)
2. The code is unreachable (remove the code)
3. The mutation is equivalent (rare, can be excluded)

---

## RECOMMENDED: Run After Each Feature

```bash
# After implementing a feature
./mvnw test                                           # Fast tests pass
./mvnw org.pitest:pitest-maven:mutationCoverage       # Mutations killed >= 80%
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| PITest for mutation testing | REQUIRED |
| Unit tests only (exclude E2E, repo, contract) | REQUIRED |
| STRONGER mutators | REQUIRED |
| 80% mutation kill threshold | REQUIRED |
| Run after each feature | RECOMMENDED |

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/java__mutation-testing.md`
