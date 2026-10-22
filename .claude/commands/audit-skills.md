# Audit Skills Against Anthropic's Official Checklist

Evaluates every skill in ~/.claude/skills/ against the checklist from
"The Complete Guide to Building Skills for Claude" (Anthropic, 2026).

## Checklist categories

Structure (5 items):
  1. Folder in kebab-case
  2. SKILL.md exists with exact spelling
  3. No README.md inside the skill folder
  4. scripts/ references/ assets/ used correctly
  5. SKILL.md under 5000 words

Frontmatter (9 items):
  1. Opening and closing --- delimiters present
  2. name field in kebab-case
  3. name does not contain claude or anthropic
  4. name matches folder name
  5. description field present
  6. description explains WHAT the skill does
  7. description explains WHEN to use it with trigger phrases
  8. description under 1024 characters
  9. No XML angle brackets anywhere in the file

Instructions (6 items):
  1. Clear and actionable — not vague
  2. Critical instructions at the top
  3. At least one concrete example
  4. Error handling documented
  5. References to bundled files are explicit
  6. Progressive disclosure used — detail in references/ not inlined

Triggering (4 items):
  1. Triggers on obvious task phrasings
  2. Triggers on paraphrased requests
  3. Does NOT trigger on unrelated topics
  4. Negative triggers present if scope is narrow

## Inventory

Run:
  ls -la ~/.claude/skills/ 2>/dev/null || echo no skills directory

## Per-skill structural checks

Run:
  for dir in ~/.claude/skills/*/; do
    name=$(basename "$dir")
    echo ""
    echo "=== $name ==="
    echo "$name" | grep -qE '^[a-z][a-z0-9-]+$' && echo "OK kebab-case" || echo "FAIL not kebab-case"
    [ -f "${dir}SKILL.md" ] && echo "OK SKILL.md" || echo "FAIL SKILL.md missing"
    [ -f "${dir}README.md" ] && echo "FAIL README.md present — remove it" || echo "OK no README.md"
    if [ -f "${dir}SKILL.md" ]; then
      head -1 "${dir}SKILL.md" | grep -q '^---' && echo "OK frontmatter open" || echo "FAIL missing opening ---"
      words=$(wc -w < "${dir}SKILL.md" 2>/dev/null || echo 0)
      [ "$words" -gt 5000 ] && echo "FAIL $words words — over 5000 limit" || echo "OK $words words"
      grep -q '[<>]' "${dir}SKILL.md" 2>/dev/null && echo "FAIL XML chars found" || echo "OK no XML"
    fi
  done

## Description quality check

For each skill, read the description field. Evaluate whether it:
- States what the skill does
- States when to use it with trigger phrases users would actually say
- Would not trigger on unrelated topics
- Is under 1024 characters

Run:
  for f in ~/.claude/skills/*/SKILL.md; do
    name=$(basename $(dirname "$f"))
    desc=$(sed -n '/^description:/,/^[a-z]*:/p' "$f" | head -5)
    chars=$(echo "$desc" | wc -c)
    echo "--- $name ($chars chars) ---"
    echo "$desc" | grep -qiE 'use when|trigger|ask|says|invoke' \
      && echo "OK trigger language" || echo "WARNING missing trigger language"
  done

## Per-skill scorecard

For each skill produce:

  SKILL: [name]
  Structure:    [n/5]
  Frontmatter:  [n/9]
  Instructions: [n/6]
  Triggering:   [n/4]
  Total: [n/24]

  Priority fixes:
  1. [most impactful issue]
  2. [second issue]
  3. [third issue]

## Summary table

  SKILLS AUDIT COMPLETE
  Total audited: [n]

  [skill]   [score]   [status]   [top issue if any]

  Most common issues across all skills:
  1. [issue] — affects [n] skills
  2. [issue] — affects [n] skills

  Fix order:
  1. Missing or malformed frontmatter
  2. Missing trigger phrases in descriptions
  3. Missing examples in instructions
  4. Oversized SKILL.md — move detail to references/
