#!/usr/bin/env bash
#
# verify-ac-tests.sh — Verify that every AC ID declared in a feature spec
# has at least one corresponding test annotation in the project's test
# tree, using the per-language convention from .claude/rules/core.md:
#
#   Java       — @Tag("AC-<PREFIX>-N")
#   TypeScript — test.describe('AC-<PREFIX>-N', ...) or describe(...)
#   Python     — @pytest.mark.spec("AC-<PREFIX>-N")
#   Go         — function name includes AC_<PREFIX>_<N>
#
# The check is per-AC, not per-spec. A spec that declares 5 ACs but ships
# tests for only 3 of them is reported as FAIL with the missing AC list.
#
# Usage:
#   ./scripts/verify-ac-tests.sh                           # all specs under spec/features/
#   ./scripts/verify-ac-tests.sh --spec spec/features/order-cancellation/order-cancellation.md
#   ./scripts/verify-ac-tests.sh --spec-dir spec/features --src-root .
#
# Exit codes:
#   0 — every AC in every checked spec has a matching test annotation
#   1 — at least one AC has no matching test annotation
#   2 — bad arguments / no specs found

set -uo pipefail

SPEC_DIR="spec/features"
SRC_ROOT="."
SINGLE_SPEC=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --spec)      SINGLE_SPEC="$2"; shift 2 ;;
        --spec-dir)  SPEC_DIR="$2"; shift 2 ;;
        --src-root)  SRC_ROOT="$2"; shift 2 ;;
        -h|--help)
            sed -n '/^# verify-ac-tests/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

err()  { echo "[verify-ac-tests] ERROR: $*" >&2; }
note() { echo "[verify-ac-tests] $*" >&2; }

# Collect specs to check.
SPECS=()
if [[ -n "$SINGLE_SPEC" ]]; then
    if [[ ! -f "$SINGLE_SPEC" ]]; then
        err "spec not found: $SINGLE_SPEC"
        exit 2
    fi
    SPECS=("$SINGLE_SPEC")
else
    if [[ ! -d "$SPEC_DIR" ]]; then
        err "spec dir not found: $SPEC_DIR"
        exit 2
    fi
    while IFS= read -r f; do
        SPECS+=("$f")
    done < <(find "$SPEC_DIR" -type f -name '*.md' \
                ! -name '_*.md' ! -name 'README.md' 2>/dev/null | sort)
fi

if [[ ${#SPECS[@]} -eq 0 ]]; then
    note "No specs found under $SPEC_DIR."
    exit 0
fi

# Returns the spec's `status:` from its YAML frontmatter, lower-cased,
# with surrounding quotes stripped. Tolerates `Status:` capitalization too.
spec_status() {
    python3 -c "
import sys, re
text = open(sys.argv[1]).read()
if not text.startswith('---\n'):
    print('')
    sys.exit(0)
end = text.find('\n---', 4)
block = text[4:end] if end > 0 else text[4:]
for line in block.splitlines():
    m = re.match(r'^[Ss]tatus:\s*(.+)$', line)
    if m:
        val = m.group(1).strip()
        # Strip surrounding single or double quotes if present.
        if (val.startswith(\"'\") and val.endswith(\"'\")) or \
           (val.startswith('\"') and val.endswith('\"')):
            val = val[1:-1]
        print(val.strip().lower())
        sys.exit(0)
print('')
" "$1"
}

# Returns one AC ID per line. Strips frontmatter, fenced code blocks
# (both \`\`\` and ~~~), and inline-backtick spans before extracting —
# so an AC ID that appears only in a code example, an inline cross-
# reference (\`AC-X-1\`), or a tests: frontmatter entry is NOT treated
# as a declaration.
extract_ac_ids() {
    python3 -c "
import sys, re
text = open(sys.argv[1]).read()
# Strip frontmatter
if text.startswith('---\n'):
    end = text.find('\n---', 4)
    if end > 0:
        text = text[end + 4:]
# Acceptance criteria live in gherkin blocks (one Scenario per AC, tagged
# @AC-<PREFIX>-N): keep their content, minus comment lines and scenarios
# tagged @removed, so the tags count as declarations.
def keep(m):
    return '\n'.join(l for l in m.group(1).split('\n')
                     if not l.strip().startswith('#') and '@removed' not in l)
text = re.sub(r'(?ms)^[ \t]*\`\`\`gherkin[^\n]*\n(.*?)^[ \t]*\`\`\`[ \t]*$', keep, text)
# Strip all other fenced code blocks (any indentation, any fence info string).
text = re.sub(r'(?ms)^[ \t]*\`\`\`.*?^[ \t]*\`\`\`[ \t]*$', '', text)
text = re.sub(r'(?ms)^[ \t]*~~~.*?^[ \t]*~~~[ \t]*$', '', text)
# Strip inline-backtick spans so prose cross-references don't get
# mistaken for declarations.
text = re.sub(r'\`[^\`\n]*\`', '', text)
ids = sorted(set(re.findall(r'AC-[A-Z][A-Z0-9_]*-\d+', text)))
print('\n'.join(ids))
" "$1"
}

# Returns 0 if at least one test annotation references the AC ID.
# Searches the whole $SRC_ROOT so Go's `internal/`, Python's flat `tests/`,
# Maven's `src/test/java/`, and TypeScript's `__tests__/` layouts are all
# covered without enumerating every project structure.
ac_has_test() {
    local ac="$1"

    # Build a single regex for ERE that matches any of the language conventions.
    # AC ID is a literal here.
    local ac_underscored
    ac_underscored=$(echo "$ac" | tr '-' '_')   # Java/Python/TS use the dash form;
                                                 # Go uses underscore form.
    # Notes on alternatives:
    #
    # Java @Tag has TWO forms — JUnit 5 supports both shorthand
    # `@Tag("AC-X-1")` and the fluent `@Tag(value = "AC-X-1")`.
    # The pattern accepts an optional `value\s*=\s*` between `(` and `"`.
    #
    # Go AC IDs are embedded in test function names with underscore
    # separators (e.g. TestCancel_AC_CANCEL_1). `\b` is a no-op between two
    # word characters, so we use `[^A-Za-z0-9]` (which treats `_` as a
    # separator while still rejecting letter/digit neighbours — that
    # distinguishes AC_CANCEL_1 from AC_CANCEL_10).
    local pattern="@Tag\\(\\s*(value\\s*=\\s*)?\"$ac\"\\s*\\)|test\\.describe\\(['\"]$ac['\"]|describe\\(['\"]$ac['\"]|@pytest\\.mark\\.spec\\(['\"]$ac['\"]\\)|(^|[^A-Za-z0-9])${ac_underscored}([^A-Za-z0-9]|$)"

    grep -rEq \
        --include='*.java' --include='*.kt' --include='*.scala' --include='*.groovy' \
        --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
        --include='*.mjs' --include='*.cjs' \
        --include='*.py' --include='*.go' --include='*.rs' \
        --exclude-dir='target' --exclude-dir='build' --exclude-dir='node_modules' \
        --exclude-dir='__pycache__' --exclude-dir='dist' --exclude-dir='out' \
        --exclude-dir='.git' --exclude-dir='vendor' --exclude-dir='_deprecated' \
        "$pattern" "$SRC_ROOT" 2>/dev/null
}

TOTAL_SPECS=0
TOTAL_ACS=0
TOTAL_MISSING=0
FAIL=0

for spec in "${SPECS[@]}"; do
    status=$(spec_status "$spec")
    # Exempt draft / planned specs from per-AC check (per core.md).
    if [[ "$status" == "draft" ]] || [[ "$status" == "planned" ]]; then
        continue
    fi

    ac_ids=$(extract_ac_ids "$spec")
    if [[ -z "$ac_ids" ]]; then
        note "skipping (no AC IDs found): $spec"
        continue
    fi

    TOTAL_SPECS=$((TOTAL_SPECS + 1))
    missing_for_spec=()
    while IFS= read -r ac; do
        [[ -z "$ac" ]] && continue
        TOTAL_ACS=$((TOTAL_ACS + 1))
        if ! ac_has_test "$ac"; then
            missing_for_spec+=("$ac")
            TOTAL_MISSING=$((TOTAL_MISSING + 1))
        fi
    done <<< "$ac_ids"

    if [[ ${#missing_for_spec[@]} -gt 0 ]]; then
        FAIL=1
        echo "FAIL: $spec"
        for ac in "${missing_for_spec[@]}"; do
            echo "  no test annotation for $ac"
        done
    fi
done

echo "[verify-ac-tests] checked $TOTAL_SPECS spec(s), $TOTAL_ACS AC ID(s), $TOTAL_MISSING missing test annotation(s)."
exit $FAIL
