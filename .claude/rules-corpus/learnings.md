# Learnings Rules

Agents MUST maintain living knowledge base of key findings in `spec/learnings/`.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## REQUIRED: Record Key Findings

Discover something significant about codebase during any task → record in `spec/learnings/`.

### What Counts as a Key Finding

| Record | Don't Record |
|--------|--------------|
| Unexpected behavior or gotchas | Obvious behavior from reading docs |
| Non-obvious dependencies between modules | Standard framework usage |
| Performance characteristics (measured) | Speculative performance concerns |
| Security constraints or patterns found | Generic security advice |
| Integration quirks with external services | Expected API behavior |
| Build/test infrastructure insights | Standard build commands |
| Debugging breakthroughs (root cause + fix) | Trivial typo fixes |
| Version/upgrade constraints discovered | Current version numbers only |

**Rule of thumb:** Saves someone 15+ minutes next time? Record it.

---

## REQUIRED: Update Learnings When Code Changes

Modify code referenced by existing learning:

1. **Check** `spec/learnings/` for related learnings (search by file path, module name, or topic)
2. **Update** learning if change affects accuracy
3. **Add** changelog entry with date

```
## Change Log

| Date | Change |
|------|--------|
| 2026-01-15 | Initial discovery |
| 2026-02-20 | Updated after migrating to Spring Boot 4.x |
```

### When to Update vs Create New

| Situation | Action |
|-----------|--------|
| Existing learning now wrong/outdated | Update it |
| Existing learning needs additional detail | Update it |
| New finding on same topic | Update existing learning, add new finding section |
| Completely new topic | Create new learning file |
| Existing learning no longer relevant | Remove it, update index |

---

## REQUIRED: Learning File Format

Files in `spec/learnings/` with naming: `<category>-<topic>.md`

Categories: `architecture`, `dependencies`, `infrastructure`, `testing`, `performance`, `security`, `integrations`, `debugging`

Use template at `spec/learnings/_template.md`.

Each learning MUST have:
- **Category** and **Last Updated** date
- **Related Files** — paths to relevant source files
- **Findings** — with discovery date and evidence
- **Change Log** — tracking all updates

---

## REQUIRED: Update the Index

After creating or removing learning, update `spec/learnings/README.md`:

```markdown
| Topic | File | Last Updated | Summary |
|-------|------|--------------|---------|
| Spring Boot 4.x Migration | [dependencies-spring-boot-4.md](dependencies-spring-boot-4.md) | 2026-02-15 | Breaking changes and workarounds |
```

---

## RECOMMENDED: Check Learnings Before Starting Work

Before any task, scan `spec/learnings/` for relevant existing knowledge:

```
1. Read spec/learnings/README.md for the index
2. Check if any learning relates to the area you're modifying
3. Apply existing knowledge to avoid repeating past mistakes
```

---

## Workflow Integration

```
Standard workflow:
  SPEC → TEST → IMPLEMENT → VERIFY

With learnings:
  CHECK LEARNINGS → SPEC → TEST → IMPLEMENT → VERIFY → UPDATE LEARNINGS
  ^                                                      |
  └──────────────── knowledge feeds back ────────────────┘
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Record key findings in spec/learnings/ | REQUIRED |
| Update learnings when related code changes | REQUIRED |
| Follow file format and template | REQUIRED |
| Update learnings index | REQUIRED |
| Check learnings before starting work | RECOMMENDED |
