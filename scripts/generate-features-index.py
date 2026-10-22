#!/usr/bin/env python3
"""
generate-features-index.py — regenerate spec/features/README.md from the
live frontmatter of every feature spec under spec/features/.

Auto-generation prevents the index from rotting (the same trap as the
earlier hardcoded skill-count claim in DAY-0.md). Hand-editing the table
is forbidden — any change should land in the per-feature spec frontmatter
and be picked up on the next regeneration.

Conventions (canonical source: .claude/rules/core.md):
- Each spec lives at spec/features/<slug>/<slug>.md.
- Frontmatter declares: feature, status, tests, gaps.
- Status is one of: draft, planned, in-progress, implemented, deprecated.

Usage:
    python3 scripts/generate-features-index.py [--spec-dir spec/features]

Exit codes:
    0 — index regenerated (or unchanged content, no rewrite needed)
    1 — bad arguments / spec dir missing
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def parse_frontmatter(text: str) -> dict[str, object]:
    """Minimal YAML frontmatter parser. Handles:
       - simple `key: value`
       - flow-style sequences `key: [a, b]`
       - block-style sequences (lines like `  - foo`)
    Refusal to depend on PyYAML keeps this script vendoring-free.
    """
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end < 0:
        return {}
    block = text[4:end]
    out: dict[str, object] = {}
    lines = block.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^([A-Za-z_][\w-]*)\s*:\s*(.*)$", line)
        if not m:
            i += 1
            continue
        key, value = m.group(1), m.group(2).rstrip()
        # Inline flow-style sequence
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            out[key] = [s.strip() for s in inner.split(",") if s.strip()] if inner else []
            i += 1
            continue
        # Block scalar marker
        if value in (">", "|", ">-", "|-"):
            collected: list[str] = []
            i += 1
            while i < len(lines) and (lines[i].startswith(("  ", "\t")) or not lines[i].strip()):
                if lines[i].strip():
                    collected.append(lines[i].strip())
                i += 1
            out[key] = " ".join(collected) if value.startswith(">") else "\n".join(collected)
            continue
        # Empty value: maybe a block-style sequence following on indented lines.
        if not value:
            seq: list[str] = []
            i += 1
            while i < len(lines) and lines[i].startswith(("  - ", "\t- ")):
                seq.append(lines[i].strip()[2:].strip())
                i += 1
            out[key] = seq
            continue
        # Strip surrounding quotes
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        out[key] = value
        i += 1
    return out


_GHERKIN_FENCE_RE = re.compile(r"(?ms)^[ \t]*```gherkin[^\n]*\n(.*?)^[ \t]*```[ \t]*$")
_FENCE_BACKTICK_RE = re.compile(r"(?ms)^[ \t]*```.*?^[ \t]*```[ \t]*$")


def _unwrap_gherkin(text: str) -> str:
    """Acceptance criteria live in ```gherkin blocks (one Scenario per AC,
    tagged @AC-<PREFIX>-N). Keep their content so the AC tags count as
    declarations, minus `#` comment lines and scenarios tagged @removed."""
    def keep(m: "re.Match[str]") -> str:
        lines = [ln for ln in m.group(1).split("\n")
                 if not ln.strip().startswith("#") and "@removed" not in ln]
        return "\n".join(lines)
    return _GHERKIN_FENCE_RE.sub(keep, text)
_FENCE_TILDE_RE = re.compile(r"(?ms)^[ \t]*~~~.*?^[ \t]*~~~[ \t]*$")
_INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
_FRONTMATTER_RE = re.compile(r"^---\n.*?\n---\n?", re.DOTALL)


def _strip_frontmatter_and_code(text: str) -> str:
    """Return the spec body with frontmatter, fenced code blocks (both
    ``` and ~~~), and inline-backtick spans removed so ID counters do
    not pick up identifiers that appear in `tests:` arrays, code
    examples, or prose cross-references like `see `AC-X-1``."""
    text = _FRONTMATTER_RE.sub("", text, count=1)
    text = _unwrap_gherkin(text)
    text = _FENCE_BACKTICK_RE.sub("", text)
    text = _FENCE_TILDE_RE.sub("", text)
    text = _INLINE_CODE_RE.sub("", text)
    return text


def count_ac_ids(text: str) -> int:
    body = _strip_frontmatter_and_code(text)
    return len(set(re.findall(r"AC-[A-Z][A-Z0-9_]*-\d+", body)))


def count_user_stories(text: str) -> int:
    body = _strip_frontmatter_and_code(text)
    return len(set(re.findall(r"US-[A-Z][A-Z0-9_]*-\d+", body)))


VALID_STATUSES = {"draft", "planned", "in-progress", "implemented", "deprecated"}


_PREFIX_RE = re.compile(r"AC-([A-Z][A-Z0-9_]*)-\d+")


def _extract_prefixes(text: str) -> set[str]:
    body = _strip_frontmatter_and_code(text)
    return set(_PREFIX_RE.findall(body))


def collect_specs(spec_dir: Path) -> list[dict[str, object]]:
    specs: list[dict[str, object]] = []
    for path in sorted(spec_dir.rglob("*.md")):
        # Skip the README and underscore-prefixed templates / docs.
        if path.name == "README.md" or path.name.startswith("_"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except Exception:
            continue
        fm = parse_frontmatter(text)
        feature = fm.get("feature", path.stem)
        status_raw = str(fm.get("status", "draft")).strip()
        # Strip surrounding quotes if the parser passed them through.
        if (status_raw.startswith("'") and status_raw.endswith("'")) or (
            status_raw.startswith('"') and status_raw.endswith('"')
        ):
            status_raw = status_raw[1:-1]
        status = status_raw.lower() or "draft"
        tests = fm.get("tests") or []
        gaps = fm.get("gaps") or []
        if not isinstance(tests, list):
            tests = [str(tests)]
        if not isinstance(gaps, list):
            gaps = [str(gaps)]
        # Compute path relative to spec_dir.parent (i.e. the repo root or
        # whatever sits above `spec/features`). Fall back to the original
        # representation if it was a relative path that's outside spec_dir's
        # parent. The README lives at spec_dir/README.md, so the link target
        # for navigation should be relative to spec_dir, not its grandparent.
        try:
            rel = path.relative_to(spec_dir)
        except ValueError:
            rel = path
        specs.append(
            {
                "rel_to_index": str(rel),
                "feature": feature,
                "status": status,
                "tests": tests,
                "gaps": gaps,
                "stories": count_user_stories(text),
                "acs": count_ac_ids(text),
                "prefixes": sorted(_extract_prefixes(text)),
            }
        )
    return specs


def detect_prefix_collisions(specs: list[dict[str, object]]) -> dict[str, list[str]]:
    """Return {prefix: [path, path, ...]} for prefixes that appear in more
    than one feature spec FILE. Keying by file path (not the `feature:`
    frontmatter value) catches the case where two distinct spec files
    happen to declare the same `feature:` slug — the collision is real
    even though the dedup-by-name approach would silently merge them."""
    by_prefix: dict[str, list[str]] = {}
    for s in specs:
        path = str(s["rel_to_index"])
        for p in s.get("prefixes") or []:
            by_prefix.setdefault(p, []).append(path)
    return {p: sorted(set(v)) for p, v in by_prefix.items() if len(set(v)) > 1}


def render_index(specs: list[dict[str, object]]) -> str:
    lines: list[str] = []
    lines.append("<!--")
    lines.append("This file is auto-generated by scripts/generate-features-index.py.")
    lines.append("Do not hand-edit. Make changes in the per-feature spec frontmatter and")
    lines.append("re-run the generator (or wait for the post-edit hook to regenerate).")
    lines.append("-->")
    lines.append("")
    lines.append("# Feature Specs")
    lines.append("")
    lines.append(
        "One file per feature at `spec/features/<slug>/<slug>.md`. Each file contains "
        "everything: overview, user stories, acceptance criteria, scope, and verification status."
    )
    lines.append("")
    lines.append("## Features")
    lines.append("")
    if not specs:
        lines.append("_No features yet. Run `/new-feature <slug>` to scaffold one._")
    else:
        lines.append("| Feature | Status | Stories | ACs | Spec |")
        lines.append("|---------|--------|---------|-----|------|")
        for s in specs:
            status = s["status"]
            badge = status if status in VALID_STATUSES else f"{status} (invalid)"
            link = s["rel_to_index"]
            lines.append(
                f"| `{s['feature']}` | {badge} | {s['stories']} | {s['acs']} | "
                f"[{link}]({link}) |"
            )

    collisions = detect_prefix_collisions(specs)
    if collisions:
        lines.append("")
        lines.append("## Prefix collisions (BLOCKER — must be resolved)")
        lines.append("")
        lines.append("Two or more features are using the same `AC-<PREFIX>-N` prefix.")
        lines.append("Pick a different prefix in one of the features and rename its AC IDs.")
        lines.append("")
        for prefix, paths in sorted(collisions.items()):
            lines.append(f"- `{prefix}` used by: {', '.join(f'`{p}`' for p in paths)}")
    lines.append("")
    lines.append("## Adding a feature")
    lines.append("")
    lines.append("1. Run `/new-feature <slug>` (kebab-case) to scaffold the spec from")
    lines.append("   `spec/features/_template.md` at `spec/features/<slug>/<slug>.md`.")
    lines.append("2. Pick a short UPPER-CASE prefix (e.g. `CANCEL`) and use it for every")
    lines.append("   AC ID in the form `AC-<PREFIX>-<N>`. Same for user stories: `US-<PREFIX>-<N>`.")
    lines.append("3. Fill in the spec, then run `/feature` to drive the multi-agent ATDD/TDD loop.")
    lines.append("4. AC→test traceability is verified by `scripts/verify-ac-tests.sh` and the")
    lines.append("   requirements-reviewer agent at commit time.")
    lines.append("")
    lines.append("Canonical conventions live in `.claude/rules/core.md`.")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--spec-dir", default="spec/features")
    args = p.parse_args()

    spec_dir = Path(args.spec_dir)
    if not spec_dir.is_dir():
        print(f"[generate-features-index] spec dir not found: {spec_dir}", file=sys.stderr)
        return 1

    specs = collect_specs(spec_dir)
    rendered = render_index(specs)
    target = spec_dir / "README.md"
    if target.is_file() and target.read_text(encoding="utf-8") == rendered:
        print(f"[generate-features-index] {target} unchanged ({len(specs)} spec(s))")
        return 0
    target.write_text(rendered, encoding="utf-8")
    print(f"[generate-features-index] wrote {target} ({len(specs)} spec(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
