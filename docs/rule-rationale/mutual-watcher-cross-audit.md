# Rationale — Mutual Watcher Cross-Audit + Orchestrator-Consumes-Verdicts Loop

## Why

- **A live watcher that's ignored is theatre.** `check-watchers` liveness
  proves the loop is running; it does NOT prove anyone read the verdict. The orchestrator quietly
  merging past a REJECT looks identical, from the outside, to "no REJECT existed."
- **A single watcher can be wrong, lazy, or empty.** Verdicts go BLIND (ref unresolved), come back
  empty (the `claude --print` body didn't land), rubber-stamp APPROVE without reading the diff, or
  miss a defect. One watcher is a single point of audit failure. Cross-checking catches it.
- **Real incident:** the Opus rules-watcher produced
  a sharp, correct REJECT — the "live data" tests were existence-only (`hasSize(3)`/`isNotEmpty`) that
  would pass against static data, the commit over-claimed an AC whose test didn't exist, and the
  capstone e2e was **fake** (`page.setContent(handBuiltHtml)` — it rendered HTML the test author
  wrote, never the real SPA, then screenshotted *that*). The orchestrator had been checking watcher
  *liveness* only, never reading the verdict, and was about to merge. The operator caught it: *"are
  you actually watching the watchers? ... nobody trusting nobody."* This rule is the structural fix.

## Cross-references

- `watchers-must-observe-live-tmux.md` — watchers read the live pane each pass; the 2-codex+1-claude
  split. This rule adds the cross-audit + orchestrator-consumption layer on top.
- `multi-agent-model-routing.md` — keeps the cross-audit cheap (cheap-engine watchers, ≤1 Opus).
- `senior-review-gates.md` / `pre-ship-checklist.md` — the merge gate this loop feeds.
