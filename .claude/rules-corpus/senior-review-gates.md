---
universal: true
applies-to:
  - code-review
  - pull-request
  - ci-cd
  - deployment
  - java
  - mcp
roles: [reviewer, arbitrator, reconciler]
severity: critical
model_tiers: [premium]
applies_to:
  task_types: [review]
---

# Senior Review Gates

The gate: PR not ready because CI green; ready only when intended behavior specified first, tested first, proven by non-tautological tests, shown not to break compatibility.

Use before asking a code owner or any senior reviewer to approve a PR.

## Hard Reject Gates

Any answer "no" → mark `REJECT`, not `Ready for review`.

1. **Did work start with spec, ADR, or explicit acceptance criteria?**
   - Behavior changes need spec.
   - CI/CD, deployment, route, cache, auth, security, database, event, contract, MCP tool-wire changes = behavior changes.
   - "It only changes YAML" NOT exemption if runtime, deploy, or review behavior changes.

2. **Did tests come before implementation, or is test-first evidence explicit?**
   - PR must show failing test written first, or explain legacy correction and still include missing behavioral tests.
   - Existing green checks only prove existing checks still pass. Do not prove new behavior.

3. **Do tests assert behavior, not implementation?**
   - Tests must prove real input/output behavior.
   - Reject tests mirroring implementation logic, grep config text instead of exercising script, assert only that something exists, or test only mocks.

4. **Do tests cover meaningful input/output matrix?**
   - Include happy path, negative path, missing input, invalid input, boundary values, compatibility cases, side effects.
   - Single happy-path test not enough for behavior that branches.

5. **Are tests non-tautological?**
   - Reject `assertTrue(true)`, `expect(true).toBe(true)`, value-equals-itself assertions, tests with no assertions, snapshots without targeted behavioral assertions.
   - Reject "green by construction" tests that cannot fail when production code wrong.

6. **Does change preserve compatibility?**
   - Public API shape, route behavior, event payloads, database migrations, MCP tool schemas, CI outputs, cache semantics, auth behavior, deployment behavior must remain compatible unless spec declares versioned breaking change with migration path.

7. **Is code small enough to understand and test?**
   - Java production classes over 400 lines need explicit human approval.
   - Reject unless PR links that approval, includes strong reason, split plan, proof class still has one responsibility.

## PR Evidence Checklist

Every PR needing senior review MUST include:

```text
Spec or ADR:
Acceptance criteria:
Test-first evidence:
Input/output matrix:
Compatibility proof:
Behavioral tests:
CI/build proof:
Maintainability notes:
Known limits:
```

## Review States

| State | Meaning |
|---|---|
| `REJECT` | One+ hard gates failed. Do not ask for senior review. |
| `Ready for senior review` | Spec, tests, compatibility proof, CI evidence exist. Human review still required. |
| `Ready to merge` | Senior reviewer or code owner approved, all gates green, no merge blocker remains. |

## Controlled Beta Rule

Beta can ship with known product bugs, not with unverified engineering behavior.

Controlled beta releases:

- Automated tests must cover committed acceptance criteria.
- Playwright or equivalent E2E flows must cover main user journeys.
- Human must manually click through main flows before release.
- Agent reviews = review evidence, not final truth.
- Known limits written down before beta users touch system.
- Team must plan fast bug fixing after beta.

Do not call beta "production certified" because agents reviewed it. Call it tested controlled beta when evidence above exists.
