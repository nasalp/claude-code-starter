# Event-Driven Orchestrator Observation (Monitors + Backstop Tick, Not Continuous Polling)

## Priority

| Priority | Meaning |
|---|---|
| **RECOMMENDED** | Best practice; default observation model for multi-builder orchestrator |

## Rule

`tmux-agent`/multi-builder orchestrator MUST observe builders, assessors, gates **event-driven** — arm one **Monitor per long-running unit that fires instant unit reaches terminal state** — plus **single fixed-interval backstop tick** (cron / `ScheduleWakeup`) as safety net. MUST NOT busy-poll or continuously `tmux capture-pane`/`tail -f` live builder output on tight loop to "keep an eye on it."

Orchestrator job between events: **idle**, not spin. State changes come as notifications; orchestrator reacts in seconds, otherwise sleeps. Backstop tick guarantees full sweep even if Monitor mis-armed.

Cost-efficient inversion of "watch builder constantly": instead of orchestrator paying attention (and tokens) every poll cycle, each unit signals once when it has news.

## What is required

### 1. One Monitor per terminal-state signal

Every builder / assessor / e2e / full-verify run: arm Monitor whose command exits (emits) when unit reaches **terminal** state — grep covers BOTH success and failure signatures so silence never masks crash:

```
# emits the moment the builder finishes (success OR failure), then exits
until grep -qE 'BUILD-<id> EXIT|BUILD SUCCESS|BUILD FAILURE' "$out"; do sleep 40; done
```

Gate completion check on **wrapper-emitted sentinel** unit cannot produce early (`<TASK>-<id> EXIT`), NOT token also in brief agent echoes (e.g. `VERDICT:` is in assessor brief — grepping it fires on echo, not verdict). Read real result from tail after sentinel.

### 2. Exactly one fixed-interval backstop sweep

Single recurring tick (e.g. 20-minute cron) does full one-by-one sweep of every machine + refreshes tracking issue. Catches anything per-unit Monitors missed (Monitor timed out, unit re-dispatched onto new sentinel, host unreachable). Backstop interval = **maximum** time orchestrator can be blind — pick from how fast you must react to stall, not how fast units finish (units finishing already covered by their Monitors).

### 3. React on the event, verify state independently, then re-arm

On each Monitor event orchestrator: reads unit's real output, **independently verifies durable state** (git committed+pushed? PR open? gate truly green? — never trust bare `EXIT 0`), acts (merge / correct / dispatch next), then re-arms fresh Monitor for whatever it just started. Re-dispatching unit changes sentinel — old Monitor stale; stop it, arm new one rather than letting stale `seen`-flag linger.

### 4. Push, don't pull, the urgent signals

When event is something human would act on **now** (build went red and queue stalled, consensus REJECT can't auto-resolve), send `PushNotification`. Routine completions don't warrant one. Orchestrator surfaces; human need not poll it either.

## What is forbidden

| Anti-pattern | Why |
|---|---|
| Tight `while true; tail/capture-pane; sleep 5` loop on each live builder | Burns tokens/attention every cycle for news that arrives only at phase boundaries |
| Trusting builder's `EXIT 0` / `BUILD SUCCESS` as "done" without verifying git/PR/gate state | Connection can drop at final commit/push, leaving work uncommitted under green-looking exit |
| Monitor exit-condition greps token echoed from brief (`VERDICT:`, `SIGN-OFF:`) | Fires on echo, falsely reporting completion |
| Monitor greps only success marker | Goes silent through crash/hang — silence reads identical to "still running" |
| Many overlapping backstop ticks at different intervals | Redundant full sweeps; one backstop enough alongside per-unit Monitors |

## What is allowed / encouraged

- Genuinely continuous **single** persistent watcher when in-flight catching worth cost (see `watchers-must-observe-live-tmux.md`) — rule does not forbid live watchers; forbids orchestrator *itself* busy-polling. Two models compose: live watchers (when used) observe pane; orchestrator observes watchers + builders **event-driven**.
- Batching several units under one Monitor that exits when all reach terminal (single `ALL-N-DONE` emit), to bound armed Monitors.
- Short focused inline check at start of each backstop tick (one-by-one per machine) — that's the sweep, not continuous polling.

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/event-driven-orchestrator-observation.md`
