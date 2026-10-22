# Refresh Project Configuration

Run when notified of structure drift or after adding new modules.
Merges only — never removes content written manually.

$ARGUMENTS

## What changed?

Run:
  [ -f .claude/project-snapshot.json ] && \
    echo "Last snapshot: $(jq -r .updated_at .claude/project-snapshot.json 2>/dev/null || python3 -c "import json; print(json.load(open('.claude/project-snapshot.json'))['updated_at'])")" || \
    echo "No snapshot"

  find . -maxdepth 3 -type d \
    | grep -vE '\.git|node_modules|target|build|dist|\.gradle|__pycache__|coverage' | sort

  find . -maxdepth 2 \
    \( -name "pom.xml" -o -name "build.gradle" -o -name "build.gradle.kts" \
       -o -name "package.json" -o -name "pyproject.toml" -o -name "go.mod" \
       -o -name "Cargo.toml" \) \
    | grep -vE 'node_modules|target|build' | sort

  ls ~/.claude/rules/ 2>/dev/null || echo no rules
  ls ~/.claude/skills/ 2>/dev/null || echo no skills
  ls ~/.claude/commands/ 2>/dev/null || echo no commands

  grep -E '^@|^- \*\*' CLAUDE.md 2>/dev/null || echo no CLAUDE.md

## Update CLAUDE.md (merge only)

Read current CLAUDE.md fully. Apply only targeted changes:
- Module structure: replace with current detected modules
- Build commands: update if build files changed
- Global rules: add @~/.claude/rules/<file>.md for any new rules not yet imported
- Global skills: add newly discovered skills not yet listed
- Global commands: add any new commands not yet listed

Never touch: architecture notes, working style, custom sections, manual imports.
Show a diff summary before writing.

## Update .claudeignore (merge only)

Add entries for new directories that should be excluded. Never remove existing.

## Verify hooks

Run:
  ls -la .claude/hooks/ 2>/dev/null || echo no hooks dir
  chmod +x .claude/hooks/*.sh 2>/dev/null

## Update snapshot

Run:
  compute_hash() { if command -v md5sum >/dev/null 2>&1; then md5sum; elif command -v md5 >/dev/null 2>&1; then md5 -r; else shasum -a 256; fi; }
  HASH=$(find . -maxdepth 3 -type d \
    | grep -vE '\.git|node_modules|target|build|\.gradle|__pycache__|coverage' \
    | sort | compute_hash | cut -d' ' -f1)
  KEY=$(find . -maxdepth 2 \
    \( -name "pom.xml" -o -name "build.gradle" -o -name "build.gradle.kts" \
       -o -name "package.json" -o -name "pyproject.toml" -o -name "go.mod" \
       -o -name "Cargo.toml" \) \
    | sort | xargs cat 2>/dev/null | compute_hash | cut -d' ' -f1)
  mkdir -p .claude
  echo "{\"structure_hash\":\"${HASH}:${KEY}\",\"updated_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    > .claude/project-snapshot.json

Tell the user concisely what changed.
End with: Configuration current. Will not notify again until something changes.
