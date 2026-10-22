# Rationale — No bloated comments — anywhere

## What goes in commit messages instead

Every "I should explain WHY" impulse goes into commit body. Right surface because:
- `git log` / `git blame` lets future reader pull it on demand
- Doesn't bloat the diff
- Doesn't bloat the file
- Doesn't visually dominate the actual change

Commit body can be 30 lines. Code comment shouldn't be 3.

## Cross-references

- `common/coding-style.md` — "default to writing no comments" — this rule is the absolute version of that line.
- This rule is the operator's correction after a multi-week pattern of comment-bloat across configs, shell, and Java.
- Feedback memory: `feedback_no_bloated_comments.md` records the incident that motivated the strict version.
