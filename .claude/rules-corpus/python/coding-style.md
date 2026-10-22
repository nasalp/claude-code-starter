---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python Coding Style

> Extends [common/coding-style.md](../common/coding-style.md) with Python content.

## Standards

- Follow **PEP 8** conventions
- **Type annotations** on all function signatures

## Immutability

Prefer immutable data structures:

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class User:
    name: str
    email: str

from typing import NamedTuple

class Point(NamedTuple):
    x: float
    y: float
```

## Formatting

- **black** for code formatting
- **isort** for import sorting
- **ruff** for linting

> Rationale (Reference): `docs/rule-rationale/python__coding-style.md`
