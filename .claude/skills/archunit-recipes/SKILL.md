---
name: archunit-recipes
description: ArchUnit rule library for Spring Boot codebases — package-private defaults, no public entities, hexagonal cross-feature gates, no-reflection, and per-package public-class cap ratchets.
origin: ECC
triggers: ArchUnit, ArchRule, JavaClasses, ClassFileImporter, package-private enforcement, no public entities, no public classes, cross-feature import, public class cap, hexagonal boundary
paths:
  - "**/*.java"
---
# ArchUnit Recipes

## When to use

You want to enforce architectural invariants at build time, not at code
review. ArchUnit reads compiled bytecode and lets you assert structural
rules — "every @Entity is package-private", "feature A may not import
feature B's adapters", "no reflection outside an allowlist" — and fails
the build on any violation.

This skill collects the rules that have actually shipped in production
backends. Each one closes a real, recurring leak (public entities
that drag table boundaries, cross-feature adapter imports that defeat
hexagonal layout, reflection that hides constructor breaks until
runtime, etc.).

## When NOT to use

- The rule is enforceable by the compiler. `final`, `sealed`, package
  visibility — the compiler is faster and more reliable than ArchUnit.
- The rule is a style preference (formatting, import order). Use
  Checkstyle / Spring Java Format. ArchUnit is for structural invariants.
- The rule is genuinely per-PR judgement (e.g. "this class should
  probably be split"). Code review owns that.
- You don't have ArchUnit on the classpath yet. Add the dep first, then
  the rules.

## The pattern

### Setup

```xml
<dependency>
    <groupId>com.tngtech.archunit</groupId>
    <artifactId>archunit-junit5</artifactId>
    <version>1.3.0</version>
    <scope>test</scope>
</dependency>
```

A shared `JavaClasses` instance, scoped to your root package and excluding
test sources:

```java
private static final JavaClasses CLASSES = new ClassFileImporter()
    .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
    .importPackages("com.example.app");
```

### Recipe 1 — Entities are always package-private

`@Entity`, `@MappedSuperclass`, and `@Embeddable` classes MUST never be
`public`. No allowlist. No ratchet.

```java
@Test
void entities_should_be_package_private() {
    ArchRuleDefinition.classes()
        .that().areAnnotatedWith(Entity.class)
            .or().areAnnotatedWith(MappedSuperclass.class)
            .or().areAnnotatedWith(Embeddable.class)
        .should().notBePublic()
        .as("@Entity / @MappedSuperclass / @Embeddable must be "
            + "package-private. Cross-feature access goes through "
            + "a public DTO-only repository in <feature>/api/.")
        .check(CLASSES);
}
```

Why: public entities make it trivial to leak table boundaries across
feature packages, drag JPA proxies / dirty checks / persistence-context
identity into call sites that should not see them, and couple a
consumer feature to a producer's column layout.

### Recipe 2 — No public classes outside the carve-out

Only interfaces, records, enums, exceptions, the `@SpringBootApplication`
main, and structural classes with no behavior may be `public`. Every
behavior-bearing class is package-private; cross-package access is
expressed as `public interface I` + `class IImpl implements I`.

```java
@Test
void no_public_classes_outside_carve_out() {
    classes()
        .that(new DescribedPredicate<JavaClass>("are not in the carve-out") {
            @Override public boolean test(JavaClass c) {
                if (c.isInterface() || c.isEnum() || c.isRecord()) return false;
                if (c.isAssignableTo(Throwable.class)) return false;
                if (c.isAnnotatedWith(SpringBootApplication.class)) return false;
                if (hasOnlyStructuralMembers(c)) return false;  // POJO/constants
                return true;
            }
        })
        .should().notBePublic()
        .as("Public classes are limited to interface, record, enum, "
            + "Throwable, the @SpringBootApplication main, and "
            + "structural-only POJOs. See no-public-classes.md.")
        .check(CLASSES);
}
```

### Recipe 3 — Cross-feature consumers go through `<feature>/api/`

Classes in feature A MUST NOT depend on feature B's `adapters/in/` or
`adapters/out/`. Cross-feature consumers depend on `<feature>/api/`
only. Cross-cutting infrastructure (`shared`, `integrations`,
`config`, `audit`, `jobs`, `security`) is exempt.

```java
@Test
void cross_feature_imports_must_go_through_api_not_adapters() {
    crossFeatureAdapterImportRule().check(CLASSES);
}

private static ArchRule crossFeatureAdapterImportRule() {
    return ArchRuleDefinition.classes()
        .should(new ArchCondition<JavaClass>("not depend on another "
                + "feature's adapters/{in,out}/") {
            @Override
            public void check(JavaClass clazz, ConditionEvents events) {
                String ownPkg = clazz.getPackageName();
                if (!ownPkg.startsWith("com.example.app.")) return;
                String ownFeature = featureNameOf(clazz);
                if (isInfrastructureFeature(ownFeature)) return;
                StringBuilder violations = new StringBuilder();
                for (var dep : clazz.getDirectDependenciesFromSelf()) {
                    String depPkg = dep.getTargetClass().getPackageName();
                    if (!depPkg.startsWith("com.example.app.")) continue;
                    String depFeature = featureFromPackage(depPkg);
                    if (depFeature.equals(ownFeature)) continue;
                    if (isInfrastructureFeature(depFeature)) continue;
                    if (depPkg.contains(".adapters.in")
                            || depPkg.contains(".adapters.out")) {
                        violations.append("\n  ").append(clazz.getName())
                            .append(" -> ").append(dep.getTargetClass().getName())
                            .append(" (").append(depPkg).append(")");
                    }
                }
                if (violations.length() > 0) {
                    events.add(SimpleConditionEvent.violated(clazz,
                        "Cross-feature adapter import:" + violations));
                } else {
                    events.add(SimpleConditionEvent.satisfied(clazz, ""));
                }
            }
            private boolean isInfrastructureFeature(String f) {
                return Set.of("shared", "integrations", "config",
                              "audit", "jobs", "security").contains(f);
            }
        }).allowEmptyShould(true);
}
```

A negative test prevents the positive rule from passing vacuously:

```java
@Test
void cross_feature_rule_negative_test_fails_on_violating_fixture() {
    JavaClasses fixture = new ClassFileImporter().importPackages(
        "com.example.app.archfeaturea",   // importer fixture
        "com.example.app.archfeatureb");  // adapter fixture
    assertThatThrownBy(() ->
            crossFeatureAdapterImportRule().check(fixture))
        .isInstanceOf(AssertionError.class)
        .hasMessageContaining("FeatureAFixtureImporter")
        .hasMessageContaining("CrossFeatureAdapterTargetFixture");
}
```

### Recipe 4 — Module-boundary (one feature must not depend on another)

Pin the unidirectional dependency direction between top-level features:

```java
@Test
void identity_should_not_depend_on_downstream_features() {
    ArchRuleDefinition.noClasses()
        .that().resideInAPackage("com.example.app.identity..")
        .should().dependOnClassesThat().resideInAnyPackage(
            "com.example.app.snapshot..",
            "com.example.app.diagnostic..",
            "com.example.app.publishing..",
            "com.example.app.agentsurface..",
            "com.example.app.whatsapp..")
        .check(CLASSES);
}

@Test
void snapshot_should_not_depend_on_diagnostic() {
    // diagnostic depends on snapshot (allowed); reverse is forbidden.
    ArchRuleDefinition.noClasses()
        .that().resideInAPackage("..snapshot..")
        .should().dependOnClassesThat().resideInAPackage("..diagnostic..")
        .check(CLASSES);
}
```

### Recipe 5 — No reflection in production

```java
@Test
void no_reflection_in_production_code() {
    ArchRuleDefinition.noClasses()
        .that().resideInAPackage("com.example.app..")
        .should().dependOnClassesThat().resideInAnyPackage(
            "java.lang.reflect..")
        .orShould().callMethod(Class.class, "forName", String.class)
        .as("Production code must not use reflection. Call "
            + "constructors and methods directly. See "
            + ".claude/rules/no-reflection-in-production.md.")
        .check(CLASSES);
}
```

Catches `Constructor.newInstance`, `Method.invoke`,
`Field.setAccessible`, `MethodHandles.Lookup.findVirtual`, and
`Class.forName(String)`.

### Recipe 6 — Public-class cap (ratchet during migration)

When you cannot make every class package-private in one PR but you
want to prevent regression:

```java
private static final Map<String, Integer> PUBLIC_CLASS_CAPS = Map.of(
    "admin",            7,
    "audit",            2,
    "auth",             9,
    "customersuccess", 28,
    "dashboard",       22,
    "engineering",     14,
    "finance",         21,
    // ...
);

@Test
void no_new_public_classes_in_feature_packages() {
    var violations = new ArrayList<String>();
    for (var entry : PUBLIC_CLASS_CAPS.entrySet()) {
        String fullPkg = "com.example.dashboard." + entry.getKey();
        long actual = CLASSES.stream()
            .filter(c -> c.getPackageName().startsWith(fullPkg))
            .filter(c -> c.getModifiers().contains(JavaModifier.PUBLIC))
            .count();
        if (actual > entry.getValue()) {
            String offenders = CLASSES.stream()
                .filter(c -> c.getPackageName().startsWith(fullPkg))
                .filter(c -> c.getModifiers().contains(JavaModifier.PUBLIC))
                .map(JavaClass::getSimpleName).sorted()
                .collect(Collectors.joining(", "));
            violations.add(String.format("%s: %d public (cap %d). [%s]",
                entry.getKey(), actual, entry.getValue(), offenders));
        }
    }
    assertThat(violations)
        .as("Feature packages have more public classes than allowed. "
            + "Make new classes package-private, or update "
            + "PUBLIC_CLASS_CAPS if public is justified.")
        .isEmpty();
}
```

This is a one-way ratchet: caps only go down, never up, and updating
them requires PR review.

## Common gotchas / variants

- **`allowEmptyShould(true)` for rules that may not match any class
  yet.** Without it, a rule that finds zero candidates fails — useful
  for forbidding patterns that don't exist *yet*, dangerous when you
  intend "this rule is OK to be vacuous".
- **Negative tests for empty-set rules.** A rule asserting "no class
  does X" passes trivially when no class does X. Add a negative test
  that imports a deliberate-violation fixture from a separate test
  package and asserts the rule fails on it. Recipe 3 shows this.
- **Don't use `@ArchTest` static fields and `JavaClasses` import
  options together unless you understand caching.** `ImportOption.DO_NOT_INCLUDE_TESTS`
  excludes anything under `src/test`; if you import a test fixture for
  a negative test, scope it to a different `ClassFileImporter`.
- **Spring Data and JPA annotations under
  `ExcludedFieldAnnotations`/`ExcludedClassAnnotations` for NullAway**
  do not affect ArchUnit. ArchUnit reads bytecode regardless.
- **`isPackagePrivate()` does not exist as a fluent verb.** Use
  `notBePublic()`. Package-private is the absence of the `public`
  modifier (and also `protected`/`private` are absent on top-level
  classes, so `notBePublic()` is correct).
- **CI parallelism.** ArchUnit tests are pure unit tests. They run on
  every commit and complete in seconds; there is no good reason to
  exclude them from `verify`.

## Verification

Run them via the same `verify` lifecycle phase as the rest of the test
suite; they MUST run in CI.

## Node.js / TypeScript equivalent

ArchUnit doesn't exist for Node; `dependency-cruiser` is the closest analogue.

### `dependency-cruiser` config

```javascript
// .dependency-cruiser.cjs
module.exports = {
  forbidden: [
    {
      name: 'no-cross-feature-adapter-imports',
      severity: 'error',
      from: { path: '^src/(\\w+)/' },
      to:   { path: '^src/(?!\\1)\\w+/adapters/' },
    },
    {
      name: 'no-deep-relative-imports',
      severity: 'error',
      from: {},
      to: { path: '^(\\.\\./){3,}' },
    },
    {
      name: 'no-circular',
      severity: 'error',
      from: {},
      to: { circular: true },
    },
  ],
  options: {
    tsConfig: { fileName: 'tsconfig.json' },
  },
};
```

Run in CI:
```bash
npx dependency-cruiser --config .dependency-cruiser.cjs src/
```

### Public-class ratchet via `ts-morph`

```typescript
// scripts/check-exports.ts
import { Project } from 'ts-morph';

const CAPS: Record<string, number> = {
  'src/auth': 3,
  'src/billing': 5,
};

const project = new Project({ tsConfigFilePath: 'tsconfig.json' });
let violations = 0;

for (const [pkg, cap] of Object.entries(CAPS)) {
  const sources = project.getSourceFiles(`${pkg}/**/*.ts`);
  const exportedSymbols = sources.flatMap((sf) =>
    Array.from(sf.getExportedDeclarations().keys())
  );
  if (exportedSymbols.length > cap) {
    console.error(`[arch-cap] ${pkg}: ${exportedSymbols.length} > cap ${cap}`);
    violations++;
  }
}
process.exit(violations);
```

### Mapping the Java recipes to TS

| Java rule | TS equivalent |
|---|---|
| Entities should be package-private | TypeScript has no package-private; use `index.ts` re-exports as public surface, lint deep imports |
| No cross-feature adapter imports | `dependency-cruiser` `forbidden` rule |
| No reflection in production | ESLint rule banning `Reflect.*` / `eval` / `Function(...)` |
| Public-class cap ratchet | `ts-morph` scan (above) |

### Differences from Java

- No JVM bytecode introspection; tools work on TS AST or import graph.
- Less expressive than ArchUnit, but adequate for boundary/layering/circular rules.
