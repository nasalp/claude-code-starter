# Project-Local Overrides

How project-specific configuration coexists with the symlinked global harness — and how to add overrides that survive a sync.

## Precedence rules

Claude Code reads from BOTH `~/.claude/` (global, symlinked from this repo) and `<project>/.claude/` (project-local). For files with the same name, **project-local wins**.

| Path | Source | Precedence |
|---|---|---|
| `~/.claude/CLAUDE.md` | Symlink → `ai-rules/CLAUDE.md` | Loaded as global default |
| `<project>/CLAUDE.md` | Project-owned | Overrides global per-session |
| `~/.claude/rules/foo.md` | Symlink → `ai-rules/.claude/rules/foo.md` | Loaded for every project |
| `<project>/.claude/rules/foo.md` | Project-owned | Overrides global `foo.md` |
| `~/.claude/skills/foo/SKILL.md` | Symlink | Available globally |
| `<project>/.claude/skills/foo/SKILL.md` | Project-owned | Overrides global skill |
| `~/.claude/settings.json` | Written by `setup.sh` | Global hooks |
| `<project>/.claude/settings.local.json` | Project-owned, gitignored | Layered on top |

## When to add a project-local override

Three legitimate reasons:

1. **Domain-specific rule** that doesn't apply globally. Example: a healthcare-only rule about PHI redaction in a healthcare project; not relevant to an infrastructure repo.
2. **Stack-specific override** of a generic rule. Example: a global rule that says "use Caffeine cache" doesn't apply to a project using Hazelcast — write a project-local override.
3. **Temporary deviation pending upstream** discussion. Example: you discovered a new pattern but haven't run `/promote-learnings` yet. Park it project-local, promote later.

## When NOT to add a project-local override

- The global rule is wrong. Fix it upstream via PR — don't fork it project-local.
- You disagree with the rule. Discuss with the team. Forking silently in a project is governance debt.
- You're prototyping. Use `SPEC_BYPASS=true` env var rather than committing project-local exceptions.

## How to add a project-local rule

1. Create the file at `<project>/.claude/rules/<name>.md`. Use the same name as the global rule it overrides (or a new name for a new rule).
2. If overriding, start the body with: `> Overrides global \`~/.claude/rules/<name>.md\`. Reason: <one sentence>.`
3. Commit it to the project repo. It survives `/refresh-project` and re-installs.

Example: a project-level `.claude/rules/no-custom-spring-profiles.md` can be a redirect-style override pointing at the upstream rule plus a project-specific carve-out (canonical script path, module list).

## How to add a project-local skill

1. Create `<project>/.claude/skills/<name>/SKILL.md`.
2. If the skill exists globally and you're overriding, add a top-of-file note: `> Overrides global skill of the same name. Reason: <…>`.
3. Commit it.

A project-local skill takes precedence in skill discovery within that project's sessions, but globally other projects still see the upstream version.

## What happens on `/refresh-project`

`/refresh-project` syncs the project-local `.claude/` against expectations from the global harness (e.g., new agents, new commands). It does NOT touch:

- Files with `> Overrides global` in their first 10 lines.
- Files in `<project>/.claude/rules/_local/` (a reserved namespace for permanently-project-only rules).
- `<project>/.claude/settings.local.json`.
- The `<project>/CLAUDE.md` (only updates on explicit `/init-project`).

## What happens on `setup.sh`

`setup.sh` (run once at install time) symlinks every directory and file under `ai-rules/.claude/` into `~/.claude/`. It does NOT touch project-local `.claude/` directories. It also skips `settings*.json` so per-machine settings survive.

If you ever want to start fresh: `./uninstall.sh` removes every symlink in `~/.claude/` that points into this repo, then re-run `./setup.sh`.

## Settings layering

`~/.claude/settings.json` (written by `setup.sh`) is the global hook config. Project-local additions go in `<project>/.claude/settings.local.json`, which Claude Code merges on top per session.

To add a project-only hook:

```json
// <project>/.claude/settings.local.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "${HOME}/repo/<project>/.claude/hooks/project-specific-check.sh" }
        ],
        "description": "Project-only enforcement"
      }
    ]
  }
}
```

The project-local file is gitignored by default — if you want the team to share it, gitignore-overrule it explicitly.

## Promotion path

When a project-local rule starts looking generally useful, promote it:

```bash
cd $PROJECTS_ROOT/   # parent folder
# In Claude Code:
/promote-learnings
```

If two projects have converged on the same rule, the command drafts a PR upstreaming it. After merge, you can usually delete the project-local copy (the global rule covers it). See `docs/META-HARNESS.md`.

## Common gotchas

- **Renaming the project-local override doesn't sever the link.** If you rename `<project>/.claude/rules/foo.md` to `.../foo-2.md`, the global `foo.md` is now active again. Be deliberate.
- **Override files in `<project>/.claude/` are NOT auto-synced from any source.** They're project-owned. The promotion path is one-way (project → global).
- **Two projects with conflicting overrides don't talk to each other.** That's the point — overrides are project-scoped. If you want consistency, promote upstream.
- **A symlinked `~/.claude/foo.md` and a project `<project>/.claude/foo.md` with the same name don't conflict on disk.** Claude Code reads them as separate files; project-local wins per-session.

## See also

- `docs/META-HARNESS.md` — promotion loop
- `docs/DAY-0.md` — first-time onboarding
- `setup.sh` — install-time linking script
- `uninstall.sh` — uninstall
