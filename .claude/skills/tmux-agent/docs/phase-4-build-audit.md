# phase 4 build audit

# Phase 4 — tmux build + audit loop

## Launching the builder

Run `scripts/launch-builder.sh $RUN_ID <repo> $RUN_DIR/builder-prompt.md $RUN_DIR/builder.out`.
The script composes the Claude invocation (model opus, stream-json,
partial messages, add-dir for repo + rules + skills) and spawns it
under tmux session `builder-$RUN_ID`. When setup has exported
`HEADROOM_LOCAL_CLAUDE_PROXY_PYTHON`, the script routes Claude through
`python -m headroom.cli wrap claude`; otherwise it falls back to raw
`claude --print`. Covered by `tests/launch-builder.bats`.

The `stream-json` output is line-delimited JSON. You can `tmux capture-pane`
for a quick eyeball OR (better) parse `$RUN_DIR/builder.out` with `jq` for
content deltas, tool calls, and text the agent emits.

## Checklist re-verification (the truth signal)

On every audit cycle, BEFORE the red-flag scan, the orchestrator:

1. Reads `/tmp/checklist-status.md` written by the builder.
2. For EVERY item the builder marked `✓`, the orchestrator re-runs that
   row's PROOF command. If the orchestrator's output disagrees with the
   builder's claim → flag immediately to the USER as `CHECKLIST_LIE`.
3. For every item still `✗`, the orchestrator checks whether the
   surrounding phase has been declared complete in the status log. If
   YES → flag as `MISSING_PROOF` (the builder skipped an item).

The checklist + proof discipline catches the failure mode where the
agent claims completion but the artifact is incomplete (e.g. "RestDocs
tests written" but only 4 of 8 endpoints covered).

## Per-phase self-audit (MANDATORY before marking phase ✅)

The orchestrator is the **LAST validation gate** before the
assessor-consensus in Phase 5. Every time a new phase commit lands
(detected via `git log origin/main..HEAD` showing a new SHA matching
the phase prefix), the orchestrator MUST run the self-audit below
BEFORE updating the PR body checkbox `- [ ]` → `- [x]` and BEFORE
posting the orchestration-log line claiming the phase is done.

Operator correction 2026-05-31 on the 227 run: *"can you each time
something seems to be shipped look at the checklist yourself and
analyze proof"* / *"you could check it to ai rules too — that you're
the last phase of the cycle"*. This section codifies the discipline.

### Per-phase self-audit (run on EVERY new phase commit)

For each newly-landed phase, the orchestrator runs and quotes back:

1. **Commit shape vs D3 (RED → GREEN)**
   - Bug-fix AC → MUST be two commits, RED first then GREEN. Verify
     via `git log --oneline | grep -E '^[a-f0-9]+ (test|fix).*\[AC-[0-9]+\]'`.
   - Honest no-RED is acceptable ONLY if the proof md explains why a
     RED would be fabricated (e.g. the bug was already fixed by a
     prior PR) and cites the rule it's honouring
     (`adversarial-testing.md` "never weaken a test").
2. **RED commit body quotes a real failure**
   - `git log -1 <RED-sha> --format=%B` MUST contain quoted assertion-
     failure output (`expected: X but was: Y`, `[ERROR] Tests run:
     N, Failures: K` with K≥1, etc.). A RED message that doesn't
     quote a failure is suspect.
3. **GREEN commit body quotes a real success**
   - `BUILD SUCCESS`, `Tests run: N, Failures: 0`, `Test Files X
     passed (X)`, or framework equivalent.
4. **Proof md exists at the expected path**
   - `test -f docs/proof/phase-<N>-<slug>.md` — if missing → REJECT.
   - File MUST contain: AC list, change summary, tests-added table,
     RED→GREEN proof block (or honest deviation), before/after
     screenshot URLs (GH-hosted per D2).
5. **No binary artefacts under `docs/proof/`**
   - `git diff origin/main..HEAD --name-only docs/proof/ | grep -E
     '\.(png|jpg|jpeg|gif|webp|mp4|webm)$' | wc -l` MUST be 0.
6. **No banned shortcuts in the phase diff** (this is the red-flag
   scan below, but run it per-phase too, not just per-cycle).
7. **Watchers' latest verdict for the same SHA**
   - At least one watcher MUST have posted a verdict file dated AFTER
     the phase SHA was pushed. If all watcher verdicts are older than
     the commit → wait one more poll interval before declaring DONE.
   - If any watcher returned `REJECT` for the phase SHA → DO NOT mark
     ✅; surface to the user.
8. **PROOF command re-run** (when mechanical)
   - Quote the test invocation from the proof md and re-run it on a
     **dedicated audit worktree** — NEVER on the builder's worktree
     (per `tmux-agent-worktree-isolation.md`: concurrent mvn/npm runs
     race on `.m2`/`node_modules` locks and dirty the builder's pane).
     Either reuse the orchestrator's worktree or create a one-shot
     audit worktree:
     `git worktree add ~/work/audit-$RUN_ID-phase<N> <phase-sha>`
     then run the command inside it; remove the worktree afterwards
     (`git worktree remove --force ~/work/audit-$RUN_ID-phase<N>`).
     Verify the output matches the proof md. If a re-run reveals a
     flake (passes 1/N), note it on the PR but do NOT mark ✅ until
     the flake is understood.

If ALL eight checks pass, the orchestrator:
- Flips the PR body checkbox `- [x]` for the phase.
- Appends a one-sentence orchestration-log line: `<ts> Phase N DONE
  (<scope>) — RED <sha> + GREEN <sha>; self-audit PASS; watcher
  consensus <verdicts>; binary-proof guard 0.`
- Updates `$RUN_DIR/state.md` with the new phase complete.

If ANY check fails, the orchestrator:
- DOES NOT flip the checkbox.
- Drops a `$RUN_DIR/builder-feedback.md` with the failure detail.
- Posts a comment on the PR explaining what's missing.
- Notifies the user.

### Self-audit is the gate before assessor-consensus

Phase 5 (assessor-consensus) is the externally-visible gate. But the
orchestrator's per-phase self-audit is what makes Phase 5 cheap — by
the time the 3 assessors look at the PR, every phase already passed
the 8-check audit. Skipping the self-audit means the assessors do
the work the orchestrator should have done first, and the assessor
loop blows up to N iterations instead of 1.

## Audit script (the "stupid shit detectors")

Save as `audit-builder.sh`. Run on every audit cycle. It checks:

- **Process alive** — `pgrep` for the builder PID.
- **Phase from status log** — `tail` the last line of
  `$RUN_DIR/status.log`.
- **Commits so far** — `git log origin/main..HEAD` in the worktree.
- **Files written** — the per-phase artifact existence check (`ls spec/...`,
  `find backend -name '*RestDocsTests*'`, etc.).
- **Red-flag scan** — `git diff origin/main..HEAD` searched for:
  - ≥ 3 consecutive `//` lines (bloated comments per `no-bloated-comments`).
  - `@Disabled` additions.
  - `vi.fn().mockResolvedValue(...)` on a stub-driven endpoint.
  - `continue-on-error: true` in workflow yaml.
  - True `--admin` / `--no-verify` / `--no-gpg-sign` in commit messages
    (use `\-\-admin` regex, not the substring `admin`, to avoid matching
    `superadmin*` package names).
  - `TODO`, `FIXME`, `follow-up`, `deferred`, "phase 2", "tracked as" in
    added lines.
  - Tautological assertions (`isNotNull()` alone, `expect(true).toBe(true)`,
    `assertTrue(true)`).
  - Hardcoded secret-shaped literals.
  - `pg.Pool` / `new pg.Client` outside test setup.
  - `org.springframework.data.domain.*` on any port/api class
.
- **Recent agent text** — last ~800 chars of text-deltas reconstructed from
  the stream-json with `jq`. Use this to see thinking, not the tmux pane
  (which is the raw stream-json firehose).

## Audit cadence

5 minutes is the operator default. The cache-aware preference is 270s
(stays in the prompt-cache TTL window) over 300s (pays a cache miss).
Schedule with `ScheduleWakeup` or by re-entering the loop skill.

## Reasoning on top of detectors

Detectors catch the obvious. Spend equal time reading the actual content
the builder is producing and reasoning about it against the rules:

- Does the spec have user stories + ACs + Mermaid diagrams per `core.md`?
- Does the learning file match `learnings.md` format?
- For each port: does the slice IT call EVERY public method, or just one?
- Do entity column renames match the truth-table? (If they don't, the
  slice IT will fail — but flagging the drift before the build saves a
  cycle.)
- Are RestDocs tests appearing in the right place
  (`backend/src/test/java/.../*ControllerRestDocsTests.java`)?
- Did Spring Cloud Contract actually emit stubs at
  `target/generated-snippets/stubs/<endpoint>/`?

When you find something off, flag it to the USER **in plain language** with
file paths + line numbers + the rule it violates. Do not just say "looks
sketchy."

## Per-phase proof gate (mandatory)

Each phase commit MUST carry a proof artifact OR the orchestrator REJECTs the
phase and refuses to advance. This closes the failure mode where a builder
ships an "engine change" or "UI page" commit with no verifiable receipt.

| Phase touches | Required proof artifact (committed in the same phase commit) |
|---|---|
| New / changed UI surface (`*.tsx`, `*.vue`, `*.svelte` under a route or page) | `docs/proof/phase-<N>-<slug>.md` referencing a Playwright deterministic screenshot (1440×900 viewport, stubbed API, assert ≥1 rendered value) **uploaded to GitHub** (PR-comment drag-drop → `user-attachments` URL, `gh gist`, or release asset). The PNG MUST NOT be committed to the repo — Check 5 above will REJECT the phase. |
| Internal / engine change (shared component, hook, util, backend service, DB migration `.sql`, config such as `pom.xml` / `package.json` / `application.yml`, CI/CD workflow under `.github/workflows/`, IaC `*.tf` / `cdk.json` / etc.) | `docs/proof/phase-<N>-<slug>.md` (paths of new/changed tests OR config-validation command + test command + the quoted `Tests run: N, passed: N` / `BUILD SUCCESS` / `Plan: …` / equivalent tail) |
| Spec / docs only | `docs/proof/phase-<N>-<slug>.md` referencing the spec edit + the `verify-spec-tests.sh` PASS line |

If a phase commit lands without its required artifact, the orchestrator MUST:
1. Flag `MISSING_PROOF` to the user with the commit SHA.
2. Block APPROVE of the phase until the proof artifact is committed.
3. Optionally inject a corrective commit that adds the proof file (when the
   artifact already exists locally and was just forgotten in `git add`).

For UI phases specifically, vitest / jsdom render tests do NOT substitute for
a Playwright screenshot — jsdom proves the component mounts; the PNG proves
the page renders at the wire-shape the user actually sees.
