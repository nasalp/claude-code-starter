# Rationale — ai-generated-config-security.md

## What this rule interacts with

- `common/security.md` — the broader security checklist; this rule
  tightens it for AI-generated config specifically.
- `mcp.md` — MCP servers have their own auth surface; this rule's
  wildcard-permission / lateral-move classes also apply to MCP tool
  scopes.

## Calibration

The 89% / 78% / 62% / 45% / 37% numbers come from a published audit
shown at a security industry event (slide screenshot 2026-05-15). They
are not specific to one team. The point is not the precise number but the
shape: AI agents systematically under-attend to permissions, secrets,
and validation. Calibrate review effort accordingly: agents need MORE
scrutiny on these classes than humans do, not less.
