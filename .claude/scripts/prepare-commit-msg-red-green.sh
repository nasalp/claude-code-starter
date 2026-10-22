#!/usr/bin/env bash
# prepare-commit-msg-red-green.sh — opt-in Git hook that pre-populates
# new commit messages with the RED→GREEN proof template documented in
# .claude/templates/commit-msg-red-green.md.
#
# Install (per-repo, opt-in):
#   cp .claude/scripts/prepare-commit-msg-red-green.sh .git/hooks/prepare-commit-msg
#   chmod +x .git/hooks/prepare-commit-msg
#
# Git invokes this hook with two args:
#   $1 = path to commit message file
#   $2 = source of the commit message (empty for plain `git commit`,
#        "message" for `-m`, "template", "merge", "squash", "commit"
#        for amend)
#
# Behavior:
#   - Skip silently when the commit is amend/merge/squash or when the
#     user passed -m / -F / --template (i.e. msg_source is non-empty
#     AND not "message").
#   - For a fresh `git commit` (msg_source empty) AND when the user has
#     NOT yet written a non-comment body line, append the template
#     comment block so the editor pre-populates with the section
#     headers. The user fills in the bodies (or deletes the whole
#     block for trivial commits — see the "When to use which sections"
#     table in the template doc).
#   - If the user has ALREADY written a non-comment body line (e.g.
#     they passed `--cleanup=verbatim` and prepared a message), do NOT
#     append — they've already authored, the template would clutter.
#
# Exit:
#   0 always (a prepare-commit-msg hook must not fail the commit).

set -uo pipefail

main() {
  local msg_file="${1:-}"
  local msg_source="${2:-}"

  if [[ -z "$msg_file" || ! -f "$msg_file" ]]; then
    return 0
  fi

  # Skip on amend / merge / squash / template / -m / -F / commit re-edit.
  # Only fire on a fresh interactive commit where Git invokes the editor
  # with an empty (or comment-only) message file.
  if [[ -n "$msg_source" ]]; then
    return 0
  fi

  # If the user has already written a non-comment line, leave it alone.
  # `^[^#]` matches any line not starting with `#` (Git's comment char).
  if grep -qE '^[^#].+' "$msg_file" 2>/dev/null; then
    return 0
  fi

  # File is empty or comment-only — pre-populate with the template.
  cat >> "$msg_file" <<'TEMPLATE'

# ---- COMMIT BODY TEMPLATE (per .claude/templates/commit-msg-red-green.md) ----
# Delete this template AND replace section bodies with real content
# OR delete the whole comment block if your commit shape doesn't need it
# (see "When to use which sections" in the template doc).
#
# ## RED → GREEN proof
#
# RED   : <sha> — <test name>
#         Reproduction:
#           $ <command>
#           <quoted FAIL tail>
#
# GREEN : <this commit> — <test name>
#         Reproduction:
#           $ <command>
#           <quoted PASS tail>
#
# ## Local verify
#
#   typecheck:     PASS | FAIL | BROKEN-PRE-EXISTING
#   lint:          PASS | FAIL | BROKEN-PRE-EXISTING
#   test:coverage: PASS (lines X% / stmt Y% / branch Z% / fn W%)
#   build:         PASS | FAIL
#
# ## ACs covered
# - AC-XYZ-N: <one-line>
#
# ## Files touched
# - <path> (+X / -Y) — <what/why>
#
# ## Not in scope
# - <bullet> — <reason>
TEMPLATE
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
