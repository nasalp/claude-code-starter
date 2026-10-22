---
name: spec-learnings-system
description: Maintain a spec/learnings/ knowledge base distinct from continuous-learning-v2 hooks and from ADRs, with frontmatter, evidence, change log, and an index in spec/learnings/README.md
origin: ECC
triggers: spec/learnings, learnings/README.md, spec/learnings index, durable findings, codebase knowledge base, knowledge base for codebase, spec/decisions vs spec/learnings, learning entry, finding category
---
# Spec Learnings System

Codify durable, codebase-specific findings in a dedicated `spec/learnings/` (or `specs/learnings/`) directory. Each learning is a markdown file with structured frontmatter, evidence pointers, and a changelog. The directory is indexed by a `README.md`. The system is deliberately **not** an ADR, **not** a session-level continuous-learning-v2 artifact, and **not** a feature spec -- it is the project's long-lived "what we discovered about ourselves" log.

## When to use

- A non-obvious gotcha was discovered while reading or modifying code (a NULL column that looks populated, a JPA flag that means the opposite of what its name suggests, an integration whose docs are wrong).
- An infrastructure constraint was uncovered (an ALB OIDC peer-trust quirk, a SPA routing rewrite, a runtime mode that only fires under a specific env var combination).
- A debugging breakthrough should not be lost (root cause + fix + how to recognize it next time).
- A measured performance characteristic exists that contradicts naive expectation.
- A version / upgrade constraint was hit (Spring Boot 4.x changed default X; library Y's autoconfig fires when on classpath).
- Rule of thumb: if it would save a future agent or human 15+ minutes, write it down.

## When NOT to use

- The finding belongs in a feature spec (`spec/features/<feature>.md`) -- it is part of the product behavior.
- The finding is an architectural decision -- write an ADR (`spec/decisions/NNNN-title.md`) instead.
- The finding is session-ephemeral or pertains to a tool's own behavior -- the `continuous-learning-v2` skill maintains a separate, instinct-based store. Spec learnings are about **the codebase**, not about the agent or the tool.
- The finding is obvious from reading the official docs of the framework or library. Don't paraphrase upstream docs.
- The finding is a TODO. Write a tech-debt ticket; learnings document state, not intent.

## The pattern

Files live in `spec/learnings/<category>-<topic>.md` (or `specs/learnings/...` if the project uses Speckit's `specs/` directory). Naming is `<category>-<kebab-topic>.md` or `YYYY-MM-DD-<category>-<kebab-topic>.md` for date-anchored entries.

Categories used in production:

- `architecture` -- bounded-context shape, layout decisions
- `data` -- column semantics, NULL columns, dual-meaning flags
- `dependencies` -- breaking changes from upgrades, version pins
- `infrastructure` -- ALB, OIDC, replica datasource quirks, SPA routing
- `integrations` -- third-party API gotchas, OIDC peer trust, broker setups
- `testing` -- shared Testcontainers, three-layer architecture, anti-patterns
- `performance` -- measured numbers, not speculation
- `security` -- PII boundaries, scrubbing, replay protection
- `debugging` -- root-cause writeups
- `process` -- ATDD workflow, never-nuke-prod-data, dont-assume-ask

Required structure. Frontmatter is YAML; `category`, `last_updated`, and `audit_ids` (when applicable) are pinned by ArchUnit-style spec verifiers in mature projects.

```markdown
---
category: integrations
last_updated: 2026-04-30
related_files:
  - frontend/playwright.config.ts
  - frontend-it/src/stub-runner.ts
audit_ids: []
---

# Frontend Stub Serving: Use Stubborn NPM Packages

## Related Files

- `frontend/playwright.config.ts` -- currently boots Docker stub-runner image
- `stub-runner/` -- Spring Boot Stub Runner Boot app
- `docker-compose.local.yml` -- stub-runner service

## Findings

### Discovery (2026-04-30)

(narrative + code evidence + reasoning)

### Key Packages / Behaviors / Gotchas

(named subsections)

## Evidence

- Upstream docs: https://...
- Local clone: /Users/.../...
- Repro steps: `mvn -pl ... ...`

## Change Log

| Date | Change |
|------|--------|
| 2026-04-30 | Initial discovery |
| 2026-05-15 | Updated after Spring Boot 4.x upgrade made X default |
```

The directory ships with a `spec/learnings/README.md` index that lists every learning with one-line summaries:

```markdown
| Topic | File | Last Updated | Summary |
|-------|------|--------------|---------|
| Frontend stubs (npm) | [2026-04-30-integrations-stubborn-npm-for-frontend-stubs.md](2026-04-30-integrations-stubborn-npm-for-frontend-stubs.md) | 2026-04-30 | Replace Docker stub-runner with @stubborn-sh/* |
| Three-layer test arch | [testing-three-layer-architecture.md](testing-three-layer-architecture.md) | 2026-04-05 | Backend ApiIT, Playwright stubs, Java E2E |
```

A `_template.md` (or just the README itself) shows agents the schema. New entries copy the template.

## Common gotchas / variants

- **Update, do not duplicate.** When a related code change occurs, update the existing learning's body and add a Change Log row. Only create a new file for a genuinely new topic. Stale learnings are worse than missing ones.
- **Cite, do not narrate.** Each finding must point to a concrete file, line, log line, or upstream issue. "I think we ran into this once" is not a learning -- it is a guess.
- **Distinguish from ADRs.** Learnings document **discovered state**. ADRs document **chosen state with consequences**. If you need to record a decision, also write the ADR; if you need to record a behavior of the existing system, write a learning.
- **Distinguish from feature specs.** A feature spec answers "what does this product do for users". A learning answers "what does this codebase secretly do that surprised someone".
- **Distinguish from continuous-learning-v2 instincts.** The `continuous-learning-v2` skill stores agent-side instincts (project + global) with confidence scoring; those are about how to operate. Spec learnings are about what the codebase is. Both are useful; they do not overlap.
- **Audit trail.** When a learning is referenced by a security audit finding, set `audit_ids: [M5, M9]` in the frontmatter. The triage / verifier scripts cross-reference.
- **Removal.** When a learning becomes obsolete (the bug was fixed in code, the misleading flag was removed), delete the file and remove its row from the index. Mark the deletion in git history; do not leave tombstones.

## Verification

The directory is healthy when:

1. Every `.md` file (except the README/template) has a `category` and `last_updated` in frontmatter.
2. Every entry in `spec/learnings/README.md` resolves to an actual file.
3. Every learning body cites at least one concrete file path or upstream URL.
4. New learnings created in the last 30 days outnumber stale (`last_updated` > 6 months ago) learnings -- the project is still learning. If the curve is flat, agents are not recording findings.

A simple `find spec/learnings -name "*.md" | xargs -I{} grep -L "category:" {}` should return zero rows.

## References

- Failure-pattern collator: `spec/learnings/failure-patterns.md` (when present, aggregates recurring root causes)
- Companion: continuous-learning-v2 skill (agent instincts, not codebase findings)
- Companion: spec/decisions/ (ADRs)
