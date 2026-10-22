# Session Lifecycle

## Auto-Init Detection

At session start `SessionStart` hook checks project init; if items missing injects message listing what's absent.

**When you see "PROJECT INIT CHECK: Incomplete setup detected":**
1. Inform user project needs initialization
2. List specific missing items
3. Suggest running `/user:init-project` to set up
4. Do NOT block work — user may proceed without full setup

**Items checked:**
- `CLAUDE.md` in project root
- `.claude/settings.json` (project-level hooks)
- `.claude/hooks/` (enforcement hooks)
- `.claude/rules/` (coding standards)
- `spec/` directory (feature specifications)

## Post-Compaction Recovery

After compaction, CLAUDE.md and rules auto-reload, but task-specific context (file you were editing, feature being implemented) may be lost.

**Recovery protocol — after any compaction:**

1. **Check for FEATURE.md** in project root. If exists, read immediately — holds active feature spec.

2. **Check for compaction state.** `SessionStart` hook may inject `Post-compaction context restore:` block with JSON containing:
   - `featureMd` — summary of active spec (read full file)
   - `branch` — git branch you were on
   - `modifiedFiles` — files with uncommitted changes
   - `hooksExecutable` — whether hooks properly configured

3. **Verify current state** with `git status` and `git diff --stat`.

4. **Re-read active spec** if `FEATURE.md` or specific spec file referenced in compaction state.

5. **Do NOT re-run completed work.** Compaction summary should say what was done. Pick up where you left off.

**If context thin and unsure what was happening:**
- Run `git log --oneline -5` for recent commits
- Run `git diff --stat` for uncommitted changes
- Check for `FEATURE.md` in project root
- Ask user for clarification if needed
