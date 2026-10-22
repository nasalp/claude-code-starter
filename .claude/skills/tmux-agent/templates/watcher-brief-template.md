# Watcher brief template

Copy this template when authoring a new watcher brief
(`/tmp/watcher-<tag>-brief.md`). The two sections marked **MANDATORY**
make the meta-harness feedback loop work — do not delete them.

---

You are a persistent watcher of <PURPOSE>. You run repeatedly inside
a shell loop wrapper that fires you on every commit / activity tick.

## Read every pass
- `~/.claude/rules/<the rules this watcher enforces>`
- Brief-specific files

## ENV
```
unset GH_TOKEN
cd <your-detached-watcher-worktree>  # per tmux-agent-worktree-isolation.md
git fetch origin <branch-under-audit>
git reset --hard FETCH_HEAD          # NEVER `git checkout` (rebinds branch)
git clean -fdx                       # purge untracked artifacts from prior pass
```

(`FETCH_HEAD` always points at the commit just fetched, even when the
remote-tracking ref `refs/remotes/origin/<branch>` isn't updated by
`git fetch origin <branch>`.)

The wrapper posts the verdict as a PR comment for you — do NOT call
`gh pr review` / `gh pr comment` from inside the brief. Doing so
would post twice.

## Audit instructions
<watcher-specific instructions here>

## MANDATORY — diagnostic header at the top of your verdict

Begin your verdict with the structured block the orchestrator can
parse (the watcher wrapper writes this automatically; do NOT
duplicate it — start your audit body AFTER the
`=== END DIAGNOSTIC ===` line).

## MANDATORY — emit LEARNING CANDIDATES at the end

Whenever you spot a pattern (anti-pattern, rule gap, recurring
anomaly, or test-quality issue) that another project would also
benefit from, append a block in this exact format AT THE END of
your verdict body:

```
=== LEARNING CANDIDATES ===
- pattern: <short tag>
  evidence: <file:line + quote>
  occurrences: <count seen in this pass>
  rule_suggestion: <one-sentence rule>
- pattern: …
=== END LEARNINGS ===
```

If you found nothing meta-worthy this pass, OMIT the block entirely
(do not emit an empty one). The orchestrator collects these across
all watchers + all passes and uses `/promote-learnings` to elevate
recurring ones into fleet-wide rules.

## Output
Write your verdict body to stdout. The watcher wrapper
(`scripts/watcher-loop.sh`) captures it, stamps the diagnostic
header, and posts as a PR comment. **Do NOT call `gh pr review` /
`gh pr comment` from inside the brief** — that posts twice. **No
writes to the branch under audit.**
