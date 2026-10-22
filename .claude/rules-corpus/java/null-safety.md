---
paths:
  - "**/*.java"
---

# Null Safety Rules

Non-null by default, by design. NullAway + JSpecify.

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |

---

## CRITICAL: Non-Null by Default

All code is non-null by default. Nullability is the exception, not the rule.

### Setup: JSpecify + NullAway

**Dependencies:**
```xml
<dependency>
    <groupId>org.jspecify</groupId>
    <artifactId>jspecify</artifactId>
    <version>1.0.0</version>
</dependency>
```

**Error Prone plugin flags:**
```
-Xep:NullAway:ERROR
-XepOpt:NullAway:OnlyNullMarked=true
-XepOpt:NullAway:JSpecifyMode=true
-XepOpt:NullAway:ExcludedFieldAnnotations=org.springframework.beans.factory.annotation.Autowired,org.springframework.beans.factory.annotation.Value,jakarta.inject.Inject,jakarta.persistence.Id,jakarta.persistence.GeneratedValue,jakarta.persistence.Column,jakarta.persistence.ManyToOne,jakarta.persistence.OneToMany,jakarta.persistence.OneToOne,jakarta.persistence.ManyToMany,jakarta.persistence.JoinColumn
-XepOpt:NullAway:ExcludedClassAnnotations=jakarta.persistence.Entity,jakarta.persistence.MappedSuperclass,jakarta.persistence.Embeddable
-XepOpt:NullAway:TreatGeneratedAsUnannotated=true
```

**Annotation processor:**
```xml
<annotationProcessorPaths>
    <path>
        <groupId>com.uber.nullaway</groupId>
        <artifactId>nullaway</artifactId>
        <version>${nullaway.version}</version>
    </path>
</annotationProcessorPaths>
```

---

## REQUIRED: @NullMarked on Every Package

Every package MUST have a `package-info.java` with `@NullMarked`:

```java
@NullMarked
package com.example.myfeature;

import org.jspecify.annotations.NullMarked;
```

**Important:** `@NullMarked` does NOT cascade to sub-packages. Each package needs its own.

---

## REQUIRED: Use @Nullable for Exceptions

Everything is non-null by default. Only annotate the exceptions:

```java
import org.jspecify.annotations.Nullable;

// Non-null return (default — no annotation needed)
Application getApplication(ApplicationName name) { ... }

// Explicitly nullable return
@Nullable Application findApplication(ApplicationName name) {
    return repository.findByName(name).orElse(null);
}

// Nullable parameter
void process(@Nullable String optionalNote) {
    if (optionalNote != null) { ... }
}
```

---

## REQUIRED: JPA Entity Handling

JPA entities are excluded from NullAway via `ExcludedClassAnnotations`.

For partial NullAway checking on an entity, use:
```java
@Entity
@SuppressWarnings("NullAway.Init")
class MyEntity { ... }
```

---

## REQUIRED: Spring Injection Handling

Fields with `@Autowired`, `@Value`, `@Inject` are excluded from initialization checks via `ExcludedFieldAnnotations`.

**Prefer constructor injection** — null-safe by default:

```java
// ✅ Good — constructor injection (NullAway checks naturally)
class OrderService {
    private final OrderRepository repository;
    OrderService(OrderRepository repository) {
        this.repository = repository;
    }
}

// ⚠️ Acceptable — field injection (excluded from NullAway init checks)
class OrderService {
    @Autowired
    private OrderRepository repository;
}
```

---

## REQUIRED: @ConfigurationProperties

Use record-based constructor binding (no uninitialized fields):

```java
@ConfigurationProperties(prefix = "broker")
record BrokerProperties(
    String name,
    @Nullable String description,
    int maxRetries
) {}
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `NullAway: @NullMarked is not applied` | Missing `package-info.java` in package | Create `package-info.java` with `@NullMarked` annotation |
| `initializer method does not guarantee @NonNull field X` | Non-null field unset in constructor | Use constructor injection, or add `@SuppressWarnings("NullAway.Init")` for JPA entities |
| `fork=true is required for Error Prone` | Compiler plugin missing `<fork>true</fork>` | Add `<fork>true</fork>` to `maven-compiler-plugin` config |
| `NullAway: returning @Nullable from @NonNull method` | Method returns null without `@Nullable` | Add `@Nullable` to method return type, or return `Optional` |
| `NullAway: passing @Nullable parameter` | Null argument where non-null expected | Add null check before call, or change parameter to `@Nullable` |
| NullAway flags `@Autowired` field | Field annotation not in exclusion list | Verify `ExcludedFieldAnnotations` includes the annotation |

---

## Quick Reference

| Rule | Priority |
|------|----------|
| Non-null by default (JSpecify + NullAway) | CRITICAL |
| `@NullMarked` on every package | REQUIRED |
| `@Nullable` only for exceptions | REQUIRED |
| JPA entities excluded | REQUIRED |
| Constructor injection preferred | REQUIRED |
| Record-based `@ConfigurationProperties` | REQUIRED |

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/java__null-safety.md`
