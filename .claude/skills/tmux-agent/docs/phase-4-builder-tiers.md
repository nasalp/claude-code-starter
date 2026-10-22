# Phase 4 addendum — Builder tiers + escalation (mixed-model)

Opt-in extension of Phase 4. Default behavior is unchanged except the builder model
default is now **sonnet** (was opus). See `docs/mixed-model-agents.md` for the full design.

## Feature flags (default OFF / safe)

| Flag | Default | Effect |
|---|---|---|
| `BUILDER_ENGINE` | `claude` | `claude` \| `cursor`/`composer` \| any provider in `agent-providers.yml` |
| `BUILDER_MODEL` | `sonnet` (claude engine) | model id; provider default on other engines |
| `WATCHER_ENGINE` | `claude` | unchanged historical default; `composer`/`codex`/… route via the registry |
| `WATCHER_MODEL` | `opus` (claude engine) | model id |
| `AGENT_ROUTE_<ROLE>` | — | override the routed provider for a role |
| `AGENT_MAX_*` | from `agent-routing.yml` | budget caps |

## Builder tier ladder

```
TIER 0 (default cheap)   composer / composer-2.5-fast
   │  escalate after N failed phase-GREEN attempts (builder_escalate_after_n=3)
   │  OR an unresolved watcher REJECT after 1 cheap round
   ▼
TIER 1 (escalated)       escalate_model (claude:opus, or codex)
```

The orchestrator tracks failed-GREEN attempts + unresolved REJECTs per **work unit** and
escalates via `scripts/lib/agent-escalation.sh::should_escalate`. Escalation is sticky for
that work unit and logged to the PR-body orchestration log (orchestrator owns the PR body).

## Watcher fleet (cheap-first)

Cost order (corrected): **composer (cheapest) < gemini-flash < gemini-pro < codex ≈ claude
(premium)**. Codex is priced ≈ Claude, so it is **NOT** a cheap watcher — it is a premium
second-opinion / escalation reviewer only.

Default cheap watcher fleet = **`composer` + `gemini-flash`** (`watcher_fleet` in
`agent-routing.yml`). These run on **distinct quotas** — Cursor (Composer) and Google
(Gemini) — so 2-quota isolation comes for free, with
no premium model in the loop. A premium **Opus** watcher is spawned **on veto only**
(disagreement or REJECT), reusing the weighted-veto in `mutual-watcher-cross-audit.md`.
Add Claude **Haiku** as an optional third watcher purely for a third (Anthropic) quota.

> **Cost-basis flag (operator decision):** `~/.claude/rules/watchers-must-observe-live-tmux.md`
> still codifies a default "2 codex + 1 claude-opus" fleet
> with a "codex is cheaper" rationale. That predates current pricing (codex ≈ claude). This
> PR does **not** silently rewrite those fleet-wide rules; it flags the discrepancy. Update
> them to the composer + gemini-flash basis when you're ready.

## Rules always hold (C1)

Every tier loads `~/.claude/rules`. Cursor `agent` (no `--add-dir`) gets the rule tree
staged into the worktree by `mount-rules-into-worktree.sh`; Gemini mounts it via
`--include-directories`. A cheaper model runs the SAME canonical local verify gate and the
SAME per-phase proof-of-work — cheaper model ≠ weaker gate.

## Verification spike (before defaulting the cheap path ON)

1. **Rules mount (Q2):** plant a sentinel rule; run
   `agent -p --workspace <wt> "name the rule under ./.cursor/rules"` and confirm it reads
   the mounted rules.
2. **Prompt delivery:** confirm `agent` reads the packet via stdin (the registry template
   uses `< {prompt_file}`); adjust `prompt_delivery` to `arg` if your CLI version differs.
3. **Billing (Q1):** capture Cursor usage + Headroom `:8787/stats` delta across one real
   build to confirm Composer is actually cheaper than the flat subscription before flipping
   the default.
