#!/usr/bin/env bash
#
# verify-spec-tests.sh — Verify that implemented specs have corresponding test classes.
#
# Supports both Maven and Gradle project structures.
# Exit code 0 = all specs verified, 1 = failures found.
#
# Usage:
#   ./scripts/verify-spec-tests.sh [--spec-dir spec/features] [--src-root .]
#
set -euo pipefail

SPEC_DIR="spec/features"
SRC_ROOT="."
ERRORS=0
WARNINGS=0
CHECKED=0
SKIPPED=0

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --spec-dir)  SPEC_DIR="$2"; shift 2 ;;
        --src-root)  SRC_ROOT="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--spec-dir spec/features] [--src-root .]"
            echo ""
            echo "Verifies that every implemented spec has corresponding test classes."
            echo "Supports Maven (src/test/java) and Gradle (src/test/java, src/test/kotlin) layouts."
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Detect project type ---
detect_test_dirs() {
    local root="$1"
    local dirs=()

    # Maven: single module or multi-module
    while IFS= read -r -d '' d; do
        dirs+=("$d")
    done < <(find "$root" -path "*/src/test/java" -type d -print0 2>/dev/null)

    # Gradle Kotlin sources
    while IFS= read -r -d '' d; do
        dirs+=("$d")
    done < <(find "$root" -path "*/src/test/kotlin" -type d -print0 2>/dev/null)

    # Gradle Groovy sources
    while IFS= read -r -d '' d; do
        dirs+=("$d")
    done < <(find "$root" -path "*/src/test/groovy" -type d -print0 2>/dev/null)

    if [[ ${#dirs[@]} -eq 0 ]]; then
        echo "ERROR: No test source directories found under '$root'." >&2
        echo "Expected: src/test/java/, src/test/kotlin/, or src/test/groovy/" >&2
        exit 1
    fi

    printf '%s\n' "${dirs[@]}"
}

# --- Extract frontmatter field from a markdown file ---
# Uses pure bash/awk — no yq dependency.
extract_frontmatter_field() {
    local file="$1"
    local field="$2"
    awk -v field="$field" '
        BEGIN { in_fm=0; in_field=0 }
        /^---$/ { if (!in_fm) { in_fm=1; next } else { exit } }
        in_fm && $0 ~ "^"field":" {
            # Single-value field on same line
            val = $0; sub("^"field":[ ]*", "", val)
            if (val != "" && val !~ /^\[/) { print val; next }
            in_field=1; next
        }
        in_fm && in_field && /^  *- / {
            val = $0; sub("^  *- *", "", val); print val; next
        }
        in_fm && in_field && !/^  *- / && !/^$/ { in_field=0 }
    ' "$file"
}

# --- Check if a test class is @Disabled ---
check_disabled() {
    local filepath="$1"
    if grep -q '@Disabled' "$filepath" 2>/dev/null; then
        # Check if @Disabled is on the class level (not just a method)
        # Simple heuristic: @Disabled appears before "class " keyword
        if awk '/^@Disabled/{found=1} /class /{if(found) exit 0; else exit 1}' "$filepath" 2>/dev/null; then
            return 0  # class-level @Disabled
        fi
    fi
    return 1  # not disabled
}

# --- Resolve a fully-qualified class name to a file path ---
resolve_class() {
    local fqcn="$1"
    shift
    local test_dirs=("$@")
    local relative_path="${fqcn//./\/}"

    for dir in "${test_dirs[@]}"; do
        # Java
        if [[ -f "${dir}/${relative_path}.java" ]]; then
            echo "${dir}/${relative_path}.java"
            return 0
        fi
        # Kotlin
        if [[ -f "${dir}/${relative_path}.kt" ]]; then
            echo "${dir}/${relative_path}.kt"
            return 0
        fi
        # Groovy
        if [[ -f "${dir}/${relative_path}.groovy" ]]; then
            echo "${dir}/${relative_path}.groovy"
            return 0
        fi
    done

    return 1
}

# --- Main ---
echo "=== Spec-Test Verification ==="
echo "Spec directory: $SPEC_DIR"
echo "Source root:    $SRC_ROOT"
echo ""

if [[ ! -d "$SPEC_DIR" ]]; then
    echo "WARNING: Spec directory '$SPEC_DIR' does not exist. Nothing to verify."
    exit 0
fi

# Collect test directories. `mapfile` is bash 4+; macOS GitHub runners
# ship /bin/bash 3.2 by default. Use a portable while-read loop instead.
TEST_DIRS=()
while IFS= read -r line; do
    [[ -n "$line" ]] && TEST_DIRS+=("$line")
done < <(detect_test_dirs "$SRC_ROOT")
echo "Test directories found:"
for d in "${TEST_DIRS[@]}"; do
    echo "  - $d"
done
echo ""

# Find all spec markdown files (skip README, _template, index files)
while IFS= read -r -d '' spec_file; do
    basename="$(basename "$spec_file")"
    [[ "$basename" == "README.md" ]] && continue
    [[ "$basename" == "_template.md" ]] && continue
    [[ "$basename" == "index.md" ]] && continue

    # Extract status
    status="$(extract_frontmatter_field "$spec_file" "status" | head -1)"

    # Skip non-implemented specs
    case "$status" in
        draft|planned|in-progress|"")
            SKIPPED=$((SKIPPED + 1))
            continue
            ;;
        implemented|deprecated)
            ;;
        *)
            echo "WARNING: $spec_file has unknown status '$status'" >&2
            WARNINGS=$((WARNINGS + 1))
            ;;
    esac

    CHECKED=$((CHECKED + 1))

    # Extract test classes (portable; mapfile is bash 4+).
    tests=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && tests+=("$line")
    done < <(extract_frontmatter_field "$spec_file" "tests")

    if [[ ${#tests[@]} -eq 0 ]]; then
        echo "FAIL: $spec_file (status: $status) — no 'tests:' field in frontmatter"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Verify each test class
    for test_class in "${tests[@]}"; do
        [[ -z "$test_class" ]] && continue

        resolved_path=""
        if resolved_path="$(resolve_class "$test_class" "${TEST_DIRS[@]}")"; then
            # Check if @Disabled at class level
            if check_disabled "$resolved_path"; then
                echo "FAIL: $spec_file — test class '$test_class' is @Disabled"
                ERRORS=$((ERRORS + 1))
            else
                echo "  OK: $spec_file — $test_class"
            fi
        else
            echo "FAIL: $spec_file — test class '$test_class' not found in any test directory"
            ERRORS=$((ERRORS + 1))
        fi
    done

done < <(find "$SPEC_DIR" -name "*.md" -type f -print0)

# --- AC-body validation (opt-in: only fires when **AC patterns found) ---
AC_CHECKED=0
AC_ERRORS=0

while IFS= read -r -d '' spec_file; do
    basename="$(basename "$spec_file")"
    [[ "$basename" == "README.md" || "$basename" == "_template.md" || "$basename" == "index.md" ]] && continue

    # Skip non-implemented specs (same logic as above)
    status="$(extract_frontmatter_field "$spec_file" "status" | head -1)"
    case "$status" in
        implemented|deprecated) ;;
        *) continue ;;
    esac

    # Check if spec body contains **AC patterns
    if ! grep -q '\*\*AC[0-9][0-9]*\*\*' "$spec_file" 2>/dev/null; then
        continue  # No AC IDs — skip (backward compatible)
    fi

    AC_CHECKED=$((AC_CHECKED + 1))

    # Extract all AC IDs and check uniqueness (portable; no mapfile).
    ac_ids=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && ac_ids+=("$line")
    done < <(grep -oE '\*\*AC[0-9]+\*\*' "$spec_file" | sort)
    unique_ids=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && unique_ids+=("$line")
    done < <(printf '%s\n' "${ac_ids[@]}" | sort -u)
    if [[ ${#ac_ids[@]} -ne ${#unique_ids[@]} ]]; then
        echo "FAIL: $spec_file — duplicate AC IDs found"
        dupes="$(printf '%s\n' "${ac_ids[@]}" | sort | uniq -d | tr '\n' ' ')"
        echo "      Duplicates: $dupes"
        AC_ERRORS=$((AC_ERRORS + 1))
    fi

    # For each AC, check its Tests: sub-line
    for ac_id in "${unique_ids[@]}"; do
        # Find the line with this AC ID, then look for Tests: on the next indented line
        test_ref="$(awk -v acid="$ac_id" '
            index($0, acid) > 0 { found=1; next }
            found && /^[[:space:]]+- Tests:/ {
                sub(/^[[:space:]]+- Tests:[[:space:]]*/, ""); print; exit
            }
            found && /^[[:space:]]*-[[:space:]]+\*\*AC/ { exit }
            found && /^[^[:space:]]/ { exit }
        ' "$spec_file")"

        if [[ -z "$test_ref" || "$test_ref" == "<"* ]]; then
            # No Tests: line or still a placeholder — warn but don't fail
            continue
        fi

        # Split on # to get class and optional method
        test_class="${test_ref%%#*}"
        test_method="${test_ref#*#}"
        [[ "$test_method" == "$test_ref" ]] && test_method=""

        # Resolve class (reuse existing function)
        if resolved_path="$(resolve_class "$test_class" "${TEST_DIRS[@]}")"; then
            # If method specified, grep for it (best-effort)
            if [[ -n "$test_method" ]]; then
                if ! grep -q "$test_method" "$resolved_path" 2>/dev/null; then
                    echo "WARN: $spec_file $ac_id — method '$test_method' not found in $test_class (best-effort check)"
                    WARNINGS=$((WARNINGS + 1))
                fi
            fi
        else
            echo "FAIL: $spec_file $ac_id — test class '$test_class' not found"
            AC_ERRORS=$((AC_ERRORS + 1))
        fi
    done

done < <(find "$SPEC_DIR" -name "*.md" -type f -print0)

ERRORS=$((ERRORS + AC_ERRORS))

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "Specs checked:  $CHECKED"
echo "Specs skipped:  $SKIPPED (draft/planned/in-progress)"
echo "AC specs:       $AC_CHECKED (with acceptance criteria IDs)"
echo "Warnings:       $WARNINGS"
echo "Errors:         $ERRORS"

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "VERIFICATION FAILED — $ERRORS spec(s) missing or broken test coverage."
    exit 1
else
    echo ""
    echo "VERIFICATION PASSED — all implemented specs have valid test classes."
    exit 0
fi
