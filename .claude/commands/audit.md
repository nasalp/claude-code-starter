# Audit Claude Code Setup

Checks global and project config. Reports what is missing or misconfigured.

## Global files

Run:
  [ -f ~/.claude/GLOBAL.md ]            && echo "OK GLOBAL.md"         || echo "MISSING GLOBAL.md"
  [ -d ~/.claude/commands ]             && echo "OK commands/"          || echo "MISSING commands/"
  [ -d ~/.claude/rules ]                && echo "OK rules/"             || echo "MISSING rules/"
  [ -d ~/.claude/skills ]               && echo "OK skills/"            || echo "MISSING skills/"
  [ -d ~/.claude/agents ]               && echo "OK agents/"            || echo "MISSING agents/"

## Agent definitions

Run:
  [ -f ~/.claude/agents/implementer.md ]           && echo "OK implementer"           || echo "MISSING implementer"
  [ -f ~/.claude/agents/adversary.md ]             && echo "OK adversary"             || echo "MISSING adversary"
  [ -f ~/.claude/agents/requirements-reviewer.md ] && echo "OK requirements-reviewer" || echo "MISSING requirements-reviewer"

## Global commands

Run:
  for cmd in init-project refresh-project feature audit audit-skills tag-rules; do
    [ -f ~/.claude/commands/${cmd}.md ] && echo "OK ${cmd}" || echo "MISSING ${cmd}"
  done

## Rule frontmatter

Run:
  for f in ~/.claude/rules/*.md; do
    [ -f "$f" ] || continue
    head -1 "$f" | grep -q '^---' \
      && echo "OK $(basename $f)" \
      || echo "NO FRONTMATTER $(basename $f) — run /user:tag-rules"
  done

## Project config

Run:
  [ -f CLAUDE.md ]                       && echo "OK CLAUDE.md"         || echo "MISSING — run /user:init-project"
  [ -f .claudeignore ]                   && echo "OK .claudeignore"      || echo "MISSING"
  [ -f .claude/settings.json ]           && echo "OK settings.json"      || echo "MISSING"
  [ -f .claude/project-snapshot.json ]   && echo "OK snapshot"           || echo "MISSING"

## CLAUDE.md imports

Run:
  [ -f CLAUDE.md ] || { echo skipped no CLAUDE.md; exit 0; }
  grep -q '@~/.claude/GLOBAL.md' CLAUDE.md && echo "OK imports GLOBAL.md" || echo "MISSING @~/.claude/GLOBAL.md import"
  COUNT=$(grep -c '@~/.claude/rules/' CLAUDE.md 2>/dev/null || echo 0)
  [ "$COUNT" -gt 0 ] && echo "OK $COUNT rules imported" || echo "WARNING no rules imported"

## Hooks

Run:
  for hook in require-test-first auto-test verify-before-stop detect-structure-change; do
    f=".claude/hooks/${hook}.sh"
    [ -f "$f" ] \
      && { [ -x "$f" ] && echo "OK ${hook}.sh" || echo "NOT EXECUTABLE ${hook}.sh — run chmod +x .claude/hooks/*.sh"; } \
      || echo "MISSING ${hook}.sh — run /user:init-project"
  done

## settings.json hooks

Run:
  [ -f .claude/settings.json ] || { echo skipped; exit 0; }
  python3 -c "
import json
with open('.claude/settings.json') as f:
    s = json.load(f)
print('OK autoCompact' if s.get('autoCompact') else 'MISSING autoCompact')
h = s.get('hooks', {})
print('OK PreToolUse' if h.get('PreToolUse') else 'MISSING PreToolUse')
print('OK PostToolUse' if h.get('PostToolUse') else 'MISSING PostToolUse')
print('OK Stop hook' if h.get('Stop') else 'MISSING Stop hook')
" 2>/dev/null || echo "ERROR reading settings.json"

## Snapshot freshness

Run:
  [ -f .claude/project-snapshot.json ] || { echo no snapshot; exit 0; }
  python3 -c "import json; print('Last:', json.load(open('.claude/project-snapshot.json'))['updated_at'])" 2>/dev/null
  compute_hash() { if command -v md5sum >/dev/null 2>&1; then md5sum; elif command -v md5 >/dev/null 2>&1; then md5 -r; else shasum -a 256; fi; }
  HASH=$(find . -maxdepth 3 -type d \
    | grep -vE '\.git|node_modules|target|build|dist|\.gradle|__pycache__|coverage' \
    | sort | compute_hash | cut -d' ' -f1)
  KEY=$(find . -maxdepth 2 \
    \( -name "pom.xml" -o -name "build.gradle" -o -name "package.json" -o -name "pyproject.toml" -o -name "go.mod" -o -name "Cargo.toml" \) \
    | sort | xargs cat 2>/dev/null | compute_hash | cut -d' ' -f1)
  STORED=$(python3 -c "import json; print(json.load(open('.claude/project-snapshot.json'))['structure_hash'])" 2>/dev/null)
  [ "${HASH}:${KEY}" = "$STORED" ] \
    && echo "OK snapshot current" \
    || echo "DRIFTED — run /user:refresh-project"

## Summary

Count OK, WARNING, MISSING lines. If any MISSING items, list them with fix commands:
  /user:init-project    — fixes most project-level items
  /user:tag-rules       — fixes rule frontmatter
  /user:refresh-project — fixes imports and snapshot
