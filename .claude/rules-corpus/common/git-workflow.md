# Git Workflow

## Commit Message Format
```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci

Note: Attribution disabled globally via ~/.claude/settings.json.

## Pull Request Workflow

Creating PRs:
1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Push with `-u` flag if new branch

> Full development process (planning, TDD, code review) before git ops → [development-workflow.md](./development-workflow.md).

## Pre-Push Verification (REQUIRED)

Before any `git push` — including reviewer-fix follow-ups, "trivial" docs commits, rebases — run project canonical local verification gate. Principle: **green local build = cheapest gate; CI not free; "I'll just see what CI says" burns CI minutes and dirties branch.**

### What "canonical local verification" means

Each project SHOULD ship `scripts/verify-like-ci.sh` (or `verify.sh`) that:

- Accepts no flags. One canonical invocation.
- Mirrors CI's exact command (e.g., `./mvnw clean verify -T 1C` for Maven, `pnpm install --frozen-lockfile && pnpm build && pnpm test` for Node).
- Sets same env vars CI does.
- Returns non-zero if anything fails.

"No flags" rule prevents gradual drift toward `verify.sh --skip-tests` always-on convenience flags create.

### Why client-side hooks aren't enough

`pre-push` hook bypassable with `git push --no-verify`. Real enforcement lives in:

1. **CI's required-checks gate on merge target branch** (only unbypassable layer).
2. **Discipline before push** — running canonical script.
3. **Project-wide commit norms** — fix-on-fail, never "fix forward in CI".

Rule = "never push without local verification." Mechanism = shared discipline + CI-side gates. Blocking client hook = theatre; document norm and enforce with required CI checks instead.

### Anti-patterns (specifically discouraged)

- **Push-and-pray:** push to see CI verdict instead of running locally.
- **Targeted-only verification:** running just modified module's tests, skipping full reactor build. Cross-module breakages = exactly what full verification catches.
- **Skip flags as habit:** `-DskipTests`, `-x test`, `--ignore-scripts`. Acceptable for local exploration; never as pre-push gate.
- **Reviewer-fix follow-ups without re-verification.** Mechanical "address review comment" commit = highest-risk push class — exactly when re-verification most often skipped.
