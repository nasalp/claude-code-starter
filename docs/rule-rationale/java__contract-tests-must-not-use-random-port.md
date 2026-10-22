# Rationale: java/contract-tests-must-not-use-random-port.md

## Why

`@SpringBootTest(RANDOM_PORT)` is the wrong tool for contract verification:

1. **Slow.** Each test class boots a full Spring context AND starts a real
   server. A typical WebFlux app pays 5–30 seconds per class for the boot.
   Fifteen SCC-generated contract classes × 30 s on a CI runner = the build
   times out before any tooling can react. This is exactly the failure
   mode that bit us in `migrate/java-monorepo` CI runs c. 2026-05-14 —
   we ended up disabling the contract suite in CI to keep the build under
   30 minutes, which silently disabled the entire SCC verification gate.
2. **Couples contract tests to the runtime stack.** RANDOM_PORT pulls in
   the real `WebFilter` chain (rate limiter → Redis, request logging →
   stdio transport, auth → JWT crypto, etc.). Now your contract test
   needs Redis, real auth secrets, real upstream connectivity. Each one
   becomes its own little integration test, with all the failure modes
   that implies, when the actual contract you're verifying is the HTTP
   wire shape.
3. **Port-binding races under parallel surefire.** `RANDOM_PORT` allocates
   one ephemeral port per test class. Even though "random" sounds safe,
   the parallel forks can race the same kernel allocation window, and
   `LocalServerPort` injection can land too early for tests that bind
   inside `@BeforeAll`. Symptoms are flaky 500s that look exactly like
   real bugs.
4. **Wrong layer of abstraction.** Contracts assert wire shape:
   "given THIS request, return THIS status + body". MockMvc/WebTestClient
   give you exactly that. Real port binding adds nothing.

## Background

The incident that motivated this rule lives in
`spec/learnings/java-contract-tests-randomport.md` (if present). Symptoms:
CI build timing out on first cold cache; the response from "ok let's skip
contract tests in CI" was scope-creeping the regression rather than fixing
the root cause. Spending an extra hour to migrate to `WebTestClient` saved
five minutes per CI run forever, **and** restored the contract gate.
