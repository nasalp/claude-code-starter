---
name: parallel-agent-aggregator-pattern
description: Local merge-aggregator branch consolidating N parallel agent worktrees into ~3 wave-PRs instead of N PRs, merging as agents complete and verifying after every 2-3 merges
origin: ECC
triggers: more agents fewer prs, aggregator branch, wave PR, merge agents locally, parallel agent dispatch, fewer CI runs, merge train conflicts, refactor consolidated branch, agent worktrees
---
# Parallel Agent Aggregator Pattern

When dispatching N parallel agents across worktrees for a multi-feature refactor, do **not** ship N PRs. Maintain a local "aggregator" branch that consolidates each agent's output as it completes, run the canonical CI-parity gate after every 2-3 merges, and push **one PR per wave** (typically 3 waves total). This trades one big merge train for many small merges, kills N-1 redundant CI runs, and resolves shared-file conflicts once locally instead of N times on `origin`.

## When to use

- A multi-feature refactor or migration is being executed by N parallel agents (one feature group per agent, each in its own worktree).
- The features touch some shared file(s) -- typically architecture-test base classes, ArchUnit support classes, common configuration -- so the conflicts are predictable.
- The team has explicitly signaled that "fewer PRs, more agents" is preferred.
- Reviewer attention is the bottleneck. N near-identical PRs cost N reviewer context switches; one wave PR costs one.

## When NOT to use

- The features are independent, ship at independent cadences, or have different reviewers. Wave consolidation forces them onto the same release boundary; if that's wrong for the org, do not aggregate.
- Each feature is genuinely self-contained (no shared-file conflicts, no cross-cutting tests). Then per-agent PRs cost no extra conflict resolution and the consolidation overhead is not earned.
- The team's convention is one-feature-per-PR for traceability or release-engineering reasons that override CI-minute economics. Honor that.
- The aggregator branch would be too large for one PR (>1000 files / >10k lines). At that point, split into multiple waves rather than one giant blob -- but each wave is still aggregated, just smaller.

## The pattern

Step 1 -- **Branch the aggregator off `origin/main` once at the start of the campaign**, before agents are dispatched.

```bash
git -C <aggregator-repo> fetch origin
git -C <aggregator-repo> checkout -b refactor/<topic>-consolidated origin/main
```

Step 2 -- **Dispatch agents into isolated worktrees in parallel.** Each agent works on `feat/<feature>-<scope>` from `origin/main`. The aggregator does not touch agent branches; agents do not touch the aggregator.

Step 3 -- **Merge each agent's branch into the aggregator as it completes**, not at the end. As soon as agent N's PR is opened or its branch is pushed, fast-forward fetch and merge with `--no-ff` so the wave PR has explicit feature commits inside its history:

```bash
git -C <aggregator-repo> fetch origin <agent-branch>
git -C <aggregator-repo> merge --no-ff origin/<agent-branch> \
    -m "Merge feature X into wave A consolidator"
```

Resolve conflicts as they accumulate. Each conflict is small because only the most recently merged agents have overlapping changes; resolution is cheap and the next merge re-uses the resolution context.

Step 4 -- **Run `scripts/verify-like-ci.sh` (or the project's equivalent canonical gate) after every 2-3 merges.** This catches integration issues early -- usually a feature that compiles solo but breaks an architecture test that another feature relies on. Catching this on the aggregator is cheap; catching it on `origin` after merging N PRs is expensive.

Step 5 -- **Group into waves if the aggregator gets too large.** Suggested granularity:

- **Wave A** -- ~5 small / low-risk features
- **Wave B** -- ~5 medium features
- **Wave C** -- ~3 large or cross-cutting features

That gives roughly 3 PRs total instead of N, each reviewable in ~30 min instead of ~5 min N times. Each wave is its own aggregator branch off `origin/main`.

Step 6 -- **Push the aggregator as one PR per wave for review.** PR description lists each feature's scope as a bullet, links the per-feature commits, and links any related learnings. Squash-merge produces one tidy commit on `main`; rebase-merge preserves per-feature commits. Pick one based on the project's git history conventions.

## Common gotchas / variants

- **Bisectability survives at wave granularity, not at feature granularity.** A regression introduced by feature 7 of 13 is bisectable to wave B, then to feature 7 by reading the wave PR's commits. Acceptable trade-off; document it for the team.
- **Agent failure inside a wave blocks the wave.** If agent 5 of 13 fails and needs redispatch, the wave PR cannot land until that agent's work is in. Mitigation: keep waves small enough (~5 features) that one redispatch does not bottleneck the others. Optionally drop the failed feature into a later wave.
- **Wave PRs are larger.** Reviewers read ~10x more lines per PR. Mitigate with explicit per-feature commits inside the squash, a clear scope bullet list in the PR body, and -- where the work is cross-cutting -- a "what to look at" guide in the description.
- **Do not run the gate in parallel with agents that hold target/ locks.** Maven's `clean` phase fails when another invocation is locking the same `target/`. Either suspend agents during gate runs, or use a separate worktree for the aggregator with its own `target/`.
- **Do not bypass the canonical gate.** "I'll just push the wave PR and let CI tell me" is the exact push-and-pray pattern that the no-push-without-local-tests rule forbids. Run the gate locally before every push, including each wave PR.
- **Cancel obsolete CI runs.** When a wave PR's next push will obsolete an in-flight run, cancel it (`gh run cancel`). The CI-minute-conservation rule applies inside the aggregator workflow too.
- **Anti-pattern (recorded as a real failure mode):** a clean-architecture migration shipped 13 PRs when 3 waves would have been correct. 13 separate CI runs, 13 reviewer context switches, 13 merge-train conflict resolutions on `ArchitectureTestSupport.java` -- more wall clock spent on PR coordination than on the work itself.

## Verification

The pattern was applied correctly when:

1. The wave PRs total roughly `ceil(N / 5)` for N parallel features, not N.
2. Each wave PR's description has a bullet list naming each consolidated feature with its scope.
3. The aggregator branch shows `--no-ff` merges with explicit per-feature commits visible in `git log`.
4. CI minutes consumed for the campaign are roughly `wave_count * full_verify_minutes`, not `N * full_verify_minutes`.
5. The conflict log shows shared-file resolutions happening once on the aggregator, not N times on origin.
6. `scripts/verify-like-ci.sh` was run on the aggregator before every wave PR push, with a `BUILD SUCCESS` line in the PR description or commit message.

## References

- Companion rule: `.claude/rules/ci-minute-conservation.md` (the rule this pattern satisfies)
- Companion rule: `.claude/rules/no-deferred-items-claimed-as-done.md` (wave PRs must be all-or-nothing per wave)
- Companion rule: `.claude/rules/no-push-without-local-tests.md` (each wave PR push must follow the canonical gate)
- User memory: `feedback_more_agents_fewer_prs`
