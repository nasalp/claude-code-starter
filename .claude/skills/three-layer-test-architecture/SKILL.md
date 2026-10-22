---
name: three-layer-test-architecture
description: Layered test taxonomy where backend ApiIT asserts SQL/business numbers, frontend Playwright asserts UI shape against contract stubs, and Java Playwright + Docker E2E asserts the full stack
origin: ECC
triggers: three-layer test architecture, ApiIT, PlaywrightE2EIT, frontend Playwright stubs, layered tests, contract stubs, where to put a test, test pyramid for monorepo, vertical slice testing
---
# Three-Layer Test Architecture

A test taxonomy for monorepos where a Java backend, a JavaScript frontend, and a Docker-built fat JAR all coexist. Each layer asserts only what it can concretely assert at its own fidelity, with no cross-layer duplication. Adopting this prevents both sprawling per-feature spec files and the opposite anti-pattern of wedging UI assertions into backend tests.

## When to use

- A repo ships a Java + Spring Boot backend, a SPA frontend, and a Docker image that bundles both.
- The backend produces Spring Cloud Contract stubs from REST Docs / MockMvc tests.
- You need to add tests for a new feature and the question is: backend? frontend? both? full stack?
- A reviewer is about to merge a PR that creates `frontend/e2e/<my-feature>.spec.ts` for the first time.
- A reviewer is about to merge a PR whose backend integration test renders DOM.

## When NOT to use

- The repo has only one tier (a pure backend service, a pure SPA, a CLI). The pyramid collapses to one layer; this skill does not apply.
- The backend does not produce contract stubs. Layer 2 cannot be implemented honestly without them; you would be testing a hand-rolled mock pretending to be a contract.
- The team has not invested in Testcontainers. Layer 1 and Layer 3 both depend on real infrastructure; without it, the layered guarantees are illusory.

## The pattern

Three layers. Each is owned by a single tooling stack and has one purpose.

| Layer | Location | Runs against | Trigger | Asserts |
|-------|----------|--------------|---------|---------|
| **1. Backend API IT** | `<backend>/src/test/java/.../api/*ApiIT.java` | Real Spring app + Testcontainers (Postgres, Redis, ...) | `mvnw verify -pl <backend>` | SQL correctness, business arithmetic, response shape, status codes, observability outcomes |
| **2. Frontend Playwright (stubs)** | `frontend/e2e/*.spec.ts` | SCC stubs server (WireMock from REST Docs) + Vite/webpack dev server | `playwright test` (via `playwright.config.ts` global setup) | UI renders contract-compliant data correctly, accessibility, routing, error states |
| **3. Full E2E (Docker)** | `<e2e-module>/src/test/java/.../*PlaywrightE2EIT.java` | The fat JAR Docker image + Postgres + Redis via Testcontainers | `mvnw verify -pl <e2e-module>` | Full stack: SPA routing, OIDC auth, DB schema, embedded static assets, JSON-API roundtrip |

Concrete repo example (example dashboard):

```
backend/src/test/java/com/example/app/api/FinanceApiIT.java
  - asserts MRR, CLV, trials conversion numbers come out right
  - Testcontainers Postgres replica + Flyway-seeded fixtures
  - never opens a browser

frontend/e2e/metrics.spec.ts
  - asserts the Finance card renders the value the contract returned
  - hits stub-runner ports allocated via @stubborn-sh/* (see stubborn-frontend-stubs)
  - never queries the database

e2e/src/test/java/com/example/app/e2e/PlaywrightE2EIT.java
  - boots the production Docker image inside Testcontainers
  - signs in via the dev-auth filter, navigates the SPA, asserts the same number end to end
  - is the slowest and the most authoritative
```

Rules of the layout:

1. **Never create a new spec file per feature in `frontend/e2e/`.** Add a `test.describe(\"feature X\", ...)` block to the existing topical file (`metrics.spec.ts`, `business-flows.spec.ts`, `features.spec.ts`). One file per topic, not one file per feature.
2. **Never create a standalone Playwright TS file that duplicates the Java E2E suite.** The Java `PlaywrightE2EIT` is the authoritative full-stack tester; TS Playwright tests run against stubs.
3. **Layer 2 requires REST Docs first.** If the new endpoint has no `*ControllerRestDocsTests.java`, the stubs JAR will not contain the contract and the frontend test will hit a 404 from WireMock. Add the REST Docs test before the frontend test.
4. **`mvnw clean install` covers Layers 1 and 2** (backend installs the stubs JAR; frontend module runs Vitest + Playwright against it). **Layer 3 is opt-in** via the e2e module so the default verify stays under the wall-clock target.
5. **Each layer asserts only at its fidelity.** Backend ApiIT asserts numbers. Frontend Playwright asserts DOM. Full E2E asserts integrations. Don't make ApiIT render Mustache templates; don't make frontend Playwright open a JDBC connection.

Adding tests for a new feature follows this checklist:

1. Backend ApiIT in `<backend>/.../api/<Dept>ApiIT.java` -- assert business data.
2. REST Docs test in `<backend>/.../<Dept>ControllerRestDocsTests.java` -- generates SCC stubs.
3. Frontend Playwright in `frontend/e2e/metrics.spec.ts` -- a new `test.describe`.
4. Java E2E in `<e2e-module>/.../PlaywrightE2EIT.java` -- a new `@Nested` class for cross-cutting flows.

## Common gotchas / variants

- **Layer 2 needs `mvn install`, not `mvn package`.** The frontend reads the stubs JAR from `~/.m2`. A bare package leaves it in `target/` only.
- **Layer 3 needs the Docker image built first.** A typical CI flow is `mvnw -pl app verify` (which builds the image) before `mvnw -pl e2e verify`. The e2e module's `pom.xml` should declare the dependency explicitly so a clean reactor build orders correctly.
- **No DOM assertions in Layer 1.** When a tester writes "the response JSON contains the rendered HTML" in an ApiIT, it is a sign the controller is returning HTML and the layering has been violated.
- **No DB writes in Layer 2.** When a frontend test wants to "set up data", it has gone outside its layer. Either move the test to Layer 3 or expand the contract / stub catalog so the data is fixture-served.
- **No fake Postgres in Layer 3.** H2 / SQLite substitutes lie about Postgres semantics. Use Testcontainers Postgres with the same version as production.
- **`SharedPostgres` singleton.** Don't instantiate a new `@Container` per test class. Layers 1 and 3 share a static singleton container so the JVM-wide test run starts Postgres once.
- **Stub provenance must be observable.** A frontend test that suddenly turns green after a backend change should be traceable to a contract update in the producer module. If you cannot trace it, the stub catalog has drifted.

## Verification

A repo using this pattern correctly satisfies:

1. `find frontend/e2e -name "*.spec.ts" | wc -l` is small and grows by topic, not by feature.
2. Every backend `*ApiIT.java` extends a base class that wires `SharedPostgres`.
3. Every controller has both a REST Docs test (producing stubs) and an ApiIT (asserting numbers).
4. The Java E2E module is the only place where `Playwright + Testcontainers + Docker image` co-occur.
5. CI logs show three distinct phases with different durations: backend verify (fastest), frontend Playwright (medium), e2e module (slowest).

If a single layer accounts for >60% of test wall-clock without a corresponding fidelity payoff, the layout has degenerated. Re-balance.

## References

- Frontend Playwright config: `frontend/playwright.config.ts`
- Companion: `stubborn-frontend-stubs` -- replaces Docker stub-runner in Layer 2
- Companion: `adversarial-frontend-test-followups` -- catches Layer 2 tests that pass without exercising the stub
