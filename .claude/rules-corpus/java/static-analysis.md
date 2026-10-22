---
paths:
  - "**/*.java"
---

# Static Analysis Rules

5 tools, all fail-on-violation from day zero.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |

---

## CRITICAL: All 5 Tools Active

| # | Tool | Phase | Purpose |
|---|------|-------|---------|
| 1 | **Spring Java Format** | `validate` | Auto-apply + validate code formatting |
| 2 | **Checkstyle** | `validate` | Spring-javaformat-checkstyle rules |
| 3 | **Error Prone** | `compile` | Compile-time bug detection |
| 4 | **SpotBugs + FindSecBugs** | `verify` | Bytecode analysis + security checks |
| 5 | **PMD** | `verify` | PMD defaults plus project rules, no unapproved suppressions |

All tools **fail the build on violation** from day zero. No warnings-only mode.

PMD defaults = baseline. Project-specific PMD rules OK; don't require custom ruleset just to accept the tool.

Never suppress PMD without explicit human approval linked in PR. Includes `@SuppressWarnings("PMD...")`, `//NOPMD`, PMD exclude lists, rule removals, build config hiding violations.

Java production classes over 400 lines fail review unless explicit human approval linked in PR.

---

## 1. Spring Java Format

Auto-formats code to Spring style (tab indentation, import ordering):

```xml
<plugin>
    <groupId>io.spring.javaformat</groupId>
    <artifactId>spring-javaformat-maven-plugin</artifactId>
    <executions>
        <execution>
            <id>apply-format</id>
            <phase>initialize</phase>
            <goals><goal>apply</goal></goals>
        </execution>
        <execution>
            <id>validate-format</id>
            <phase>process-sources</phase>
            <goals><goal>validate</goal></goals>
        </execution>
    </executions>
</plugin>
```

---

## 2. Checkstyle

Uses Spring-javaformat-checkstyle rules:

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-checkstyle-plugin</artifactId>
    <configuration>
        <configLocation>io/spring/javaformat/checkstyle/checkstyle.xml</configLocation>
        <includeTestSourceDirectory>true</includeTestSourceDirectory>
    </configuration>
</plugin>
```

---

## 3. Error Prone + NullAway

Compile-time bug detection via Error Prone, with NullAway for null safety:

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <fork>true</fork>
        <compilerArgs>
            <arg>-XDcompilePolicy=simple</arg>
            <arg>-Xplugin:ErrorProne
                -XepAllErrorsAsWarnings
                -Xep:MissingOverride:ERROR
                -Xep:NullAway:ERROR
                -XepOpt:NullAway:OnlyNullMarked=true
                -XepOpt:NullAway:JSpecifyMode=true
            </arg>
            <!-- JVM flags for Java 25 (team baseline; same flags apply on Java 21+) -->
            <arg>-J--add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED</arg>
            <!-- ... more --add-exports flags ... -->
        </compilerArgs>
        <annotationProcessorPaths>
            <path>
                <groupId>com.google.errorprone</groupId>
                <artifactId>error_prone_core</artifactId>
                <version>${error-prone.version}</version>
            </path>
            <path>
                <groupId>com.uber.nullaway</groupId>
                <artifactId>nullaway</artifactId>
                <version>${nullaway.version}</version>
            </path>
        </annotationProcessorPaths>
    </configuration>
</plugin>
```

Requires `fork=true` and `--add-exports` JVM flags (team baseline Java 25; same flags on Java 21+).

---

## 4. SpotBugs + FindSecBugs

Bytecode analysis with security plugin:

```xml
<plugin>
    <groupId>com.github.spotbugs</groupId>
    <artifactId>spotbugs-maven-plugin</artifactId>
    <configuration>
        <effort>Max</effort>
        <threshold>Low</threshold>
        <failOnError>true</failOnError>
        <excludeFilterFile>spotbugs-exclude.xml</excludeFilterFile>
        <plugins>
            <plugin>
                <groupId>com.h3xstream.findsecbugs</groupId>
                <artifactId>findsecbugs-plugin</artifactId>
            </plugin>
        </plugins>
    </configuration>
</plugin>
```

---

## 5. PMD

PMD defaults with fail-on-violation:

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-pmd-plugin</artifactId>
    <configuration>
        <failOnViolation>true</failOnViolation>
        <includeTests>false</includeTests>
        <printFailingErrors>true</printFailingErrors>
    </configuration>
</plugin>
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| All 5 tools active and failing build | CRITICAL |
| Spring Java Format auto-apply + validate | REQUIRED |
| Error Prone + NullAway at compile time | REQUIRED |
| SpotBugs + FindSecBugs at verify time | REQUIRED |
| PMD defaults at verify time, no unapproved suppressions | REQUIRED |
