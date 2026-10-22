# Hooks System

## CRITICAL: Hooks emit warnings, not blocks

**Every hook exits 0.** Hooks emit `[<hook-name>] WARNING: …` to stderr, return zero → agent tool call proceeds.

**Agent MUST read and act on warnings.** Silent stderr ignore = defect. See `WARNING` in tool output → treat as rule reminder you MUST address (write spec, write test, fix failing tests, run in tmux, etc.) before moving on.

Policy: blocking hooks (`exit 2`) = theatre — agents bypass via `SPEC_BYPASS=true` or skip flags. Warnings-without-blocks clarify message, put accountability on agent. Rules still apply; only enforcement changes.

Hook with `exit 2` after warning = defect — file issue.

## Hook Types

- **PreToolUse**: before tool exec (validation, param modification)
- **PostToolUse**: after tool exec (auto-format, checks)
- **Stop**: session ends (final verification)
- **SubagentStop**: spawned Agent finishes (transcript inspection)

## Installed Hooks

### `hooks/spec-first-check.sh` (PreToolUse: Write, Edit)

Warns when production source modified without corresponding spec changes. Language-agnostic — detects source for:

Java, Kotlin, Groovy, Scala, Python, Go, TypeScript, JavaScript, Rust,
Swift, C/C++, PHP, Perl.

**Behavior:**
- Detects if file written/edited is production source
- Checks if any `spec/` files modified in current git session
- Emits WARNING to stderr if specs missing (does not block)
- Skips: test files, config files, generated code, package-info, migrations

### `hooks/triage-check.sh` (Stop)

At session end, reminds agent to run 3-agent triage review before considering work complete:

1. **Senior Adversarial QA** — specs exist? tests before code? edge cases?
2. **Senior Dev** — code matches spec? SPEC→TEST→IMPLEMENT followed? KISS?
3. **Senior DevOps** — observable? resilient? deployable? configs externalized?

All 3 MUST reach consensus before work ships.

**Behavior:**
- Counts modified source files in git working tree
- Warns if specs not modified alongside source changes
- Emits triage checklist to stderr

## Auto-Accept Permissions

Use with caution:
- Enable for trusted, well-defined plans
- Disable for exploratory work
- Never use dangerously-skip-permissions flag
- Configure `allowedTools` in `~/.claude.json` instead

## TodoWrite Best Practices

Use TodoWrite to:
- Track progress on multi-step tasks
- Verify understanding of instructions
- Enable real-time steering
- Show granular implementation steps
