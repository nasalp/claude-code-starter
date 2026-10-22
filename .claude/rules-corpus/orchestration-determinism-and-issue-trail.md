# Orchestration determinism + GitHub-issue trail for tmux-agent builds

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment / merge, no exceptions |

## Rule

Long-running `tmux-agent` build (1 orchestrator + N builders + assessors) MUST make guardrails **mechanically enforceable** and orchestration state **auditable in GitHub**, not just in orchestrator chat or `/tmp`. Two requirements:

1. **Deterministic merge gate.** Before any `gh pr merge --squash --admin` orchestrator MUST run `.claude/skills/tmux-agent/scripts/orchestration/pre-admin-merge-gate.sh` and it MUST exit 0. Script mechanically re-checks guardrails tired/over-eager orchestrator might wave through: local build green, 3-assessor unanimous APPROVE, screenshot proof for UI changes, no suppressions in diff, GitHub-issue trail (below). Human or LLM saying "it's green, 3 approved" NOT sufficient — script is source of truth.
2. **GitHub-issue trail.** Three orchestration artifacts that today live only in `/tmp` or chat — **consensus plan-of-work**, **production-readiness checklist**, **watcher/assessor quality-verification cadence** — MUST each be mirrored to GitHub issue (or tracked comment on parent issue) so build reconstructable after session crash and reviewable by human never in chat.

Determinism + auditability layer on top of `mutual-watcher-cross-audit.md`, `consensus-plan-per-work-unit.md`, `per-ac-end-to-end-coverage.md`. Those say WHAT loop must do; this says **prove it with script and GitHub trail**.

## What is required

### 1. The deterministic pre-merge gate (script)

`.claude/skills/tmux-agent/scripts/orchestration/pre-admin-merge-gate.sh <PR#> <run-dir>` MUST run and exit 0 before `gh pr merge --admin`. Checks, failing closed (non-zero) on any miss:

- **Local build green**: captured `verify-like-ci` (or project gate) tail containing success marker (`BUILD SUCCESS`, `Tests run: N, Failures: 0`, `Test Files X passed`) exists for PR's head SHA in run dir. Stale tail (different SHA) fails.
- **3-assessor unanimous APPROVE**: exactly assessor verdict files for this round each end with `VERDICT: APPROVE`. Any `REJECT`, any missing/empty/`BLIND` verdict, or fewer than required count fails. `2 of 3` does NOT pass.
- **Screenshot proof for UI diffs**: if PR diff touches UI files (`.tsx`/`.vue`/`.svelte` under page/component dir), PR body MUST contain GitHub-hosted image URL (`user-attachments` / `user-images.githubusercontent.com` / release-asset). Backend-only PRs exempt (and must say so).
- **No suppressions in diff**: PR diff (merge-base, 3-dot) MUST NOT add `@Disabled`, `@SuppressWarnings`, `NOPMD`, `// CHECKSTYLE:OFF`, `continue-on-error`, or teardown-verb-less `|| true` (per `no-silent-pass-in-ci.md`'s teardown allowlist).
- **GH-issue trail present**: consensus-plan issue/comment and production-checklist issue/comment for this work unit exist and referenced from PR body.

Script verdict is the gate. Invoked from Phase 6 BEFORE merge command; tail pasted into PR as merge evidence.

### 2. Consensus plan-of-work → GitHub issue

Per `consensus-plan-per-work-unit.md` every work unit runs Phase-2 consensus and produces plan-of-work. Doc MUST mirror to GitHub issue (or clearly-labelled `## Plan-of-work` comment on parent epic issue) containing: locked decisions (D1, D2, …), phase/PR sequence, per-PR test strategy, watcher composition. Builder/assessor briefs reference by URL. On session resume orchestrator reads issue, not `/tmp`.

### 3. Production-readiness checklist → GitHub issue

Production-readiness checklist for work unit MUST live as GitHub issue with tickable `- [ ]` items (Visibility/Boundaries, Runtime State, Compile-Time Safety, Tenant Isolation, Test Pyramid, Security, Observability, Spec & Audit Hygiene, CI & Build, Pre-Merge Gate). Each merged PR ticks items it satisfies in that issue. Pre-merge gate verifies issue exists and referenced; assessor briefs require walking it per PR.

### 4. Watcher / assessor quality-verification cadence → GitHub trail

Watcher + assessor process MUST post verdicts to PR as review comments **as often as it runs**. Cadence: verify, as often as possible, (a) is implementation high-quality (no static-presented-as-real, no suppressions, no shortcuts), (b) is there PROOF for every claim (verify tail, screenshot, RED→GREEN), (c) does diff match spec AC. Orchestrator's per-cycle job: CONSUME those verdicts and refuse merge while any REJECT unaddressed (`mutual-watcher-cross-audit.md`). Pre-merge gate makes "all-APPROVE-this-round" check mechanical.

## What is allowed (documented variant — multi-machine codex fleet)

Canonical tmux-agent skill runs ONE builder + N watchers on one host through Headroom-Claude. A **variant** is allowed when documented in the plan-of-work issue:

- **codex as builder + 2-of-3 assessor engine** (Claude as 3rd), for provider-quota isolation and cost.
- **3 physical machines, one lane each** (true parallelism; each boots own e2e backend on fixed ports without collision).
- **one PR per AC**, each independently gated (smallest blast radius; flake/broken-on-base isolation).
- **event-driven monitors + cron backstop** instead of fixed N-min poll.

**Honest deviation MUST be declared** in plan-of-work issue if taken — e.g. a build that relies on per-cycle orchestrator audit + hard Phase-5 assessor gate INSTEAD of mandatory Phase-4½ persistent watcher loops. Trades in-flight catching for stronger merge gate. Acceptable ONLY when pre-merge gate script enforced and assessor trio re-runs proofs every merge. Do not silently drop watchers — declare trade in issue so reviewer knows.

## What is forbidden

| Pattern | Why |
|---|---|
| `gh pr merge --admin` without running `pre-admin-merge-gate.sh` exit 0 | Re-introduces assert-don't-check trust debt |
| Plan-of-work / production checklist living only in `/tmp` or chat | Lost on crash; not human-reviewable |
| Reading 3-assessor verdict from chat instead of script | Mis-read `2 of 3` merges a REJECT |
| Dropping persistent watchers WITHOUT declaring in issue | Silent weakening of audit layer |

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/orchestration-determinism-and-issue-trail.md`
