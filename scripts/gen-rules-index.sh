#!/usr/bin/env bash
# Generate .claude/rules/INDEX.md from always-on rules + rules-corpus.
set -euo pipefail

REPO_ROOT="${AI_RULES_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
RULES_DIR="$REPO_ROOT/.claude/rules"
CORPUS_DIR="$REPO_ROOT/.claude/rules-corpus"
OUT="$RULES_DIR/INDEX.md"

command -v yq >/dev/null 2>&1 || { echo "gen-rules-index: yq not found on PATH" >&2; exit 2; }

_rule_meta() {
  local f="$1"
  local name desc roles always_on rel
  name="$(yq --front-matter=extract -r '.name // .id // ""' "$f" 2>/dev/null || true)"
  if [[ -z "$name" ]]; then
    name="$(basename "$f" .md)"
  fi
  desc="$(yq --front-matter=extract -r '.description // ""' "$f" 2>/dev/null || true)"
  if [[ -z "$desc" ]]; then
    desc="$(awk 'BEGIN{fm=1} /^---$/{fm++; next} fm==2{next} /^# /{sub(/^# +/,""); print; exit}' "$f")"
  fi
  if [[ -z "$desc" ]]; then
    echo "gen-rules-index: missing description in $f (add frontmatter description: or a # heading)" >&2
    return 1
  fi
  roles="$(yq --front-matter=extract -r '(.roles // []) | join(",")' "$f" 2>/dev/null || true)"
  always_on="$(yq --front-matter=extract -r '.always_on // false' "$f" 2>/dev/null || true)"
  rel="${f#"$REPO_ROOT/"}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$desc" "$rel" "$roles" "$always_on"
}

rows=()
while IFS= read -r f; do
  base="$(basename "$f")"
  [[ "$base" == "INDEX.md" || "$base" == "README.md" ]] && continue
  row="$(_rule_meta "$f")" || exit 1
  rows+=("$row")
done < <(find "$RULES_DIR" "$CORPUS_DIR" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)

IFS=$'\n' sorted=($(printf '%s\n' "${rows[@]}" | LC_ALL=C sort -t $'\t' -k1,1f))
unset IFS

{
  echo "# Rules index (generated — do not edit)"
  echo
  echo "> Regenerate: \`bash scripts/gen-rules-index.sh\`"
  echo
  echo "| name | description | path | roles | always_on |"
  echo "| --- | --- | --- | --- | --- |"
  for row in "${sorted[@]}"; do
    IFS=$'\t' read -r name desc rel roles always_on <<<"$row"
    echo "| $name | $desc | $rel | ${roles:-—} | ${always_on:-false} |"
  done
} > "$OUT"

echo "gen-rules-index: wrote $OUT (${#sorted[@]} rules)"
