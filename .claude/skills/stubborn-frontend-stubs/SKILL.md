---
name: stubborn-frontend-stubs
description: Serve Spring Cloud Contract stubs to frontend tests (Jest, Vitest, Playwright) directly from Node, replacing Docker-based stub-runner with the @stubborn-sh/* npm packages
origin: ECC
triggers: spring-cloud-contract, stub-runner, @stubborn-sh, setupStubs, springcloud/spring-cloud-contract-stub-runner, frontend stubs, contract stubs in jest, contract stubs in vitest, contract stubs in playwright, stubs.jar, WireMock from contracts
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/package.json"
---
# Stubborn Frontend Stubs

Serve Spring Cloud Contract (SCC) stubs to frontend tests **without** booting a Docker stub-runner container. The `@stubborn-sh/*` npm packages start a local HTTP server in-process from a stubs JAR, a broker-served version, or a WireMock mappings directory. This skill is the canonical replacement for `springcloud/spring-cloud-contract-stub-runner` in Playwright / Vitest / Jest workflows.

## When to use

- A Java backend already publishes an SCC stubs JAR (typically `*-stubs.jar` under `target/` or installed in the local Maven repo by `mvn install`).
- Your frontend tests (Jest, Vitest, Playwright) need contract-compliant HTTP responses but you do **not** want to pay the Docker startup tax on every test run, in CI, or on a developer laptop.
- You want a single, in-process server running on a dynamically allocated port that is consumed by `vite`, `webpack-dev-server`, or `playwright.config.ts` via env-vars.
- You want to consume contracts from a centralized contract broker (Stubborn broker) for governed cross-team contract testing.

This skill is the **npm-side** counterpart of `@AutoConfigureStubRunner`. Java consumers continue to use `@AutoConfigureStubRunner` for backend-to-backend contract testing -- that pipeline stays unchanged.

## When NOT to use

- The backend does not produce SCC stubs. Use plain MSW or hand-rolled `fetch` mocks instead.
- You need a Java service to consume stubs -- use `@AutoConfigureStubRunner`, not this.
- You need to author stubs by hand. Author SCC contracts in the producer repo, generate the JAR, then consume here. Do not bypass the contract pipeline.
- You need wire-level recording from a real backend -- use WireMock record mode in a one-off script, not this.

## The pattern

Add the dev dependencies. The frontend `package.json` (e.g. `frontend/package.json`) declares:

```jsonc
"devDependencies": {
  "@stubborn-sh/stub-server": "^0.1.0",
  "@stubborn-sh/jest": "^0.1.0"
}
```

In a Jest or Vitest test, wire `setupStubs` / `teardownStubs` into the lifecycle hooks. The server starts once per test run and exposes a port that the system under test must point at.

```ts
import { setupStubs, teardownStubs } from "@stubborn-sh/jest";

let stubPort: number;

beforeAll(async () => {
  stubPort = await setupStubs({
    // Strategy 1 -- local Maven JAR (default for monorepo / mvn install workflows)
    jarPath:
      "~/.m2/repository/com/example/app/0.1.0-SNAPSHOT/app-0.1.0-SNAPSHOT-stubs.jar",
  });
  process.env.API_TARGET = `http://localhost:${stubPort}`;
});

afterAll(() => teardownStubs());
```

Three loading strategies are supported. Pick exactly one:

```ts
// Strategy 1 -- JAR path (local Maven cache, mvn install pipeline)
await setupStubs({ jarPath: "~/.m2/.../app-0.1.0-SNAPSHOT-stubs.jar" });

// Strategy 2 -- Stubborn broker (governed contract distribution)
await setupStubs({
  brokerUrl: "http://localhost:18080",
  applicationName: "api",
  version: "1.0.0",
});

// Strategy 3 -- WireMock mappings directory (already-extracted stubs)
await setupStubs({ mappingsDir: "./target/stubs/mappings" });
```

For Playwright, `setupStubs` runs in `globalSetup` and writes the dynamic port into the worker env so `playwright.config.ts` and the dev server pick it up:

```ts
// playwright.global-setup.ts
import { setupStubs } from "@stubborn-sh/stub-server";

export default async function globalSetup() {
  const port = await setupStubs({ jarPath: process.env.STUBS_JAR! });
  process.env.API_TARGET = `http://localhost:${port}`;
}
```

```ts
// playwright.config.ts (sketch)
export default defineConfig({
  globalSetup: require.resolve("./playwright.global-setup.ts"),
  webServer: {
    command: "npm run dev:stubbed",
    env: { API_TARGET: process.env.API_TARGET! },
    url: "http://localhost:5173",
  },
});
```

(Replace `dev` with your project script name -- typically `dev` for Vite projects.)

## Common gotchas / variants

- **Port allocation must be dynamic.** Hardcoding `8750` or any other fixed port breaks parallel test runs and Vitest worker pools. Always read the port returned by `setupStubs`.
- **Strategy mixing.** `jarPath` + `mappingsDir` + `brokerUrl` are mutually exclusive. Passing two emits a confusing error from the underlying stub server. Pick one and document why in the test file.
- **`mvn install` is required** for the JAR strategy. A bare `mvn package` puts the stubs JAR in `target/` only -- fine if you point `jarPath` there, but breaks for downstream developers who expect the artifact in `~/.m2`. The CI job that runs frontend tests should depend on the install phase of the producer module.
- **The `stub-runner` Spring Boot module / `springcloud/spring-cloud-contract-stub-runner` Docker image become unused for frontend tests.** Java backend consumers still need `@AutoConfigureStubRunner`. Don't delete the JAR producer pipeline.
- **WireMock semantics still apply.** Stubs are matched by request method, URL, headers, and body; non-deterministic ordering of multiple stubs that match the same request is still a producer-side bug. Fix it in the SCC contract, not in the frontend test.
- **Hand-written external service stubs (`stubs` modules) are unaffected.** Those exist for non-SCC services (Stripe, Twilio, Meta) and continue to use WireMock or in-process fakes.

## Verification

A frontend test run that uses `setupStubs` should produce, on stdout / pino logs:

1. Exactly one `Stubborn server listening on http://localhost:<port>` line per worker.
2. A matching `teardown complete` line when the suite finishes.
3. Zero references to `docker run`, `springcloud/spring-cloud-contract-stub-runner`, or `STUB_RUNNER_PORT` env-vars in the test command.

CI evidence: the GitHub Actions runner logs should not contain `Pulling from springcloud/...`. Local evidence: `docker ps` during the test run should show no stub-runner container.

A green test does not prove correctness -- it proves the contract was matched. Pair this with an adversarial-frontend test (see `adversarial-frontend-test-followups`) so a tautological `isLoading=true` assertion does not silently pass against a stub server that nothing ever calls.

## References

- Upstream docs: https://docs.stubborn.sh/
- Upstream source: https://github.com/stubborn-sh/stubborn
- Java-side counterpart: `@AutoConfigureStubRunner` -- keep for backend-to-backend contract testing
