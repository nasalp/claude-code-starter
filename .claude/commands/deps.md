# Command: /deps

Manage and check dependencies.

## Usage

```
/deps                    # Show dependency tree
/deps outdated           # Check for updates
/deps security           # Check for vulnerabilities
/deps add <artifact>     # Add dependency
```

## Commands

### Dependency Tree

```bash
# Maven
./mvnw dependency:tree

# Gradle
./gradlew dependencies
```

### Check for Updates

```bash
# Maven
./mvnw versions:display-dependency-updates

# Gradle (requires plugin)
./gradlew dependencyUpdates
```

### Security Check

```bash
# Maven (OWASP dependency check)
./mvnw org.owasp:dependency-check-maven:check

# Gradle
./gradlew dependencyCheckAnalyze
```

### Add Dependency

#### Maven

Add to `pom.xml`:
```xml
<dependency>
    <groupId>group</groupId>
    <artifactId>artifact</artifactId>
    <version>version</version>
</dependency>
```

#### Gradle

Add to `build.gradle`:
```groovy
implementation 'group:artifact:version'
```

Or if using version catalog (`gradle/libs.versions.toml`):
```toml
[versions]
artifact = "version"

[libraries]
artifact = { module = "group:artifact", version.ref = "artifact" }
```

## Rules

- Always use **stable versions** (no `+`, `LATEST`, `RELEASE`)
- Check **Maven Central** for latest version
- Run **security check** before adding new deps
- Prefer **BOM-managed** versions when available
