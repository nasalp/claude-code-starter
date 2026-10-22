---
paths:
  - "**/*.php"
  - "**/phpunit.xml"
  - "**/phpunit.xml.dist"
  - "**/composer.json"
---
# PHP Testing

> Extends [common/testing.md](../common/testing.md) with PHP content.

## Framework

Use **PHPUnit** by default. **Pest** acceptable when project already uses it.

## Coverage

```bash
vendor/bin/phpunit --coverage-text
# or
vendor/bin/pest --coverage
```

Prefer **pcov** or **Xdebug** in CI; keep coverage thresholds in CI, not tribal knowledge.

## Test Organization

- Separate fast unit tests from framework/database integration tests.
- Use factory/builders for fixtures instead of large hand-written arrays.
- Keep HTTP/controller tests focused on transport and validation; move business rules into service-level tests.

> Rationale (Reference): `docs/rule-rationale/php__testing.md`
