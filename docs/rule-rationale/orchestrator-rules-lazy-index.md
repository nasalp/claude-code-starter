# Rationale — orchestrator-rules-lazy-index

Deep context for `.claude/rules/orchestrator-rules-lazy-index.md`. Not auto-loaded.

## The cost model in detail

Each turn of a chat-completion API call re-sends the entire prefix (system prompt + full transcript so
far). Pricing is per input token on that re-send. Two mechanisms change the unit price but not the fact
of the re-send:

1. **Prompt caching** — the provider caches a marked prefix and bills cache-reads (~10x cheaper) on a
   hit. TTL is short (Anthropic ~5 min, refreshed on use). A hit requires the prefix to be byte-identical
   and still warm.
2. **Proxy compression / token reduction** (e.g. Headroom) — strips redundant content and manages cache
   breakpoints before the request leaves the machine. Observed in the calibrating session: large cache
   savings plus ~9% compression, ~3.7% average per-request token removal.

Neither extends the TTL. The orchestrator's failure mode is **idle gaps**: when it waits 10–20 min on a
`verify-like-ci` / CI build, the cache goes cold, and the next turn re-reads the **whole** ruleset at
full input price. Multiply by the number of such gaps in a long build session and the full-ruleset
overhead dominates.

## Why rules, not skills, are the problem

Skills are already lazy: only the one-line catalog entries live in context; a skill body is loaded by the
Skill tool on invocation. Rules, by contrast, are typically `@`-imported in full via CLAUDE.md, so every
rule's complete body is in the system prompt of every session — including an orchestrator that never
writes code and so never needs the Java/JPA/SQL/Spring rule bodies.

## Calibration (2026-06-10)

Opus-4.8 orchestrator session with full ai-rules ruleset re-billed every turn; 15-min `verify-like-ci` waits cold-cached context. Headroom softened (~9% compression) but cold-reload cost persisted. Skills lazy; rules dominant fixed overhead. Structural fix: index + lazy fetch + role packets.

## The fix is the existing role-packet machinery

The tmux-agent harness already ships `scripts/select-rules.sh` and `scripts/gen-packet.sh` to hand each
spawned agent a role-scoped rule subset (rules-block-first for cache discipline). The optimization is to
apply the same scoping to the **orchestrator's own** context: boot with a generated index + the
coordination rules (`core`, `security`, `no-injected-instructions`, CI/git/orchestration), and let the
builder/reviewer packets carry the language- and layer-specific bodies.

## Cross-references

- `~/.claude/skills/tmux-agent/scripts/select-rules.sh`, `gen-packet.sh` — role-scoped packets.
- `~/.claude/rules/parallel-cli-sessions.md`, `multi-agent-model-routing` — the fleet whose agents
  receive the scoped packets.
