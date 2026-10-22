#!/bin/bash
set -e

echo "Setting up AI agent system..."

# Create spec structure
mkdir -p spec/{features,contracts,acceptance}

# Create spec README
cat > spec/README.md << 'EOF'
# Specifications

This directory contains all feature specifications for the project.

## Structure

- `features/` — Feature specifications
- `contracts/` — API contracts (OpenAPI, AsyncAPI)
- `acceptance/` — Acceptance criteria and scenarios

## Quick Links

- [Feature Index](features/README.md)

## Rules

1. **Spec before code** — Every feature needs a spec before implementation
2. **Keep specs updated** — Specs are the source of truth
3. **Index all features** — Every feature must be in the index
EOF

# Create feature index
cat > spec/features/README.md << 'EOF'
# Feature Index

## Overview

All features in this system, with their implementation status.

## Features

| Feature | Spec | Backend | Frontend | Status |
|---------|------|---------|----------|--------|
| *No features yet* | | | | |

## Status Legend

- ✅ Complete
- ⚠️ In Progress
- ❌ Not Started
- 🚫 Deprecated

## Adding a Feature

1. Create directory: `spec/features/<feature-name>/`
2. Create spec from template: `cp _template.md <feature-name>/<feature>.md`
3. Fill in the spec completely
4. Add entry to this index
5. Write tests, then implementation
6. Update status as you progress
EOF

# Create feature template
cat > spec/features/_template.md << 'EOF'
# Feature: <Feature Name>

## Overview

Brief description of what this feature does and why it exists.

## User Stories

- As a <role>, I want <goal>, so that <benefit>

## Behavior

### Happy Path

1. Given <precondition>
2. When <action>
3. Then <expected outcome>

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| <edge case> | <what happens> |

### Error Cases

| Error Condition | Response |
|-----------------|----------|
| <condition> | <error response> |

## API

### Endpoint

```
POST /api/v1/<resource>
```

### Request

```json
{
  "field": "value"
}
```

### Response

```json
{
  "id": "uuid",
  "field": "value"
}
```

### Error Codes

| Code | Meaning |
|------|---------|
| 400 | Invalid request |
| 404 | Resource not found |
| 409 | Conflict |

## Dependencies

- **Requires:** <upstream dependencies>
- **Used by:** <downstream consumers>

## Status

- [ ] Spec complete
- [ ] Acceptance tests
- [ ] Backend implemented
- [ ] Unit tests
- [ ] Contract tests
- [ ] Frontend implemented
- [ ] Documentation updated
EOF

# Create OpenAPI template
cat > spec/contracts/openapi.yaml << 'EOF'
openapi: 3.0.3
info:
  title: Project API
  version: 1.0.0
  description: |
    API specification for the project.

    ## Versioning
    All endpoints are versioned with URL path: `/api/v1/`

    ## Authentication
    All endpoints require Bearer token authentication.

servers:
  - url: /api/v1
    description: API v1

paths: {}

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

  schemas:
    Error:
      type: object
      required:
        - code
        - message
      properties:
        code:
          type: string
          description: Machine-readable error code
        message:
          type: string
          description: Human-readable error message
        traceId:
          type: string
          description: Correlation ID for debugging
        timestamp:
          type: string
          format: date-time
        details:
          type: object
          additionalProperties:
            type: string
          description: Field-level error details

security:
  - bearerAuth: []
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "Structure created:"
echo ""
echo "spec/"
echo "├── README.md"
echo "├── features/"
echo "│   ├── README.md"
echo "│   └── _template.md"
echo "├── contracts/"
echo "│   └── openapi.yaml"
echo "└── acceptance/"
echo ""
echo "Next steps:"
echo "1. Create your first feature: mkdir -p spec/features/my-feature"
echo "2. Copy template: cp spec/features/_template.md spec/features/my-feature/feature.md"
echo "3. Fill in the spec"
echo "4. Add to spec/features/README.md index"
echo "5. Write tests, then implement"
