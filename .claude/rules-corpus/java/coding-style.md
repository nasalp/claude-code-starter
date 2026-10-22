---
paths:
  - "**/*.java"
---
# Java Coding Style

> Extends [common/coding-style.md](../common/coding-style.md). Java-specific.

## Formatting

- **google-java-format** or **Checkstyle** (Google or Sun style) for enforcement
- One public top-level type per file
- Consistent indent: 2 or 4 spaces (match project standard)
- Member order: constants, fields, constructors, public methods, protected, private

## Class Size

- Java production classes over 400 lines require explicit human approval before merge
- Split large classes into package-private collaborators before senior review
- One responsibility per class so tests stay small
- If a class must stay over 400 lines: link the human approval, document why, prove one responsibility, add a follow-up split plan

## Immutability

- Prefer `record` for value types (Java 16+)
- Mark fields `final` by default — mutable state only when required
- Return defensive copies from public APIs: `List.copyOf()`, `Map.copyOf()`, `Set.copyOf()`
- Copy-on-write: return new instances rather than mutating existing ones

```java
// GOOD — immutable value type
public record OrderSummary(Long id, String customerName, BigDecimal total) {}

// GOOD — final fields, no setters
public class Order {
    private final Long id;
    private final List<LineItem> items;

    public List<LineItem> getItems() {
        return List.copyOf(items);
    }
}
```

## Naming

Standard Java conventions:
- `PascalCase` for classes, interfaces, records, enums
- `camelCase` for methods, fields, parameters, local variables
- `SCREAMING_SNAKE_CASE` for `static final` constants
- Packages: all lowercase, reverse domain (`com.example.app.service`)

## Modern Java Features

Use modern features where they improve clarity:
- **Records** for DTOs and value types (Java 16+)
- **Sealed classes** for closed type hierarchies (Java 17+)
- **Pattern matching** with `instanceof` — no explicit cast (Java 16+)
- **Text blocks** for multi-line strings — SQL, JSON templates (Java 15+)
- **Switch expressions** with arrow syntax (Java 14+)
- **Pattern matching in switch** — exhaustive sealed type handling (Java 21+; team baseline is Java 25)

```java
// Pattern matching instanceof
if (shape instanceof Circle c) {
    return Math.PI * c.radius() * c.radius();
}

// Sealed type hierarchy
public sealed interface PaymentMethod permits CreditCard, BankTransfer, Wallet {}

// Switch expression
String label = switch (status) {
    case ACTIVE -> "Active";
    case SUSPENDED -> "Suspended";
    case CLOSED -> "Closed";
};
```

## Optional Usage

- Return `Optional<T>` from finder methods that may have no result
- Use `map()`, `flatMap()`, `orElseThrow()` — never call `get()` without `isPresent()`
- Never use `Optional` as a field type or method parameter

```java
// GOOD
return repository.findById(id)
    .map(ResponseDto::from)
    .orElseThrow(() -> new OrderNotFoundException(id));

// BAD — Optional as parameter
public void process(Optional<String> name) {}
```

## Error Handling

- Prefer unchecked exceptions for domain errors
- Create domain-specific exceptions extending `RuntimeException`
- Avoid broad `catch (Exception e)` unless at top-level handlers
- Include context in exception messages

```java
public class OrderNotFoundException extends RuntimeException {
    public OrderNotFoundException(Long id) {
        super("Order not found: id=" + id);
    }
}
```

## Streams

- Use streams for transformations; keep pipelines short (3-4 operations max)
- Prefer method references when readable: `.map(Order::getTotal)`
- Avoid side effects in stream operations
- For complex logic, prefer a loop over a convoluted stream pipeline

## Imports

- Always use imports; never fully-qualified type names in code
- Remove unused imports on save (IDE) or via `./mvnw impsort:sort` /
  `./gradlew spotlessApply`
- One public top-level type per file (repeated from Formatting because
  it interacts with imports — wildcard imports across multiple
  packages compound the violation)

## Dead code

Delete unused code; never comment it out. Git history preserves it.

```java
// BAD — commented code, unused method, unused variable
// private void oldMethod() { ... }
private void neverCalled() { }
var unused = calculateSomething();
```

## Method size and shape

Methods do one thing — roughly 10–15 lines, judgment not a hard rule.
Signs too long: multiple levels of abstraction, multiple responsibilities,
hard to name, needs comments to explain sections. Split into named helpers.

Minimise blank lines inside a method body. A single blank line between logical
sections is acceptable when the method genuinely cannot be split further.
Repeated blank lines signal the method should be two methods.

## Meaningful names

Names carry intent — favour clarity over brevity.

```java
// BAD
int d;
void proc(Order o) { }
List<User> list1;

// GOOD
int elapsedDays;
void processOrder(Order order) { }
List<User> activeUsers;
```

Class names containing `Manager`, `Handler`, `Processor`, `Helper`
are an anti-signal: the class probably has multiple responsibilities
and needs splitting.

## Fail fast

Validate inputs at the top of the method, before any work. Invalid input
throwing 30 lines into the body is a debugging cost paid by every future reader.

```java
// GOOD
void process(Request request) {
    if (request.isInvalid()) throw new IllegalArgumentException(...);
    // ... proceed with valid data ...
}
```

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/java__coding-style.md`
