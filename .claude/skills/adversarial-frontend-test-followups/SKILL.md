---
name: adversarial-frontend-test-followups
description: Companion *.adversarial.test.ts files that resolve and reject fetches and assert on real values, paired with original tests that only check the loading state and prove nothing
origin: ECC
triggers: adversarial.test.ts, tautological frontend test, isLoading=true assertion, useQuery initial state, vi.stubGlobal fetch, fetch resolved promise test, react-query test that asserts only loading, frontend coverage drift
paths:
  - "**/*.test.ts"
  - "**/*.test.tsx"
  - "**/*.spec.ts"
  - "**/*.spec.tsx"
---
# Adversarial Frontend Test Followups

A widespread frontend-test failure mode is the *tautological useQuery test*: a hook is rendered, the assertion is `expect(result.current.isLoading).toBe(true)`, the test passes -- because every `useQuery` hook starts in `isLoading=true` with `data=undefined` regardless of whether the network call ever succeeds, fails, or is even made. These tests prove nothing. The remediation is to ship a parallel `*.adversarial.test.ts` companion that resolves and rejects fetches with controlled responses and asserts on the real values that come back.

## When to use

- Reviewing or auditing a `frontend/src/**/*.test.ts(x)` file whose only assertions are about `isLoading`, `isPending`, `isFetching`, or `data === undefined` immediately after `renderHook`.
- Writing or porting tests for `@tanstack/react-query` hooks (`useQuery`, `useMutation`, `useInfiniteQuery`).
- A coverage report shows lines green inside an API hook but the hook's success / error branches are never visibly exercised.
- A reviewer asks "if this hook returned the wrong shape, would the test fail?" and the answer is no.

## When NOT to use

- The original test is already adversarial (resolves the fetch, asserts on returned shape, asserts on error path). Then no companion is needed; just maintain the one file.
- The hook has no async behavior. Synchronous selectors / derived state can be tested directly without the fetch boundary.
- The test is a snapshot or visual regression test that intentionally captures one specific render state.

## The pattern

The adversarial file lives next to the original with the `.adversarial.test.ts` suffix:

```
frontend/src/app/api/
  engineering.ts                       (production hook)
  engineering.test.ts                  (existing -- often tautological)
  engineering.adversarial.test.ts      (new -- resolves and rejects)
```

The adversarial file installs `vi.stubGlobal("fetch", ...)` (Vitest) or the equivalent Jest mock, returns one canned response per endpoint, awaits the hook to settle via `waitFor`, and asserts on the actual values:

```ts
/**
 * Adversarial tests for engineering API hooks.
 *
 * The existing engineering.test.ts only checks the initial loading state -- it
 * never resolves or rejects the fetch. All three tests in that file are
 * tautological: any useQuery hook starts in isLoading=true with data=undefined.
 * These tests expose the missing coverage.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import React from "react";

import { useIssueStats, usePrStats, useBoardStatus } from "./engineering";

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return function Wrapper({ children }: { children: React.ReactNode }) {
    return React.createElement(
      QueryClientProvider,
      { client: queryClient },
      children,
    );
  };
}

const validIssueStatsResponse = {
  weeks: [
    { weekStart: "2026-03-23", created: 10, closed: 8, bugs: 2, closeRate: 80.0 },
    { weekStart: "2026-03-16", created: 5,  closed: 5, bugs: 0, closeRate: 100.0 },
  ],
  openBacklog: 42,
};

beforeEach(() => {
  vi.stubGlobal(
    "fetch",
    vi.fn((url: string) => {
      if (url.includes("/engineering/issue-stats")) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve(validIssueStatsResponse),
        });
      }
      return Promise.resolve({ ok: false, status: 404 });
    }),
  );
});

afterEach(() => vi.unstubAllGlobals());

it("resolves issue stats with the real shape", async () => {
  const { result } = renderHook(() => useIssueStats(), { wrapper: createWrapper() });
  await waitFor(() => expect(result.current.isSuccess).toBe(true));
  expect(result.current.data?.weeks).toHaveLength(2);
  expect(result.current.data?.openBacklog).toBe(42);
});

it("surfaces failure as isError, not silent undefined", async () => {
  vi.stubGlobal(
    "fetch",
    vi.fn(() => Promise.resolve({ ok: false, status: 500 })),
  );
  const { result } = renderHook(() => useIssueStats(), { wrapper: createWrapper() });
  await waitFor(() => expect(result.current.isError).toBe(true));
});
```

The companion file is **not** a replacement for the original test -- it is a parallel file that addresses the gap. Original `engineering.test.ts` may still cover render-time concerns; the `.adversarial.test.ts` covers behavior. Over time, when the original is rewritten to be adversarial, the companion can be folded back in.

## Common gotchas / variants

- **Disable retry in the test `QueryClient`.** With `retry: 3` (the react-query default), failure-path tests take ~30s and intermittently flake. Pass `defaultOptions: { queries: { retry: false } }` in the wrapper.
- **Use `waitFor`, not `setTimeout`.** Per the project's testing rule, no manual delays. `waitFor(() => expect(result.current.isSuccess).toBe(true))` polls deterministically.
- **Match the response shape exactly.** A fetch mock that returns `{ data: ... }` when the hook expects `{ weeks: ... }` will silently fail-cast at runtime; the test then errors instead of asserting. Mirror the OpenAPI / contract response precisely.
- **Mock `fetch`, not the hook itself.** Mocking the hook turns the test into a tautology of a different kind: you assert that the mock returned the value you set. Mock the boundary (the network call), not the unit under test.
- **Add a 4xx case as well.** A test that only proves the success path is half a test. Adversarial files should include at least one rejection per endpoint (404, 500, network error / `Promise.reject`).
- **`vi.unstubAllGlobals()` in `afterEach`.** Forgetting this leaks `fetch` into the next test file when run with `pool: "threads"`.
- **Name the file `.adversarial.test.ts`, not `.adversarial.spec.ts`.** Vitest config's `include` pattern in this codebase keys on `.test.ts(x)`. Spec files in `frontend/e2e/` are Playwright; the unit-test runner is separate.
- **Do not delete the tautological original silently.** The adversarial companion exists precisely to make the gap visible. Once the gap is closed (i.e. the original is rewritten to assert on real values), squash the two files; until then, both files document the diff between "what the test claimed" and "what the test actually proved".

## Verification

The companion is doing its job when:

1. The companion file exists in the same directory as the original, with the `.adversarial.test.ts` suffix.
2. The companion mocks `fetch` with `vi.stubGlobal` (or Jest equivalent) and returns at least one resolved 2xx response and at least one rejected / 4xx-or-5xx response per endpoint.
3. Every test in the companion has at least one assertion on `result.current.data` or `result.current.error`, not just on `isLoading` / `isPending`.
4. Each companion test ends with `await waitFor(...)` so the hook has reached its terminal state.
5. The companion file's top-of-file comment explicitly describes the gap the file is closing.
6. Running the companion alone (without the original) produces failures if the production hook is broken -- prove this once, locally, by deliberately breaking the hook and watching the companion fail.

## References

- Companion: `stubborn-frontend-stubs` -- when adversarial assertions need contract-driven response bodies instead of hand-rolled `validIssueStatsResponse` literals, route them through the SCC stub server.
- Companion: `three-layer-test-architecture` -- adversarial unit tests live in Layer 2 alongside the rest of the frontend test suite.
