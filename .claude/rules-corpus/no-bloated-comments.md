# No bloated comments — anywhere

## Rule

**Default: write zero comments.** Code, config, YAML, JSON, shell scripts, BATS, CI workflows, Java, TypeScript, Python — all of it.

Comment allowed only when ALL three tests pass:

1. **Specific future reader would otherwise be wrong.** Not "might find useful" — would actively make wrong call.
2. **Wrongness isn't already captured by name, type, function signature, or test name.**
3. **One line is enough.** Two lines → commit-message material, not code-comment material.

Can't satisfy all three → don't write comment.

## What this looks like

**❌ BAD — typical comment-bloat this rule bans:**

```ts
// BlockHound is a Reactor blocking-call detector that attaches a
// ByteBuddy agent at JVM start. Java 21+ requires either the full
// JDK image (jdk.attach module) or `-XX:+EnableDynamicAgentLoading`.
// The Paketo JRE image we use strips jdk.attach, so the install
// throws `No compatible attachment provider is available` and the
// Spring context fails → ECS crash-loop → ALB 502.
BLOCK_DETECT_ENABLED: 'false',
```

**✅ GOOD:**

```ts
BLOCK_DETECT_ENABLED: 'false',
```

(8-line story goes in commit message body. Future reader runs `git blame` on that line.)

---

**❌ BAD — bash script with explanatory preambles before each block:**

```bash
# Resolve the actual Secrets Manager ARN by exact-name match. CDK creates
# secrets like "jwt-hs256-secret-Ab12Cd" (6-char hex suffix). We filter
# `aws secretsmanager list-secrets` by the base name prefix; the operator
# can rotate suffixes during stack replacements without breaking this.
resolve_secret_arn() {
    local base_name="$1"
    # Guard against injection into the JMESPath --query expression.
    # The expression interpolates $base_name into backtick-delimited
    # JMESPath literals; an unexpected character (quote, backtick,
    # bracket) could silently break the filter and return a wrong
    # ARN. Base names in this script are hardcoded to a strict
    # [a-z0-9-]+ shape — enforce that as a defensive check.
    if [[ ! "$base_name" =~ ^[a-z0-9-]+$ ]]; then
        echo "ERROR: secret base name '$base_name' contains unsupported characters" >&2
        exit 2
    fi
    ...
```

**✅ GOOD:**

```bash
resolve_secret_arn() {
    local base_name="$1"
    if [[ ! "$base_name" =~ ^[a-z0-9-]+$ ]]; then
        echo "ERROR: secret base name '$base_name' contains unsupported characters" >&2
        exit 2
    fi
    ...
```

("Guards against JMESPath injection" rationale in commit message of PR that added it.)

---

**❌ BAD — Java field/method with story-comment above:**

```java
/**
 * Build the standard emotion-AI POST body shape. Mirrors python
 * lib/emotion_ai_helpers.py::validate_and_build_request including the
 * languageCode default of "en", optional sentimentAnalysis passthrough,
 * and optional nextStartDate / nextEndDate pair for the Group B endpoints.
 * <p>
 * groupIds is ALWAYS present in the returned map — an empty list when the
 * caller didn't supply one — because the upstream API rejects requests
 * that omit the field. See lib/emotion_ai_helpers.py:217 for the equivalent.
 *
 * @param arguments raw tool arguments
 * @param includeNextDates whether to include nextStartDate / nextEndDate
 * @return the upstream JSON request body
 */
public static Map<String, Object> emotionAiBody(...) { ... }
```

**✅ GOOD:** No Javadoc on internal helpers. Non-obvious invariant (e.g. `groupIds` always present) → `@throws` or test named `emotionAiBody_alwaysSetsGroupIds_evenWhenAbsent`. Test outlives prose.

---

## Specific anti-patterns banned

| Pattern | Why it's banned |
|---|---|
| Multi-line `//` block above any single line of code/config | Buries actual line, dominates diff |
| `/** ... */` Javadoc on private/package-private methods | Caller can't see it; noise |
| Section banner comments inside file (`// === Helpers ===`) | Small file unnecessary; large file → split file |
| Comments explaining what well-named code does | "Validates the request" above `validate(req)` |
| TODO/FIXME comments | Important → ticket; else delete |
| `@author` / `@since` / `@version` Javadoc tags | Git tracks this |
| Justification comments under `git rm`'d code | git history tracks deletions |
| "Note that" / "Important:" / "WARNING:" prefaces | Real constraint → assertion or test, not prose |
| Restating body of `if` in comment above it | Body IS the comment |

## When a comment passes all three tests

Real examples that pass:

```ts
const sleepMs = 250;  // 250ms specifically — anything lower trips Lambda's cold-start throttle
```

```python
raise InvalidArgumentError(...)  # MUST raise here; caller relies on type-narrowing
```

```bash
exec "$@"   # exec not eval — preserve signals for the wrapped process
```

Each **one line**, constraint a name can't capture, future reader would otherwise be wrong.

> Rationale (Cross-references): `docs/rule-rationale/no-bloated-comments.md`
