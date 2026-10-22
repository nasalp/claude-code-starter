# CLAUDE.md — Global Default

> This file is symlinked into `~/.claude/CLAUDE.md` by `setup.sh`. It is loaded at the start of every Claude Code session, in every project, as the global default.
>
> **Per-project context belongs in `<project>/CLAUDE.md`** — that file overrides this one for sessions opened inside that project.
>
> If you find yourself wanting to put project-specific details here, you almost certainly want a project-level `CLAUDE.md` instead.

## What this is

`ai-rules` is the shared Claude Code workflow harness for your team. The harness ships:

- **Rules** — **always-on gates** in `.claude/rules/` (auto-loaded every session) plus a generated **index** (`.claude/rules/INDEX.md`). Full rule bodies live in `.claude/rules-corpus/` and load **on demand** (Read by path from the index) or via role packets (`select-rules.sh` / `gen-packet.sh`). See `docs/rules-structure.md`.
- **Skills** in `.claude/skills/` — deep how-to references (180+).
- **Agents** in `.claude/agents/` — specialized reviewers and builders.
- **Commands** in `.claude/commands/` — slash commands like `/feature`, `/code-review`, `/promote-learnings`.
- **Hooks** in `.claude/hooks/` — automation triggers on Edit/Write/Stop.
- **Workflows** in `.claude/workflows/` — multi-step playbooks (feature, bugfix, planning).

## How sessions work

1. **SPEC → TEST → IMPLEMENT → VERIFY.** Every behavior change goes through this loop.
2. **Hooks back it up.** `spec-first-check.sh` warns when production code changes without a spec; `require-test-first.sh` warns when production code is edited without a test.
3. **Hooks emit warnings, not blocks.** Per harness convention, every hook exits 0 and warns loudly to stderr; none of them stops a tool call. Agents must read hook output and act on it — ignoring a warning is a defect. `SPEC_BYPASS=true` silences the spec-first warning for explicit prototype mode.
4. **Specs live in `spec/features/<name>/<name>.md`.** One file per feature, with user stories + AC IDs.
5. **Learnings live in `spec/learnings/<category>-<topic>.md`.** Findings about the codebase that other projects might benefit from.
6. **Senior review gates apply before senior review.** Use `.claude/rules-corpus/senior-review-gates.md` before saying a PR is ready for a code owner or a senior reviewer.

## Lazy rule loading

Sessions boot with **~10 always-on coordination gates** + `INDEX.md` — not all 100+ rule files.

| What | Path | Loaded when |
|------|------|-------------|
| Always-on gates | `.claude/rules/*.md` (see `scripts/always-on-rules.list`) | Every session (via `~/.claude/rules/`) |
| Rules index | `.claude/rules/INDEX.md` | Every session — use to find corpus paths |
| Full rule corpus | `.claude/rules-corpus/**` | On demand (`Read`) or role packets for builders/reviewers |

Regenerate index after rule changes: `bash scripts/gen-rules-index.sh`. CI checks staleness via `scripts/check-rules-index.sh`.

Opt into full ruleset: `RULES_LOAD_MODE=full` (single-session / non-orchestrated work).

## Where to find things

- New engineer: `docs/DAY-0.md`.
- Project-local override of a global rule: `docs/OVERRIDES.md`.
- Promoting a project learning upstream: `docs/META-HARNESS.md` + `/promote-learnings`.
- Architecture decisions: `spec/decisions/`.

## Project-level CLAUDE.md

Each project should ship its own `CLAUDE.md` at the project root with:

- One-paragraph project overview
- Tech stack (specific versions, build tool, DB)
- Canonical build/test commands (e.g., `mvnd clean install`, `pnpm verify`)
- Module overview if multi-module
- External-service inventory (which to mock in tests)
- Project-specific conventions that override or extend the global rules

When a project has its own `CLAUDE.md`, Claude Code reads it INSTEAD of (or layered on top of) this global default for sessions opened in that project.

## When a hook warns

| Symptom | Fix |
|---|---|
| `[spec-first] WARNING: Modifying production source without a spec change` | Author the spec first |
| `[require-test-first] WARNING: No test file found` | Write the failing test first |
| Want to bypass for prototype work | `SPEC_BYPASS=true` env var |
| Stop verification is reminder-only by default | Opt into the full build/test run with `RUN_VERIFY_STOP=true`; silence entirely with `SKIP_VERIFY_STOP=true` |
| Drift detected | `/refresh-project` |

## Critical conventions

- **Tests run in parallel.** No shared mutable state. No hardcoded ports.
- **Money: `BigDecimal` (Java) / `Decimal` (TS) — never `double` / `number`.**
- **IDs: typed (`OrderId`), not raw `String`/`UUID` at API boundaries.**
- **Time: `Instant` for timestamps, `ZonedDateTime`/`OffsetDateTime` for display.**
- **No hardcoded secrets in source. Env vars + secret manager.**
- **Hooks warn → agents must read warnings.** Silent ignoring of stderr is a defect.
- **Green CI is not proof by itself.** Senior review needs a spec or ADR, test-first evidence, behavioral tests, compatibility proof, and maintainable code shape.

## Contributing back

Found a pattern that 2+ projects independently re-derived? Run `/promote-learnings` from the parent folder containing your project repos. The harness drafts a PR upstreaming the rule. See `docs/META-HARNESS.md`.
