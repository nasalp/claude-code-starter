#!/usr/bin/env bash
# Stop hook: detects project structure drift (directory layout or build file changes).
# Compares hashes to a stored snapshot in .claude/project-snapshot.json.
# Reads JSON from stdin, extracts cwd and stop_hook_active via python3.

set -uo pipefail

# Read JSON from stdin
INPUT=$(cat)

# Extract cwd and stop_hook_active
eval "$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    cwd = data.get('cwd', '')
    active = data.get('stop_hook_active', False)
    cwd = cwd.replace(\"'\", \"'\\\\''\" )
    print(f\"CWD='{cwd}'\")
    print(f\"STOP_HOOK_ACTIVE={'true' if active else 'false'}\")
except Exception:
    print(\"CWD=''\")
    print(\"STOP_HOOK_ACTIVE=false\")
" 2>/dev/null)"

# Recursion guard
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    exit 0
fi

if [[ -z "$CWD" ]]; then
    exit 0
fi

cd "$CWD" || exit 0

SNAPSHOT_FILE=".claude/project-snapshot.json"

# --- Portable hash function ---
portable_hash() {
    # Accepts data on stdin, outputs hex hash
    if command -v md5sum &>/dev/null; then
        md5sum | awk '{print $1}'
    elif command -v md5 &>/dev/null; then
        md5 -r | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 | awk '{print $1}'
    else
        # Last resort: use python3
        python3 -c "import hashlib,sys; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())"
    fi
}

# --- Hash directory structure ---
# List directories up to depth 3, excluding common generated/transient dirs
DIR_HASH=$(find . -maxdepth 3 -type d \
    -not -path './.git*' \
    -not -path '*/node_modules*' \
    -not -path '*/target*' \
    -not -path '*/build*' \
    -not -path '*/.gradle*' \
    -not -path '*/dist*' \
    -not -path '*/out*' \
    -not -path '*/__pycache__*' \
    -not -path '*/vendor*' \
    -not -path '*/.next*' \
    -not -path '*/.nuxt*' \
    2>/dev/null | sort | portable_hash)

# --- Hash build file contents ---
BUILD_FILES=(
    "pom.xml"
    "build.gradle"
    "build.gradle.kts"
    "settings.gradle"
    "settings.gradle.kts"
    "package.json"
    "package-lock.json"
    "pyproject.toml"
    "go.mod"
    "go.sum"
    "Cargo.toml"
    "Cargo.lock"
)

BUILD_HASH=""
BUILD_CONTENT=""
for bf in "${BUILD_FILES[@]}"; do
    if [[ -f "$bf" ]]; then
        BUILD_CONTENT+=$(cat "$bf" 2>/dev/null)
        BUILD_CONTENT+=$'\n'
    fi
done

if [[ -n "$BUILD_CONTENT" ]]; then
    BUILD_HASH=$(echo "$BUILD_CONTENT" | portable_hash)
else
    BUILD_HASH="empty"
fi

# --- Combine hashes ---
COMBINED_HASH=$(echo "${DIR_HASH}:${BUILD_HASH}" | portable_hash)

# --- Compare to stored snapshot ---
if [[ ! -f "$SNAPSHOT_FILE" ]]; then
    # No snapshot exists — create it
    mkdir -p "$(dirname "$SNAPSHOT_FILE")"
    python3 -c "
import json, sys
snapshot = {
    'dir_hash': sys.argv[1],
    'build_hash': sys.argv[2],
    'combined_hash': sys.argv[3],
    'created_at': sys.argv[4]
}
print(json.dumps(snapshot, indent=2))
" "$DIR_HASH" "$BUILD_HASH" "$COMBINED_HASH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SNAPSHOT_FILE"
    exit 0
fi

# Read stored snapshot
STORED_COMBINED=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('combined_hash', ''))
except Exception:
    print('')
" "$SNAPSHOT_FILE" 2>/dev/null)

if [[ "$COMBINED_HASH" == "$STORED_COMBINED" ]]; then
    # No drift
    exit 0
fi

# --- Drift detected: determine what changed ---
STORED_DIR_HASH=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('dir_hash', ''))
except Exception:
    print('')
" "$SNAPSHOT_FILE" 2>/dev/null)

STORED_BUILD_HASH=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('build_hash', ''))
except Exception:
    print('')
" "$SNAPSHOT_FILE" 2>/dev/null)

CHANGES=""
if [[ "$DIR_HASH" != "$STORED_DIR_HASH" ]]; then
    CHANGES+="directory structure changed; "
fi
if [[ "$BUILD_HASH" != "$STORED_BUILD_HASH" ]]; then
    CHANGES+="build files changed; "
fi
CHANGES="${CHANGES%; }"

# Update snapshot
python3 -c "
import json, sys
snapshot = {
    'dir_hash': sys.argv[1],
    'build_hash': sys.argv[2],
    'combined_hash': sys.argv[3],
    'updated_at': sys.argv[4]
}
print(json.dumps(snapshot, indent=2))
" "$DIR_HASH" "$BUILD_HASH" "$COMBINED_HASH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SNAPSHOT_FILE"

# Output notification.
# Stop-hook output schema does NOT allow hookSpecificOutput (that field is
# reserved for PreToolUse / UserPromptSubmit / PostToolUse / PostToolBatch).
# Stop hooks emit `systemMessage` for one-shot human-readable notifications,
# or just exit 0 and print to stderr for log-only.
NOTIFICATION="Project structure drift detected: ${CHANGES}. Snapshot updated."
python3 -c "
import json, sys
print(json.dumps({'systemMessage': sys.argv[1]}))
" "$NOTIFICATION"

exit 0
