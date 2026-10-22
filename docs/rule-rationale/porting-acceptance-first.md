# Rationale: porting-acceptance-first

---
topic: testing.acceptance
name: Language-port acceptance-first rule
description: Rewrites between languages MUST start by pinning the source's full behavior in a language-agnostic acceptance suite, run against the SOURCE until green. Only then port the target. Anything else is rewriting from intuition.
type: feedback
tier: canonical
calibrated-against: mcp-server Python→Java port (2026-05-09)
status: promoted
proposed-on: 2026-05-25
promoted-on: 2026-06-01
---

## Promoted from `_proposed/` on 2026-06-01

Originally promoted-from `mcp-server/spec/learnings/porting-acceptance-first.md`
under the Tier-1 grace-period convention (proposed 2026-05-25, grace
through 2026-06-24). Promoted to canonical on 2026-06-01 ahead of
grace expiry: the rule has been referenced from multiple downstream
PRs (Java MCP-server port + tmux-agent migration workflow) since
proposal. Solo-operator mode acknowledged — no second-project
authorship corroboration was achieved during the grace window.

## Why

"Envelope" tests (status 200, response has the right shape, no exception) look like coverage but check almost nothing. A target that passes envelope tests can silently send wrong field names, skip merge steps, drop optional params, hardcode defaults, fabricate response data — and the suite stays green. You discover the divergence only in production, when the backend rejects the call or returns garbage, or when a caller tries to use a feature that "exists" but was never reachable.

## How to apply

- Before writing line one of target code, list every source tool / endpoint / function. For each, *read the entire file*, not just the obvious wire call. Note: every conditional, every default injected by the source, every upstream call in order, every response field populated.
- Convert that list into per-behavior assertions in the acceptance suite. Each source-side `if` branch is at least one test. Each upstream call is asserted with a full body/query predicate. Each response metadata key has its own assertion.
- Run that suite against the source. If anything fails, the suite is wrong — fix the suite, not the source. Source is ground truth by definition.
- Only when the suite is green against the source do you start the port. Now the suite is your contract; the target is correct iff it's green.

## Calibration note (single-project, do not over-generalize)

The originating Python→Java MCP-server port measured the
following ratios on its specific tool shape (50 MCP tools, ~200 lines
each, FastMCP envelope with `_meta` keys):

- 20–40 acceptance tests per 200-line tool (per-conditional + per-upstream-call + per-meta-key)
- 50 tools × 20–40 = 1000–2000 tests total
- A suite with 5 tests per tool was empirically 20% coverage (8 of 50 tools later showed silent drifts)

These numbers are **calibrated against one codebase shape**. Do NOT
read them as fleet-wide norms — a REST CRUD service or a CLI tool will
have a different ratio. The principle is "enumerate every observable
behavior", not "20–40 tests per file."

## Anti-pattern (what NOT to do)

- Writing the suite against intuition / spec docs / hand-wavy "acceptance criteria" — these always under-specify what the source actually does.
- Writing the suite against the *target* (or both) — then green just means target matches itself.
- Iterating "fix the failure, declare green" — closes only what's pinned; the un-pinned remainder silently diverges. The originating incident: 23 failures in a 390-test suite shown as "fully green," then a deep audit found ~80 additional drifts (18 of them production-blocking data-loss bugs).
- Treating envelope tests (HTTP 200 + request-id present) as "the tool works." They prove nothing about wire shape, response correctness, or feature parity.
- Trusting the wire-contract document to be complete. It's a guide, not a contract — the contract is the assertions in the suite.

## Cross-references

- `.claude/rules/core.md` Rule 2 (Test First / ATDD + TDD) — this rule is a specialization for the language-port scenario.
- `.claude/rules/legacy-code.md` "characterization tests" — structurally similar (test what you have before changing it); this rule is the wholesale-rewrite version.
- `.claude/skills/hexagonal-architecture/SKILL.md` "No big-bang rewrites" — preserves behavior with characterization tests; this rule operationalizes that for cross-language ports.

## 3-agent panel verdicts (2026-05-25)

- **Architect:** APPROVE — distinct mechanism with clear enforcement story, no overlap in existing harness, generalizes cleanly across language pairs.
- **Field Engineer:** APPROVE — would have caught the original 18 production-blocking data-loss bugs; drift-resistant (pins process, not framework versions); fills a genuine gap.
- **Adversary:** APPROVE with required narrowing — empirical ratios attributed to source project (above) rather than promoted as fleet norms. Tier 1 / `_proposed/` placement contains scope-creep risk into adjacent areas (infra/IaC migrations).
