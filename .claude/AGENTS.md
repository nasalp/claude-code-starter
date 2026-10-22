# AGENTS.md

## Project Overview

**Stack:** Java + Spring Boot
**Build:** Maven/Gradle — use wrapper (`./mvnw`) or Maven Daemon (`mvnd`)

## Core Philosophy

**Specs are permanent. Code is replaceable.**

Specs define WHAT (high-level behavior). Code defines HOW. With complete specs, you can rewrite everything in any technology.

```
SPEC → TEST → IMPLEMENT → VERIFY
```

---

## When Specs Are Required

| Change | Spec? |
|--------|-------|
| New feature | Yes |
| Behavior change | Yes |
| Dockerfile, CI/CD | No |
| Config, dependencies | No |
| Refactoring (same behavior) | No |
| Trivial (typos, logs) | No |

**Specs are high-level** — describe behavior, not implementation details.

---

## Quick Reference

### Skills

| Skill | Purpose |
|-------|---------|
| [/create-spec](skills/create-spec.md) | Create feature specifications |
| [/write-test](skills/write-test.md) | Write tests |
| [/implement](skills/implement.md) | Implement features |
| [/run-tests](skills/run-tests.md) | Execute tests |

### Rules

| Category | Rules |
|----------|-------|
| Core | [Spec-first](rules/core.md), [Exceptions](rules/exceptions.md) |
| Every Change | [Security](rules/security.md), [Performance](rules/performance.md), [Code Style](rules/code-style.md) |
| Development | [Java/Spring](rules/java-spring.md), [Testing](rules/testing.md), [Errors](rules/error-handling.md) |
| Data | [Database](rules/database.md), [API Design](rules/api-design.md) |
| Operations | [Git](rules/git-workflow.md), [Observability](rules/observability.md), [Legacy](rules/legacy-code.md) |

---

## CRITICAL Rules (Never Skip)

### Security
- Security review every change
- No sensitive data in logs
- No hardcoded secrets

### Stability
- Bounded caches and queues

### Performance
- Tests run in parallel
- Tests are isolated

### Code Style (Required)
- Use imports, not FQNs
- Remove unused code
- Remove unused imports
- KISS, YAGNI, DRY

### Code Style (Suggested Targets)
- Short methods (~10-15 lines)
- Short classes (~100-200 lines)
- Single responsibility

---

## Build Commands

```bash
# Maven Daemon (fastest, if available)
mvnd verify -T 1C

# Standard Maven
./mvnw verify -T 1C

# Gradle
./gradlew build --parallel
```

---

## Quick Setup

```bash
./.claude/init/setup.sh
```


<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
