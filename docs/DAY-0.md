# Day 0 — New Engineer Onboarding

A 30-minute path from "I have a laptop" to "I can ship a feature with the harness." If anything below confuses you, that's a doc bug — file an issue.

## 0. What this repo is

`ai-rules` is the shared Claude Code workflow harness for your team. It provides:

- Rules (development standards) loaded into every session
- Agents (specialized reviewers, builders, testers) on demand
- Skills (deep how-to references) discoverable by topic
- Hooks (automation triggers) that run on every Edit/Write/Stop
- Commands (slash commands like `/feature`, `/code-review`, `/promote-learnings`) you invoke directly

Every project you work on inherits from this one repo via symlinks into `~/.claude/`.

## 1. Prerequisites

- macOS or Linux (Windows works via WSL but isn't first-class).
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed.
- Git, bash, jq, Python 3, Node 22+. Most projects also need Maven/Gradle and `mvnd`.
- Access to `nasalp/claude-code-starter` on GitHub (public) — or your team's fork of it.

## 2. First-time install

Clone the repo somewhere on your machine and export `AI_RULES_REPO` so other
commands and hooks can find it. The path itself is your choice — `~/code/claude-code-starter`,
`~/dev/claude-code-starter`, or anywhere else works equally well.

```bash
# Pick any path you like; the example below uses ~/repo/claude-code-starter.
export AI_RULES_REPO="$HOME/repo/claude-code-starter"
git clone https://github.com/nasalp/claude-code-starter.git "$AI_RULES_REPO"
cd "$AI_RULES_REPO"
./setup.sh --dry-run   # preview: what will be linked / written
./setup.sh             # symlinks .claude/, CLAUDE.md, AGENTS.md into ~/.claude/ and writes ~/.claude/settings.json
```

Persist the variable in your shell profile so every session sees it:

```bash
# Append to ~/.zshrc or ~/.bashrc:
export AI_RULES_REPO="$HOME/repo/claude-code-starter"
```

Verify:

```bash
ls -la ~/.claude/        # should show symlinks pointing into $AI_RULES_REPO/.claude/
```

If you already had a `~/.claude/settings.json`, setup backs it up to
`settings.json.backup-<timestamp>`. If you already had your own
`~/.claude/skills/` (or similar) folder, setup refuses to overwrite it and
tells you to move it aside first. To undo the install: `./uninstall.sh`.

Open Claude Code in any project. The rules and skills are now globally available.

## 3. Bootstrap your first project

`cd` into the project repo, then in Claude Code:

```
/init-project
```

This creates `CLAUDE.md`, `.claude/settings.local.json`, and `spec/` if missing. Commit those.

## 4. The 5-minute mental model

```
SPEC → TEST → IMPLEMENT → VERIFY
```

Every behavior change goes through this loop. Hooks warn (loudly, on stderr) when production code is edited without a corresponding spec or test — the agent is expected to stop and fix that before continuing.

- **Specs** live in `spec/features/<name>/<name>.md`. One file per feature, with user stories + AC IDs.
- **Learnings** live in `spec/learnings/<category>-<topic>.md`. Findings about the codebase that other projects might benefit from.
- **ADRs** (architectural decisions) live in `spec/decisions/NNNN-<title>.md`.

When two projects independently surface the same learning, run `/promote-learnings` from a folder containing both projects to draft a PR upstreaming the rule.

## 5. Your first feature, end-to-end

In Claude Code, in your project:

```
/feature Add user-cancellable orders within 24 hours of placement
```

The harness drafts a spec with user stories and AC IDs, asks you to confirm, then runs the full ATDD loop:

1. **Architect** drafts the spec.
2. You confirm or refine.
3. **Implementer** + **Adversary** run in parallel per AC: failing acceptance test → minimal code to pass → adversary attacks edge cases.
4. **Independent Auditor** runs `./mvnw clean verify` in a separate worktree.
5. **Requirements Reviewer** + **Adversary** + **Implementer** vote APPROVE/REJECT.
6. Commit only on unanimous APPROVE.

You don't need to memorize commands. Describe what you want; the harness routes.

## 6. When a hook warns

| Symptom | Cause | Fix |
|---|---|---|
| Warning "Modifying production source without a spec change" | `spec-first-check.sh` | Author the spec first, then retry |
| Warning "No test file found" | `require-test-first.sh` | Write the failing test first |
| Stop hook reports failing tests | `verify-before-stop.sh` | Fix tests, or `SKIP_VERIFY_STOP=true` for explicit override |
| Drift detected ("project structure changed") | `detect-structure-change.sh` | Run `/refresh-project` |
| Skills/rules out of date | Symlinks point to source | `( cd "$AI_RULES_REPO" && git pull )` |

## 7. Where to learn more

- **Rules:** `~/.claude/rules/` — start with `core.md` and `security.md`. Everything else (`testing.md`, language rules, …) is in `$AI_RULES_REPO/.claude/rules-corpus/`, listed in `~/.claude/rules/INDEX.md`.
- **Skills:** `~/.claude/skills/` — deep references searchable by topic. See `~/.claude/skills/INDEX.md` for the live catalogue (auto-regenerated; never count by hand).
- **Agents:** `~/.claude/agents/` — list of available specialists.
- **Commands:** `~/.claude/commands/` — slash commands you can invoke.
- **Workflows:** `~/.claude/workflows/feature.md`, `bugfix.md`, `planning.md`.
- **Meta-harness:** `docs/META-HARNESS.md` — how `/promote-learnings` works.
- **Project-local overrides:** `docs/OVERRIDES.md` — when project rules diverge from global.

## 8. Project-local overrides

Sometimes a project needs a rule that contradicts the global default (e.g., a Postgres-only pattern in a global rule that doesn't apply to a Mongo project). Project-local rules at `<project>/.claude/rules/<name>.md` take precedence over symlinked global rules of the same name.

See `docs/OVERRIDES.md` for the precedence rules and how to add a project-local override that survives a sync.

## 9. Contributing back upstream

Found a pattern that 2+ projects independently re-derived? Promote it:

```bash
export PROJECTS_ROOT="$HOME/repo/your-projects-folder"   # parent folder
cd "$PROJECTS_ROOT"                                       # contains all sibling project repos
# In Claude Code:
/promote-learnings
```

The command scans all sibling projects, finds convergent patterns, and drafts a PR against ai-rules. See `docs/META-HARNESS.md` for the full loop.

## 10. Common gotchas

- `~/.claude/CLAUDE.md` is the GLOBAL Claude context (loaded in every session). It's a thin default. **Project-level `CLAUDE.md`** in each repo overrides it.
- `~/.claude/codebase-map.md` is intentionally generic. Each project should write its own at `<project>/.claude/codebase-map.md`.
- The harness assumes `mvnd` is installed for Java projects. `brew install mvndaemon/tap/mvnd` if missing.
- New rules and skills need `git pull` in `$AI_RULES_REPO` to land — the symlink shows you the local checkout.

## 11. Where to ask for help

- Bugs in the harness itself: open an issue in `nasalp/claude-code-starter` (or your team's fork).
- Unclear rules or skills: PR to clarify them — every line of friction is a doc bug.
- Stuck mid-feature: `/feature` and `/multi-plan` both accept "I'm stuck on X, help me figure out next step."

Welcome to the team.
