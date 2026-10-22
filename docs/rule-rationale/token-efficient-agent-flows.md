# Rationale — token-efficient-agent-flows.md

## Why

The orchestrator is the most expensive model and re-pays its entire context every turn (caching softens
this only within the provider's short TTL — a long build with idle gaps re-reads at full price). Spawned
agents are cheaper and **ephemeral**: their context is built for one task and discarded. So the cost-optimal
shape is: **keep the orchestrator's resident context minimal, push heavy reading into the ephemeral agents,
and give each agent only its slice.** Inlining file contents or the full ruleset into a brief pays for that
content twice — once in the orchestrator's transcript, once in the agent — and forever in the orchestrator
(it stays resident and re-billed every later turn).

## Calibration

Extracted 2026-06-10 from an Opus-orchestrator build (composer builder + sonnet review/watch). Early in the
session the orchestrator read several full source files itself to "understand" before delegating; that
content stayed resident and was re-billed on every later turn (and cold-re-read after each ~15-min verify
gap). The fix that worked: pass the builder/watcher only paths + role rules + the exact proof line to return,
and verify via `grep` of one result line and short agent verdicts. The sonnet PII review, given just the diff
+ the single "no-PII" dimension, caught a real leak in a ~25-line verdict without the orchestrator reading the
files at all.

## Cross-references

- `orchestrator-rules-lazy-index.md` — scopes *rules*; this rule generalizes to all context a flow moves.
- `tmux-agent-worktree-isolation.md` — parallel builders need isolation.
