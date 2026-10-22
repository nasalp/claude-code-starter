# Rationale — java/visibility-and-javadoc.md

## Cross-reference

- `.claude/rules/no-deferred-work.md` — TODO-shaped Javadoc placeholders are deferred-as-done in micro form.
- Project-specific extensions (each consumer project ships its own carve-out tightened for its own architecture):

## Calibration

The rule was hardened 2026-05-20 after a review pass flagged that `public class` was being used as the default modifier in new code, and that the Javadoc requirement was being interpreted as "optional, when convenient." Both are wrong. Public is not the default; it is a deliberate widening with an obligation. The Javadoc is the obligation in writing.
