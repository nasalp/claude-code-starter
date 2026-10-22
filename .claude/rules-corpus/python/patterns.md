---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python Patterns

> Extends [common/patterns.md](../common/patterns.md) w/ Python content.

## Protocol (Duck Typing)

```python
from typing import Protocol

class Repository(Protocol):
    def find_by_id(self, id: str) -> dict | None: ...
    def save(self, entity: dict) -> dict: ...
```

## Dataclasses as DTOs

```python
from dataclasses import dataclass

@dataclass
class CreateUserRequest:
    name: str
    email: str
    age: int | None = None
```

## Context Managers & Generators

- Context managers (`with`) for resource mgmt
- Generators for lazy eval + memory-efficient iteration

## Reference

Skill: `python-patterns` — decorators, concurrency, package org.
