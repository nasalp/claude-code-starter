---
roles: [watcher, reviewer, arbitrator, reconciler]
severity: critical
model_tiers: [premium, standard, cheap]
applies_to:
  task_types: [review]
---

# Mutual Watcher Cross-Audit + Orchestrator-Consumes-Verdicts Loop — nobody trusts nobody

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

In a multi-agent build (tmux-agent: 1 builder + N watchers + orchestrator), **no agent's output
is trusted without verification, and no REJECT may die unconsumed.** Two structural requirements:

1. **Watchers cross-audit each other, not just the builder.** Each watcher, every pass, audits the
   builder's live work AND spot-checks the *other watchers'* latest verdicts — is a peer's verdict
   substantive and correct, or empty / BLIND / rubber-stamping / wrong ("full of shit")? A watcher
   that flags a peer's bogus APPROVE (or a peer that missed a real defect) is doing its job.
2. **The orchestrator runs a PERSISTENT LOOP and is the consumer-of-record for every verdict.** Every
   cycle, it observes ALL watchers + the builder and MUST:
   - confirm each watcher produced a **non-empty, non-BLIND** verdict this pass (a watcher whose
     `.md.body` is empty or whose diagnostic says BLIND is NOT auditing — re-spawn / fix it);
   - **read and act on every REJECT** — relay it to the builder, or fix it, before proceeding;
   - **refuse to merge / declare done while any REJECT (builder-watcher OR cross-audit) is
     unaddressed.**

The proven failure mode this prevents: a watcher produces a *correct* REJECT and **nobody consumes
it** — the orchestrator checks the watcher is alive, never reads its verdict, and merges past real
defects. Liveness ≠ consumption.

## What is required

### 1. Cross-audit, bounded (no N² blowup, no infinite regress)

- Each watcher's brief includes: "Each pass, after auditing the builder, read the latest verdict of
  each *other* watcher (`$RUN_DIR/verdicts-<peer>/`) and flag in your output any peer verdict that is
  empty/BLIND, rubber-stamps without diff-grounded evidence, or contradicts the diff you just read.
  Emit a `=== PEER-CHECK ===` block: `peer: <tag> | verdict: APPROVE/REJECT/EMPTY | concur: yes/no |
  reason`."
- **Bound the cost** (per `multi-agent-model-routing.md`): cross-checks **sample/rotate** — a watcher
  need not deeply re-derive every peer's full audit every pass; a substantive-vs-bogus spot-check is
  enough. Watchers run on cheap engines (codex / Sonnet), ≤1 Opus per the calibrated split.
- **The chain terminates at the orchestrator.** Watchers check the builder + peers (one hop). The
  orchestrator checks the watchers. There is NO watcher-watcher-watcher — the orchestrator is the
  terminal auditor, so regress is bounded.

### 2. The orchestrator loop (the consumer-of-record)

Run the orchestrator audit as a persistent loop (the `/loop` skill, or the tmux-agent orchestrator
cadence). Every cycle it MUST, for the builder and EACH watcher:

```
for each watcher W:
  - verdict = latest $RUN_DIR/verdicts-W/*.md (+ .body)
  - assert verdict is non-empty AND diagnostic sha != NONE/BLIND
    # on failure, branch the action — DO NOT blindly re-spawn:
    #   - if branch not yet on origin → BLIND is expected (per 2026-05-29-watcher-blind-spot.md);
    #     wait or prompt the builder to push, do NOT re-spawn
    #   - if branch IS on origin and W is dead/stale → re-spawn W (it is not auditing)
    # unconditional re-spawn-on-BLIND is an infinite token sink.
  - if verdict == REJECT: record the finding; it is now BLOCKING
  - read W's PEER-CHECK block; if a peer flagged another watcher as empty/bogus: act (re-spawn / discount)
gate: MERGE/DONE is forbidden while any recorded REJECT is unaddressed (acted-on + re-audited clean)
```

The orchestrator does NOT take the builder's "done" or a single APPROVE at face value — it
independently reads the diff for the highest-risk claim (e.g. "renders real data" → confirm the test
loads the REAL component, not a hand-built mock; "no score/tier" → confirm a rendered-DOM assertion,
not just an API-body check).

### 3. Watch the live STREAM, not just pushed commits (react in-flight)

The canonical `launch-builder.sh` runs the builder as `claude --print --output-format=stream-json
... > builder.out 2>&1` — **stdout/stderr are redirected to a file, so the builder's tmux pane is
EMPTY.** A watcher that only `tmux capture-pane`s the builder session captures **nothing**, and the
"LIVE BUILDER TMUX PANE" block from `watchers-must-observe-live-tmux.md` comes out blank. The real
live signal is **`builder.out` itself** — the stream-json of the builder's thinking + tool calls.

So each watcher pass MUST feed the **recent CONTENT of `builder.out`** (e.g. `tail -c 50000`, decoded
text + tool-call names/args) into the audit — NOT merely use its byte-size as an activity tripwire and
then audit only the pushed git commit. Auditing only the pushed commit makes the watcher react **a
commit behind**: it sees a defect (e.g. a fake `page.setContent(handBuiltHtml)` "render" test) only
*after* it's committed + pushed — when the cheapest moment to stop it was while the builder was
*writing* it. Per-pass input = live `builder.out` tail (in-flight actions) **+** the pushed diff. If
the live stream shows the builder about to do something forbidden (a mock-render test, a suppression,
an out-of-scope edit), **REJECT now**, before the commit. (If a build is launched WITHOUT the
redirect so the pane is live, `capture-pane` is the equivalent signal — the point is "observe the
in-flight work," whatever surface carries it.)

### 4. Optional dedicated meta-watcher (≥3-watcher fleets)

When running ≥3 watchers, ONE may be a dedicated **meta/loop-health watcher** whose sole job is the
audit-loop itself, not the code: are the other watchers producing non-empty/non-BLIND verdicts each
pass? Did the orchestrator ACT on every REJECT (or is one going stale)? It does NOT re-audit the code
(that's the builder-watchers' job) — it audits the *process*. Cheapest way to guarantee "REJECTs
can't die unconsumed" without the orchestrator being the only safeguard.

## What is forbidden

| Pattern | Why |
|---|---|
| Orchestrator checks watcher *liveness* but never reads the *verdict* | Liveness ≠ consumption; the 2026-06-01 lapse |
| Merging / declaring done with an unaddressed REJECT (builder-watcher or peer-check) | A REJECT that doesn't block is decoration |
| Treating a single watcher's APPROVE as sufficient with no cross-check or orchestrator re-read | Single point of audit failure |
| Counting an empty/BLIND watcher pass as a real audit | It audited nothing |
| Full N²-every-pass cross-audit, or watcher-watcher-watcher chains | Cost blowup + infinite regress; sample + terminate at orchestrator |

## What is allowed

- Sampling/rotating cross-checks to control cost.
- A watcher APPROVE that the orchestrator independently re-confirms on the highest-risk claim.
- The orchestrator relaying a REJECT to the builder and re-auditing after the fix (the normal loop).

> Rationale (Why/Calibration/Cross-refs): docs/rule-rationale/mutual-watcher-cross-audit.md
