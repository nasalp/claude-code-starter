# Proof of Work

Every claim work done MUST be backed by evidence user can verify without re-running work.

Universal — applies to main session, every subagent, every parallel CLI session, every cron-triggered run.

---

## CRITICAL: No bare claims

Bare claim = failure mode. Red flags when not followed by evidence:

- "Done."
- "Implemented X."
- "Tests pass."
- "Build is green."
- "Fixed the bug."
- "Should work now."
- "I believe this is correct."
- "In theory this addresses…"

Claim without evidence = indistinguishable from hallucination. **Treat future self and user as adversaries who do not trust you** — show receipt.

---

## REQUIRED: Per work type, attach this evidence

| Claim | Required evidence |
|---|---|
| Code change | File path + line range + commit SHA, OR the new content quoted |
| Tests pass | Tail of test output containing `Tests run: N, Failures: 0` (or framework equivalent) and exit code |
| Build green | Tail of build output containing `BUILD SUCCESS` / `Build successful` / equivalent |
| BATS test added | `ok N <test-name>` line from `./acceptance/run.sh` output |
| BATS test catches gap | `ok N` on Python SUT + `not ok N` on Java/target SUT, both quoted |
| Commit landed | `git log --oneline -1` output (SHA + message) |
| PR created | URL printed by `gh pr create` |
| Bug reproduced | Exact failing command + its output |
| Bug fixed | Same command + new output showing pass, with the commit SHA between them |
| Lint / static analysis clean | Tail showing zero violations |
| Agent finished | Per `parallel-cli-sessions.md` heartbeat rule: rc=0 + final status line + output file size |
| Spec / AC traceability gate | `acceptance/scripts/check-ac-ids.sh` PASS line |

If work doesn't produce quotable line, owe reader one-line description of what you'd quote and why it can't be quoted ("change in `Foo.java:42-58`, no output to capture — verify by reading file").

---

## REQUIRED: For subagents

Every subagent prompt MUST instruct agent to include evidence in final report. Suggested boilerplate:

```
Your final report MUST include:
- Files changed (paths, line ranges)
- Build status (paste the BUILD SUCCESS / BUILD FAILURE line + exit code)
- Tests run (paste the Tests run: line)
- For each claim in your report, paste the command output that proves it.

A bare "done" or "tests pass" without evidence is a failure mode.
If you cannot capture evidence, say so explicitly with the reason.
```

When reading subagent report, **scan for evidence first**. Claim with no evidence = unverified — verify yourself before relaying to user.

---

## REQUIRED: For parallel CLI sessions

Per `parallel-cli-sessions.md`, every `claude --print` spawn must write status file (`/tmp/status_<task-id>.log`) with heartbeats. Status file IS proof-of-work for agent lifecycle.

After the agent exits:
1. Append the exit code, output byte count, and timestamp to the status file.
2. Parent session pastes the last 2-3 status lines + first 20 lines of the output file into its summary.

Session with zero output AND zero status lines = presumed hung — kill it, do not "wait longer".

---

## RECOMMENDED: Format

Quote evidence in fenced block, not paraphrased. Paraphrasing loses proof and lets errors creep in.

```
✅ Good:
> mvn verify
> ... [INFO] Tests run: 246, Failures: 0
> [INFO] BUILD SUCCESS

❌ Bad:
"Build is green, 246 tests pass."
```

For long output, quote tail (last 5-10 relevant lines) — don't dump whole log.

---

## Detection

Completion claim in summary with no quoted output, no SHA, no file:line reference, and no pasted log line = defect. Either:
- Work didn't happen (caught early — good)
- Work happened but proof withheld (bad habit, fix report)
- Work happened and produces no observable output (rare — say so explicitly)

When in doubt, **assume work did not happen** until evidence shown.

---

## Anti-patterns

| Anti-pattern | Why it's wrong |
|---|---|
| "Tests pass." | No exit code, no count, no SUT, no command |
| "I implemented the fix and verified it works." | No diff, no verify command, no output |
| "The agent finished." | No exit code, no output file path, no status |
| "Build is green now." | No `BUILD SUCCESS` line quoted |
| Reporting passing test without naming which test | Reader can't re-run it |
| Quoting only success line and hiding warnings | Selective evidence = no evidence |

---

## When evidence is genuinely unavailable

Some work has no output: designing approach (no code yet), reading code to understand system, triaging long log without fix.

For these, proof-of-work = **specific, falsifiable statement**, not action verb:

- Not: "I understand the auth flow."
- Yes: "The auth flow is: `OAuthController.authorize()` (line 42) → calls `PkceStore.store()` (line 89) → redirects via `Location:` header to `AGENT_URL`. The token comes back to `/oauth/callback` and is verified by `JwtValidator.validate()` (line 17)."

Statement specific enough reader can disprove by reading one file = itself evidence.

---

## Quick reference

| Rule | Priority |
|------|----------|
| No bare claims | CRITICAL |
| Attach evidence per work type | REQUIRED |
| Subagent prompts demand evidence | REQUIRED |
| Parallel CLI sessions have heartbeat files | REQUIRED |
| Quote output, don't paraphrase | RECOMMENDED |
| Specific falsifiable statement when no output exists | REQUIRED |
