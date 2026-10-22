# phase 1 clarify

# Phase 1 — clarify

Pull JUST the questions where the answer changes the data model, the public
API shape, or who's allowed to do what. Examples of MUST-ask:

- Cardinality (one X per Y, or many)?
- Soft-delete vs hard-delete?
- Default permission gate (super-admin? a property-driven allowlist? a new role)?
- Source of an ID list (which table, what filter)?

Do NOT ask about implementation tactics, file paths, helper names, or
"should I split this into N PRs" — those are orchestrator decisions, not
user decisions.

Output of this phase: a small table of "Decision X → user said Y", saved
in the prompt for the builder so it cannot re-decide.

## Also emit a CHECKLIST in Phase 1

Alongside the decisions table, write a `checklist.md` at
`$RUN_DIR/checklist.md`. It enumerates every concrete deliverable, one
row per item, with three columns:

| # | Item (what must exist) | PROOF (how we'll know it's done) |

Examples of well-formed rows:

| 1 | spec/features/060-x.md exists with ≥ 8 ACs and Mermaid per US | `wc -l spec/features/060-x.md` + `grep -c 'AC-' spec/features/060-x.md` + `grep -c sequenceDiagram spec/features/060-x.md` |
| 2 | V22 Flyway migration creates table X with UNIQUE constraint Y | `git show V22 file` + `ls backend/.../db/migration/V22*.sql` |
| 3 | 8 JPA slice-IT classes exist, one per BC, each extending AbstractSchemaJpaIT | `find backend-it -name '*JpaIT.java' \| wc -l` (= 8) |
| 4 | CustomerHealthControllerRestDocsTests has ≥ 8 @Test methods (one per endpoint) | `grep -c '@Test' CustomerHealthControllerRestDocsTests.java` (≥ 8) |
| 5 | SCC stubs generated at backend/target/generated-snippets/stubs/customer-health/ | `ls backend/target/generated-snippets/stubs/customer-health/` (non-empty) |
| 6 | Frontend Vitest tests consume the stubs via @stubborn-sh/jest, NOT vi.fn().mockResolvedValue | grep should find `setupStubs` and NOT find `vi.fn().mockResolvedValue` in customer-health test files |
| 7 | Full reactor verify BUILD SUCCESS | `./mvnw clean verify -T 1C` exit 0 + `grep "BUILD SUCCESS" verify.log` |

Every row's PROOF column MUST be a command (or a small set of commands)
that the orchestrator can run mechanically. "Looks done" is not proof.

The builder receives this checklist in the prompt with the instruction:
"after each phase, append `✓` or `✗` to each item AND quote the proof
output back to `$RUN_DIR/checklist-status.md`. The orchestrator reads
that file every audit cycle and re-runs every PROOF command itself —
never trusts the builder's `✓` without running the proof."

