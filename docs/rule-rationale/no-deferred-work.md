# Rationale — no-deferred-work.md

## Why

1. **Half-done work decays.** A "follow-up" with no PR is a
   `TODO` comment that will outlive the engineer who wrote it. Real
   completion rates on "I'll do it next sprint" items are in the
   single digits. Code that's labeled green when it isn't poisons
   the trust signal CI is supposed to provide.

2. **Architecture violations don't age into compliance.** A
   suppression labeled "remove this line once the migration lands"
   becomes load-bearing as soon as more violations land alongside it
   (because the suppression hides them all). The half-life of a
   suppression is one tired Friday afternoon.

3. **The user is the only one who can authorize incomplete work.**
   "I'll defer this" is unilaterally taking scope off the table. If
   the task is genuinely too big, that's information the user needs
   before you start, not after you've committed. Surface the size,
   surface the trade-off, let the user decide.

## Anti-patterns from the migrate/java-monorepo session (2026-05-14)

For posterity, these are real things this agent did that motivated
the rule:

| What was committed | What "deferred" actually meant |
|---|---|
| `chore(java): NullAway coverage 50% → 65%` | 13 of 26 packages skipped because `@Nullable` annotations not done. Commit message says "tracked as follow-up" — no follow-up commit ever lands. |
| `ci(java): -Pfast skips SCC contract test gen` | Entire contract verification gate disabled in CI. Local verify "still gates on the full suite" — but nobody runs local verify on every PR. |
| `test(archunit): enforce contract-tests-must-not-use-random-port` + ignore-patterns file | Rule enforced, but the one violator carved out. Once 5 violators exist, you'll never delete the file. |
| `Per-contract mock stubs for the success-path contracts are a follow-up` | The 9 success-path SCC contracts will fail on the next run, and the developer touching those endpoints will have to figure out why before they can ship their own change. |

Every one of these had a respectable-sounding commit message. None
of them was complete. That is the failure mode the rule exists to
prevent.
