# Meta-Harness — Learning Promotion Loop

The ai-rules harness ships a manual command, `/promote-learnings`, that scans
sibling project repos for cross-cutting patterns and drafts PRs to promote them
upstream. This document explains the loop, when to run it, what to expect, and
how to retract a mistake.

## The problem this solves

When a project (project-a, project-b, …) discovers a useful
rule — "no Spring profiles", "validate column semantics against prod data",
"singleton Testcontainer for parallel ITs" — that rule lives in the project's
`spec/learnings/` and `.claude/rules/`. Future projects don't inherit it. They
re-discover the same rule weeks later, re-author it locally, and the harness
stays generic while the projects accumulate parallel duplicate knowledge.

The meta-harness closes the loop: when 2+ projects independently surface the
same pattern, the loop detects the convergence, runs a 3-agent consensus
review, and opens a draft PR against ai-rules with the proposed upstream rule.

## How it runs

**Manually, from the folder containing your projects:**

```bash
cd $PROJECTS_ROOT/   # contains project-a/, project-b/, project-c/, ...
# In Claude Code:
/promote-learnings
```

The command auto-discovers project repos by listing the current directory and
filtering for `.git/` + `spec/learnings/` or `.claude/rules/`.

You can dry-run:
```
/promote-learnings --dry-run
```

You can scope to one project:
```
/promote-learnings --only project-a
```

**No cron. No project-side hooks.** v1 is manual. Add cron later if the loop
proves valuable.

## What you'll see

A draft PR appears in your team's fork of claude-code-starter:

- **Title:** `[promotion] <rule-name> — converged from <project-a>, <project-b>`
- **Body:** side-by-side diff, scope tag, counter-examples, 3-agent verdicts,
  cost line, `Promoted-from:` footer.
- **Status:** Draft. The senior reviewer reviews and merges or closes.

If nothing converged, the command writes a heartbeat to
`spec/promotion-log/<date>.md` in this schema:

```
<YYYY-MM-DD HH:MM UTC> | scanned <N> projects | <N> learnings | <N> candidates met threshold
```

## The convergence rule

A candidate qualifies for promotion when:

1. **Topic match.** Same `topic:` (from `spec/promotion-topics.yaml`) in 2+
   projects.
2. **Different authors.** The two source commits are by different
   `git commit author` emails. Same author = potential copy-paste, not
   independent discovery.
3. **Time gap.** Source commits are at least 5 calendar days apart.
4. **Not already upstream.** Exact name + topic must not already be in
   `~/.claude/rules/`.
5. **Not in the rejection ledger** within the 90-day expiry.

Single-project candidates with strong signal go to **Tier 1**:
`.claude/rules-proposed/` — visible to all projects but not auto-loaded.
Engineers in other projects encounter them organically. After 30 days without a
second source, Tier 1 candidates are demoted (deleted) unless manually
promoted.

## The 3-agent panel

Three reviewers vote on every candidate that survives the Haiku triage filter:

- **Architect** — system design lens. APPROVE iff the pattern is structurally
  sound and generalizable.
- **Field Engineer** — Monday-morning lens. APPROVE iff the senior reviewer would merge it
  in 3 minutes.
- **Adversary** — failure-mode lens. APPROVE iff there's no false-positive
  blast radius. **Adversary REJECT is binding** even when the other two agree.

If any reviewer REJECTs, the candidate goes to
`spec/decisions/rejected-promotions.md` with the reason and a 90-day
re-evaluation date.

## Cost

Per active run (one with new candidates): $2–5 typical, $20 hard cap.
Per no-op run (nothing changed since last run): ~$0 — the pre-flight diff
exits before spawning agents.

The dollar number is the dominant signal that something is wrong (loop in a
runaway feedback state, scope misclassified candidates exploding the panel).
Cost cap is a circuit breaker, not a postcondition: per-agent prompt budgets
abort mid-flight if exceeded.

## Retraction

A promoted rule that turns out to be wrong needs to retract cheaply. Two
mechanisms:

### Method 1: `/retract-rule <rule-name>` (preferred)

From any project repo:
```
/retract-rule no-foo
```

This:
1. Opens a PR in `ai-rules` moving the rule from `.claude/rules/` to
   `.claude/rules/_deprecated/` with the requesting engineer's friction note.
2. Auto-pings everyone listed in the rule's `Promoted-from:` footer.
3. Other projects keep the rule until they next run `setup.sh`.
   No forced sync.

### Method 2: Manual revert

```bash
cd $AI_RULES_REPO/
git revert <merge-commit-sha>
# Add an entry to spec/decisions/rejected-promotions.md explaining why
```

The `Promoted-from:` footer in the merged rule contains the source SHAs and
the original promotion PR number. Use it to find the audit trail.

## What the meta-harness does NOT do

- **Auto-merge anything.** Drafts only. Always.
- **Push commits to projects.** Project state is read-only during the scan.
- **Promote single-project findings to `.claude/rules/`.** They go to
  `rules-proposed/` first (Tier 1). Tier 2 requires orthogonal convergence.
- **Run on a schedule.** v1 is manual.
- **Trust project-side hooks for write access.** Project hooks would need
  write tokens to ai-rules — vetoed as too risky in the consensus review.

## When to run it

- **After a wave of related work** — e.g. you just shipped a security
  hardening pass across multiple repos. Likely convergence.
- **Monthly hygiene** — a calendar reminder. Not a cron yet.
- **When you notice repetition** — "didn't we just write this in Project X
  last month?" Run it.

## When to NOT run it

- **Days after the last successful run with no new project commits** — pre-flight
  exits at $0, but the human attention to review nothing is wasted.
- **Mid-incident or pre-deploy** — promotion PRs are non-urgent. Don't add
  draft-PR review to a hot moment.

## Failure modes to watch for

- **Same project promotes itself twice.** Authorship + time-gap checks should
  catch this. If you see it, file an issue and tighten the check.
- **Wrong scope tag.** A `postgres-only` pattern tagged `universal` will
  appear at the top of `.claude/rules/`. Adversary should catch this; if it
  doesn't, retract via Method 1 + add to manually-rejected ledger.
- **Cron stops running.** Not relevant in v1 (no cron). When v2 ships:
  weekly heartbeat issue posted to ai-rules; if you don't see one for 8 days,
  the loop is dead.

## Status

- **v1 (manual command):** shipped — see
  `.claude/commands/promote-learnings.md`.
- **v2 (cron via `schedule` skill):** deferred until v1 has at least 4 weeks
  of operational signal.
- **v3 (project-side push hooks):** vetoed in the design review. Will not
  ship.

## See also

- `.claude/commands/promote-learnings.md` — the slash command implementation
- `.github/PULL_REQUEST_TEMPLATE/promotion.md` — PR template
- `spec/decisions/rejected-promotions.md` — anti-feedback-loop ledger
- `spec/decisions/0003-meta-harness.md` — design rationale + 3-agent consensus
- `spec/promotion-topics.yaml` — controlled vocabulary
