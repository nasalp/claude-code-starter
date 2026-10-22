# Toolchain Setup Checklist

Complete, copy-paste-ready configuration for all 7 mandatory tools. Every project MUST have all of these configured before the first feature is implemented.

---

## Overview

| # | Tool | Phase | Purpose | Fail on Violation |
|---|------|-------|---------|-------------------|
| 1 | Spring Java Format | `initialize` / `process-sources` | Auto-format + validate | Yes |
| 2 | Checkstyle | `validate` | Spring-javaformat-checkstyle rules | Yes |
| 3 | Error Prone + NullAway | `compile` | Compile-time bug detection + null safety | Yes |
| 4 | SpotBugs + FindSecBugs | `verify` | Bytecode analysis + security | Yes |
| 5 | PMD | `verify` | PMD defaults plus project rules, no unapproved suppressions | Yes |
| 6 | PITest | on-demand | Mutation testing (80% kill threshold) | Yes |
| 7 | jqwik | `test` | Property-based testing | Yes |

---

## Version Properties

Add to `<properties>` in `pom.xml`. Pin all versions — no `LATEST` or ranges.

```xml
<properties>
    <java.version>21</java.version>

    <!-- Static analysis -->
    <spring-javaformat.version>0.0.43</spring-javaformat.version>
    <error-prone.version>2.36.0</error-prone.version>
    <nullaway.version>0.12.3</nullaway.version>
    <jspecify.version>1.0.0</jspecify.version>
    <spotbugs-maven-plugin.version>4.8.6.6</spotbugs-maven-plugin.version>
    <findsecbugs.version>1.13.0</findsecbugs.version>
    <maven-pmd-plugin.version>3.26.0</maven-pmd-plugin.version>

    <!-- Mutation testing -->
    <pitest-maven.version>1.17.4</pitest-maven.version>
    <pitest-junit5-plugin.version>1.2.2</pitest-junit5-plugin.version>

    <!-- Property-based testing -->
    <jqwik.version>1.9.2</jqwik.version>
</properties>
```

> **IMPORTANT:** Check for latest stable versions before using. These are reference versions as of 2026-03.

---

## Dependencies

```xml
<!-- Null safety annotations -->
<dependency>
    <groupId>org.jspecify</groupId>
    <artifactId>jspecify</artifactId>
    <version>${jspecify.version}</version>
</dependency>

<!-- Property-based testing -->
<dependency>
    <groupId>net.jqwik</groupId>
    <artifactId>jqwik</artifactId>
    <version>${jqwik.version}</version>
    <scope>test</scope>
</dependency>
```

---

## Plugin Configuration

### 1. Spring Java Format

```xml
<plugin>
    <groupId>io.spring.javaformat</groupId>
    <artifactId>spring-javaformat-maven-plugin</artifactId>
    <version>${spring-javaformat.version}</version>
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

### 2. Checkstyle (with Spring Java Format rules)

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-checkstyle-plugin</artifactId>
    <dependencies>
        <dependency>
            <groupId>io.spring.javaformat</groupId>
            <artifactId>spring-javaformat-checkstyle</artifactId>
            <version>${spring-javaformat.version}</version>
        </dependency>
    </dependencies>
    <configuration>
        <configLocation>io/spring/javaformat/checkstyle/checkstyle.xml</configLocation>
        <includeTestSourceDirectory>true</includeTestSourceDirectory>
        <failOnViolation>true</failOnViolation>
    </configuration>
    <executions>
        <execution>
            <id>checkstyle-validate</id>
            <phase>validate</phase>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

### 3. Error Prone + NullAway (via maven-compiler-plugin)

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <source>${java.version}</source>
        <target>${java.version}</target>
        <fork>true</fork>
        <compilerArgs>
            <arg>-XDcompilePolicy=simple</arg>
            <arg>-Xplugin:ErrorProne
                -XepAllErrorsAsWarnings
                -Xep:MissingOverride:ERROR
                -Xep:NullAway:ERROR
                -XepOpt:NullAway:OnlyNullMarked=true
                -XepOpt:NullAway:JSpecifyMode=true
                -XepOpt:NullAway:ExcludedFieldAnnotations=org.springframework.beans.factory.annotation.Autowired,org.springframework.beans.factory.annotation.Value,jakarta.inject.Inject,jakarta.persistence.Id,jakarta.persistence.GeneratedValue,jakarta.persistence.Column,jakarta.persistence.ManyToOne,jakarta.persistence.OneToMany,jakarta.persistence.OneToOne,jakarta.persistence.ManyToMany,jakarta.persistence.JoinColumn
                -XepOpt:NullAway:ExcludedClassAnnotations=jakarta.persistence.Entity,jakarta.persistence.MappedSuperclass,jakarta.persistence.Embeddable
                -XepOpt:NullAway:TreatGeneratedAsUnannotated=true
            </arg>
            <arg>-J--add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED</arg>
            <arg>-J--add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED</arg>
            <arg>-J--add-exports=jdk.compiler/com.sun.tools.javac.main=ALL-UNNAMED</arg>
            <arg>-J--add-exports=jdk.compiler/com.sun.tools.javac.model=ALL-UNNAMED</arg>
            <arg>-J--add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED</arg>
            <arg>-J--add-exports=jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED</arg>
            <arg>-J--add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED</arg>
            <arg>-J--add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED</arg>
            <arg>-J--add-opens=jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED</arg>
            <arg>-J--add-opens=jdk.compiler/com.sun.tools.javac.comp=ALL-UNNAMED</arg>
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

### 4. SpotBugs + FindSecBugs

```xml
<plugin>
    <groupId>com.github.spotbugs</groupId>
    <artifactId>spotbugs-maven-plugin</artifactId>
    <version>${spotbugs-maven-plugin.version}</version>
    <configuration>
        <effort>Max</effort>
        <threshold>Low</threshold>
        <failOnError>true</failOnError>
        <excludeFilterFile>spotbugs-exclude.xml</excludeFilterFile>
        <plugins>
            <plugin>
                <groupId>com.h3xstream.findsecbugs</groupId>
                <artifactId>findsecbugs-plugin</artifactId>
                <version>${findsecbugs.version}</version>
            </plugin>
        </plugins>
    </configuration>
    <executions>
        <execution>
            <id>spotbugs-verify</id>
            <phase>verify</phase>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

**Required file:** `spotbugs-exclude.xml` in project root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<FindBugsFilter>
    <!-- Exclude Spring-generated configuration classes -->
    <Match>
        <Source name="~.*Application\.java"/>
        <Bug pattern="EI_EXPOSE_REP,EI_EXPOSE_REP2"/>
    </Match>
</FindBugsFilter>
```

### 5. PMD

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-pmd-plugin</artifactId>
    <version>${maven-pmd-plugin.version}</version>
    <configuration>
        <failOnViolation>true</failOnViolation>
        <includeTests>false</includeTests>
        <printFailingErrors>true</printFailingErrors>
    </configuration>
    <executions>
        <execution>
            <id>pmd-verify</id>
            <phase>verify</phase>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

PMD defaults are enough to make PMD mandatory. Add a project `pmd-rules.xml` only when the project has a real reason for stricter local rules.

Never suppress PMD without explicit human approval linked in the PR. This includes `@SuppressWarnings("PMD...")`, `//NOPMD`, PMD exclude lists, rule removals, and build configuration that hides violations.

### 6. PITest (Mutation Testing)

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

> **Note:** Update `targetClasses` and `targetTests` to match your project's base package.

---

## Surefire Configuration

Surefire must include both `*Test.java` and `*Properties.java` (jqwik) patterns:

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-surefire-plugin</artifactId>
    <configuration>
        <includes>
            <include>**/*Test.java</include>
            <include>**/*Properties.java</include>
        </includes>
        <parallel>classes</parallel>
        <threadCount>4</threadCount>
        <perCoreThreadCount>true</perCoreThreadCount>
    </configuration>
</plugin>
```

---

## Verification Commands

```bash
# Full build (all 5 static analysis tools run during verify)
mvnd verify -T 1C 2>/dev/null || ./mvnw verify -T 1C

# Mutation testing (run after features, not on every build)
./mvnw org.pitest:pitest-maven:mutationCoverage

# Individual tools
./mvnw checkstyle:check                         # Checkstyle only
./mvnw spotbugs:check                           # SpotBugs only
./mvnw pmd:check                                # PMD only
./mvnw spring-javaformat:validate               # Format check only
./mvnw test -Dtest="*Properties"                # Property-based tests only
```

---

## Setup Checklist

When setting up a new project, verify:

- [ ] All 7 version properties defined in `<properties>`
- [ ] JSpecify dependency added
- [ ] jqwik test dependency added
- [ ] Spring Java Format plugin configured (apply + validate)
- [ ] Checkstyle plugin configured with spring-javaformat-checkstyle rules
- [ ] maven-compiler-plugin configured with Error Prone + NullAway
- [ ] SpotBugs plugin configured with FindSecBugs
- [ ] `spotbugs-exclude.xml` created
- [ ] PMD plugin configured with defaults and fail-on-violation
- [ ] No PMD suppressions unless human approval is linked in the PR
- [ ] PITest plugin configured (STRONGER, 80% threshold)
- [ ] Surefire includes `*Properties.java`
- [ ] `@NullMarked` on every `package-info.java`
- [ ] `./mvnw verify -T 1C` passes with zero violations
- [ ] `./mvnw org.pitest:pitest-maven:mutationCoverage` passes (80%+ kill rate)
