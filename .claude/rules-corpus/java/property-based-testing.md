---
paths:
  - "**/*.java"
---

# Property-Based Testing Rules

Use jqwik when behavior must hold for all inputs.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## REQUIRED: jqwik for Property-Based Tests

Use jqwik (not QuickCheck, not junit-quickcheck).

```xml
<dependency>
    <groupId>net.jqwik</groupId>
    <artifactId>jqwik</artifactId>
    <version>${jqwik.version}</version>
    <scope>test</scope>
</dependency>
```

---

## REQUIRED: When to Use Property-Based Tests

Use property-based tests for:

| Use Case | Example |
|----------|---------|
| **Validation invariants** | "All valid names match pattern X" |
| **Roundtrip serialization** | "serialize then deserialize = original" |
| **Domain rules that must hold for all inputs** | "price is always positive" |
| **Inverse operations** | "encode then decode = original" |
| **Idempotency** | "applying twice = applying once" |

Do NOT use for:
- Specific business scenarios (use unit tests)
- Integration behavior (use integration tests)
- UI interactions

---

## REQUIRED: Naming Convention

Property test classes end with `Properties`:

```java
class ApplicationNameProperties { ... }   // ✅
class OrderPriceProperties { ... }        // ✅
class ApplicationNamePropertyTest { ... } // ❌
```

Aligns with Surefire includes: `**/*Properties.java`

---

## REQUIRED: Use @Property Annotation

```java
import net.jqwik.api.ForAll;
import net.jqwik.api.Property;
import net.jqwik.api.constraints.AlphaChars;
import net.jqwik.api.constraints.StringLength;

class ApplicationNameProperties {

    @Property
    void should_accept_all_valid_alphanumeric_names(
            @ForAll @AlphaChars @StringLength(min = 1, max = 128) String name) {
        // given/when/then
        ApplicationName result = ApplicationName.of(name);
        assertThat(result.value()).isEqualTo(name);
    }

    @Property
    void should_reject_all_empty_names(@ForAll @StringLength(max = 0) String name) {
        assertThatThrownBy(() -> ApplicationName.of(name))
            .isInstanceOf(IllegalArgumentException.class);
    }
}
```

---

## RECOMMENDED: Custom Arbitraries

For complex domain objects, create custom generators:

```java
@Provide
Arbitrary<ApplicationName> validApplicationNames() {
    return Arbitraries.strings()
        .alpha()
        .numeric()
        .withChars('-')
        .ofMinLength(1)
        .ofMaxLength(128)
        .filter(s -> !s.startsWith("-") && !s.endsWith("-"))
        .map(ApplicationName::of);
}
```

---

## RECOMMENDED: Roundtrip Serialization

```java
@Property
void should_survive_json_roundtrip(@ForAll("validApplicationNames") ApplicationName name) {
    // given
    String json = objectMapper.writeValueAsString(name);

    // when
    ApplicationName deserialized = objectMapper.readValue(json, ApplicationName.class);

    // then
    assertThat(deserialized).isEqualTo(name);
}
```

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Use jqwik | REQUIRED |
| Use for invariants, roundtrips, domain rules | REQUIRED |
| Classes named `*Properties` | REQUIRED |
| Use `@Property` annotation | REQUIRED |
| Custom arbitraries for complex objects | RECOMMENDED |
| Roundtrip serialization tests | RECOMMENDED |
