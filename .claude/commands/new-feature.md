# Command: /new-feature

Scaffold a new feature spec at the canonical location and hand off to
`/feature` to drive the ATDD loop. This command is a **scaffold-only**
helper — it does not write any production or test code. After it runs,
invoke `/feature` (or `/feature <description>`) to start the
multi-agent ATDD/TDD flow.

## Usage

```
/new-feature <feature-slug>
/new-feature order-cancellation
```

The slug must be lowercase-kebab-case (matches the `feature:`
frontmatter key and the directory under `spec/features/`). Derive a
short UPPER-CASE prefix from the slug (e.g. `CANCEL` for
`order-cancellation`) — the prefix is reused in every AC ID.

## Steps

### 1. Create the spec from the template

```
spec/features/<feature-slug>/<feature-slug>.md
```

Copy `spec/features/_template.md` and replace the placeholders:

- `feature: <feature-slug>` in frontmatter
- `status: draft` (or `planned` if the spec is ready to start)
- `tests: []` (filled in once acceptance test classes are decided)
- Title, overview, business rules, error/edge cases
- User stories with role/goal/benefit
- ACs with the prefix form `AC-<PREFIX>-<N>` — never bare `AC1`

Refuse to overwrite an existing spec file at the same path; if one
exists, print the path and exit so the operator can decide.

### 2. Update the features index

Run `python3 scripts/generate-features-index.py` to regenerate
`spec/features/README.md` from the live frontmatter of every spec.
Do not hand-edit the table — it is auto-generated.

### 3. Hand off to /feature

After scaffolding, print:

```
Spec created at: spec/features/<feature-slug>/<feature-slug>.md
Next: run `/feature` to drive the ATDD loop with implementer, adversary, and requirements-reviewer.
```

## Conventions (canonical source: `.claude/rules/core.md`)

- **One file per feature** at `spec/features/<slug>/<slug>.md`.
- **AC IDs use `AC-<PREFIX>-N` form.** A bare `AC1` is a contract
  violation — the per-language test annotation table in `core.md`
  assumes the prefix.
- **A business person must be able to read every AC.** No class
  names, no framework references, no method signatures.
- **Each user story has a Mermaid sequence diagram** showing the
  happy-path flow, placed under the story heading and before the ACs.
  Bug-fix specs show two diagrams (buggy vs fixed). The validator at
  `scripts/verify-mermaid.sh` rejects diagrams with missing
  `sequenceDiagram` headers, unbalanced block constructs, malformed
  arrows, or unknown statement keywords.
- **Each AC maps to one or more test methods**, annotated with that
  AC ID per the language convention (Java `@Tag`, TS `test.describe`,
  Python `@pytest.mark.spec`, Go function-name fragment).

## What this command does NOT do

- Create test files (use `/feature` and the implementer/adversary loop).
- Create implementation files (same).
- Modify any existing spec (refuses on collision).
- Move or rename existing files.
