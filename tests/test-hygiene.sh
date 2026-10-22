#!/usr/bin/env bash
# Repo hygiene: line endings, executable bits, and syntax of every script.
# These catch the two problems that silently disable hooks on macOS/Linux:
# CRLF line endings and missing executable bits.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

crlf=$(grep -rlI $'\r' --exclude-dir=.git --exclude-dir=node_modules . 2>/dev/null || true)
assert_eq "" "$crlf" "no text file has CRLF line endings"

not_exec=$(find . -name '*.sh' -not -path './.git/*' ! -perm -u+x)
assert_eq "" "$not_exec" "every .sh file is executable"

bad_sh=""
while IFS= read -r -d '' f; do
    bash -n "$f" 2>/dev/null || bad_sh+="$f "
done < <(find . -name '*.sh' -not -path './.git/*' -print0)
assert_eq "" "$bad_sh" "every .sh file passes bash -n"

bad_js=""
while IFS= read -r -d '' f; do
    node --check "$f" 2>/dev/null || bad_js+="$f "
done < <(find .claude/scripts -name '*.js' -print0)
assert_eq "" "$bad_js" "every hook/library .js file passes node --check"

bad_py=$(find . -name '*.py' -not -path './.git/*' -print0 | xargs -0 python3 -I -c '
import ast, sys
bad = []
for f in sys.argv[1:]:
    try:
        ast.parse(open(f, encoding="utf-8").read(), f)
    except SyntaxError:
        bad.append(f)
print(" ".join(bad))
' 2>/dev/null)
assert_eq "" "$bad_py" "every .py file parses"

rendered=$(sed -e "s|{{SCRIPTS}}|/x/scripts/hooks|g" -e "s|{{HOOKS}}|/x/hooks|g" -e "s|{{SKILLS}}|/x/skills|g" .claude/settings.json.template)
if echo "$rendered" | jq empty 2>/dev/null; then
    pass "settings.json.template renders to valid JSON"
else
    fail "settings.json.template renders to valid JSON"
fi

missing=""
for p in $(grep -oE '\{\{(HOOKS|SCRIPTS)\}\}/[A-Za-z0-9._-]+' .claude/settings.json.template | sort -u); do
    f=${p/\{\{HOOKS\}\}/.claude/hooks}
    f=${f/\{\{SCRIPTS\}\}/.claude/scripts/hooks}
    [[ -f "$f" ]] || missing+="$f "
done
assert_eq "" "$missing" "every hook referenced by the settings template exists"

finish
