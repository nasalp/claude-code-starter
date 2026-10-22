# Shell-script workflow

Every new/modified `.sh` in this repo:

1. **Bats test first.** Failing test before script change. Test = contract.
2. **`shellcheck -x -P SCRIPTDIR` MUST pass** (CI gate `pr-diff.yml`). No warnings; exceptions need directive comment naming SC code + why.
3. **Extract logic into named functions.** One responsibility each. Single-line comment above: what it does + returns. No paragraph docstrings — long context in commit message.
4. **Test each function independently** (bats sources script, calls functions) **and** whole-script behaviour (end-to-end, stubbed deps).
5. **`set -euo pipefail`** unless documented reason (orchestrators aggregating per-step failures: `set -uo pipefail` + explicit exit-code checks).
6. **Quote every variable expansion.** `[[ ]]` over `[ ]`. Arrays for multi-value args.
7. **No bloated in-script comments.** Terse one-liners only. "Why" → commit body.

Function-extraction example:

```bash
# Print the OS name in lowercase (linux | darwin).
_os() { uname -s | tr '[:upper:]' '[:lower:]'; }

# Verify that <file> matches the expected SHA-256. Exits 1 on mismatch.
_verify_sha256() {
  local file="$1" expected="$2"
  ...
}
```

Bats test pattern for an extracted function:

```bash
@test "_verify_sha256 returns 0 on a matching hash" {
  printf 'payload' > "$TMP/f"
  expected="$(shasum -a 256 "$TMP/f" | awk '{print $1}')"
  run bash -c "source '$(deps_lib)'; _verify_sha256 '$TMP/f' '$expected'"
  [ "$status" -eq 0 ]
}
```
