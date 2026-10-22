---
paths:
  - "**/*.java"
  - "**/pom.xml"
  - "**/build.gradle"
  - "**/build.gradle.kts"
---
# Java Hooks

> Extends [common/hooks.md](../common/hooks.md). Java-specific.

## PostToolUse Hooks

Configure in `~/.claude/settings.json`:

- **google-java-format**: auto-format `.java` after edit
- **checkstyle**: style checks after Java edit
- **./mvnw compile** or **./gradlew compileJava**: verify compilation after changes
