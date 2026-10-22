# Audit Warning Loop

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Agents MUST address warnings; scripts MUST NOT hard-block on findings |

## Rule

During active `tmux-agent` run, audit scripts emit structured WARN lines agents MUST read and address in next orchestration, watcher, or builder response.

Contract:

```text
WARN <category>: <short description>
```

Warnings ≠ hard blocks. Check exits 0 when it finds rule violation and prints one+ WARN lines on stdout. Check exits non-zero only when script itself cannot run (invalid args, missing run state, unreadable repo).

## Categories

| Category | Example |
|---|---|
| `proof-blank` | `WARN proof-blank: docs/proof/phase-7.md cites chart.png with 3 unique colors` |
| `proof-404` | `WARN proof-404: release asset proof-pr254-cycle4/chart.png could not be downloaded` |
| `watcher-stale` | `WARN watcher-stale: approved proof command failed: ./mvnw test` |
| `no-red-commit` | `WARN no-red-commit: fix: repair snapshot writer has no preceding related RED test commit` |
| `mock-on-it` | `WARN mock-on-it: CustomerHealthSnapshotWriterJobIT.java uses @MockitoBean in integration test` |
| `pr-owned-mutation` | `WARN pr-owned-mutation: PR-owned mutation score 50% below 80%` |
| `regex-over-source` | `WARN regex-over-source: source-shape.test.ts reads source text and asserts regex/string shape` |

## Required Agent Behavior

1. Orchestrator MUST keep Monitor alive for active run; surface WARN lines in run transcript.
2. Watcher wrappers MUST prepend current WARN lines to each watcher brief before invoking model.
3. Watcher verdicts MUST explicitly address current WARN lines before approving.
4. Builder prompts and PR comments MUST treat WARN lines as review feedback — fix or rebut with evidence.
5. Repeated warnings MUST NOT be silently ignored because later check passes; agent MUST explain corrective action or why warning no longer applies.

## What Is Forbidden

| Anti-pattern | Why |
|---|---|
| Exiting non-zero because a finding exists | Converts warning checks into hard blocks; invites bypassing. |
| Printing non-`WARN` findings for agent action | Breaks grep/dedupe; warnings easier to miss. |
| Adding silent skip branches around risky repositories, languages, or phases | Creates bypass surface the loop exists to close. |
| Treating a warning-free run as proof the feature is correct | Loop is mechanical signal, not substitute for review. |

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/audit-warning-loop.md`
