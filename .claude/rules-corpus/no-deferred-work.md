---
roles: [builder, watcher, reviewer, reconciler]
severity: critical
model_tiers: [premium, standard, cheap]
applies_to:
  task_types: [implementation, review]
---

# Don't defer anything

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

User asks to fix something -> **fix it now**. Do NOT commit partial fixes labeled "follow-up", "deferred", "TODO", "tracked", "phase 2", or any framing that lets unfinished work pass as finished. Task too large for current session -> **say so out loud and ask for direction before committing anything** — never bury remaining work in a commit message or tracking comment.

## What "deferred" looks like in commits and replies

All banned, however reasonable they sound:

- "Per-contract mock stubs for the success-path contracts are a follow-up"
- "Tracked as CI follow-up; not in this commit"
- "Migration is a 1–2 day refactor; landing what I have"
- "FIXME(scope): rest of the cleanup in a later PR"
- "Phase 1 complete; phase 2 in a follow-up commit"
- "Carve-out file documents the migration plan" (i.e. suppression labeled "temporary")
- "Per-package ignore list; one entry per pending migration" (same trick)
- "Honest follow-up framing" (the framing is the dodge)

Shared pattern: **moving work from done to not-done while calling the commit a fix.** Next reader sees green build + "fix(area): X done", assumes X done. It isn't.

## How to apply

Before writing a commit message for any task the user asked, check the diff against the user's actual instruction. Ship only if all true:

- User said "fix X" and diff fixes X end-to-end.
- Anything skipped was explicitly approved by user this session.
- No file in diff has a `TODO`, `FIXME`, suppression, or carve-out that exists solely because you ran out of time.
- Commit message does NOT contain "follow-up", "deferred", "tracked as", "phase 2", "next commit will…", "not in this commit" (unless user explicitly accepted them).

Else: stop, ask user how to scope it, then complete it or back the partial work out.

## What to do when the task IS genuinely too large

Be honest about scope without deferring: **describe the work, estimate it, ask for the call** — only then write code.

- ❌ Bad: commit easy 80% with message "X done — remaining 20% is a follow-up".
- ✅ Good: "X has 5 pieces. I can finish 2 in ~30 min; 3 more need ~2 hours of careful per-controller work. Want me to (a) do the 2, mark the 3 with explicit test failures documenting remaining work, pause for your call, or (b) commit nothing yet and keep going for the full 2 hours?"

User can always say "do all 5". They can never say it if you already committed "fix(area): 2 of 5 done".

## What to do when CI is red while the fix is incomplete

CI red is informative. CI green with a hidden suppression is a lie.

When in doubt: leave the test/gate failing in CI rather than ship a suppression or carve-out. Failing CI is honest. A disabled rule is not.

Banned:

- Adding entries to `archunit_ignore_patterns.txt` "temporarily".
- Adding `@SuppressWarnings("...")` to pass a rule, fix "later".
- Adding `@Disabled` to tests "until the migration lands".
- Excluding test patterns via `-Dtest='!...'` to dodge CI flakiness when the issue is a real bug.
- Bumping a timeout to green a slow build when the cause is unbounded growth.

All turn a present problem into a future one, on someone else's watch.

## Quick reference

| Rule | Priority |
|------|----------|
| User says "fix X" → fix X end-to-end before committing | CRITICAL |
| No suppressions, ignore-pattern files, or `@Disabled` to hide unfinished work | CRITICAL |
| If genuinely too big: state scope, ask for the call, commit nothing yet | REQUIRED |
| If the user explicitly accepts partial scope in this session, partial is OK | REQUIRED |
| CI red is honest; CI green with a hidden suppression is a lie | CRITICAL |

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/no-deferred-work.md`
