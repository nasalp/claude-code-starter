#!/usr/bin/env bash
# Example: spawn one watcher under tmux. Wire one of these per tag.
# Usage: spawn-watcher.sh RUN_ID TAG REPO BRANCH_REF PR_REPO BUILDER_OUT BRIEF VERDICT_DIR
# BRANCH_REF: pass `origin/foo` to track pushed commits OR `foo` to track local.
set -uo pipefail

RUN_ID="$1"
TAG="$2"
REPO="$3"
BRANCH_REF="$4"
PR_REPO="$5"
BUILDER_OUT="$6"
BRIEF="$7"
VERDICT_DIR="$8"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"

_quote() {
  printf '%q' "$1"
}

cmd="env"
if [[ -n "${HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON:-}" ]]; then
  cmd+=" HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON=$(_quote "$HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON")"
  cmd+=" HEADROOM_LOCAL_CLAUDE_PROXY_PORT=$(_quote "${HEADROOM_LOCAL_CLAUDE_PROXY_PORT:-8787}")"
fi
cmd+=" bash $(_quote "${SCRIPT_DIR}/watcher-loop.sh")"
cmd+=" $(_quote "$REPO") $(_quote "$BRANCH_REF") $(_quote "$PR_REPO")"
cmd+=" $(_quote "$BUILDER_OUT") $(_quote "$BRIEF") $(_quote "$VERDICT_DIR")"
cmd+=" $(_quote "builder-${RUN_ID}")"

tmux new-session -d -s "watch-${TAG}-${RUN_ID}" \
  "$cmd"
