# Rationale — audit-warning-loop.md

## Why Warnings, Not Blocks

Hard blocks teach autonomous agents to route around the control: skip the
script, narrow the command, or reframe the work as out of scope. WARN lines keep
the work moving while making the violation visible in three places that are
harder to silently bypass:

1. The Monitor injects warnings into the orchestrator's attention stream.
2. The watcher-loop prepend places warnings directly in each watcher brief.
3. Watcher PR comments expose warnings where the builder sees review feedback.

This rule operationalizes existing proof, testing, mutation, and no-deferred
rules. It does not replace them and does not weaken their review authority.
