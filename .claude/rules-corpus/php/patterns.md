---
paths:
  - "**/*.php"
  - "**/composer.json"
---
# PHP Patterns

> Extends [common/patterns.md](../common/patterns.md) with PHP content.

## Thin Controllers, Explicit Services

- Controllers handle transport only: auth, validation, serialization, status codes.
- Business rules in application/domain services testable without HTTP bootstrapping.

## DTOs and Value Objects

- Replace shape-heavy associative arrays with DTOs for requests, commands, external API payloads.
- Value objects for money, identifiers, date ranges, other constrained concepts.

## Dependency Injection

- Depend on interfaces / narrow service contracts, not framework globals.
- Pass collaborators through constructors — testable without service-locator lookups.

## Boundaries

- Isolate ORM models from domain decisions when model layer does more than persistence.
- Wrap third-party SDKs behind small adapters so codebase depends on your contract, not theirs.

> Rationale (Reference): `docs/rule-rationale/php__patterns.md`
