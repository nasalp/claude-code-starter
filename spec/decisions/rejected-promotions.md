# Rejected Promotions Ledger

Tracks learning/rule promotion candidates that the `/promote-learnings`
3-agent consensus voted REJECT, with the reason and a re-evaluation date.

The ledger has two purposes:
1. **Anti-feedback-loop guard.** Prevent the same candidate from being
   re-proposed on every weekly run.
2. **Audit trail.** Document the reasoning for future revisitation.

## Format

```markdown
## <rule-name> (<topic>) — rejected <YYYY-MM-DD>

- **Reviewer:** <Architect | Field Engineer | Adversary>
- **Reason:** <one paragraph>
- **Re-evaluation:** <YYYY-MM-DD> (90 days from rejection)
- **Re-evaluation condition:** <what would have to change for this to be re-proposed>
- **Cited evidence:** <project-a>/path/to/source.md vs <ai-rules-target.md>
- **Prior rejections (same topic, different name):** <link to earlier entry> (optional)
```

The `Cited evidence` line points at the source learning(s) in fleet
repos and the upstream rule/skill that already covers the topic. Use
file paths (not SHAs) because they survive history rewrites and are
the form the 3-agent panel cites at decision time.

## Expiry

Entries expire 90 days after rejection. Expired entries can be re-proposed if
the listed `Re-evaluation condition` is met. Expired entries are NOT auto-deleted
— they're moved to `### Expired (re-evaluation allowed)` so the audit trail
survives.

## Manual entries

Entries can also be added manually when a human-rejected pattern shouldn't be
re-proposed (e.g. an architectural decision that's permanently decided). Mark
manual entries with `Re-evaluation: never` and `Re-evaluation condition: -`.

---

## Active rejections

(none yet — populated by `/promote-learnings`)

---

## Expired (re-evaluation allowed)

(none yet)

---

## Permanently rejected (manual)


(none yet)
