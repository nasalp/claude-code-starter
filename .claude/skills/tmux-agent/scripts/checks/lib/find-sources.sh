#!/usr/bin/env bash
# Pruned find for repo source scanning — skip build artifacts and vendor trees.

_find_prune_paths() {
  local repo="$1"
  printf '%s\n' \
    "$repo/.git" \
    "$repo/node_modules" \
    "$repo/target" \
    "$repo/build" \
    "$repo/dist" \
    "$repo/.gradle" \
    "$repo/.agent" \
    "$repo/.agent-runs" \
    "$repo/vendor" \
    "$repo/.next" \
    "$repo/coverage" \
    "$repo/.venv" \
    "$repo/__pycache__"
}

_find_source_files() {
  local repo="$1"
  shift
  local prune=()
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] && prune+=( -path "$path" -o )
  done < <(_find_prune_paths "$repo")
  # Drop trailing -o
  if ((${#prune[@]} > 0)); then
    unset 'prune[${#prune[@]}-1]'
  fi
  find "$repo" \( "${prune[@]}" \) -prune -o -type f \( "$@" \) -print | sort
}
