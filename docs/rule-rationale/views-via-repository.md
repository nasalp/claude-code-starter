# Rationale — views-via-repository

## Why

1. **Controllers describe orchestration, not data shape.** A handler should read `extractFilters(req.query)`, call `repo.findX(filters)`, and return `apiResponse(res, 200, true, 'X', result)`. Inlining SQL strings forces the handler to also know column names, parameterization rules, sort whitelists, and pagination math — four concerns out of scope for HTTP routing.

2. **Repositories isolate the view contract.** When the SQL view evolves (column rename, grain change, new filter), there is one file to update. Every consumer continues to call the same `repo.findX(...)` function. The blast radius of a view rename without a repository is "grep every controller and hope you found all the call sites."

3. **Tests prove equivalence honestly.** With a repository, the test injects `sequelize` (or a mock pool) and asserts on the return value. Under Testcontainers it asserts against a real Postgres applying real migrations, real view DDL, and a real fixture seed. No shared dev DB. No stubs that "should" behave like the real planner. No CI flake from a coworker's data.

4. **Without a repository, the SQL is unreviewable.** SQL strings inside a controller method look like part of the JS — reviewers skim them. Pull them into `repositories/<context>Repository.js` and they become a first-class artifact that gets attention.

5. **Migration safety.** Cutting over from a Sequelize/Hibernate include-chain to a view is a high-risk refactor. With a repository + Testcontainers + equivalence tests, the cutover commit is "controller now calls repository instead of ORM include." Pre-cutover, the repository tests already proved the view returns the same rows as the ORM path. Post-cutover, the same tests guard against regressions. There is no flag day where production is testing the new path for the first time.

## Cross-references

- `.claude/rules/common/testing.md` — broader integration-test discipline; this rule is the strict version for view-backed reads.
- `.claude/rules/no-deferred-work.md` — partner. "Repository TODO" comments in a controller that contains raw SQL are deferred-as-done in micro form.
- `.claude/rules/legacy-code.md` — when existing controllers contain raw SQL, leave them until you touch them; when you touch them, the touch must include the repository extraction.
- `.claude/rules/senior-review-gates.md` — under "Is the code small enough to understand and test?" — a controller with embedded SQL is by definition too coupled.

## Calibration

This rule was written 2026-05-21 after a multi-week effort to consolidate 18 superadmin endpoints behind 6 PostgreSQL views in `services/dashboard-v1`. The first implementation attempt put `sequelize.query(...)` calls directly in `adminController.js` handlers. The operator's correction: "The view must be tested using test containers and accessible through a repository concept. No direct sql in controller!!!!" Both halves of the correction are durable principles; this rule captures both.

If a future project genuinely cannot use Testcontainers (e.g. a target DB engine with no container image), the test infrastructure SHOULD migrate to a per-test ephemeral schema on a shared CI DB — still real DB, still isolated, never mocked. The repository pattern itself does not bend.
