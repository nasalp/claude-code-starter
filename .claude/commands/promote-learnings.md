---
description: Scan all sibling project repos in the current directory for convergent learnings/rules and draft a PR against ai-rules to promote them upstream
---

# /promote-learnings

Manually trigger the learning-promotion meta-harness. Scans every project repo in
the current working directory, finds patterns that 2+ projects independently
surfaced, runs a 3-agent consensus review, and opens a draft PR against ai-rules.

**Run this from a folder that contains all your project repos** (e.g. a
`projects/` directory holding sibling git repos). The command discovers
projects by listing the current working directory and filtering for `.git` +
`spec/learnings/` or `.claude/rules/` presence.

### Required environment variables

| Variable | Purpose | How to set |
|----------|---------|-----------|
| `AI_RULES_REPO` | Absolute path to your ai-rules checkout. | `export AI_RULES_REPO=/path/to/your/ai-rules` |
| `PROJECTS_ROOT` | Absolute path to the folder containing your project repos. | `export PROJECTS_ROOT=$(pwd)` (or wherever you keep them) |

If either is unset, the command prints a one-line how-to and exits 1.

This is the v1 manual mode. No cron, no project-side push hooks. You run it when
you want to. It opens a draft PR and pings you for review.

## Arguments

None. Discovery is by directory listing of the current working directory.

If you want to scope to a single project:
```
/promote-learnings --only project-a
```

If you want a dry run that prints candidates without opening a PR:
```
/promote-learnings --dry-run
```

## Pre-flight checks (cheap, fail fast)

All preflight logic is implemented as a testable script. The agent invokes it
and reads the exit code:

```bash
"$AI_RULES_REPO/scripts/promote-learnings/preflight.sh"
# 0 = proceed; STATE_SHA=<hex> printed on stdout
# 1 = abort (env vars missing, missing dirs)
# 2 = clean no-op (kill switch on, PR already open, no changes since last run)
```

The script enforces three checks:

1. **Kill switch:** if `$AI_RULES_REPO/spec/promotion-disabled` exists, exit 2
   with a message. One-commit disable; no flag wrangling.
2. **Pending PR:** if a draft PR with the `[promotion]` label is already open
   against ai-rules, exit 2. At most 1 promotion PR open at a time.
3. **No changes:** if the per-project state hash matches the last successful
   run logged in `$AI_RULES_REPO/spec/promotion-log/<latest>.md`, exit 2.

If preflight returns 0, the printed `STATE_SHA=...` line should be passed to
`scripts/promote-learnings/write-heartbeat.sh --state-sha` at the end of the
run so the next invocation can skip on no-op.

## Backfill phase — ensure every doc has a topic

Before scanning for convergence, run the topic backfill so untopiced
learnings/rules are not invisible to the pipeline:

```bash
"$AI_RULES_REPO/scripts/promote-learnings/backfill-topics.sh"
# Prints per-file tag decisions and per-project untopiced lists.
# Auto-commits per project (does NOT push) with message
# "chore(learnings): backfill topic: frontmatter".
```

The script only tags files with **high-confidence** keyword matches against
the controlled vocabulary in `spec/promotion-topics.yaml` (filename hit OR
content-score margin >=2 over the runner-up). Ambiguous files stay untopiced
and are listed for human review — the agent surfaces that list in the run
summary so a human can hand-tag them later. Use `--dry-run` to preview
without writing, or `--no-commit` to write files but leave the trees dirty.

This step makes the harness self-healing on newly-added learnings: the next
`/promote-learnings` invocation absorbs the missing tags automatically.
Confidence-gated inference is the trade — wrong topics fake convergence and
poison the pipeline, so the script declines to guess when signals conflict.

## Adoption phase — surface re-authored upstream rules

After backfill but before scanning for new promotions, run the adoption
check so the user sees which project rules duplicate something already
upstream. The output is informational — it does not gate the scan — but
it usually points at higher-leverage work than new promotions.

```bash
"$AI_RULES_REPO/scripts/promote-learnings/check-adoption.sh"
# Prints an ADOPTION REPORT grouped by project, listing each project
# rule that matches an upstream rule/skill by filename slug, topic, or
# strong content overlap.
```

Detection signals (any one + content threshold triggers a hit):

| Signal | Description | Body threshold |
|---|---|---|
| `filename` | exact slug match (e.g. `observability.md` ↔ `typescript/observability.md`) | none (strong intent) |
| `filename-fuzzy` | ≥2 shared significant tokens (stopwords stripped) | >= 0.60 bigram |
| `filename-subsumption` | every upstream token appears in project slug (catches `no-custom-spring-profiles` ↔ `no-profiles`) | >= 0.70 bigram |
| `topic` | matching `topic:` frontmatter | >= 0.40 bigram |

For each adoption hit, two paths:

- **Delete** the project-local copy and let the project inherit the
  upstream rule via the symlink chain (`~/.claude/rules/...`).
- **Patch** the upstream file with whatever extra detail the project
  rule has accreted — see Patch phase.

## Patch phase — propose upstream patches for richer project rules

```bash
"$AI_RULES_REPO/scripts/promote-learnings/propose-upstream-patch.sh"
# Reads /tmp/adoption-best.txt (output of check-adoption.sh) and lists
# H2/H3 sections present in the PROJECT rule but missing from the
# UPSTREAM rule. Those are patch candidates.
```

The script identifies markdown sections that exist only in the project
copy. A typical case: upstream `no-profiles.md` has the abstract rule;
project `no-custom-spring-profiles.md` adds an `Enforcement` section
(ArchUnit example), a `Local-dev contract` section (env-var table), and
a `What is forbidden` section (banned profile-name list). All three are
fleet-generalizable and belong upstream.

The output is intentionally a *proposal*, not an auto-patch — section
headings are flagged but the actual wording stays under human review.

## Scan phase — discover candidate projects

The agent invokes the discovery script:

```bash
"$AI_RULES_REPO/scripts/promote-learnings/discover-projects.sh"
# Prints one project repo path per line.
# Honours ONLY=<repo-name> for --only invocations.
# Excludes the ai-rules checkout itself.
```

For each project, collect:
- Every `spec/learnings/*.md` file (full content, frontmatter included).
- Every `.claude/rules/*.md` file.
- For each file: its primary author from `git log --format='%ae' -- <file> | head -1`.
- Latest commit timestamp from `git log -1 --format='%ai' -- <file>`.

## Convergence detection

A candidate qualifies for promotion if **all** of:

1. **Topic match.** The same `topic:` (controlled vocabulary in
   `spec/promotion-topics.yaml`) appears in 2+ projects. Topic match is by
   string equality, not semantic similarity.
2. **Authorship independence.** The two source commits are by different
   `git commit author` email addresses.

   **Solo-operator relaxation:** if the union of author emails across *all*
   scanned projects is a single unique address (the fleet is run by one human
   on multiple machines, e.g. `reviewer@example.com` ↔ `reviewer@example.org`
   resolved as the same person), this check is **skipped** and the PR body
   must include a `> Authorship check: skipped (solo-operator mode — N
   projects, 1 distinct author).` callout so a human reviewer notices that
   the "two independent discoveries" guarantee is weaker. Time independence
   (rule 3) is *not* relaxed — it remains the only anti-copy-paste signal in
   solo mode.

   To declare two emails as the same human, list them as siblings in
   `$AI_RULES_REPO/spec/promotion-authors.yaml`:

   ```yaml
   identities:
     - name: senior-reviewer
       emails:
         - reviewer@example.com
         - reviewer@example.org
   ```

   The check uses canonicalized identity (via this file) before counting
   distinct authors. Without the file, raw email equality is used.
3. **Time independence.** The two source commits are at least 5 calendar days
   apart. Same-week double-promotion likely indicates copy-paste.
4. **Not already in `$AI_RULES_REPO/.claude/rules/`.** The candidate name +
   topic must not already exist upstream.
5. **Not in the rejection ledger** (`spec/decisions/rejected-promotions.md`)
   within the 90-day expiry window.

If a candidate has only one project source, it qualifies for **Tier 1**: copy
into `$AI_RULES_REPO/.claude/rules-proposed/<topic>.md` (visible, NOT
auto-loaded). Tier 1 promotions have a 30-day grace period before being
demoted unless a second project surfaces the same topic.

## Triage pass (Haiku)

Before spawning the full 3-agent panel, run a cheap Haiku-class classifier on
each candidate:

> You are filtering candidates for a learning-promotion pipeline. Read this
> learning and respond with a single token:
> - `PROMOTE` if it captures a non-obvious pattern that would benefit other
>   projects in the fleet.
> - `REJECT` if it's project-specific advice with no general applicability.
> - `HUMAN` if you can't tell and a human should review.

Drop `REJECT` candidates (log them with reason). Forward `PROMOTE` candidates to
the full panel. `HUMAN` goes into the PR description as "ambiguous".

This typically prunes ~70% of candidates and brings cost from $5–15 to $2–5
per active run.

## 3-agent consensus

For each surviving candidate, spawn three reviewers IN PARALLEL. Each reviewer
must produce **structured evidence**, not just a vote — the goal is that anyone
reading the PR body can verify the claim independently.

### Architect

> You are reviewing a candidate for promotion to a shared rules harness.
> Lens: system design, generality, mechanism vs policy.
>
> Before voting, perform these checks and report each result on its own line:
>
>   1. **Existing-rule overlap.** Search `$AI_RULES_REPO/.claude/rules/` for a
>      rule that already covers the same intent. Cite the file:line if found,
>      or write `none-found`. If a near-duplicate exists, REJECT.
>   2. **Mechanism vs policy.** State whether the proposed rule changes
>      mechanism (how the system behaves) or policy (what the team prefers).
>      A policy rule with no enforcement story is a candidate for REJECT.
>   3. **Generalization test.** Name two stacks the rule would apply to (e.g.
>      "any Spring Boot service with a JPA repository", "any Node service
>      using JWT cookies"). If you cannot name two, REJECT.
>
> Then vote APPROVE or REJECT in a single sentence. If REJECT, name the
> specific failure (e.g. "duplicates rules/java/null-safety.md:42").

### Field Engineer

> You are reviewing a candidate for promotion to a shared rules harness.
> Lens: would the operator merge this on Monday morning in 3 minutes? Will it
> survive 4 weeks of unrelated drift?
>
> Before voting, perform these checks and report each result:
>
>   1. **Retroactive applicability.** Read the source learning's incident or
>      scenario. Apply the proposed rule to that scenario. Would it have caught
>      the original problem? If not, REJECT.
>   2. **Effort to comply.** State the worst-case time cost for an engineer to
>      satisfy this rule on a typical PR (e.g. "30s — copy a one-line annotation",
>      "2h — restructure module"). Anything over 1h with no escape hatch is a
>      candidate for REJECT.
>   3. **Drift survivability.** Will this rule still be true in 4 weeks if
>      Spring Boot, the AWS SDK, or the Node version bumps a minor version?
>      State the drift risk explicitly.
>
> Then vote APPROVE or REJECT in a single sentence.

### Adversary

> You are stress-testing a candidate for promotion to a shared rules harness.
> Lens: false positives, scope misclassification, opinion laundering.
> **Adversary REJECT is binding even if the other two APPROVE.**
>
> Before voting, perform these three checks and report each result:
>
>   1. **Named false-positive stack.** Name one production stack visible in
>      the fleet (`$PROJECTS_ROOT/*` — the sibling project repos) where this
>      rule would produce a false positive. If you cannot name one, that's a
>      strong signal the rule is well-scoped — but you must still try.
>   2. **Scope inflation.** Was the source learning project-specific (e.g. one
>      Postgres replica) being promoted as `universal`? If yes, REJECT and
>      propose a narrower scope tag.
>   3. **Existing-rule overlap (intentionally independent of Architect's
>      check 1).** This duplication is on purpose — two reviewers cite the
>      same rule from different lenses, and divergent citations are a
>      signal worth flagging in the PR. Search for a rule that already
>      covers this. Cite file:line if found.
>
> Then vote APPROVE or REJECT in a single sentence. If REJECT, name the
> specific breakage with file:line where possible.

All three must APPROVE for the PR to draft. Any REJECT routes the candidate to
the rejection ledger with the reason. The **structured-evidence outputs above
are copied verbatim into the PR body** so a human reviewer can audit each check
without re-running the agent.

## Tie-breakers

- **Scope tag conflict** (Architect says `java-spring`, Field Engineer says
  `universal`): Adversary breaks the tie. If Adversary disagrees with both,
  default to the **narrower** scope.
- **Approve count tie**: doesn't happen — all three must APPROVE.

## Draft PR format

For each approved candidate, draft a PR via `gh -R your-org/claude-code-starter pr create --draft`:

**Title:** `[promotion] <rule-name> — converged from <project-a>, <project-b>`

**Body** (uses `.github/PULL_REQUEST_TEMPLATE/promotion.md`):

```markdown
## Sources

- `<project-a>/spec/learnings/<file>.md` (commit <sha>, author <name>, <date>)
- `<project-b>/spec/learnings/<file>.md` (commit <sha>, author <name>, <date>)

## Side-by-side diff

<details>
<summary>Source A</summary>

\`\`\`markdown
<full content of project-a source>
\`\`\`
</details>

<details>
<summary>Source B</summary>

\`\`\`markdown
<full content of project-b source>
\`\`\`
</details>

## Proposed upstream rule

Path: `~/.claude/rules/<scope>/<rule-name>.md`

\`\`\`markdown
<the proposed rule body>
\`\`\`

## Scope

`<universal | java-spring | postgres-only | aws-only | typescript | web>`

## Counter-examples

Stacks where this rule does NOT apply:
- <e.g. MongoDB projects (this is a Postgres-specific pattern)>

## Verdicts

- **Architect:** APPROVE — <one-line reason>
- **Field Engineer:** APPROVE — <one-line reason>
- **Adversary:** APPROVE — <one-line reason>

## Cost

`$X.XX` spent on this analysis (Haiku triage + 3-agent panel).

## Promoted-from footer

Will be added to the merged rule:
`Promoted-from: <project-a>@<sha> + <project-b>@<sha> on <date>`
```

## Heartbeat log

Every run writes a one-line entry to
`$AI_RULES_REPO/spec/promotion-log/<YYYY-MM-DD>.md` via the testable script:

```bash
"$AI_RULES_REPO/scripts/promote-learnings/write-heartbeat.sh" \
  --projects-scanned 5 \
  --learnings-seen   23 \
  --candidates       4 \
  --prs-drafted      2 \
  --cost-usd         4.17 \
  --state-sha        "$STATE_SHA"
```

If you don't see a log entry from the past two weeks, the loop is broken.

## Feedback signal: forbidden-literal trend

After a successful promotion run, invoke the compliance runner so the
fleet's literal-drift trend is recorded as a heartbeat counterpart to
the promotion summary:

```bash
"$AI_RULES_REPO/scripts/promote-learnings/check-compliance.sh"
```

The runner reads `<rule>.compliance.regex` sidecars next to each rule
(see `docs/compliance-regex-howto.md` for the convention) and
appends a line to today's heartbeat log in this exact schema:

```
<YYYY-MM-DD HH:MM UTC> | compliance: <N> rules / <N> clean / <N> violated
```

A rule whose violation count rises over consecutive runs is a
candidate for `/retract-rule` — the rejection ledger then memorialises
why it was removed and prevents accidental re-promotion.

The runner only scans **production source** roots (`src/main/`,
`lib/`, top-level `src/` minus `test/`). Test fixtures with
intentional placeholder secrets or `Thread.sleep` in setup are
correctly ignored. Adoption tracking ("did consumer X wire ArchUnit
for rule Y?") is intentionally NOT done via grep — that signal is too
fragile against multi-line wraps and reformatting. Use consumer CI
status instead.

## Hygiene runners (run on every promotion pass)

Two short scripts keep the harness directories honest. Both are
covered by BATS in `tests/bats/` and produce summary lines suitable
for the heartbeat log:

```bash
# 1. Audit Tier-1/2 rules-proposed/ rules for grace-period expiry.
#    Exits 1 if any file is past its grace date.
#    Pass --prune-expired to delete them in the same pass.
"$AI_RULES_REPO/scripts/promote-learnings/check-proposed-expiry.sh" \
  --warn-days 7

# 2. Regenerate spec/learnings/README.md from the files on disk.
#    --check mode (CI gate) exits 1 on drift instead of writing.
"$AI_RULES_REPO/scripts/promote-learnings/build-learnings-index.sh"
```

If either reports a non-zero exit, the promotion run halts and
surfaces the issue rather than papering over it. The index-builder
in particular makes `spec/learnings/README.md` a derived artifact;
adding a learning file is enough — no manual table edit required.

## Rejection ledger

For each `REJECT` from any reviewer, append a structured entry via:

```bash
"$AI_RULES_REPO/scripts/promote-learnings/append-rejection.sh" \
  --rule       "<rule-name>" \
  --reviewer   "Adversary" \
  --reason     "Pattern is Postgres-specific; tagged as 'universal' would break Mongo." \
  --condition  "If a second Postgres-only project surfaces the same topic, re-propose with scope: postgres-only." \
  --evidence   "<source learning file:line>"
# --reevaluation defaults to today + 90 days; pass --reevaluation never for permanent.
```

The on-disk format the script produces:

```markdown
## <rule-name> (<topic>) — rejected <date>

- **Reviewer:** Adversary
- **Reason:** Pattern is Postgres-specific; tagged as `universal` would break Mongo project.
- **Re-evaluation:** 2026-08-04 (90-day expiry).
- **Re-evaluation condition:** if a second Postgres-only project surfaces the same topic, re-propose with `scope: postgres-only`.
```

## Cost cap

If the running total exceeds `$20` mid-flight, abort the run, write a partial
log entry, and exit 1. Default budget is enforced via per-agent prompt budget
+ a postcondition check.

## What this command does NOT do

- Auto-merge anything. Drafts only.
- Push commits to projects. Project state is read-only during the scan.
- Modify the user-level `~/.claude/` directly. Only opens a PR against
  `$AI_RULES_REPO/`.
- Run on a schedule. v1 is manual; cron is a separate decision.
- Trigger from project-side hooks. Inbox-as-branch was vetoed (write creds in
  every dev environment is too risky).

## See also

- `docs/META-HARNESS.md` — explainer + retraction flow
- `spec/decisions/0003-meta-harness.md` — design rationale + reviewer consensus
- `spec/promotion-topics.yaml` — controlled vocabulary
- `.github/PULL_REQUEST_TEMPLATE/promotion.md` — PR template
