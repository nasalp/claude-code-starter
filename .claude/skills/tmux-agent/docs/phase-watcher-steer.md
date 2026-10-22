# Phase 4½ — Cooperative STEER channel (V1)

V1 adds a file-mailbox steering channel between watchers and the builder. On drift,
the watcher writes structured `$RUN_DIR/STEER.md`; the builder reads it at checkpoints
and course-corrects. No `tmux send-keys` — cooperative only.

## Builder-facing files

| Path | Purpose |
|---|---|
| `$RUN_DIR/STEER.md` | Current steer: severity, whats_wrong, required_change, rule_ref, phase, ts |
| `$RUN_DIR/STEER.halt` | Present when severity is `reject` — builder halts the phase until addressed |

## Internal state (`$RUN_DIR/steer/`)

| Path | Purpose |
|---|---|
| `trail.ndjson` | Append-only JSON log: `written`, `dedup_suppressed`, `cap_suppressed`, `halt_written`, `phase_reset` |
| `state/count` | Steers written this phase (cap guard) |
| `state/hashes/<hash>` | Dedup markers (cksum of payload) |
| `state/phase` | Last seen phase identity |
| `phase.current` | Optional builder-written phase override |

## Drift detection

1. **Primary:** structured watcher verdict (`reject` / `escalate` / `approve`).
2. **Secondary backstop:** forbidden-pattern grep (`TODO`, `FIXME`, `@Disabled`, `|| true`, …) → `warn` only, never `reject` alone.

## Env knobs

| Variable | Default | Effect |
|---|---|---|
| `STEER_MAX_PER_PHASE` | `3` | Max distinct steers per phase before cap suppression |
| `STEER_POLL_SECONDS` | `45` | Default watcher poll for cheap engines (`composer`, `gemini-flash`) |
| `WATCHER_POLL_SECONDS` | — | Hard override of poll interval (all engines) |

Premium `claude` watcher default poll remains **300s** unless `WATCHER_POLL_SECONDS` is set.

## Builder brief contract

`launch-builder.sh` appends a STEER checkpoint section to an augmented prompt at
`$RUN_DIR/builder-prompt.augmented.md` (source prompt is never mutated). The builder
must read `STEER.md` before each phase and each commit, acknowledge with
`STEER_ACK phase=<p> severity=<s> action=<summary>`, and respect `STEER.halt`.

## Library

Implementation lives in `scripts/lib/steer.sh`, sourced from `watcher-loop.sh`.
Entry point: `_steer_process_verdict RUN_DIR VERDICT_FILE`.
