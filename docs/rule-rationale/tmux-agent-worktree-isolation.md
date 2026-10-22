# Rationale — tmux-agent-worktree-isolation

## Why

Git's working tree is shared filesystem state. Two agents calling `git checkout`
in the same directory race each other:

1. Watcher fires `git checkout -B audit-tmp origin/<build-branch>` to "get latest"
2. That command mutates HEAD in the directory it ran in — for ALL processes
3. The builder, mid-edit, finds its working tree reset under it; uncommitted edits silently disappear
4. The builder's just-committed RED commit gets replaced by `audit-tmp` (which points at origin)
5. Builder re-applies its edits unaware that its prior commit is gone
6. Next watcher pass repeats the cycle every ~60s
7. Build never advances; reflog shows ghost commits that appear and disappear

`git worktree add` exists specifically to give multiple workers independent
working trees backed by a single bare repo. Use it.

## Cross-references

- `~/.claude/skills/tmux-agent/SKILL.md` — Phase 0 / Phase 4½: the worktree
  creation is now part of Phase 0 setup.
- `~/.claude/rules/watchers-must-observe-live-tmux.md` — partner rule on
  capturing live pane state per pass; this rule is about file-system
  isolation between the builder and the watchers that watch it.
- `~/.claude/rules/parallel-cli-sessions.md` "Fast smoke test" — the
  companion-pre-spawn-smoke section of this rule is the worktree-specific
  application of that rule's general advice.

## Why not `/tmp`?

`/tmp` is volatile — most distros either wipe it on reboot or have `systemd-tmpfiles-clean.service` periodically delete files older than N days. If the physical worktree directory disappears while its git metadata in `/home/<user>/repo/<project>/.git/worktrees/<name>/` survives, the next `git worktree add <same-path>` fails with `fatal: '<path>' already exists`, and `git worktree list` reports the stale entry. Recovery requires `git worktree prune` (removes the orphan metadata) before re-adding. For a long-running orchestrator that may span reboots, prefer a stable parent under `~/work/` (or `$XDG_DATA_HOME/agents/`). Short-lived dev sessions may still use `/tmp` if the operator is OK with manual `git worktree prune` after every reboot.

## Repo type

The orchestrator's main checkout MUST be a normal (non-bare) repository, AND `<build-branch>` MUST NOT be its currently-checked-out branch. If `<build-branch>` IS checked out in the main repo, `git worktree add <path> <build-branch>` fails with `fatal: '<build-branch>' is already checked out at '<main path>'`. The orchestrator must either switch the main repo to a different branch first (e.g. `main`) or use `--detach` when adding the builder worktree (which gives up the named-branch convenience but bypasses the check).

## Companion: pre-spawn smoke test

Before spawning the full N-watcher fleet, run ONE watcher pass against ONE isolated worktree and verify:

1. The watcher's verdict file is non-empty (proves `claude --print` + tools work).
2. `git -C /tmp/builder-wt reflog -10` shows NO `reset:` or `checkout:` lines triggered by the watcher.
3. The builder's working tree on the build branch is unchanged.

Only after the smoke passes do you spawn the remaining watchers. This catches the worktree-collision class of bug in ~3 minutes instead of after 30+ minutes of corrupted commits.
