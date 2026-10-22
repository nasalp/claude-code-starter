---
paths:
  - "**/*.php"
  - "**/composer.json"
---
# PHP Coding Style

> Extends [common/coding-style.md](../common/coding-style.md) with PHP content.

## Standards

- **PSR-12** formatting and naming.
- Prefer `declare(strict_types=1);` in application code.
- Scalar type hints, return types, typed properties everywhere new code permits.

## Immutability

- Prefer immutable DTOs and value objects for data crossing service boundaries.
- `readonly` properties or immutable constructors for request/response payloads where possible.
- Arrays for simple maps; promote business-critical structures into explicit classes.

## Formatting

- **PHP-CS-Fixer** or **Laravel Pint** for formatting.
- **PHPStan** or **Psalm** for static analysis.
- Keep Composer scripts checked in so same commands run locally and in CI.

## Error Handling

- Throw exceptions for exceptional states; avoid returning `false`/`null` as hidden error channels in new code.
- Convert framework/request input into validated DTOs before domain logic.

> Rationale (Reference): `docs/rule-rationale/php__coding-style.md`
