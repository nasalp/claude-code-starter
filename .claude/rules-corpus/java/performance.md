---
paths:
  - "**/*.java"
---

# Performance Rules

Build fast, test fast, deploy fast.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## REQUIRED: Parallel Test Execution

**Tests MUST run in parallel by default.**

### Maven Configuration

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-surefire-plugin</artifactId>
    <configuration>
        <parallel>classes</parallel>
        <threadCount>4</threadCount>
        <perCoreThreadCount>true</perCoreThreadCount>
    </configuration>
</plugin>
```

### Gradle Configuration

```groovy
test {
    maxParallelForks = Runtime.runtime.availableProcessors()
}
```

### JUnit 5 Parallel Execution

```properties
# src/test/resources/junit-platform.properties
junit.jupiter.execution.parallel.enabled=true
junit.jupiter.execution.parallel.mode.default=concurrent
junit.jupiter.execution.parallel.mode.classes.default=concurrent
```

---

## REQUIRED: Test Isolation

**Tests MUST be isolated to run in parallel safely.**

- [ ] No shared mutable state between tests
- [ ] No hardcoded ports — use random ports
- [ ] No shared files — use temp directories
- [ ] No test order dependencies

```java
// ❌ Shared state
static List<Order> orders = new ArrayList<>();

// ✅ Isolated
@Test void test() {
    var orders = new ArrayList<Order>();
}
```

### Random Ports

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class IntegrationTest {
    @LocalServerPort
    private int port;
}
```

---

## RECOMMENDED: Maven Daemon

**Use Maven Daemon (mvnd) if available** — keeps JVM warm between builds, cuts build times.

```bash
# Check if mvnd is available
which mvnd

# Use mvnd instead of mvn
mvnd verify -T 1C
mvnd test

# Falls back gracefully - if mvnd not present, use mvnw
mvnd verify -T 1C || ./mvnw verify -T 1C
```

### Installation

```bash
# macOS
brew install mvndaemon/tap/mvnd

# Linux/Windows - see https://github.com/apache/maven-mvnd
```

### Benefits
- 2-10x faster builds after first run
- Keeps JVM and Maven plugins in memory
- Compatible with existing Maven projects

---

## REQUIRED: Fast Build Configuration

### Maven

```bash
# Parallel build (1 thread per core)
./mvnw -T 1C verify

# With daemon (if available)
mvnd -T 1C verify

# Fast local development (skip static analysis)
./mvnw test -T 1C -Pfast
```

### Gradle

```groovy
// gradle.properties
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.daemon=true
```

---

## REQUIRED: Use Test Slices

Don't load full Spring context when not needed:

```java
// ❌ SLOW — loads everything
@SpringBootTest
class ControllerTest { }

// ✅ FAST — loads only web layer
@WebMvcTest(OrderController.class)
class ControllerTest { }

// ✅ FAST — loads only JPA
@DataJpaTest
class RepositoryTest { }
```

| Annotation | Loads | Use For |
|------------|-------|---------|
| `@WebMvcTest` | Web layer | Controller tests |
| `@DataJpaTest` | JPA layer | Repository tests |
| `@JsonTest` | JSON | Serialization tests |
| `@SpringBootTest` | Everything | Full integration |

---

## RECOMMENDED: Reuse Testcontainers

```java
// ✅ Singleton container — shared across tests
abstract class AbstractIntegrationTest {
    static final PostgreSQLContainer<?> postgres;
    static {
        postgres = new PostgreSQLContainer<>("postgres:15");
        postgres.start();
    }
}
```

---

## Build Commands

```bash
# With Maven Daemon (fastest)
mvnd verify -T 1C

# Standard Maven (parallel)
./mvnw verify -T 1C

# Gradle (parallel)
./gradlew build --parallel

# Fast local dev (skip checks)
./mvnw test -T 1C -Pfast
./gradlew test -x checkstyleMain -x spotbugsMain
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Tests run in parallel | REQUIRED |
| Tests are isolated | REQUIRED |
| Use test slices | REQUIRED |
| Build caching enabled | REQUIRED |
| Maven Daemon (mvnd) | RECOMMENDED |
| Reuse Testcontainers | RECOMMENDED |
