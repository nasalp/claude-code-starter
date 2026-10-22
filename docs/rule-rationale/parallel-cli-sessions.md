# Rationale — parallel-cli-sessions.md

## Why This Works Better

| Approach | Quality | Context | Issues |
|----------|---------|---------|--------|
| **Specialized Agents** | ❌ Narrow, error-prone | ❌ No inheritance | ❌ False confidence, corruption |
| **Claude CLI Sessions** | ✅ Full intelligence | ✅ Full project context | ✅ Real analysis, actionable |

## Lessons learned (hang incident)

- 3 Opus agents hung 4+ hours at 0% CPU
- No output files written (early hang sign)
- Status files never created (agents never started properly)
- Manual validation completed work in minutes

## Lessons learned (duplicate dispatch)

Real incident: first dispatcher thought it orphaned children, re-dispatch triggered:
- **3 specs** (cmp-campaign-analytics, cmp-campaigns, cmp-survey-questions)
- **2 commits each** instead of 1 (12 commits instead of 7)
- **Additive work**: first pass ~30 lines, second pass ~10 lines (both needed but duplicated effort)

| Issue | Cause | Prevention |
|-------|-------|------------|
| **Duplicate commits** | Thought agents orphaned, re-dispatched | `pkill -f` check before dispatch |
| **Orphaned agents** | Lost track of background processes | Lockfiles + PID tracking |
| **Status collision** | Multiple agents writing same file | PID + timestamp in names |
| **Incomplete cleanup** | Agents survived termination | Verify with `ps aux` after kill |

## Real example (validation methodology)

Entire "BATS corruption crisis" was false positives from using `bash -n` instead of `bats --count`.

## Moved examples (from loaded rule)

## Example: BATS Rule 6 Validation

```bash
claude --print --model opus --add-dir acceptance/tests "You are validating BATS Rule 6 deep audit fixes in the project.

MISSION: Verify that Rule 6 (F10/F11 findings) has been correctly applied to eliminate shallow work patterns.

WHAT TO CHECK FOR:
1. SCOPED HELPER FUNCTION:
   - Must exist: __[module]_assert_no_external_egress() 
   - Must have proper regex: maps|google|places|uberall|listingHelper|listing-helper
   - Must have proper error messages with hit counts
   - Function name must match module name (file basename with - replaced by _)

2. FUNCTION USAGE:
   - No bare 'wm_assert_no_outbound_calls' calls in actual code
   - All calls should use the scoped helper instead
   - Comments referencing old function are OK

3. NO || TRUE SWALLOWS:
   - No '|| true' on dump_trace, assert_trace_dump_root, assert_trace_no_errors
   - Setup function || true patterns are OK (wm_clear_overrides, wm_reset_requests)

4. SYNTAX ISSUES:
   - No corrupted function definitions
   - No orphaned code blocks
   - Functions have proper opening/closing braces

SUCCESS CRITERIA: All files pass all 4 checks
FAILURE CRITERIA: Any syntax errors, missing helpers, or wrong patterns

OUTPUT FORMAT: For each file report PASS/FAIL with specific issues found. End with summary count.

FILES: [file list]

Check these files and report validation results."
```


## Model Selection Guide

### **Use Opus 4.7 When:**

| Task Type | Examples | Why Opus |
|-----------|----------|----------|
| **Validation & Auditing** | Code review, Rule 6 audits, security checks | Catches subtle issues, deep structural analysis |
| **Architecture Analysis** | System design review, refactoring plans | Complex reasoning about relationships |
| **Bug Investigation** | Root cause analysis, intermittent failures | Superior debugging and pattern recognition |
| **Complex Code Changes** | Multi-file refactors, API redesigns | Understands broader implications |
| **Quality Gates** | Pre-commit validation, production readiness | Thorough, catches edge cases |
| **Learning/Research** | Understanding unfamiliar codebases | Better at connecting concepts |

**Default Opus Prompt Pattern:**
```bash
claude --print --model opus --permission-mode bypassPermissions --tools default --add-dir [dirs] "[Rich context + complex requirements]"
```

### **Use Sonnet 4.6 When:**

| Task Type | Examples | Why Sonnet |
|-----------|----------|----------|
| **Bulk Processing** | File format checks, pattern replacements | Faster, good enough quality |
| **Simple Validation** | Syntax checks, basic linting | Quick turnaround |
| **Documentation** | README updates, comment generation | Efficient for straightforward tasks |
| **Data Transformation** | Log parsing, CSV processing | Handles routine transformations well |
| **Template Generation** | Boilerplate code, config files | Fast template creation |

**Default Sonnet Prompt Pattern:**
```bash
claude --print --model sonnet --permission-mode bypassPermissions --tools default --add-dir [dirs] "[Clear task + specific criteria]"
```

### **Use Haiku 4.5 When:**

| Task Type | Examples | Why Haiku |
|-----------|----------|----------|
| **Simple Questions** | "Does file X exist?", "What's the status?" | Instant responses |
| **Binary Checks** | Pass/fail, exists/missing | Fast yes/no answers |
| **Quick Counts** | File counts, line counts | Simple numeric results |
| **Status Updates** | Progress checks, completion status | Lightweight monitoring |

**Default Haiku Prompt Pattern:**
```bash
claude --print --model haiku --permission-mode bypassPermissions --tools default "[Simple question]"
```

### **Decision Matrix for Task Planners**

```
Is the task complex or subtle?
├── YES: Does it involve validation, debugging, or architecture?
│   ├── YES: Use OPUS (quality critical)
│   └── NO: Does it need deep understanding?
│       ├── YES: Use OPUS
│       └── NO: Use SONNET
└── NO: Is it a simple binary question or count?
    ├── YES: Use HAIKU
    └── NO: Use SONNET
```

### **Cost vs Quality Considerations**

| Model | Relative Cost | Speed | Quality | Best Use Cases |
|-------|---------------|--------|---------|----------------|
| **Opus** | 3x | Slowest | Highest | Critical validation, complex analysis |
| **Sonnet** | 1x | Medium | High | General purpose, bulk processing |
| **Haiku** | 0.3x | Fastest | Good | Simple checks, monitoring |

**Rule of thumb:** Opus when complexity unknown; Sonnet only if speed/cost bites.
