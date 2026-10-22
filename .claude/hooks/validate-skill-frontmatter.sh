#!/usr/bin/env bash
#
# Hook: validate-skill-frontmatter.sh
# Trigger: PreToolUse on Edit|Write
# Purpose: When a SKILL.md is being edited or created, verify the frontmatter
#          has the required fields (name, description, origin, triggers).
#
# WARNINGS ONLY. Always exits 0. Per harness convention.
#
# The agent is responsible for reading and acting on warnings.

set -euo pipefail

INPUT=$(cat)

# Only fire on tool inputs that target a SKILL.md file
FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('file_path', ''))
except Exception:
    pass
" 2>/dev/null)

if [[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" != *SKILL.md ]]; then
    echo "$INPUT"
    exit 0
fi

# If we're CREATING the file (Write), validate the new content; if EDITING,
# we have to be conservative — we only see the new_string for Edit, not the
# resulting full file. Defer to a post-edit check by reading the file if it
# exists, otherwise inspect new_string.
NEW_CONTENT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    inp = data.get('tool_input', {})
    # For Write, content is at tool_input.content
    if 'content' in inp:
        print(inp['content'])
    # For Edit, the new content portion is in new_string — only useful
    # if the new_string contains the whole frontmatter
    elif 'new_string' in inp:
        print(inp['new_string'])
except Exception:
    pass
" 2>/dev/null)

# If the new content includes a YAML frontmatter block, validate it.
# Per Gemini review: shell-only grep/sed parsing misses block scalars
# (`description: >` followed by indented lines). Delegate to python3 which
# handles single-line scalars AND folded/literal block scalars correctly.
if echo "$NEW_CONTENT" | head -1 | grep -q '^---$'; then
    VALIDATION=$(echo "$NEW_CONTENT" | python3 -c '
import re, sys

text = sys.stdin.read()
if not text.startswith("---\n"):
    sys.exit(0)
end = text.find("\n---", 4)
block = text[4:end] if end > 0 else text[4:]

fm = {}
lines = block.split("\n")
i = 0
while i < len(lines):
    line = lines[i]
    m = re.match(r"^([A-Za-z_][\w-]*)\s*:\s*(.*)$", line)
    if not m:
        i += 1
        continue
    key, value = m.group(1), m.group(2).rstrip()
    if value in (">", "|", ">-", "|-"):
        collected = []
        i += 1
        while i < len(lines) and (lines[i].startswith(("  ", "\t")) or not lines[i].strip()):
            if lines[i].strip():
                collected.append(lines[i].strip())
            i += 1
        fm[key] = " ".join(collected) if value.startswith(">") else "\n".join(collected)
        continue
    if (value.startswith("\"") and value.endswith("\"")) or (value.startswith("'\''") and value.endswith("'\''")):
        value = value[1:-1]
    fm[key] = value
    i += 1

warnings = []
for field in ("name", "description", "origin", "triggers"):
    if field not in fm or not fm[field].strip():
        warnings.append(f"missing field: {field}")

origin = fm.get("origin", "").strip()
if origin and origin not in {"ECC", "community", "apple", "Health1"}:
    warnings.append(f"origin not in closed enum: {origin}")

desc = fm.get("description", "")
if len(desc) > 200:
    warnings.append(f"description is {len(desc)} chars (>200)")

if "version" in fm:
    warnings.append("version field is dropped by policy")

for w in warnings:
    print(w)
' 2>/dev/null)

    if [[ -n "$VALIDATION" ]]; then
        echo "[validate-skill-frontmatter] WARNING: SKILL.md frontmatter has issues:" >&2
        while IFS= read -r line; do
            echo "[validate-skill-frontmatter]   - $line" >&2
        done <<< "$VALIDATION"
        echo "[validate-skill-frontmatter] File: $FILE_PATH" >&2
        echo "[validate-skill-frontmatter] Required canonical fields: name, description, origin, triggers" >&2
    fi
fi

# Always exit 0 — warnings only.
echo "$INPUT"
exit 0
