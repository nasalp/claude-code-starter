# Command: /test

Run tests with automatic build tool detection.

## Usage

```
/test              # Run all tests
/test <class>      # Run specific test class
/test <pattern>    # Run tests matching pattern
```

## Behavior

1. Detect build tool (Maven or Gradle)
2. Use Maven Daemon if available
3. Run tests in parallel
4. Report results

## Commands

### All Tests

```bash
# Maven (prefer daemon)
mvnd test -T 1C 2>/dev/null || ./mvnw test -T 1C

# Gradle
./gradlew test --parallel
```

### Specific Test

```bash
# Maven
mvnd test -Dtest=OrderServiceTest -T 1C 2>/dev/null || ./mvnw test -Dtest=OrderServiceTest -T 1C

# Gradle
./gradlew test --tests OrderServiceTest --parallel
```

### Pattern Match

```bash
# Maven
./mvnw test -Dtest="*Integration*" -T 1C

# Gradle
./gradlew test --tests "*Integration*" --parallel
```

## Expected Output

```
Tests run: X, Failures: 0, Errors: 0
BUILD SUCCESS
```

## On Failure

1. Show failure details
2. Identify failing test
3. Suggest fix based on error message
