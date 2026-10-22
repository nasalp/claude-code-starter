---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python Security

> Extends [common/security.md](../common/security.md) w/ Python content.

## Secret Management

```python
import os
from dotenv import load_dotenv

load_dotenv()

api_key = os.environ["OPENAI_API_KEY"]  # Raises KeyError if missing
```

## Security Scanning

- **bandit** for static security analysis:
  ```bash
  bandit -r src/
  ```

## Reference

Skill: `django-security` — Django-specific security (if applicable).
