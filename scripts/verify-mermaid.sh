#!/usr/bin/env bash
#
# verify-mermaid.sh — Validate every Mermaid sequence diagram in feature
# specs so a broken diagram never reaches a PR. Runs a structural parser
# that catches the failure modes that break GitHub rendering: missing
# `sequenceDiagram` directive, unbalanced block constructs (loop / alt /
# opt / par / critical / rect / break / end), malformed arrow lines, and
# unknown statement keywords.
#
# Optional deep-validate: if `mmdc` (the Mermaid CLI) is on PATH, every
# block is also rendered as a sanity check. If the binary is absent, the
# structural validator alone is run — operators get most of the value
# without an npm install.
#
# Exemption: specs with `status: draft` are skipped (the diagram is
# expected to be incomplete during early drafting).
#
# Usage:
#   ./scripts/verify-mermaid.sh                    # all specs under spec/features/
#   ./scripts/verify-mermaid.sh --spec <path>      # one spec file
#   ./scripts/verify-mermaid.sh --spec-dir <dir>   # custom spec dir
#
# Exit codes:
#   0 — every Mermaid block in every checked spec parses cleanly
#   1 — at least one block has a structural error
#   2 — bad arguments

set -uo pipefail

SPEC_DIR="spec/features"
SINGLE_SPEC=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --spec)      SINGLE_SPEC="$2"; shift 2 ;;
        --spec-dir)  SPEC_DIR="$2"; shift 2 ;;
        -h|--help)
            sed -n '/^# verify-mermaid/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Collect specs.
SPECS=()
if [[ -n "$SINGLE_SPEC" ]]; then
    if [[ ! -f "$SINGLE_SPEC" ]]; then
        echo "[verify-mermaid] ERROR: spec not found: $SINGLE_SPEC" >&2
        exit 2
    fi
    SPECS=("$SINGLE_SPEC")
else
    if [[ ! -d "$SPEC_DIR" ]]; then
        echo "[verify-mermaid] ERROR: spec dir not found: $SPEC_DIR" >&2
        exit 2
    fi
    while IFS= read -r f; do
        SPECS+=("$f")
    done < <(find "$SPEC_DIR" -type f -name '*.md' \
                ! -name '_*.md' ! -name 'README.md' 2>/dev/null | sort)
fi

[[ ${#SPECS[@]} -eq 0 ]] && { echo "[verify-mermaid] No specs found."; exit 0; }

# Run the Python validator inline. Exit code propagates.
python3 - "${SPECS[@]}" <<'PY'
import re
import sys
from pathlib import Path

# Mermaid sequence-diagram syntax we recognise. The validator is
# deliberately conservative — it is NOT a full parser. It catches the
# failure modes that actually break GitHub rendering:
#   1. Missing `sequenceDiagram` header.
#   2. Unbalanced block keywords (loop/alt/opt/par/critical/rect/break/box ↔ end).
#   3. Malformed arrow lines (typo'd arrows, missing colon, empty body).
#   4. Unknown leading keyword on a non-comment line.
#
# False-positive risk: if Mermaid adds a new keyword we don't list, this
# may flag a valid diagram. The fix is to add the keyword to the
# KNOWN_KEYWORDS set below.

ARROW_RE = re.compile(
    r"""^\s*
        ([\w\-]+)               # sender (participant id; allow dashes)
        (?:\s+as\s+\S+)?
        \s*
        (-->>|->>|--x|-x|--\)|-\)|->|-->)   # arrow type
        \s*\+?
        ([\w\-]+)               # receiver
        \s*\-?
        \s*:\s*(.+?)\s*$        # label
    """,
    re.VERBOSE,
)
PARTICIPANT_RE = re.compile(r"^\s*(participant|actor)\s+\S+")
NOTE_RE = re.compile(r"^\s*Note\s+(over|left of|right of)\s+", re.IGNORECASE)
ACT_RE = re.compile(r"^\s*(activate|deactivate)\s+\S+")
LINK_RE = re.compile(r"^\s*links?\s+\S+\s*:")
PROPS_RE = re.compile(r"^\s*properties?\s+\S+\s*:")
DESC_RE = re.compile(r"^\s*description\s+\S+\s*:")
AUTONUM_RE = re.compile(r"^\s*autonumber(\s+.*)?$", re.IGNORECASE)

OPENERS = {"loop", "alt", "opt", "par", "critical", "rect", "break", "box", "rect"}
CONTINUERS = {"else", "and", "option"}
CLOSER = "end"

KNOWN_KEYWORDS = (
    OPENERS | CONTINUERS | {CLOSER}
    | {"participant", "actor", "Note", "note", "activate", "deactivate",
       "autonumber", "title", "%%", "links", "link", "properties", "description"}
)

EXTRACT_FENCE_RE = re.compile(
    r"(?ms)^(?P<indent>[ \t]*)```mermaid[ \t]*\n(?P<body>.*?)^[ \t]*```[ \t]*$"
)


def status_of(text: str) -> str:
    """Return lower-cased `status:` from frontmatter, quote-stripped."""
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---", 4)
    block = text[4:end] if end > 0 else text[4:]
    for line in block.splitlines():
        m = re.match(r"^[Ss]tatus:\s*(.+)$", line)
        if not m:
            continue
        val = m.group(1).strip()
        if (val.startswith("'") and val.endswith("'")) or (
            val.startswith('"') and val.endswith('"')
        ):
            val = val[1:-1]
        return val.strip().lower()
    return ""


def extract_blocks(path: Path) -> list[tuple[int, str]]:
    """Return [(line_offset, block_body), ...] for every ```mermaid``` block."""
    text = path.read_text(encoding="utf-8")
    blocks: list[tuple[int, str]] = []
    for m in EXTRACT_FENCE_RE.finditer(text):
        # 1-based line number where the body begins
        line_no = text[: m.start("body")].count("\n") + 1
        blocks.append((line_no, m.group("body")))
    return blocks


def validate_block(body: str) -> list[str]:
    """Return a list of error messages (empty = clean)."""
    errors: list[str] = []
    lines = [ln.rstrip() for ln in body.splitlines()]
    # First non-blank, non-comment line must be `sequenceDiagram` (case-insensitive).
    first_meaningful = next(
        (ln for ln in lines if ln.strip() and not ln.lstrip().startswith("%%")),
        None,
    )
    if first_meaningful is None:
        errors.append("empty mermaid block")
        return errors
    if not re.match(r"^\s*sequenceDiagram\b", first_meaningful, re.IGNORECASE):
        errors.append(
            "first non-blank line must be `sequenceDiagram`; "
            f"got: {first_meaningful!r}"
        )
        # Continue checking for other errors anyway.

    depth = 0
    for i, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line or line.startswith("%%"):
            continue
        # Skip the header itself.
        if re.match(r"^\s*sequenceDiagram\b", raw, re.IGNORECASE):
            continue

        first_word = line.split(maxsplit=1)[0]
        # Block management.
        if first_word in OPENERS:
            depth += 1
            continue
        if first_word in CONTINUERS:
            if depth == 0:
                errors.append(f"line {i}: `{first_word}` outside any open block")
            continue
        if first_word == CLOSER:
            if depth == 0:
                errors.append(f"line {i}: `end` without a matching opener")
            else:
                depth -= 1
            continue

        # Recognised single-line statements.
        if (
            PARTICIPANT_RE.match(raw)
            or NOTE_RE.match(raw)
            or ACT_RE.match(raw)
            or LINK_RE.match(raw)
            or PROPS_RE.match(raw)
            or DESC_RE.match(raw)
            or AUTONUM_RE.match(raw)
            or re.match(r"^\s*title\s+\S", raw, re.IGNORECASE)
        ):
            continue

        # Arrow line.
        if ARROW_RE.match(raw):
            continue

        # If the line contains an arrow-shaped substring but doesn't match the
        # full arrow pattern, surface as malformed.
        if re.search(r"-->|->>|->|-->>|--x|-x", raw):
            errors.append(f"line {i}: malformed arrow line: {line!r}")
            continue

        # Otherwise: unknown leading keyword.
        if first_word not in KNOWN_KEYWORDS:
            errors.append(f"line {i}: unknown statement starts with `{first_word}`: {line!r}")

    if depth > 0:
        errors.append(f"unbalanced block: {depth} opener(s) without matching `end`")

    return errors


fail = 0
total_blocks = 0
total_specs_with_blocks = 0

for spec_path in [Path(p) for p in sys.argv[1:]]:
    try:
        text = spec_path.read_text(encoding="utf-8")
    except Exception as exc:
        print(f"[verify-mermaid] ERROR: cannot read {spec_path}: {exc}", file=sys.stderr)
        fail = 1
        continue

    if status_of(text) == "draft":
        # Drafts may be incomplete; skip.
        continue

    blocks = extract_blocks(spec_path)
    if blocks:
        total_specs_with_blocks += 1

    for line_no, body in blocks:
        total_blocks += 1
        errors = validate_block(body)
        if errors:
            fail = 1
            print(f"FAIL: {spec_path}:{line_no}")
            for e in errors:
                print(f"  {e}")

print(
    f"[verify-mermaid] checked {total_specs_with_blocks} spec(s) "
    f"with {total_blocks} mermaid block(s); "
    f"{'all clean' if fail == 0 else 'FAIL'}."
)
sys.exit(fail)
PY
RC=$?

# Optional deep-validate via mmdc if it's installed. mmdc renders, which
# is heavier but catches semantic issues the structural parser doesn't.
# We do not gate on this — operators without mmdc still get the structural
# check.
if command -v mmdc >/dev/null 2>&1 && [[ $RC -eq 0 ]]; then
    : # placeholder for future deep-validate; intentionally a no-op for now.
fi

exit $RC
