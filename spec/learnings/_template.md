---
topic: <controlled-vocabulary entry from spec/promotion-topics.yaml>
category: <architecture | dependencies | infrastructure | testing | performance | security | integrations | debugging>
last-updated: <YYYY-MM-DD>
related-files:
  - <path/to/file>
  - <path/to/other>
---

# Learning: <Topic>

> **Why the frontmatter matters.** `/promote-learnings` matches candidates
> across projects by exact `topic:` string equality (controlled vocabulary
> in `spec/promotion-topics.yaml`). Without `topic:`, this learning will
> never be detected as convergent and cannot be promoted upstream.

---

## Summary

One-paragraph summary of this learning.

## Findings

### <Finding Title>

**Discovered:** <YYYY-MM-DD>

<What was found, with specifics. Include error messages, measurements, or code references.>

```
# Evidence: logs, metrics, code snippets, etc.
```

**Impact:** <What this means for development — what to do or avoid.>

---

## Change Log

| Date | Change |
|------|--------|
| <YYYY-MM-DD> | Initial discovery |
