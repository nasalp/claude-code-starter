---
topic: process.planning
name: Consensus plan runs per work unit, not per session
description: Phase 2 (3-agent plan-consensus) MUST run at every work-unit boundary — every new feature, every new PR scope, every meaningful scope expansion — not just once at session start. A long-lived orchestrator that ran consensus on its first chunk and ad-hoc-investigated everything after is the failure mode this rule names.
type: rule
tier: canonical
status: promoted
proposed-on: 2026-06-01
promoted-on: 2026-06-01
---

# Consensus plan runs per work unit, not per session

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

`tmux-agent` Phase 2 (3-agent plan-consensus — 2 codex + 1 claude opus, see `.claude/skills/tmux-agent/docs/phase-2-plan-consensus.md`) MUST run at the start of **every work unit** the orchestrator handles, not just once at session start. Long-lived orchestrator that opened Phase 2 for its first chunk then fell back to "my own investigation + AskUserQuestion clarifications" for chunks #2, #3, … = the failure mode this rule names.

Decision is per-work-unit, not per-session. Session can contain N work units; Phase 2 fires N times.

## What counts as a "work unit"

Any one of these triggers a fresh Phase 2 run:

| Trigger | Examples |
|---|---|
| A new feature kickoff in the same session | "now let's build the Pilot V1 dashboard"; "next chunk: snapshot-report live-data" |
| A new branch cut from main (or any non-build-branch base) | `git checkout -b feat/foo origin/main` for a different feature than the one currently in flight |
| A new PR scope (different AC IDs, different bounded context) | a feature PR following an earlier harness PR — different ACs, different files, different surfaces |
| A scope expansion of an existing in-flight PR beyond the originally-planned file set | original plan touched 8 files; new ask adds a 4th frontend page and 2 backend endpoints → re-plan |
| A scope re-orientation triggered by a discovered constraint | mid-build finding that the original plan's data source doesn't exist → re-plan around the operator decision |
| The session resumes after a reboot / context-compact / multi-hour gap | the in-memory plan-of-work is gone; the orchestrator MUST re-plan from the PR body + git state, not from its faded recollection |

In doubt: re-plan. Extra Phase 2 pass (3 agents × small plan-generation token budget) is trivial vs shipping a chunk under an ad-hoc plan that never got codex+claude triangulation.

## What is required

### 1. The plan-of-work artifact

Every Phase 2 run produces a single **plan-of-work** markdown file, committed to the branch under `docs/plans/<YYYY-MM-DD>-<work-unit-slug>.md`, containing:

- The mission statement (what the user asked for, verbatim)
- The locked decisions (D1, D2, … format from Phase 1)
- The 3 independent agent plans (or summaries thereof) AND the diffs between them
- The synthesised plan-of-work: phase order, file list, test list, risks, success criteria
- The watcher composition for this work unit (codex/claude split)

The committed file is the PR body's source of truth and the session-resume substrate. The PR body links to it, and the orchestrator updates the PR body from this doc.

### 2. The orchestrator self-check

Before opening or extending a chunk of work, the orchestrator MUST answer **out loud** (to the user / to the log):

> "Is this a new work unit per
> `consensus-plan-per-work-unit.md`? If yes → Phase 2. If no → cite
> the existing plan-of-work doc this work falls under."

A silent skip is the defect this prevents. The audit-trail sentence MUST appear in either:

- The orchestrator's response to the user that opens the work unit, OR
- The first commit body of the work unit ("Per plan-of-work `docs/plans/2026-06-01-pilot-v1.md`, this commit lands Phase 1 of …").

### 3. The "5-agent fan-out analysis" is NOT a substitute

A wide investigation pass ("5 parallel analysis agents map the AC → test landscape") is a legitimate INPUT to Phase 2 — better source material for the plan-generation agents — but it is NOT itself Phase 2. Phase 2 is specifically: **3 fresh independent agents, DIFFERENT model families, each produces an end-to-end plan, then the orchestrator picks the consensus or surfaces disagreement**.

A 5-agent fan-out + locked decisions is closer to a deep Phase 1 than to Phase 2. The plan-of-work doc MUST cite both the fan-out OUTPUT and the 3 independent plans Phase 2 produces.

### 4. Direct scope decisions + AskUserQuestion are NOT a substitute

The orchestrator may use `AskUserQuestion` to clarify decisions during Phase 1 (the canonical Phase 1 mechanism). It MUST NOT substitute `AskUserQuestion` clarifications for Phase 2's multi-agent plan generation. They answer different questions:

| Mechanism | Answers |
|---|---|
| `AskUserQuestion` | "Which option does the operator want? Which approach is acceptable?" |
| Phase 2 plan-consensus | "Given the operator's answers, what's the right phase ordering / file decomposition / test strategy? Where do experienced independent agents disagree?" |

Skipping Phase 2 because Phase 1 was thorough conflates the two.

## What is forbidden

| Pattern | Why |
|---|---|
| Long-lived orchestrator session that ran Phase 2 once and ad-hoc-plans every chunk thereafter | The discipline that protects work unit #1 does not protect work units #2-N; quality regresses |
| Treating a multi-agent FAN-OUT analysis as Phase 2 | Fan-out maps the terrain; Phase 2 produces independent end-to-end plans. Different artifact, different protection |
| Treating `AskUserQuestion` clarifications + orchestrator investigation as Phase 2 | Same conflation — that's Phase 1 + execution, not plan-consensus |
| Per-feature investigation writeups in the brief instead of a plan-of-work doc | Investigation belongs in Phase 2 input; the plan-of-work is the synthesised output |
| "We're under time pressure, skip Phase 2 this time" | The cost is trivial; the bypass becomes permanent |
| Session resumes after compaction / reboot without re-planning | In-memory plan is gone; ad-hoc reconstruction from faded recollection is the worst-quality plan-generation mode |

## What is allowed

- ONE Phase 2 plan-of-work doc covering MULTIPLE small related work units when they were planned together at the same time. Example: "Phase 2 produced one plan for AC-harness #424 + Pilot V1 #428 + snapshot-report #430 together." Fine when the doc actually exists and covers all three. NOT a license to retroactively call the AC-harness plan a cover for two later chunks that were not in the original scope.
- Skipping Phase 2 for trivial one-line fixes — same exception as `build-via-orchestrator.md` carves for the broader skill ("≥ 5 sub-deliverables" threshold). If the work doesn't trigger the orchestrator, it doesn't trigger Phase 2 either.
- Re-using the previous Phase 2's locked decisions when the new work unit is genuinely a continuation. The decisions don't re-litigate; the plan is what re-runs.

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/consensus-plan-per-work-unit.md`
