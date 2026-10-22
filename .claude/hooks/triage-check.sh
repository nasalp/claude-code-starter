#!/usr/bin/env bash
#
# Stop hook: Triage verification with 3 review perspectives.
#
# At session end, this reminds Claude to run the triage check:
# 1. Senior Adversarial QA — are tests comprehensive? Do they catch edge cases?
# 2. Senior Dev — does the code follow specs? Is the architecture sound?
# 3. Senior DevOps — is it operable? Observable? Resilient?
#
# All 3 must reach consensus before the work is considered complete.
#
# This hook emits a reminder to stderr. The actual triage is performed
# by Claude spawning 3 review agents in parallel.
#
set -euo pipefail

# Check if there are uncommitted production source changes
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$PROJECT_ROOT" ]; then
    exit 0
fi

# Count modified/untracked production source files
SRC_PATTERN="\.(java|kt|groovy|py|go|ts|tsx|js|jsx|rs|swift|c|cpp|cc|h|hpp|php|pl|pm)$"
CHANGED_SRC=$(git diff --name-only 2>/dev/null | grep -cE "$SRC_PATTERN" || true)
STAGED_SRC=$(git diff --cached --name-only 2>/dev/null | grep -cE "$SRC_PATTERN" || true)
UNTRACKED_SRC=$(git ls-files --others --exclude-standard 2>/dev/null | grep -cE "$SRC_PATTERN" || true)

TOTAL=$((CHANGED_SRC + STAGED_SRC + UNTRACKED_SRC))

if [ "$TOTAL" -eq 0 ]; then
    exit 0  # No source changes, skip triage
fi

# Check if spec/ was touched (modified, staged, or untracked)
SPEC_CHANGED=$(git diff --name-only 2>/dev/null | grep -c "^spec/" || true)
SPEC_STAGED=$(git diff --cached --name-only 2>/dev/null | grep -c "^spec/" || true)
SPEC_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep -c "^spec/" || true)
SPEC_TOTAL=$((SPEC_CHANGED + SPEC_STAGED + SPEC_UNTRACKED))

cat >&2 << 'EOF'

╔══════════════════════════════════════════════════════════════╗
║  TRIAGE CHECK REQUIRED                                       ║
║                                                              ║
║  Before completing this session, run 3 review agents:        ║
║                                                              ║
║  1. Senior Adversarial QA                                    ║
║     - Are specs complete for all behavior changes?           ║
║     - Do tests exist BEFORE the implementation?              ║
║     - Are edge cases and error paths covered?                ║
║     - Would mutation testing kill all important mutants?      ║
║                                                              ║
║  2. Senior Dev                                               ║
║     - Does code match the spec (not the other way around)?   ║
║     - Was SPEC → TEST → IMPLEMENT → VERIFY followed?        ║
║     - Is the code the simplest solution (KISS/YAGNI)?        ║
║     - Are there security concerns?                           ║
║                                                              ║
║  3. Senior DevOps                                            ║
║     - Is it observable? (metrics, logs, health checks)       ║
║     - Is it resilient? (timeouts, retries, circuit breakers) ║
║     - Can it be deployed safely? (backward compatible)       ║
║     - Are configs externalized, not hardcoded?               ║
║                                                              ║
║  All 3 must reach CONSENSUS before work ships.               ║
╚══════════════════════════════════════════════════════════════╝

EOF

if [ "$SPEC_TOTAL" -eq 0 ]; then
    echo "[triage] WARNING: $TOTAL source files changed but NO specs were modified." >&2
    echo "[triage] This likely violates the SPEC → TEST → IMPLEMENT rule." >&2
fi

exit 0
