---
description: Retract a previously-promoted rule from ai-rules — deprecate the file, append to the rejection ledger, and open a PR with the trail
---

# /retract-rule

Removes a rule that turned out to be wrong, harmful, or outdated. This is the
inverse of `/promote-learnings`: it takes a rule that the harness has been
shipping, marks it deprecated, and records *why* so the same rule cannot be
re-promoted by accident.

Run this when:
- A promoted rule caused an incident or false positive in production.
- A rule was retroactively contradicted by a framework upgrade or a project
  decision.
- A rule was promoted on weak evidence and a follow-up review (this one)
  rejects it.
- A skill or hook references a rule that is no longer canonical.

## Arguments

```
/retract-rule <rule-path-or-name> --reason "<one-sentence cause>"
```

Examples:

```
/retract-rule rules/java/no-spring-profiles.md \
  --reason "Spring Boot 4 introduced first-class profile groups; the rule blocks them."

/retract-rule java-coding-standards \
  --reason "Duplicates rules/java/coding-style.md and inflates context with no new information."
```

If `--reason` is omitted, the command exits non-zero and prints a help message —
the rejection ledger requires evidence, not just a removal.

### Required environment

| Variable | Purpose | How to set |
|----------|---------|-----------|
| `AI_RULES_REPO` | Absolute path to your ai-rules checkout. | `export AI_RULES_REPO=/path/to/your/ai-rules` |

If unset, the command prints a one-line how-to and exits 1.

## Pre-flight checks

All preflight logic is implemented as a testable script. The agent invokes:

```bash
"$AI_RULES_REPO/scripts/retract-rule/preflight.sh" \
  --target "<rule-path-or-name>" \
  --reason "<one-sentence cause>"
# Exit 0: prints resolved relative path on stdout (e.g. .claude/rules/java/foo.md)
# Exit 1: abort (env missing, missing reason, ambiguous match, dirty tree)
# Exit 2: idempotent no-op (already in _deprecated/)
```

The script enforces:

1. **Env present.** `$AI_RULES_REPO` is set and points at an ai-rules checkout.
2. **Reason present.** The rejection ledger requires evidence, not just removal.
3. **Target resolves.** Resolves `<rule-path-or-name>` against:
   - An exact relative path under `$AI_RULES_REPO/`.
   - A bare path under `.claude/rules/`.
   - A filename match anywhere under `.claude/rules/` (with or without `.md`).
   - A skill directory under `.claude/skills/`.
   Multiple matches abort with the candidate list so the operator disambiguates.
4. **Not already deprecated.** If the resolved path is under `_deprecated/`,
   exit 2 — idempotent.
5. **Clean tree.** Refuse to run with uncommitted changes in `$AI_RULES_REPO/`
   so the retraction trail lands in a single PR.

The agent should still create a fresh `retract/<slugified-rule-name>` branch
from latest `origin/main` before invoking the move script — never amend an
existing PR.

## Retraction steps

1. **Move the rule to `_deprecated/`** via the testable script:
   ```bash
   "$AI_RULES_REPO/scripts/retract-rule/move-to-deprecated.sh" \
     --rel-path       "<resolved-rel-path>" \
     --reason         "<reason>" \
     --retracted-from "<commit sha that originally promoted this>"
   # Exit 0 prints the new path on stdout (e.g. .claude/rules/_deprecated/java/foo.md).
   ```
   The script uses `git mv` so history is preserved, mirrors the live-tree
   path under `_deprecated/`, and prepends a deprecation banner.

2. **Append to the rejection ledger** via the same shared script used by
   `/promote-learnings`:
   ```bash
   "$AI_RULES_REPO/scripts/promote-learnings/append-rejection.sh" \
     --rule         "<rule-name>" \
     --reviewer     "Operator" \
     --reason       "<reason>" \
     --reevaluation "never" \
     --evidence     "<file:line / incident link / failing test>"
   ```
   `Re-evaluation: never` is the default for retractions. Use a conditional
   re-evaluation only when there is a clear future state that would make the
   rule applicable again.

3. **Update `INDEX.md` if the retracted item was a skill.** Run
   `python3 scripts/generate-skills-index.py` so the skill index reflects the
   removal.

4. **Search for inbound references** via the testable script:
   ```bash
   "$AI_RULES_REPO/scripts/retract-rule/find-inbound-refs.sh" --name "<rule-name>"
   ```
   Output is one `<file>:<line>: <snippet>` per line, scoped to live trees
   (the `_deprecated/` tree is excluded). Surface the list in the PR body —
   those references will go stale and may need follow-up edits.

6. **Open a draft PR** via `gh pr create --draft`:

   **Title:** `[retract] <rule-name> — <one-line reason>`

   **Body:**
   ```markdown
   ## Reason

   <full reason>

   ## What is being retracted

   - Path: `<original-rel-path>` → moved to `_deprecated/<original-rel-path>`
   - Original promotion: <commit sha> on <date>

   ## Inbound references that may need follow-up

   - <file:line>
   - …

   ## Rejection ledger entry

   <verbatim block appended to spec/decisions/rejected-promotions.md>

   ## Distribution impact

   Consumer repos with symlinks into `.claude/rules/` will pick up the
   removal automatically on next `git pull`. There is no migration step
   for them — the rule simply stops loading.

   ## Promoted-from footer (for the audit trail)

   `Retracted-from: <commit sha> on <date>`
   ```

## Post-retraction

- The PR is **draft** — a human (typically the senior reviewer) reviews and merges.
- After merge, downstream consumer repos pick up the deprecation on their next
  `git pull` of `$AI_RULES_REPO/` (the symlink target).
- The rejection ledger entry serves as memory: `/promote-learnings` checks the
  ledger before drafting any new promotion, so the same idea cannot resurface
  silently.

## What this command does NOT do

- **Auto-merge.** Drafts only.
- **Force-delete the file.** The rule moves to `_deprecated/`; nothing is lost.
- **Fix inbound references automatically.** The list is printed and surfaced
  in the PR body for human follow-up.
- **Notify project repos.** Distribution is implicit via the symlink — no
  cross-repo PR is opened.

## See also

- `.claude/commands/promote-learnings.md` — the inverse flow
- `spec/decisions/rejected-promotions.md` — the canonical ledger
- `docs/META-HARNESS.md` — full lifecycle explainer
