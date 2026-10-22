---
name: spring-data-rest-docs-stubs
description: Generate Spring Cloud Contract WireMock stubs from Spring REST Docs tests via a Maven assembly that repackages target/generated-snippets/stubs into the SCC classpath layout
origin: ECC
triggers: spring cloud contract, stub runner, RestDocsTests, WireMock stubs, generated-snippets/stubs, RestDocsTests.java, contract testing, frontend stub backend
paths:
  - "**/*.java"
  - "**/pom.xml"
---
# Spring Cloud Contract Stubs From REST Docs

Backend pattern for generating WireMock stubs that the frontend (Playwright, Vite dev) and stub-runner consume — without writing a single Groovy/YAML contract. Spring REST Docs `*RestDocsTests` exercise controllers with realistic mock data; the snippets dump WireMock stub JSONs to `target/generated-snippets/stubs/`. A separate assembly module repackages those JSONs into a `*-stubs.jar` matching the Spring Cloud Contract path layout (`META-INF/{groupId}/{artifactId}/{version}/mappings/`), and the stub runner serves them on a port.

This is the lightest possible contract-test pipeline: the production controller, its DTOs, and Jackson serialization are the contract source. Frontend code consumes responses byte-for-byte identical to production.

## When to use

- You have a Spring Boot backend with `spring-restdocs-mockmvc` already wired into controller tests.
- You need the React/Vite frontend (or another consumer) to develop and E2E-test against fixed, realistic JSON shapes without booting Postgres + the full backend.
- You want one source of truth: the controller test data IS the stub. No drift between contract YAML and runtime DTOs.
- You want stubs published as a Maven artifact (e.g. to GitHub Packages) so consumers resolve them by GAV.

## When NOT to use

- The consumer is another Spring service that needs CDC verification — use full Spring Cloud Contract DSL with `BaseContractTest`. RestDocs-derived stubs are response-only; they don't fail the producer build when the consumer's expectation drifts.
- You need request matching beyond URL + method (header/body matchers, scenarios). RestDocs stubs are flat HTTP exchanges.
- The frontend is fine hitting a live backend behind feature flags — the stub-runner is overhead you don't need.
- You're testing failure modes (5xx, timeouts). RestDocs only captures the success path the test exercised.

Note: pair this with the `stubborn-frontend-stubs` skill for the npm-side serving.

## The pattern

### 1. Producer side: REST Docs in controller tests

In `backend/src/test/java/.../api/*RestDocsTests.java`, every controller test MUST return non-empty, realistic mock data. Empty `List.of()` responses produce useless empty-array stubs. Use inner records that implement the `*Row` projection interface for clean Jackson serialization — Mockito proxy mocks serialize their internals and break the stub.

```java
@WebMvcTest(FinanceController.class)
@AutoConfigureRestDocs
class FinanceRestDocsTests {

    @Autowired MockMvc mockMvc;
    @MockitoBean FinanceService service;

    record FakeMrrRow(String tier, BigDecimal mrr, int locations) implements MrrRow {}

    @Test
    void mrr_per_location() throws Exception {
        when(service.getMrrPerLocation()).thenReturn(List.of(
            new FakeMrrRow("starter",  new BigDecimal("12500.00"),  87),
            new FakeMrrRow("growth",   new BigDecimal("48200.00"), 213),
            new FakeMrrRow("scale",    new BigDecimal("96400.00"), 142)));
        this.mockMvc.perform(get("/api/v1/finance/mrr/per-location"))
            .andExpect(status().isOk())
            .andDo(document("finance/mrr-per-location"));
    }
}
```

After `./mvnw test`, snippets land at `backend/target/generated-snippets/stubs/<test>/<doc-id>.json`.

### 2. Assembly module: `app/src/assembly/stubs.xml`

The assembly descriptor builds a JAR whose internal layout matches what the SCC `StubRunner` looks for on the classpath: `META-INF/{groupId}/{artifactId}/{version}/mappings/**/*.json`.

```xml
<assembly xmlns="http://maven.apache.org/ASSEMBLY/2.2.0">
    <id>stubs</id>
    <formats><format>jar</format></formats>
    <includeBaseDirectory>false</includeBaseDirectory>
    <fileSets>
        <fileSet>
            <directory>${project.basedir}/../backend/target/generated-snippets/stubs</directory>
            <outputDirectory>META-INF/${project.groupId}/${project.artifactId}/${project.version}/mappings</outputDirectory>
            <includes><include>**/*.json</include></includes>
        </fileSet>
    </fileSets>
</assembly>
```

### 3. Assembly module: `app/pom.xml`

Wire `maven-assembly-plugin` to attach a `stubs`-classifier JAR at `package` phase. Add a `maven-antrun-plugin` `mkdir`/`touch` in `prepare-package` so dev builds (`-DskipTests`) don't fail on a missing snippets directory.

### 4. Consumer side: `stub-runner/src/main/resources/application.yml`

```yaml
server:
  port: 8750
spring:
  cloud:
    contract:
      stubrunner:
        stubs-mode: CLASSPATH
        fail-on-no-stubs: false
        ids:
          - com.example.dashboard:app:+:stubs:8750
          - com.example.dashboard:stubs:+:stubs:8750
```

Note the property prefix is `spring.cloud.contract.stubrunner.*`, NOT `stubrunner.*` — the latter is the standalone-flavor namespace and silently does nothing in the boot starter.

## Common gotchas / variants

- **Empty stubs.** A RestDocs test that returns `List.of()` is technically valid but the stub is `[]`, hiding every frontend rendering bug. Review checklist: every stub JSON must contain ≥2 records with realistic, non-null values.
- **Mockito serialization.** `@MockitoBean` returning a Mockito-mocked projection interface serializes proxy internals into the snippet. Define a static nested `record FakeXxxRow(...) implements XxxRow {}` per controller test.
- **Wrong stubrunner property prefix.** `stubrunner.ids` (server flavor) vs `spring.cloud.contract.stubrunner.ids` (boot starter). Use the starter; symptom of the wrong prefix is the runner booting cleanly but serving 404 for everything.
- **Docker image cache.** When iterating, the `springcloud/spring-cloud-contract-stub-runner:5.0.0-M1` container caches the resolved JAR. Stop+remove the container after `mvn install` to pick up the updated stubs JAR from `~/.m2`. Mount `~/.m2/repository` to `/home/scc/.m2/repository`.
- **Race condition on parallel tests.** Multiple `*RestDocsTests` writing into the same `generated-snippets/stubs/` directory race on `mkdir`. Pre-create the subdirectories in `generate-test-resources` if you observe sporadic IO failures.
- **Port mapping.** Server (`server.port`) and stubs (`...:stubs:<port>`) MUST share a port when you want the runner itself to serve stubs (set both to `8750`). Don't split server/stubs onto separate ports unless you have a reason — frontend code only knows one base URL.

## Verification

- `./mvnw -pl app package` produces `app-${version}-stubs.jar` of non-trivial size.
- `unzip -l app-*-stubs.jar | grep mappings` shows entries under `META-INF/com.example.dashboard/app/<version>/mappings/...`.
- Boot the stub runner: `java -jar stub-runner/target/stub-runner-*.jar` and `curl http://localhost:8750/api/v1/finance/mrr/per-location` returns the 3-record JSON authored in the test.
- Frontend Playwright suite passes against `BASE_URL=http://localhost:8750` with no backend, no Postgres.
- A new RestDocs test added today shows up in tomorrow's stubs JAR with no DSL changes.

## References

- `specs/learnings/testing-stub-runner-setup.md` — the iteration history.
- `specs/learnings/testing-empty-restdocs-stubs.md` — why empty-array stubs are the most insidious failure mode.
- Spring Cloud Contract docs, "Stub Runner Boot": https://docs.spring.io/spring-cloud-contract/reference/
