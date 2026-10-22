#!/usr/bin/env bash
#
# setup.sh — install the ai-rules Claude Code harness on a developer machine.
#
# What it does:
#   1. Symlinks the repo's .claude/* (rules, agents, commands, skills, hooks,
#      workflows, ...) plus CLAUDE.md and AGENTS.md into ~/.claude/.
#   2. Writes ~/.claude/settings.json from .claude/settings.json.template
#      (hook wiring). An existing, different settings.json is backed up first.
#
# Safe to re-run: entries that are already correct are reported as "ok" and
# left untouched. Existing non-empty directories and regular files in
# ~/.claude are never overwritten — setup.sh stops and tells you what to move.
#
# Flags:
#   --dry-run    Report what would change without touching anything.
#   --no-hooks   Skip step 2 (leave ~/.claude/settings.json alone).
#   --help, -h   Show this help.
#
# Undo with ./uninstall.sh.

set -euo pipefail

usage() {
    sed -n '/^# setup.sh/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

DRY_RUN=false
DO_HOOKS=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true; shift ;;
        --no-hooks) DO_HOOKS=false; shift ;;
        --help|-h)  usage; exit 0 ;;
        *) echo "[setup] ERROR: unknown flag: $1" >&2; usage >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$REPO_ROOT/.claude"
CLAUDE_HOME="$HOME/.claude"

if [[ ! -d "$CLAUDE_DIR" ]]; then
    echo "[setup] ERROR: $CLAUDE_DIR does not exist — is this an ai-rules checkout?" >&2
    exit 1
fi

CHANGES=0
SKIPS=0
FAILURES=0

note()    { echo "[setup] $*"; }
ok()      { echo "  ok    $*"; SKIPS=$((SKIPS + 1)); }
applied() { echo "  +     $*"; CHANGES=$((CHANGES + 1)); }
would()   { echo "  would $*"; CHANGES=$((CHANGES + 1)); }
warn()    { echo "  warn  $*" >&2; }
err()     { echo "[setup] ERROR: $*" >&2; }

ensure_dir() {
    local target="$1"
    [[ -d "$target" ]] && return 0
    if [[ "$DRY_RUN" == "true" ]]; then
        would "mkdir -p $target"
        return 0
    fi
    mkdir -p "$target"
}

# Link target into dst. Already-correct symlink → ok. Stale symlink → replace.
# Empty directory → replace. Non-empty directory or regular file → refuse
# (never silently destroy user state).
link_one() {
    local target="$1" dst="$2"
    if [[ -L "$dst" ]]; then
        local actual
        actual=$(readlink "$dst")
        if [[ "$actual" == "$target" ]]; then
            ok "$dst -> $target"
            return 0
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            would "refresh stale symlink: $dst (was: $actual, want: $target)"
            return 0
        fi
        ln -sfn "$target" "$dst"
        applied "refreshed $dst -> $target (was: $actual)"
        return 0
    fi
    if [[ -e "$dst" ]]; then
        if [[ -d "$dst" && -z "$(ls -A "$dst" 2>/dev/null)" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                would "replace empty dir with symlink: $dst -> $target"
                return 0
            fi
            rmdir "$dst"
            ln -sfn "$target" "$dst"
            applied "replaced empty dir with symlink: $dst -> $target"
            return 0
        fi
        if [[ -d "$dst" ]]; then
            err "refusing to overwrite non-empty directory: $dst"
        else
            err "refusing to overwrite regular file: $dst"
        fi
        err "  move it aside (mv '$dst' '$dst.bak') and re-run setup.sh."
        FAILURES=$((FAILURES + 1))
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        would "link $dst -> $target"
        return 0
    fi
    ln -sfn "$target" "$dst"
    applied "$dst -> $target"
}

# -------- Step 0: prerequisites (warn only) --------
note "0) Checking prerequisites"
for cmd in claude git node python3 jq; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd found"
    else
        warn "$cmd not found on PATH — see docs/DAY-0.md"
    fi
done

# -------- Step 1: link the repo's .claude/* into ~/.claude --------
note "1) Linking $CLAUDE_DIR -> $CLAUDE_HOME"
ensure_dir "$CLAUDE_HOME"
for item in "$CLAUDE_DIR"/*; do
    [[ -e "$item" ]] || continue
    name=$(basename "$item")
    # Lazy-loaded rule corpus stays repo-local; agents Read it by path from rules/INDEX.md.
    [[ "$name" == "rules-corpus" ]] && continue
    # settings* are machine-local; settings.json is rendered in step 2.
    [[ "$name" == settings* ]] && continue
    # CLAUDE.md / AGENTS.md are linked from the repo root below.
    [[ "$name" == "CLAUDE.md" || "$name" == "AGENTS.md" ]] && continue
    link_one "$item" "$CLAUDE_HOME/$name"
done
for file in CLAUDE.md AGENTS.md; do
    src="$REPO_ROOT/$file"
    [[ -f "$src" ]] || continue
    link_one "$src" "$CLAUDE_HOME/$file"
done

# -------- Step 2: install ~/.claude/settings.json from template --------
if [[ "$DO_HOOKS" == "true" ]]; then
    note "2) Installing $CLAUDE_HOME/settings.json from template"
    template="$CLAUDE_DIR/settings.json.template"
    target="$CLAUDE_HOME/settings.json"
    if [[ ! -f "$template" ]]; then
        err "template not found: $template"
        exit 1
    fi
    rendered=$(sed \
        -e "s|{{SCRIPTS}}|$CLAUDE_DIR/scripts/hooks|g" \
        -e "s|{{HOOKS}}|$CLAUDE_DIR/hooks|g" \
        -e "s|{{SKILLS}}|$CLAUDE_DIR/skills|g" \
        "$template")
    if [[ -f "$target" ]] && [[ "$(cat "$target")" == "$rendered" ]]; then
        ok "$target (content matches template)"
    elif [[ "$DRY_RUN" == "true" ]]; then
        [[ -f "$target" ]] && would "back up existing $target"
        would "write $target"
    else
        if [[ -f "$target" ]]; then
            backup="$target.backup-$(date +%Y%m%d-%H%M%S)"
            cp "$target" "$backup"
            applied "backed up existing settings to $backup"
        fi
        printf '%s\n' "$rendered" > "$target"
        applied "$target"
        if command -v jq >/dev/null 2>&1 && ! jq empty "$target" >/dev/null 2>&1; then
            err "generated $target is not valid JSON — check the template"
            exit 1
        fi
    fi
else
    note "2) Skipping settings.json (--no-hooks)"
fi

echo
note "Summary: $CHANGES change(s), $SKIPS already-correct, $FAILURES refused."
if [[ "$DRY_RUN" == "true" ]]; then
    note "Dry run — no filesystem changes were made."
fi
if [[ $FAILURES -gt 0 ]]; then
    note "Some paths were refused (see errors above). Move them aside and re-run."
    exit 1
fi
cat <<EOF

Next steps:
  1. Add to your shell profile (~/.zshrc or ~/.bashrc):
       export AI_RULES_REPO="$REPO_ROOT"
  2. Open Claude Code in a project repo and run:  /init-project
  3. Read docs/DAY-0.md for the day-to-day flow.
EOF
