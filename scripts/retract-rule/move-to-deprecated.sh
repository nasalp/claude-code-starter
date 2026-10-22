#!/usr/bin/env bash
#
# scripts/retract-rule/move-to-deprecated.sh
#
# Move a rule or skill file into the parallel _deprecated/ tree, prepending a
# deprecation banner so the historical content is recoverable but no longer
# loaded as live guidance.
#
# Usage:
#   AI_RULES_REPO=/path scripts/retract-rule/move-to-deprecated.sh \
#     --rel-path '.claude/rules/<...>.md' \
#     --reason   '<one-sentence cause>' \
#     [--retracted-from '<git sha>']
#
# Exit codes:
#   0 — moved successfully; new path printed on stdout
#   1 — bad args, missing file, mv failed

set -uo pipefail

err()  { echo "[retract-rule:move] ERROR: $*" >&2; }
info() { echo "[retract-rule:move] $*" >&2; }

REL_PATH=""
REASON=""
RETRACTED_FROM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rel-path)        REL_PATH="$2"; shift 2 ;;
        --reason)          REASON="$2"; shift 2 ;;
        --retracted-from)  RETRACTED_FROM="$2"; shift 2 ;;
        *) err "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "${AI_RULES_REPO:-}" ]]; then
    err "AI_RULES_REPO is not set."
    exit 1
fi
if [[ -z "$REL_PATH" ]] || [[ -z "$REASON" ]]; then
    err "Both --rel-path and --reason are required."
    exit 1
fi

SRC="$AI_RULES_REPO/$REL_PATH"
if [[ ! -f "$SRC" ]]; then
    err "Source file does not exist: $SRC"
    exit 1
fi

# Compute destination — mirror the path under .claude/<live-tree>/_deprecated/.
case "$REL_PATH" in
    .claude/rules/*)
        SUB=".claude/rules/_deprecated/${REL_PATH#.claude/rules/}"
        ;;
    .claude/skills/*)
        # For skills, the file is .claude/skills/<name>/SKILL.md — move the
        # whole directory under _deprecated/.
        SKILL_NAME=$(echo "$REL_PATH" | sed -E 's|^\.claude/skills/([^/]+)/.*|\1|')
        if [[ -z "$SKILL_NAME" ]] || [[ "$SKILL_NAME" == "$REL_PATH" ]]; then
            err "Could not parse skill name from $REL_PATH"
            exit 1
        fi
        SUB=".claude/skills/_deprecated/$SKILL_NAME/SKILL.md"
        ;;
    *)
        err "Unsupported live tree for retraction: $REL_PATH"
        err "Only .claude/rules/ and .claude/skills/ are supported."
        exit 1
        ;;
esac

DEST="$AI_RULES_REPO/$SUB"

# Track every directory we create with mkdir -p so we can rmdir-walk them on
# rollback. Without this, a failed retraction leaves empty `_deprecated/java/`
# (or similar) directories behind even though the working tree is otherwise
# restored.
CREATED_DIRS=()
# ensure_dir creates `target` (and any missing ancestors) one level at a
# time and records each newly-created directory in CREATED_DIRS so a later
# rollback can rmdir them in reverse. Returns non-zero on mkdir failure so
# the caller can abort with a clear diagnostic instead of letting a later
# `mv` produce a misleading "No such file or directory" error.
ensure_dir() {
    local target="$1"
    [[ -z "$target" ]] && return 0
    [[ -d "$target" ]] && return 0
    local parent
    parent=$(dirname "$target")
    if [[ "$parent" != "$target" ]] && [[ ! -d "$parent" ]]; then
        ensure_dir "$parent" || return 1
    fi
    if mkdir "$target" 2>/dev/null; then
        CREATED_DIRS+=("$target")
        return 0
    fi
    err "cannot create directory: $target (mkdir failed — check permissions or disk space)"
    return 1
}

if ! ensure_dir "$(dirname "$DEST")"; then
    # Note: BANNER_FILE is not yet created at this point in the script, so
    # there is nothing to clean up here. Any cleanup must happen at exits
    # AFTER the mktemp on the next block.
    exit 1
fi

TODAY=$(date -u +%Y-%m-%d)
BANNER_FILE=$(mktemp)
{
    echo "> **DEPRECATED on $TODAY.**"
    echo ">"
    echo "> Reason: $REASON"
    if [[ -n "$RETRACTED_FROM" ]]; then
        echo ">"
        echo "> Retracted-from: $RETRACTED_FROM"
    fi
    echo ">"
    echo "> See: spec/decisions/rejected-promotions.md for full context."
    echo
    echo "---"
    echo
} > "$BANNER_FILE"

# Build the move plan: rule first, then any sibling sidecars. Each entry is
# "src|dest". We attempt every move in sequence and on the FIRST failure
# revert all completed moves so the working tree and git index never end up
# partially staged. This guarantees atomicity from the operator's POV: either
# the entire retraction lands cleanly, or the tree looks exactly like it did
# before the script ran.
PLAN=("$REL_PATH|$SUB")

SIDECAR_BASE_SRC="${REL_PATH%.md}"
SIDECAR_BASE_DEST="${SUB%.md}"
SIDECAR_EXTENSIONS=(compliance.regex)
for ext in "${SIDECAR_EXTENSIONS[@]}"; do
    SIDECAR_REL_SRC="${SIDECAR_BASE_SRC}.${ext}"
    if [[ -f "$AI_RULES_REPO/$SIDECAR_REL_SRC" ]]; then
        SIDECAR_REL_DEST="${SIDECAR_BASE_DEST}.${ext}"
        PLAN+=("$SIDECAR_REL_SRC|$SIDECAR_REL_DEST")
    fi
done

USE_GIT=false
if [[ -d "$AI_RULES_REPO/.git" ]] && command -v git >/dev/null 2>&1; then
    USE_GIT=true
fi

# Execute the plan with rollback on failure.
COMPLETED=()
move_one() {
    local src="$1" dest="$2"
    if [[ "$USE_GIT" == "true" ]]; then
        ( cd "$AI_RULES_REPO" && git mv "$src" "$dest" ) >/dev/null 2>&1
    else
        # Propagate ensure_dir failure so move_one returns non-zero with the
        # right diagnostic, instead of letting `mv` produce a misleading
        # "No such file or directory".
        ensure_dir "$(dirname "$AI_RULES_REPO/$dest")" || return 1
        mv "$AI_RULES_REPO/$src" "$AI_RULES_REPO/$dest"
    fi
}

# When rollback itself fails (a "double failure"), the operator must know.
# Silently swallowing the error is worse than the original problem because
# it leaves the index in an unknown state with zero diagnostic output.
ROLLBACK_FAILURES=()

revert_all() {
    # Iterate completed list in reverse so dependencies unwind cleanly.
    local i
    for ((i=${#COMPLETED[@]}-1; i>=0; i--)); do
        local entry="${COMPLETED[$i]}"
        local prev_src="${entry%|*}"
        local prev_dest="${entry#*|}"
        local rc=0
        if [[ "$USE_GIT" == "true" ]]; then
            ( cd "$AI_RULES_REPO" && git mv "$prev_dest" "$prev_src" ) >/dev/null 2>&1 || rc=$?
        else
            mv "$AI_RULES_REPO/$prev_dest" "$AI_RULES_REPO/$prev_src" 2>/dev/null || rc=$?
        fi
        if [[ $rc -ne 0 ]]; then
            ROLLBACK_FAILURES+=("$prev_dest → $prev_src")
        fi
    done

    # rmdir any directories the script created during this run, in
    # reverse-creation order. rmdir naturally refuses non-empty dirs, so
    # this is safe — pre-existing dirs that happened to be on the path
    # are not affected.
    for ((i=${#CREATED_DIRS[@]}-1; i>=0; i--)); do
        rmdir "${CREATED_DIRS[$i]}" 2>/dev/null || true
    done

    # Surface any rollback failures explicitly. Exit code from the caller
    # is still non-zero; this just makes sure the operator sees what could
    # not be undone.
    if [[ ${#ROLLBACK_FAILURES[@]} -gt 0 ]]; then
        err "ROLLBACK INCOMPLETE — the following inverse moves failed:"
        for f in "${ROLLBACK_FAILURES[@]}"; do
            err "  $f"
        done
        err "The git index may be partially staged. Run 'git -C \"$AI_RULES_REPO\" status' and either resolve manually or use 'git restore --staged .'."
    fi
}

for entry in "${PLAN[@]}"; do
    src="${entry%|*}"
    dest="${entry#*|}"
    if move_one "$src" "$dest"; then
        COMPLETED+=("$src|$dest")
    else
        err "move failed: $src → $dest. Rolling back ${#COMPLETED[@]} prior move(s)."
        revert_all
        rm -f "$BANNER_FILE"
        exit 1
    fi
done

# Prepend the banner to the moved rule file. If this step itself fails, we
# still roll back the moves so the operator sees a consistent state.
TMP=$(mktemp)
if ! cat "$BANNER_FILE" "$DEST" > "$TMP"; then
    err "banner prepend failed for $DEST. Rolling back."
    revert_all
    rm -f "$BANNER_FILE" "$TMP"
    exit 1
fi
mv "$TMP" "$DEST" || { err "banner write failed for $DEST."; revert_all; rm -f "$BANNER_FILE"; exit 1; }
rm -f "$BANNER_FILE"

# Surface the sidecar moves to the operator for the audit trail in the PR body.
for entry in "${COMPLETED[@]:1}"; do
    src="${entry%|*}"
    dest="${entry#*|}"
    info "  also moved sidecar: $src → $dest"
done

echo "$SUB"
info "Moved $REL_PATH → $SUB and prepended deprecation banner."
exit 0
