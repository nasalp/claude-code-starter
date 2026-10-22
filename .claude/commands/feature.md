# Feature or Bug Fix Kickoff

Start a new feature or bug fix conversationally. No parameters needed.
If $ARGUMENTS is provided treat it as the initial description and skip step 1.

## Step 1: Listen

If no arguments provided, say exactly this:
  "Tell me about the feature or bug — what should it do or what is broken,
  who is affected, any constraints you already know. Plain language is fine."

Wait for response. Restate in 2-3 sentences to confirm understanding.
Ask ONE question if genuinely unclear. Do not ask about frameworks.

## Step 2: Infer tech tags silently

Detect the build tool and dependencies without asking:
  pom.xml present      -> grep -E '<artifactId>' pom.xml | sed 's/.*<artifactId>//;s/<\/artifactId>//'
  build.gradle present -> grep -E "implementation|testImplementation" build.gradle
  package.json present -> read scripts and dependencies sections
  pyproject.toml       -> read tool.poetry.dependencies or project.dependencies
  go.mod present       -> read require block
  Cargo.toml present   -> read dependencies section

Infer feature type: rest-endpoint, event-listener, batch-job, cli-command,
scheduled-task, repository, service, bug-fix, or other.

Infer tech tags. Do not surface this reasoning to the user.

## Step 3: Match global rules silently

Read ~/.claude/rules/*.md frontmatter.
Activate a rule when any tech tag matches tags: field, feature type matches
applies-to: field, or universal: true is set.

Read ~/.claude/skills/*/ SKILL.md. Note relevant skills.

## Step 4: Propose the spec

Show the draft. Do NOT write it yet. Say:
  "Here's what I'd create — confirm or tell me what to change:"

The spec lives at `spec/features/<feature-slug>/<feature-slug>.md`
from kickoff onward. Do NOT use a `FEATURE.md` at the project root —
that home was deprecated in favour of the canonical path so
`scripts/verify-spec-tests.sh` and the requirements-reviewer agent
look at the same place. The slug is a lowercase-kebab-case form of
the feature name (e.g. `order-cancellation`).

The PREFIX used in AC IDs is a short UPPER-CASE token derived from
the slug (e.g. `CANCEL` for `order-cancellation`, `SNAP` for
`profile-snapshot`). It must be unique within the project.

Spec structure to propose (matches `spec/features/_template.md`):

  ---
  feature: <slug>
  status: in-progress
  tests:
    - <fully.qualified.AcceptanceTestClass>
    - <fully.qualified.PropertyTestClass>
  gaps: []
  ---

  # <Feature Name>

  Type: [feature / bug-fix]
  Started: [today's date]

  ## Overview
  [2-3 sentences]

  ## Primary Actors
  [who uses this feature]

  ## Business Rules
  [technology-independent rules]

  ## Error and Edge Cases
  | Scenario | Expected behavior |
  |----------|-------------------|

  ## User Stories

  ### US-<PREFIX>-1: <story title>

  > As a **<role>**, I want <goal>, so that <benefit>.

  ```gherkin
  # Tests: planned
  @AC-<PREFIX>-1
  Scenario: <happy path, in business words>
    Given <the starting situation>
    When <the one action>
    Then <the observable outcome>

  # Tests: planned
  @AC-<PREFIX>-2
  Scenario: <an error or edge case>
    Given <the starting situation>
    When <the one action>
    Then <the observable outcome>
  ```

  ### US-<PREFIX>-2: <next story title>

  > As a **<role>**, I want <goal>, so that <benefit>.

  ```gherkin
  # Tests: planned
  @AC-<PREFIX>-3
  Scenario: <observable behaviour>
    Given <the starting situation>
    When <the one action>
    Then <the observable outcome>
  ```

  ## Scope
  ### In scope
  [what this feature covers]
  ### Out of scope
  [what is explicitly excluded]
  ### Not changing
  [existing behavior preserved as-is]

  ## Access matrix
  | Endpoint | Public | Authenticated | Admin | Rate Limited |
  |----------|--------|---------------|-------|--------------|

  ## Tech in play
  [tag]: [one-line reason each]

  ## Activated rules
  @~/.claude/rules/[each matched rule].md

  ## Activated skills
  - [skill]: [description]

  ## Agent triage
  Implementer          : ~/.claude/agents/implementer.md
  Adversary            : ~/.claude/agents/adversary.md
  Requirements review  : ~/.claude/agents/requirements-reviewer.md

  ## ATDD + TDD plan
  For each AC, the outer ATDD loop writes an acceptance test that
  verifies business intent (real DB via Testcontainers, no mocks).
  The inner TDD loop implements minimal code to pass it.

  RED — acceptance tests per AC:
  1. [AC-<PREFIX>-1] acceptance test — verifies business outcome end-to-end
  2. [AC-<PREFIX>-2] acceptance test — verifies business outcome end-to-end
  3. [AC-<PREFIX>-3] acceptance test — verifies business outcome end-to-end
  4. property-based test for domain invariants
  5. contract test for API shape

  GREEN — implement per AC in dependency order.

  CHECKPOINT after each AC: re-read this plan, verify progress.

  ## Verification
  <!-- Filled after implementation -->
  - Test output:
  - Coverage:
  - Mutation kill rate:
  - Reviewer approval:

Acceptance-criteria rules (canonical source: `.claude/rules/core.md`):
- Every AC is a Gherkin `Scenario` inside a ```` ```gherkin ```` block under
  its user story — one scenario per observable promise, tagged with
  exactly one AC ID: `@AC-<PREFIX>-<N>`. Never bare `AC1`.
- Draft the happy path AND the error/edge cases — each is its own scenario.
- Business language only: no class names, endpoints, tables, HTTP codes
  or UI selectors. A business person must be able to read every scenario.
- `Given` = context, `When` = one action, `Then` = observable outcome.
- `# Tests: planned` above each tag; replaced with the proving test
  (`TestClass#method`) once it exists.
- Per-language test annotation carries the AC ID: Java
  `@Tag("AC-<PREFIX>-N")`, TS `test.describe('AC-<PREFIX>-N', ...)`,
  Python `@pytest.mark.spec("AC-<PREFIX>-N")`, Go function-name includes
  `AC_<PREFIX>_<N>`.

When presenting the draft, ask the user to trim or correct the scenarios
explicitly — they are the reference for what gets built. No test or
production code is written until the user confirms them.

Wait for confirmation. Apply any changes requested. Then write the
file at `spec/features/<slug>/<slug>.md`.

## Step 5: Read learnings and activate

MANDATORY before writing any code:
1. Read spec/learnings/README.md (the index)
2. Pull and read entries relevant to the modules this feature touches
3. Note any known gotchas or patterns to apply

Print:
  FEATURE ACTIVE: [name]
  Type: [type] | Tech: [tags]
  Status: RED
  Learnings applied: [list relevant learnings or "none found"]

  Agents: implementer + adversary running in parallel
  Pre-commit: requirements-reviewer + production readiness checklist (v10)

  First AC: [AC1 from ATDD plan]

Propose the first failing acceptance test. Wait for the user to say go.
Do not implement anything yet.

## Multi-agent ATDD + TDD loop

Once the user approves, run this loop FOR EACH AC:

1. Write acceptance test for the AC (ATDD outer loop):
   - Test verifies the business outcome end-to-end
   - Uses real infrastructure (Testcontainers), no mocks/stubs
   - Test MUST fail (RED) before proceeding
2. Spawn implementer and adversary IN PARALLEL (TDD inner loop):
   - Implementer receives: the spec, failing test files, previous STATUS
   - Adversary receives: the spec, implementer's changed files, previous ISSUES
   - Implementer: write minimal code to pass the acceptance test
   - Adversary: try to break the implementation, write additional failing tests
3. If adversary STATUS is ISSUES_FOUND: loop back to step 2 with new failing tests
4. If adversary STATUS is APPROVED: AC is GREEN
5. CHECKPOINT: re-read the spec, verify this AC is done, mark checkbox [x]
   If process violation detected (code without test, spec drift):
   ⚠️ Emit warning and self-correct before next AC
6. Move to next AC. Repeat until all ACs are green.

Max 3 adversary rounds per AC. After 3 rounds, present unresolved issues to user.

## Pre-commit verification

After all ACs are green, run verification:

1. Run three spec verifiers in sequence — all three must pass:
   - `scripts/verify-spec-tests.sh` (structural — `tests:` frontmatter
     classes exist on disk)
   - `scripts/verify-ac-tests.sh` (per-AC — every AC ID has a test
     annotated with that exact ID per the per-language convention)
   - `scripts/verify-mermaid.sh` (Mermaid sequence diagrams parse
     cleanly — no unbalanced blocks, missing `sequenceDiagram` header,
     malformed arrows, or unknown statements)
2. Run property-based tests and mutation testing
3. If a separate worktree is available, run independent auditor:
   - git worktree add ../project-audit HEAD
   - cd ../project-audit && ./mvnw clean verify
   - Compare Builder claims vs fresh build results
   - git worktree remove ../project-audit

## Pre-commit review loop

Before any commit, spawn ALL THREE AGENTS:

  Implementer: confirms all tests pass and implementation is complete
  Adversary: one final sweep for anything missed
  Requirements reviewer: full spec check + production readiness checklist v10
    MUST verify: every **AC-<PREFIX>-N** has at least one acceptance test annotated with that AC ID
    MUST verify: tests verify business outcomes, not stubs

Collect all three votes. If any agent votes REJECT:
- Show the user the combined BLOCKING issues list
- Distinguish from ADVISORY items (flagged but not blocking)
- Implement the blocking fixes
- Re-run the pre-commit review loop
- Max 3 review rounds. After 3, present to user for decision.

Only commit after unanimous APPROVE (or user override).

After commit:
- Update the spec frontmatter: `status: in-progress` → `status: implemented`.
- Fill in the ## Verification section with actual test output, coverage, and reviewer notes.
- The spec stays at `spec/features/<slug>/<slug>.md` permanently. Do NOT move it to
  `.claude/features/`. The canonical home matches what `verify-spec-tests.sh` and
  the requirements-reviewer agent both look at.
- Update `spec/features/README.md` by running `python3 scripts/generate-features-index.py`
  (or wait for the corresponding hook if it's wired in `hooks.json`).
- Update `spec/learnings/` if key findings were discovered.
- Say: "Run /user:refresh-project to sync any new modules this feature added."
