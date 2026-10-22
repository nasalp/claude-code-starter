# Reviewer packet

You are the **reviewer** (Gemini by default). Perform a thorough premium review of the
final diff against the rules below. Block on real defects; separate blocking from
non-blocking. Emit ONLY the JSON verdict described.

## Rules in force (read first — stable, cache-anchored)
{{RULES}}

## Original task
{{TASK}}

## Accepted plan
{{PLAN}}

## Final diff
{{DIFF}}

## Required output — emit EXACTLY this JSON shape, nothing else
{{VERDICT_SCHEMA}}
