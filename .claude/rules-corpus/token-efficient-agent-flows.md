# Token-efficient multi-agent flows: every node loads only what its role needs

## Priority

| Priority | Meaning |
|---|---|
| **RECOMMENDED** | Best practice; default operating posture for any orchestrated build |

## Rule

Multi-agent flow (orchestrator + builder + watchers/reviewers): **every node carries smallest context that lets it do its job** — orchestrator **passes each agent scoped packet, not everything it knows**. Orchestrator stays lean by delegating reading; verifies via **cheap signals** (exit codes, greps, short structured verdicts) not whole files/outputs back into its context.

Generalizes `orchestrator-rules-lazy-index.md` (scopes *rules*) to **all** context a flow moves: rules, skills, file contents, specs, prior-agent outputs.

## What is required

### Orchestrator stays lean
- **Don't read what agent can read.** Agent Read files for its task; orchestrator passes **paths**, not pasted bodies.
- **Verify via cheap signals**: build/test **exit code**, `grep` of one result line, or **short structured verdict** (`VERDICT: APPROVE/REJECT + reasons`). Do NOT re-load full diffs, build logs, or files into orchestrator to confirm — redirect logs to file, grep verdict.
- Boot with rules **index + coordination rules only** (per `orchestrator-rules-lazy-index.md`); fetch rule body on demand.

### Builder packet = task + role rules + paths + locked decisions
Builder brief contains **only**: task, **role-scoped rules** (Java / testing / SQL / etc. via `select-rules.sh` / `gen-packet.sh`), **file paths** to touch (builder reads them), **locked decisions** it must not re-litigate, **proof** it must return (exact command + success line to paste). Does **not** contain: full ruleset, orchestrator transcript, unrelated specs, pasted bodies of files builder will open anyway.

### Watcher/reviewer packet = artifact + audit dimension + its rules
Watcher/reviewer brief contains **only**: **artifact/diff** (or path + diff-base to compute it), **single audit dimension** it owns (PII, security, coverage, arch-boundary, …), **rules for that dimension**. No rule bodies for dimensions it doesn't audit. Returns **short verdict**, not re-dump of what it read.

### Pass paths, not contents
Default: hand agent **path + line range + diff-base**; inline snippet only when few lines and agent genuinely cannot resolve itself. Agent reads into **own** budget; orchestrator budget not charged for that content on every subsequent turn.

### Parallelize independent work; fail-at-end to collapse gate-peeling
Idle wall-clock = **token** cost: long sequential wait (15-min build) lets orchestrator prompt cache go cold → next turn re-reads whole context at full price. Shorter, fewer, parallel waits keep cache warm.
- **Surface all failures in one pass.** Run quality gates with **fail-at-end** (Maven `-fae` / `--fail-at-end`, test runners' no-fail-fast) so ONE run reports *every* failing gate, not just first. Fail-fast pipeline revealing ArchUnit, then SpotBugs, then PMD, then coverage across four separate 15-min runs = four cold-cache gaps for what could be one.
- **Run independent checks concurrently.** Fan independent gates / suites out as parallel background jobs; collect together (mind shared build-dir contention — use build tool parallelism, e.g. Maven `-T 1C` + parallel test execution, or separate output dirs).
- **Parallel builders need isolation.** Two builders cannot edit one working tree at once — give each **git worktree** (per `tmux-agent-worktree-isolation.md`) when fixes independent; keep dependent fixes in one builder. Spawn independent agents in **single batch** so they run concurrently, then verify once after converge.

## What is forbidden

- Pasting **full ruleset** (or large rule bodies for irrelevant roles) into any agent brief.
- Inlining **large file contents** into brief when path + range would do.
- Orchestrator **reading whole files / full build logs** to verify when exit code, one-line grep, or agent verdict answers the question.
- Giving watcher rule bodies for dimensions it doesn't audit, or builder the review rules, etc.
- Treating cache/compression proxy as license to load everything — lowers unit price, not bill for content nobody needed.

## What is allowed

- Inlining **short** snippet (few lines) when resolving path is more expensive than snippet.
- Loading broader context in **single-session non-orchestrated** run (one model plans + builds, no fan-out) — no hand-off to scope.
- Deliberately **wide** audit packet when one reviewer genuinely owns multiple dimensions — scope to *those* dimensions, still not whole ruleset.

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/token-efficient-agent-flows.md`
