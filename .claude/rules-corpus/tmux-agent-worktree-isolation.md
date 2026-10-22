# tmux-agent: Builder + Watchers MUST Occupy Distinct Git Worktrees

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

In any `tmux-agent` run, builder + every persistent watcher MUST operate in **its own dedicated `git worktree`**. No two agents share a working tree. Watcher MUST NEVER `git checkout` in any worktree the builder writes to.

Canonical layout:

```
/home/<user>/repo/<project>            ← non-bare main checkout (orchestrator only;
                                         MUST NOT have <build-branch> currently checked out)
~/work/agents-<run-id>/builder-wt      ← builder's worktree (writes + commits + pushes)
~/work/agents-<run-id>/watcher-wt-<role-1>   ← watcher 1 (read-only against branch under audit)
~/work/agents-<run-id>/watcher-wt-<role-2>   ← watcher 2
~/work/agents-<run-id>/watcher-wt-<role-3>   ← watcher 3
```

Each worktree created once at run start:

```bash
cd /home/<user>/repo/<project>
mkdir -p ~/work/agents-<run-id>
git fetch origin <build-branch>      # ensure remote ref exists locally
# Builder gets a named-branch worktree so commits land on <build-branch>.
git worktree add ~/work/agents-<run-id>/builder-wt <build-branch>
# Watchers stay detached so they cannot accidentally move a branch.
git worktree add --detach ~/work/agents-<run-id>/watcher-wt-security  origin/<build-branch>
git worktree add --detach ~/work/agents-<run-id>/watcher-wt-coverage  origin/<build-branch>
git worktree add --detach ~/work/agents-<run-id>/watcher-wt-prodready origin/<build-branch>
```

Watchers refresh view by:

```bash
cd ~/work/agents-<run-id>/watcher-wt-<role>
git fetch origin <build-branch>
git reset --hard origin/<build-branch>
git clean -fdx   # nuke untracked files + build artifacts from prior pass
                 # so each audit pass sees the same shape the builder pushed
```

Watchers MUST NOT:
- `cd` into orchestrator's worktree or builder's worktree
- `git checkout` any branch (creates / moves local branch; races other watchers + builder)
- `git checkout -B audit-tmp origin/<branch>` (classic anti-pattern — see Calibration)
- `git stash` or `git reset` anything outside their own detached-HEAD worktree

Builder MUST NOT:
- Write into any path under `/tmp/watcher-wt-*`
- Reset / rebase its branch in way that invalidates watcher's currently-fetched SHA without first announcing via `$RUN_DIR/builder-reset-announce.md`

## Detection

- `git -C <builder-wt> reflog -10` MUST contain only commits/amends/rebases builder authored. Any `reset:` or `checkout:` line not initiated by builder = worktree-isolation defect.
- Orchestrator monitors SHOULD include per-cycle reflog check on builder worktree; alert on unexpected `reset:` / `checkout:` lines.
- Watcher pass fetching branch HEAD SHA X but builder worktree HEAD at SHA Y ≠ X = worktree raced.

## What is forbidden

| Pattern | Why |
|---|---|
| Single worktree shared by builder + watchers | Race on `HEAD` + working tree mutation |
| Watcher running `git checkout -B audit-tmp ...` anywhere | Even in own worktree, `checkout -B` rebinds local branch name; in shared tree wipes builder; in isolated tree still confusing — `git reset --hard` is correct primitive |
| Watcher mutating files in its worktree (`Edit`, `Write`) | Watchers READ-ONLY auditors; any mutation invalidates audit |
| Builder reading files from watcher worktree | Reads technically safe but signal layering violation; builder reads only own worktree |
| `git worktree add` to path builder writes to | Same as shared-worktree case |

## What is allowed

- Orchestrator may `cd` into main repo for `git worktree add` / `git worktree list` / `git fetch`.
- Watcher may `cat` / `Read` files anywhere on disk (isolation guard is on `git` commands, not file reads — but reading BUILDER'S worktree racy because builder mid-edit; prefer `git show origin/<branch>:<path>` for branch state).
- Builder may push, pull, fetch, commit in own worktree freely.

> Rationale (Why/Cross-refs/Calibration): `docs/rule-rationale/tmux-agent-worktree-isolation.md`
