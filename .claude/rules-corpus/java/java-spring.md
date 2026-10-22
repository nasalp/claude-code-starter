---
paths:
  - "**/*.java"
---

# Java & Spring Boot Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## Build Tool

### REQUIRED: Use Wrapper

```bash
# ✅ Always
./mvnw test
./gradlew test

# ❌ Never
mvn test
gradle test
```

### Command Reference

| Task | Maven | Gradle |
|------|-------|--------|
| Run tests | `./mvnw test` | `./gradlew test` |
| Full build | `./mvnw verify` | `./gradlew build` |
| Single test | `./mvnw test -Dtest=MyTest` | `./gradlew test --tests MyTest` |

### CRITICAL: `spring-boot-maven-plugin` Belongs in the Assembly Module Only

In a multi-module Maven project, `spring-boot-maven-plugin` MUST be declared
**only on the application/assembly module**, never in the parent `<plugins>` block
or `<pluginManagement>` with execution bindings inherited downward.

```xml
<!-- ❌ NEVER — parent pom.xml, applied to every module -->
<build>
  <plugins>
    <plugin>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-maven-plugin</artifactId>
      <executions>
        <execution><goals><goal>repackage</goal></goals></execution>
      </executions>
    </plugin>
  </plugins>
</build>

<!-- ✅ ALWAYS — only in the assembly module pom.xml (e.g., app/pom.xml) -->
<build>
  <plugins>
    <plugin>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-maven-plugin</artifactId>
      <executions>
        <execution><goals><goal>repackage</goal></goals></execution>
      </executions>
    </plugin>
  </plugins>
</build>
```

**Detection:** downstream consumer reports `ClassNotFoundException` for a class they can `unzip -l` and see in your library JAR → JAR has been repackaged. `unzip -p target/library.jar META-INF/MANIFEST.MF | grep -E 'Boot-|Spring-'` — any `Boot-*`/`Spring-Boot-Lib` headers on a library JAR are the smoking gun.

---

## Code Organization

### REQUIRED: Vertical Slices

```
com.example.orders/
├── api/            # Controllers, DTOs
├── application/    # Services
├── domain/         # Entities, value objects
└── infrastructure/ # Repositories, clients
```

**Not:**
```
com.example.controller/
com.example.service/
com.example.repository/
```

---

## Visibility

### CRITICAL: Entities Never Public

```java
// ❌ NEVER
public class Order { }

// ✅ ALWAYS
class Order { }  // package-private
```

### REQUIRED: Package-Private by Default

```java
// Default — no modifier
class OrderService { }

// Public only with justification
// Public: Spring Bean for cross-feature communication
public class OrderFacade { }
```

---

## Dependencies

### REQUIRED: Stable Versions Only

```xml
<!-- ✅ Pinned version -->
<version>4.0.2</version>

<!-- ❌ Never -->
<version>LATEST</version>
<version>[3.0,)</version>
```

```groovy
// ❌ Never
implementation 'com.example:lib:+'
```

### RECOMMENDED: Version Catalog (Gradle)

Use `gradle/libs.versions.toml` for centralized version management.

---

## Static Analysis

### REQUIRED: SpotBugs

- Run in `verify` phase
- HIGH/MEDIUM bugs fail build
- Include FindSecBugs plugin

```bash
./mvnw spotbugs:check
```

### REQUIRED: Checkstyle

Any violation fails the build.

---

## Resource Management

### CRITICAL: Bounded Caches

```java
// ✅ REQUIRED
Cache<K, V> cache = Caffeine.newBuilder()
    .maximumSize(10_000)
    .build();

// ❌ NEVER — unbounded
Map<K, V> cache = new ConcurrentHashMap<>();
```

### CRITICAL: Bounded Queues

```java
// ✅ REQUIRED
new ArrayBlockingQueue<>(1000);

// ❌ NEVER — unbounded
new LinkedBlockingQueue<>();
```

### CRITICAL: Spring-Managed Executors

```java
// ✅ REQUIRED
@Autowired Executor taskExecutor;
CompletableFuture.runAsync(() -> work(), taskExecutor);

// ❌ NEVER — loses trace context
CompletableFuture.runAsync(() -> work());
```

---

## Async & Virtual Threads

### REQUIRED: Context Propagation

Always include on classpath:
```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>context-propagation</artifactId>
</dependency>
```

### RECOMMENDED: Virtual Threads (Spring Boot 4.x)

```yaml
spring:
  threads:
    virtual:
      enabled: true
```

**Note:** Avoid `synchronized` — use `ReentrantLock` instead.

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Entities never public | CRITICAL |
| Bounded caches | CRITICAL |
| Bounded queues | CRITICAL |
| Spring-managed executors | CRITICAL |
| Use wrapper (mvnw/gradlew) | REQUIRED |
| Vertical slice packaging | REQUIRED |
| Package-private by default | REQUIRED |
| Pinned dependency versions | REQUIRED |
| SpotBugs + Checkstyle | REQUIRED |
| Context propagation | REQUIRED |
| Version catalog (Gradle) | RECOMMENDED |
| Virtual threads | RECOMMENDED |

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/java__java-spring.md`
