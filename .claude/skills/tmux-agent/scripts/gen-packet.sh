#!/usr/bin/env bash
# gen-packet.sh <role> <out> [--task f] [--plan f] [--diff f] [--repo d] [--severity csv]
# Assemble a role-scoped task packet from templates/packets/<role>.md.
# CACHING DISCIPLINE: the stable, deterministically-sorted RULES block is emitted
# BEFORE any dynamic task/diff content so the prompt prefix stays cache-stable.
set -uo pipefail

GP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$GP_DIR/.." && pwd)"

role="${1:-}" out="${2:-}"
[[ -n "$role" && -n "$out" ]] || { echo "usage: gen-packet.sh <role> <out> [--task f --plan f --diff f --repo d --severity csv]" >&2; exit 2; }
shift 2

task="" plan="" diff="" repo="" severity=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) task="$2"; shift 2;;
    --plan) plan="$2"; shift 2;;
    --diff) diff="$2"; shift 2;;
    --repo) repo="$2"; shift 2;;
    --severity) severity="$2"; shift 2;;
    *) echo "gen-packet: unknown arg $1" >&2; exit 2;;
  esac
done

tmpl="$SKILL_DIR/templates/packets/${role}.md"
[[ -f "$tmpl" ]] || { echo "gen-packet: no template for role '$role' ($tmpl)" >&2; exit 1; }

# Build the RULES block (sorted rule paths + their content) for this role.
rules_block="$(mktemp)"
sev_args=()
[[ -n "$severity" ]] && sev_args=(--severity "$severity")
while IFS= read -r rp; do
  [[ -z "$rp" ]] && continue
  echo "### ${rp##*/}"
  echo '```'
  cat "$rp"
  echo '```'
# `${sev_args[@]+...}` guards the empty-array case: bash 3.2 (macOS /bin/bash) under
# `set -u` errors on a bare "${sev_args[@]}" when the array is empty.
done < <(bash "$GP_DIR/select-rules.sh" --role "$role" ${sev_args[@]+"${sev_args[@]}"} 2>/dev/null) > "$rules_block"

# Verdict schema for roles that emit structured output.
schema=""
case "$role" in
  watcher)  schema="$SKILL_DIR/config/verdict-schemas/watcher.schema.json";;
  reviewer) schema="$SKILL_DIR/config/verdict-schemas/reviewer.schema.json";;
esac

# Render: replace whole-line placeholders with file/section content.
_emit_file() { [[ -n "$1" && -f "$1" ]] && cat "$1" || echo "(none)"; }

{
  # Stable workspace hint first (deterministic; preserves prefix-cache).
  [[ -n "$repo" ]] && echo "> Workspace: $repo"
  while IFS= read -r line; do
    case "$line" in
      '{{RULES}}')          cat "$rules_block";;
      '{{TASK}}')           _emit_file "$task";;
      '{{PLAN}}')           _emit_file "$plan";;
      '{{DIFF}}')           _emit_file "$diff";;
      '{{VERDICT_SCHEMA}}') [[ -n "$schema" && -f "$schema" ]] && cat "$schema" || echo "(no schema)";;
      *)                    printf '%s\n' "$line";;
    esac
  done < "$tmpl"
} > "$out"

rm -f "$rules_block"
echo "gen-packet: wrote $out (role=$role)"
