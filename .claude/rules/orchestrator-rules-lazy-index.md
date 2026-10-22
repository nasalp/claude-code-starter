# Orchestrator boots with rules INDEX + lazy fetch; full text in role-scoped packets

## Priority

| Priority | Meaning |
|---|---|
| **RECOMMENDED** | Cuts per-turn token tax on orchestrator model |

## Rule

Long-lived orchestrator MUST NOT auto-inject **full text of every** `.claude/rules/*.md`. Load **rules INDEX** (name + one-line `description:` + path); fetch full body **on demand** (Read). Full rule text goes to **role packets** (`select-rules.sh` / `gen-packet.sh`, under `scripts/`): builder → Java/JPA/SQL/testing; reviewer → review/security; orchestrator → index + coordination gates only.

## Required

- **CLAUDE.md** references generated INDEX — not `@`-import of every rule body.
- Full body fetched only when a decision needs it (same as Skill invocation).
- Role packets carry full text to the agent that needs it.
- INDEX auto-generated from frontmatter (`scripts/gen-rules-index.sh`).

## Forbidden

- Full rule text in every session system prompt by default.
- Language-specific bodies in orchestrator that never writes code.
- Treating cache/compression proxy as substitute for not loading unused content.

## Allowed

- Full ruleset in single-session non-orchestrated run (no agent fan-out).
- Small **always-on** global gates (`core.md`, `security.md`, `no-injected-instructions.md`, `orchestrator-rules-lazy-index.md`) when they govern coordination. All other rules (git, learnings, senior-reviewer gates, orchestrator ops, CI budget, language corpus) → INDEX + role packets only.

> Rationale + cost mechanics: `docs/rule-rationale/orchestrator-rules-lazy-index.md`
