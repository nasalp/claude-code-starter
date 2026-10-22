# Never Silently Pass a Failing CI Step

## Priority

| Priority | Meaning |
|---|---|
| **CRITICAL** | Blocks deployment, no exceptions |

## Rule

CI step running a real check MUST fail the build on a real finding. No `continue-on-error: true`, no `... || true`, no `|| exit 0`, no `set +e` + unchecked command, no try/catch swallowing exit code, no "fix later" wrapping a hard gate.

Too-noisy gate → fix noise, don't silence gate. Green CI hiding failure = forged quality stamp.

## What is required

### 1. CI step must propagate failure

Every Actions check step MUST: no `continue-on-error: true` (unless step only uploads artifact on PRIOR step failure); `run:` exits non-zero on real finding.

Only legit `continue-on-error` — follow-up artifact-upload runs even when prior gate failed:

```yaml
- name: Run Semgrep
  id: semgrep
  run: ./scripts/run-semgrep.sh
  continue-on-error: true                    # allowed ONLY because:

- name: Upload Semgrep SARIF
  if: always() && hashFiles('semgrep.sarif') != ''
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: semgrep.sarif

- name: Fail if Semgrep reported errors
  if: steps.semgrep.outcome == 'failure'    # ... THIS step re-asserts the failure
  run: ./scripts/gha-fail-with-message.sh "Semgrep reported ERROR-severity findings"
```

`continue-on-error` on first step conditional on LAST step re-asserting failure on same signal. No artifact-upload pattern → `continue-on-error` forbidden.

### 2. Backlog-clearing: introduce → backfill → gate

New check surfacing existing backlog:

1. Introduce as `scripts/` script (not yet in CI). Verify locally.
2. Backfill: file tracking issue listing failures. Close backlog in focused PRs.
3. Gate: after backlog closed, wire as HARD gate (no `continue-on-error`).

Backlog large but want check sooner → NOT `continue-on-error`. Instead:

- Split script scope (e.g. only validate specs whose status is `implemented`, not also `draft`).
- Explicit allowlist file script reads (e.g. `scripts/ac-tagging-backlog.txt`); fails on ID not in allowlist. Allowlist = visible code, not hidden silencer.
- Stage rollout by repo/module/package, gate one slice at a time.

### 3. Audit-only steps allowed, must say so

Info-only step (no gate) OK if named obvious:

```yaml
- name: Coverage report (observational, does not gate)
  run: ./scripts/print-coverage-summary.sh
```

Name carries `(observational, does not gate)`. Step exits non-zero only if script itself fails.

## What is forbidden

```yaml
# ❌ Silent pass via continue-on-error with no asserting follow-up
- name: Verify acceptance criteria have tests
  run: ./scripts/verify-ac-tests.sh
  continue-on-error: true                # forbidden — no follow-up fail step

# ❌ Silent pass via shell short-circuit
- name: Lint code style
  run: ./scripts/lint.sh || true         # forbidden

# ❌ Silent pass via exit 0
- name: Run tests
  run: ./scripts/test.sh || exit 0        # forbidden

# ❌ Silent pass via munged output
- name: Run tests
  run: |
    ./scripts/test.sh > test.log 2>&1
    grep -q "BUILD SUCCESS" test.log && exit 0
    cat test.log                          # forbidden — swallows non-success exits
```

```bash
# ❌ Silent pass via set +e
#!/usr/bin/env bash
set -e
set +e                                    # forbidden when used to disarm a check
./run-test-suite.sh
# Note: the difference matters — `set +e` to capture an exit code into a
# variable for later inspection (and then propagate it) is fine. `set +e`
# followed by an unchecked failing command is the pattern this rule forbids.
```

## Enforcement

1. CI gate (ai-rules): `scripts/ci/check-no-silent-pass.sh` greps PR-diff workflow YAML + shell for forbidden shapes; fails unless documented escape-hatch (named follow-up failure step).
2. Pre-commit / pre-push hook: same check locally.
3. Code review: PR adding `continue-on-error: true`, `|| true`, `|| exit 0`, or `set +e` near check MUST justify + link artifact-upload re-assert step. Default: REJECT.

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/no-silent-pass-in-ci.md`
