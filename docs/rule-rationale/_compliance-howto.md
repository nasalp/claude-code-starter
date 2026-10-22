# Rationale — _compliance-howto.md

## Why this layering, not a built-in scanner

The harness used to plan its own JavaParser-based AST scanner. That
duplicates ArchUnit, which already runs in every consumer project's
CI and fails the build on violation.

| Layer | Tool | Where | What it catches |
|---|---|---|---|
| Build-time enforcement | ArchUnit / ESLint / Spotless / SpotBugs | Inside each consumer | Every violation, blocks merge |
| Trend signal | `.compliance.regex` + grep | ai-rules orchestrator | "Forbidden literal `OtlpMeterRegistry` is creeping into the fleet" |

Anything else belongs in the consumer's build. Don't reinvent.
