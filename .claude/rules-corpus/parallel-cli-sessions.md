# Parallel Claude CLI Sessions

## When to Use

Need intelligent parallel work without dumbing down main session → multiple `claude` CLI calls, not specialized agents.

## CRITICAL: --tools default mandatory for tool-using prompts

**Background `claude --print` subprocesses silently hang at 0% CPU on first tool call unless `--tools default`.** No output, no stderr, no file modifications — looks like auth/network hang but is `--print` shipping tools disabled. `--permission-mode bypassPermissions` necessary but NOT sufficient — controls permission prompts, not tool availability.

Every spawn-from-shell `claude --print` expecting read files, run shell, edit code MUST pass `--tools default` (or explicit allowlist like `--tools Bash,Edit,Read,Write,Grep,Glob`).

**Fast smoke test** before spawning N agents: one throwaway with same flags asking "list files in /tmp using bash, then say done". No "done" within ~60s → flags wrong; fix before scaling. Catches missing-`--tools` failure in seconds vs 30 min idle background processes.

## Standard CLI Prompt Template

```bash
claude --print \
  --model [opus|sonnet|haiku] \
  --permission-mode bypassPermissions \
  --tools default \
  --add-dir [relevant-dirs] \
  "[CONTEXT]

[MISSION STATEMENT]

MANDATORY STATUS REPORTING:
Write progress to /tmp/status_[task-id].log every 60 seconds:
- 'YYYY-MM-DDTHH:MM:SSZ: [STATUS] message'  
- Include: STARTING → IN_PROGRESS → FINDING → FIXING → COMPLETE
- Heartbeat: '[HEARTBEAT] Still working...' if no progress

[SPECIFIC TASK REQUIREMENTS]

[SUCCESS/FAILURE CRITERIA]

[OUTPUT FORMAT]

FILES/SCOPE: [specific files or scope]

[SPECIFIC QUESTION/ACTION]"
```

## Example: BATS Rule 6 Validation
Moved to rationale (full script/example): `docs/rule-rationale/parallel-cli-sessions.md` — Example: BATS Rule 6 Validation
## Parallel Execution Pattern

```bash
# Split work into groups
find path -name "*.ext" | split -l 5 - /tmp/group_

# Run parallel sessions
i=1
for group_file in /tmp/group_*; do
  files=$(cat "$group_file")
  
  claude --print --model opus --permission-mode bypassPermissions --tools default "[FULL PROMPT WITH $files]" > /tmp/result_$i.out 2>&1 &
  ((i++))
done

# Wait and collect results
wait
cat /tmp/result_*.out
```

## Key Success Factors

1. **Rich Context**: background, mission, patterns
2. **Clear Criteria**: exact pass/fail
3. **Specific Scope**: exact files/areas
4. **Actionable Output**: format for next steps
5. **Model Selection**: by complexity (guide below)
6. **Directory Access**: `--add-dir` for file access

## Model Selection Guide

## Model Selection Guide

| Model | Use when | Flags |
|-------|----------|-------|
| **Opus** | Validation, debugging, architecture, quality gates, unfamiliar code | `--model opus` |
| **Sonnet** | Bulk checks, docs, templates, routine transforms | `--model sonnet` |
| **Haiku** | Binary/count/status questions | `--model haiku` |

```
Is the task complex or subtle?
├── YES: validation/debug/arch? → OPUS
└── NO: binary/count? → HAIKU; else SONNET
```

Default Opus when complexity unknown.
## CRITICAL: Two-Layer Permission Solution

Two permission issues — different fixes:

**Layer 1: Enable Tools (prevents silent hang)**
```bash
--tools default --permission-mode bypassPermissions
```
- **Required for ALL CLI sessions** needing tools
- No `--tools default` → silent hang at 0% CPU on first tool call
- No `--permission-mode bypassPermissions` → permission prompts on basic ops

**Layer 2: Skip Validation Prompts (unblock validation cmds)**
```bash
--dangerously-skip-permissions
```
- **Required for validation/analysis** running `bash -n`, `bats --count`, etc.
- Layer 1 alone → validation cmds still prompt
- Bypasses all permission checks — trusted env only

**Recommended combined usage:**
```bash
claude --print --model [model] --dangerously-skip-permissions --tools default --add-dir [dirs] "[prompt]"
```

**Why both layers:**
- Layer 1 alone → tools work; validation cmds blocked
- Layer 2 alone → may still hang without `--tools default`
- Combined → full unblocked validation/analysis

## Status Reporting Pattern

### CRITICAL: Heartbeat Monitoring for Hang Detection

**Long-running tasks (>5 minutes) → ALWAYS include heartbeat reporting:**

```bash
claude --print --model opus --dangerously-skip-permissions --add-dir [dirs] "Your task description.

CRITICAL STATUS REPORTING:
1. Write to /tmp/status_[unique-task-id].log with timestamps
2. HEARTBEAT: Update status every 60 seconds minimum, even if no progress
3. FORMAT: 'YYYY-MM-DDTHH:MM:SSZ: [STATUS] message'
4. STATUSES: STARTING → IN_PROGRESS → ANALYZING → FINDING → FIXING → COMPLETE

Example status updates:
- '2026-05-12T20:15:30Z: [STARTING] Beginning analysis of 24 BATS files'
- '2026-05-12T20:16:30Z: [IN_PROGRESS] Analyzed 5/24 files, found 2 issues'
- '2026-05-12T20:17:30Z: [HEARTBEAT] Still processing, 8/24 files complete'
- '2026-05-12T20:18:30Z: [FINDING] Issue found in file.bats line 42: missing helper'
- '2026-05-12T20:19:30Z: [FIXING] Applying fix to file.bats'
- '2026-05-12T20:20:30Z: [COMPLETE] All 24 files processed and verified'

MANDATORY: If no progress to report, write '[HEARTBEAT] Still working...' every minute.

[specific task requirements]"
```

### Hang Detection and Recovery

**Monitor for hangs:**
```bash
# Watch all status files
tail -f /tmp/status_*.log &

# Check for stale processes (no updates >3 minutes)
find /tmp -name "status_*.log" -mmin +3 -exec echo "STALE: {}" \;

# Kill hanging processes
ps aux | grep "claude --print" | grep -v grep
kill <hanging-pids>
```

### Status File Naming Convention
- Unique task IDs: `/tmp/status_adversarial_qa_$(date +%s).log`
- Include agent role: `/tmp/status_senior_dev_rule6.log`  
- Avoid collisions: `/tmp/status_review_agent_$$_$(date +%H%M).log`

## Real-time vs Background Execution

| Prompt Length | Behavior | Best Use |
|---------------|----------|----------|
| **Simple** (1-2 lines) | Real-time output | Quick questions, immediate feedback |
| **Complex** (multi-paragraph) | Auto-backgrounds | Analysis, validation, bulk processing |

**Simple real-time example:**
```bash
claude --print --model sonnet --dangerously-skip-permissions "Check file X for syntax errors"
# Gets immediate response
```

**Complex background example:**
```bash
claude --print --model opus --dangerously-skip-permissions "Analyze 20 files for Rule 6 compliance..."  
# Automatically backgrounds with output file
```

## Validation Methodology Warning

**CRITICAL:** Always verify correct validation tool for file type.

| File Type | ❌ Wrong Validator | ✅ Correct Validator |
|-----------|-------------------|-------------------|
| **BATS files** | `bash -n file.bats` (false positives) | `bats --count file.bats` |
| **Python** | Generic shell syntax | `python -m py_compile file.py` |
| **JSON** | Text-based checks | `jq . file.json` |
| **YAML** | Text-based checks | `yq . file.yml` |

## Template Variables

Replace in template:
- `[CONTEXT]`: Project/task background
- `[MISSION STATEMENT]`: What we're trying to achieve
- `[SPECIFIC TASK REQUIREMENTS]`: Detailed technical requirements
- `[SUCCESS/FAILURE CRITERIA]`: Clear pass/fail definitions
- `[OUTPUT FORMAT]`: How results should be presented
- `[FILES/SCOPE]`: Specific files or areas to analyze
- `[SPECIFIC QUESTION/ACTION]`: The actual request

## Hang Prevention and Detection

### CRITICAL: Early Hang Detection

**Signs of hanging agents:**
- No status updates for >3 minutes
- CPU usage drops to 0% and stays there
- Process stuck in 'S' (sleeping) state for extended periods
- No file modifications in working directory

**Automatic hang detection script:**
```bash
#!/bin/bash
# hang-monitor.sh - Monitor Claude CLI sessions for hangs

while true; do
    # Check for stale status files (no updates >3 minutes)
    stale=$(find /tmp -name "status_*.log" -mmin +3 2>/dev/null)
    
    if [[ -n "$stale" ]]; then
        echo "⚠️  HANG DETECTED - Stale status files:"
        echo "$stale"
        
        # Show hanging processes
        echo "🔍 Hanging Claude processes:"
        ps aux | grep "claude --print" | grep -v grep | while read line; do
            pid=$(echo "$line" | awk '{print $2}')
            cpu=$(echo "$line" | awk '{print $3}')
            if (( $(echo "$cpu < 0.1" | bc -l) )); then
                echo "  PID $pid: CPU $cpu% (SUSPECTED HANG)"
            fi
        done
        
        echo "💡 Kill with: kill <pid>"
    fi
    
    sleep 60
done
```

### Recovery Strategy

**When agents hang:**
1. **Identify hanging processes**: `ps aux | grep "claude --print"`
2. **Check CPU usage**: Look for 0% CPU for >5 minutes
3. **Kill immediately**: `kill <pid>` - don't wait longer  
4. **Restart with enhanced monitoring**: Add more frequent status reporting
5. **Consider shorter tasks**: Split work into smaller chunks

## Don't Use Specialized Agents When

- Quality matters more than speed
- You need real file analysis (not hallucination)
- Corruption risk is high
- The task requires intelligence and context
- You're doing validation or quality checks
- **Agents frequently hang and need monitoring**

## CRITICAL: Duplicate Dispatch Prevention

### Problem: Double-Commit from Orphaned Agents

Orphaned-agent re-dispatch → duplicate commits per spec (incident detail in rationale).

### MANDATORY: Pre-Dispatch Cleanup

Before new parallel sessions → kill existing:

```bash
# Kill all Claude CLI sessions with specific task tag
pkill -f 'claude --print.*<task-tag>'

# Example: Kill all Rule 6 audit agents
pkill -f 'claude --print.*rule6'

# Verify they're dead
ps aux | grep "claude --print" | grep -v grep

# Wait for cleanup
sleep 5
```

### Task Locking Pattern

**For critical workflows, use lockfiles per task:**

```bash
#!/bin/bash
# dispatch-with-lock.sh - Prevent duplicate dispatches

TASK_TAG="$1"
LOCKFILE="/tmp/claude-dispatch-${TASK_TAG}.lock"

# Check for existing dispatch
if [[ -f "$LOCKFILE" ]]; then
    PID=$(cat "$LOCKFILE" 2>/dev/null)
    if kill -0 "$PID" 2>/dev/null; then
        echo "❌ Task $TASK_TAG already running (PID $PID)"
        exit 1
    else
        echo "🧹 Cleaning stale lockfile"
        rm -f "$LOCKFILE"
    fi
fi

# Create lockfile
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Launch agents with unique status files
for i in {1..5}; do
    claude --print --model opus --dangerously-skip-permissions "
    Task: $TASK_TAG batch $i
    
    MANDATORY STATUS REPORTING:
    Write to /tmp/status_${TASK_TAG}_batch_${i}_$$.log
    
    [task details]
    " &
done

wait  # Wait for all background jobs
echo "✅ All $TASK_TAG agents complete"
```

### Status File Collision Prevention

**Use unique identifiers in status files:**

```bash
# ❌ BAD - Collision risk
/tmp/status_rule6_audit.log

# ✅ GOOD - Unique per dispatch
/tmp/status_rule6_audit_$(date +%s)_$$.log
/tmp/status_rule6_audit_batch_${i}_$$.log
```

### Dispatch Recovery Commands

**When you suspect duplicate dispatch:**

```bash
# 1. List all Claude processes with task details
ps aux | grep "claude --print" | grep -E "(rule6|campaign|audit)" 

# 2. Kill by task pattern
pkill -f 'claude --print.*rule6'

# 3. Clean up status files
rm -f /tmp/status_*rule6*.log

# 4. Check git for duplicate commits
git log --oneline -20 | grep -E "(rule6|campaign|audit)"

# 5. If duplicates found, interactive rebase to squash
git rebase -i HEAD~12  # Edit to squash duplicates
```

### Integration with Hang Detection

**Combined safe dispatch pattern:**

```bash
#!/bin/bash
# safe-dispatch.sh - Prevents hangs AND duplicates

TASK_TAG="$1"
LOCKFILE="/tmp/claude-dispatch-${TASK_TAG}.lock"

# Step 1: Kill any existing agents
echo "🧹 Cleaning existing agents..."
pkill -f "claude --print.*${TASK_TAG}" || true
sleep 5

# Step 2: Check lockfile
[[ -f "$LOCKFILE" ]] && rm -f "$LOCKFILE"
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Step 3: Launch with monitoring
./scripts/monitor-claude-agents.sh &
MONITOR_PID=$!
trap 'kill $MONITOR_PID; rm -f "$LOCKFILE"' EXIT

# Step 4: Dispatch agents
for i in {1..5}; do
    claude --print --model opus --dangerously-skip-permissions "
    Task: $TASK_TAG batch $i
    
    MANDATORY STATUS REPORTING:
    Write to /tmp/status_${TASK_TAG}_${i}_$$.log every 60 seconds
    
    [task details]
    " &
done

# Step 5: Wait and cleanup
wait
kill $MONITOR_PID
echo "✅ All $TASK_TAG agents complete, no duplicates"
```

## Use This Approach For

Code validation/review, systematic file analysis, pattern detection, quality audits, parallel investigation, complex analysis needing full context, any multi-agent dispatch (with duplicate prevention).

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/parallel-cli-sessions.md`

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/parallel-cli-sessions.md`
