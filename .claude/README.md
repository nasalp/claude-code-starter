# AI Agent System

Configuration for AI-assisted development.

## Core Philosophy

**Specs are permanent. Code is replaceable.**

## Structure

```
.claude/
├── AGENTS.md              # Main entry point
├── codebase-map.md        # Navigate the codebase
├── commands/              # Custom slash commands
│   ├── test.md           # /test
│   ├── build.md          # /build
│   ├── review.md         # /review
│   ├── security-review.md # /security-review
│   ├── new-feature.md    # /new-feature
│   ├── deps.md           # /deps
│   └── adr.md            # /adr
├── prompts/               # Reusable prompt templates
│   ├── security-review.md
│   ├── code-review.md
│   ├── refactor.md
│   ├── debug.md
│   └── explain.md
├── rules/                 # Enforced constraints
├── skills/                # Modular capabilities
├── workflows/             # Multi-step processes
├── checklists/            # Quality gates
└── init/                  # Setup scripts
```

## Quick Commands

| Command | Purpose |
|---------|---------|
| `/test` | Run tests (auto-detects Maven/Gradle) |
| `/build` | Full build with checks |
| `/review` | Review changes against standards |
| `/security-review` | Security-focused review |
| `/new-feature` | Scaffold new feature |
| `/deps` | Manage dependencies |
| `/adr` | Architecture decisions |

## Build Tool Support

All commands support both Maven and Gradle:

```bash
# Auto-detection
if [ -f "pom.xml" ]; then
    # Maven (prefers daemon)
    mvnd test -T 1C || ./mvnw test -T 1C
else
    # Gradle
    ./gradlew test --parallel
fi
```

## Key Files

| File | Purpose |
|------|---------|
| `/CLAUDE.md` | Project-specific context (read every session) |
| `/AGENTS.md` | Quick reference |
| `/.claude/codebase-map.md` | Navigate codebase |
| `/spec/decisions/` | Architecture Decision Records |

## Setup

```bash
# Initialize spec structure
./.claude/init/setup.sh
```

## Related

- [Main AGENTS.md](AGENTS.md)
- [Quality Gates](checklists/quality-gates.md)
- [All Rules](rules/)
