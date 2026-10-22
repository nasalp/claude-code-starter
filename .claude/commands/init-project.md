# Initialize Claude Code Project

One-time setup. Scans structure, merges global config into CLAUDE.md,
writes .claudeignore, installs hooks, creates snapshot, loads context.

Hint: $ARGUMENTS

## Inventory existing config

Run:
  ls ~/.claude/rules/ 2>/dev/null || echo no rules
  ls ~/.claude/skills/ 2>/dev/null || echo no skills
  ls ~/.claude/commands/ 2>/dev/null || echo no commands
  cat CLAUDE.md 2>/dev/null || echo no CLAUDE.md
  cat .claudeignore 2>/dev/null || echo no .claudeignore
  cat .claude/settings.json 2>/dev/null || echo no settings.json

## Scan project structure

Run:
  find . -maxdepth 3 -type d | grep -vE '\.(git|idea|vscode)|node_modules|target|build|dist|out|\.gradle|__pycache__|coverage|\.m2' | sort
  du -sh */ 2>/dev/null | sort -rh | head -15

For build tool detection run:
  cat pom.xml 2>/dev/null | grep -E '<module>|<artifactId>' | head -20
  cat build.gradle 2>/dev/null | head -20
  cat build.gradle.kts 2>/dev/null | head -20
  cat package.json 2>/dev/null | head -20
  cat pyproject.toml 2>/dev/null | head -10
  cat go.mod 2>/dev/null | head -10
  cat Cargo.toml 2>/dev/null | head -10

## Generate .claudeignore

Read existing, preserve all entries, add missing by detected project type.

JVM add: target/ build/ out/ .gradle/ *.class *.jar *.war *.ear
  generated-sources/ generated-test-sources/ .mvn/wrapper/maven-wrapper.jar

Node add: node_modules/ dist/ .next/ .nuxt/ coverage/

Python add: __pycache__/ *.pyc .venv/ venv/ .pytest_cache/ htmlcov/ *.egg-info/

Go add: vendor/ (if not using vendor mode)

Rust add: target/

Always add: .idea/ .vscode/ *.iml *.log tmp/ .tmp/ site/ reports/ .DS_Store

Show merged content then write.

## Create/update CLAUDE.md

Read existing and preserve all content. Add only missing sections.

Required sections:
  Project name and 1-2 sentence description
  Build and test commands (exact commands from build files, not generic)
  Module structure (from pom.xml modules or detected subdirectories)
  Architecture notes (key frameworks, entry points)
  Global configuration: @~/.claude/GLOBAL.md
  Global rules: @~/.claude/rules/[each file].md for every file in rules/
  Global skills: list each skill from skills/ with one-line description
  Global commands: list all commands from commands/

Write CLAUDE.md.

## Install hooks

Create .claude/hooks/ directory. Write each hook script.
All hooks use python3 for JSON parsing (not jq — not guaranteed on all systems).
All hooks are macOS and Linux compatible.

Write .claude/hooks/require-test-first.sh:
  See ~/.claude/hooks/require-test-first.sh (installed by this command)

Write .claude/hooks/auto-test.sh:
  See ~/.claude/hooks/auto-test.sh (installed by this command)

Write .claude/hooks/verify-before-stop.sh:
  See ~/.claude/hooks/verify-before-stop.sh (installed by this command)

Write .claude/hooks/detect-structure-change.sh:
  See ~/.claude/hooks/detect-structure-change.sh (installed by this command)

Make all hooks executable:
  chmod +x .claude/hooks/*.sh

## Install settings.json

Read existing .claude/settings.json if present and merge.

Ensure these settings exist:
  autoCompact: true
  autoCompactThreshold: 0.7

Ensure hooks are configured:
  PreToolUse on Write|Edit|MultiEdit -> require-test-first.sh (timeout 10s)
  PostToolUse on Write|Edit|MultiEdit -> auto-test.sh (timeout 120s, async true)
  Stop -> verify-before-stop.sh (timeout 300s)
  Stop -> detect-structure-change.sh (timeout 15s)

## Create structure snapshot

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

## Warm context

Run:
  echo "=== $(basename $(pwd)) ===" \
  && git log --oneline -5 2>/dev/null || echo no git \
  && cat .claude/project-snapshot.json 2>/dev/null

## Confirm to user

Print:
  .claudeignore — merged
  CLAUDE.md — created with global rules and skills wired in
  .claude/settings.json — auto-compact on, 4 hooks active
  .claude/hooks/ — TDD guard, test runner, stop gate, drift detector
  .claude/project-snapshot.json — baseline recorded

  Ready. Describe a feature in plain language to start.
