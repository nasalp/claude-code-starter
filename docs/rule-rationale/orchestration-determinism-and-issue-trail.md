# Rationale — orchestration-determinism-and-issue-trail.md

## Why

Multi-day autonomous build accumulates trust debt: every "verify is green", "3 assessors approved", "screenshot looks fine" is orchestrator assertion. Across dozens of merges, one un-checked assertion slips (blank screenshot, 2-of-3 read as 3-of-3, `|| true` in diff). Fix: stop *asserting* guardrails, start *executing* check that fails closed. Orchestrator session can die (reboot, OOM, context compaction) → plan/checklist/cadence must survive in GitHub, not volatile `/tmp` — else resuming session re-derives from faded memory.

## Cross-references

- `mutual-watcher-cross-audit.md` — nobody-trusts-nobody; orchestrator is consumer-of-record.
- `consensus-plan-per-work-unit.md` — Phase-2 per work unit (now → GH issue).
- `per-ac-end-to-end-coverage.md` — per-AC test pyramid gate checks.
- `no-silent-pass-in-ci.md` — suppression/`|| true` list gate scans.
- `.claude/skills/tmux-agent/scripts/orchestration/pre-admin-merge-gate.sh` — the enforcer.
