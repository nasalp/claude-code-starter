# status and anti patterns

# Anti-patterns this skill exists to prevent

- **"Should I split this into waves?"** — the agent shipping prose instead
  of code. Phase 3's override section is exactly this.
- **One-shot Agent invocation for 20-file features** — the orchestrator
  loses observability. Use this skill instead.
- **Background `claude --print` with no `--tools default`** — silent hang
  at 0% CPU on first tool call. Already covered by `parallel-cli-sessions`.
- **`--admin` on a PR the orchestrator's own diff caused failures on** —
  forbidden. Auto-approve only when the failure
  classification is "pre-existing" or human says "admin merge".
- **Reading the tmux pane in the user's status** — that's the raw
  stream-json firehose. Parse it with jq for human-readable output.
- **Hand-writing `vi.fn().mockResolvedValue` for endpoints that have SCC
  stubs** — violates the contract chain. Audit catches it.

# Status reporting to the user

Every audit cycle, give the USER a 3-section update:

```
# Status (t+Nmin) — <one-line current state>

| Metric | State |
| Builder PID | <pid> (alive, <cpu> CPU) |
| Commits | <N> on <branch> |
| Current phase | <PHASE_N>: <substep> |
| Red flags | <all clear | N concerns> |

**Reasoning vs rules:** <one paragraph: what the builder is actually doing
right now and how it lines up with the rules and the locked decisions>

**Concerns:** <list, or "none">
```

If "none" — schedule the next wakeup and end the turn. If there are
concerns, present them and wait for the user's call.

