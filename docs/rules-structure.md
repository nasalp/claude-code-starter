# Rules — structure & conventions

> Moved out of `.claude/rules/README.md` so it no longer auto-loads into every
> session (it's maintainer reference, not a behavioral rule). Keeping it out
> of the auto-loaded set saves tokens in every session.

## Structure

Rules organized into a **common** layer plus **language-specific** directories:

```
rules/
├── *.md             # Language-agnostic rules (loaded globally)
├── common/          # Language-agnostic principles
│   ├── coding-style.md
│   ├── git-workflow.md
│   ├── testing.md
│   ├── performance.md
│   ├── patterns.md
│   ├── hooks.md
│   ├── agents.md
│   └── security.md
├── java/            # Java/Spring specific (incl. java-spring.md)
├── typescript/      # TypeScript/JavaScript specific
├── web/             # Frontend/web specific
├── python/          # Python specific
└── php/             # PHP specific
```

Officially supported languages: typescript, web, java, php, python. Other languages have no rule directories here — add one only on real demand from a fleet project.

- **common/** contains universal principles — no language-specific code examples.
- **Language directories** extend common rules with framework-specific patterns, tools, code examples.

## Global Gates

These top-level rules apply before language-specific rules:

- [core.md](../.claude/rules/core.md): spec first, test first, verify before done
- [testing.md](../.claude/rules/testing.md): behavioral tests and input/output coverage
- [security.md](../.claude/rules/security.md): security review for every change
- [senior-review-gates.md](../.claude/rules/senior-review-gates.md): hard reject gates before senior review

## Rules vs Skills

- **Rules** define standards, conventions, checklists that apply broadly (e.g., "80% test coverage", "no hardcoded secrets").
- **Skills** (`skills/` directory) provide deep, actionable reference material for specific tasks (e.g., `python-patterns`, `golang-testing`).

Language-specific rule files reference relevant skills. Rules tell you *what* to do; skills tell you *how*.

## Adding a New Language

Adding a language directory means signing up to maintain that language's rules. Do this only when one of your projects starts using the language.

1. Add the language to the supported list in this doc.
2. Create `rules/<lang>/` and the standard files (`coding-style.md`,
   `testing.md`, `patterns.md`, `hooks.md`, `security.md`).
3. Each file should start with:
   ```
   > This file extends [common/xxx.md](../common/xxx.md) with <Language> specific content.
   ```
4. Reference existing skills if available, or create new ones under `skills/`.

## Rule Priority

When language-specific rules and common rules conflict, **language-specific rules take precedence** (specific overrides general). Standard layered configuration pattern (like CSS specificity or `.gitignore` precedence).

- `rules/common/` defines universal defaults applicable to all projects.
- `rules/java/`, `rules/python/`, `rules/typescript/`, `rules/web/`, etc. override those defaults where language idioms differ.

### Example

`common/coding-style.md` recommends immutability as a default principle. A language-specific extension can override this where idiomatic — e.g. idiomatic Java uses builder mutation during construction; the override note documents the deviation.

### Common rules with override notes

Rules in `rules/common/` that may be overridden by language-specific files are marked with:

> **Language note**: This rule may be overridden by language-specific rules for languages where this pattern is not idiomatic.
