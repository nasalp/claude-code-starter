# Quick Start Guide

Set up the AI agent system in a new project.

---

## Option 1: Copy From Existing Project

```bash
# Copy entire .claude directory
cp -r /path/to/existing-project/.claude /path/to/new-project/

# Copy root AGENTS.md (optional, for quick reference)
cp /path/to/existing-project/AGENTS.md /path/to/new-project/
```

---

## Option 2: Initialize Manually

### Step 1: Create Directory Structure

```bash
# Create .claude structure
mkdir -p .claude/{skills,rules,workflows,checklists,init}

# Create spec structure
mkdir -p spec/{features,contracts,acceptance}
```

### Step 2: Create Spec Templates

Create `spec/README.md`:
```markdown
# Specifications

This directory contains all feature specifications for the project.

## Structure

- `features/` — Feature specifications
- `contracts/` — API contracts (OpenAPI, AsyncAPI)
- `acceptance/` — Acceptance criteria and scenarios

## Quick Links

- [Feature Index](features/README.md)
```

Create `spec/features/README.md`:
```markdown
# Feature Index

| Feature | Spec | Backend | Frontend | Status |
|---------|------|---------|----------|--------|
| *No features yet* | | | | |

## Adding a Feature

1. Create directory: `spec/features/<feature-name>/`
2. Create spec file: `spec/features/<feature-name>/<feature>.md`
3. Add entry to this index
4. Write implementation
5. Update status
```

### Step 3: Create Feature Spec Template

Create `spec/features/_template.md`:
```markdown
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
- What happens when <edge case>? → <behavior>

### Error Cases
- What happens when <error condition>? → <error response>

## API (if applicable)
- Endpoint: `POST /api/v1/resource`
- Request: `{ ... }`
- Response: `{ ... }`
- Error codes: 400, 404, etc.

## Dependencies
- Requires: <upstream dependencies>
- Used by: <downstream consumers>

## Status
- [ ] Spec complete
- [ ] Backend implemented
- [ ] Frontend implemented
- [ ] Tests passing
```

---

## Option 3: Init Script

Save as `.claude/init/setup.sh`:

```bash
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
EOF

# Create feature index
cat > spec/features/README.md << 'EOF'
# Feature Index

| Feature | Spec | Backend | Frontend | Status |
|---------|------|---------|----------|--------|
| *No features yet* | | | | |

## Adding a Feature

1. Create directory: `spec/features/<feature-name>/`
2. Create spec file using template
3. Add entry to this index
4. Write implementation
5. Update status
EOF

# Create feature template
cat > spec/features/_template.md << 'EOF'
# Feature: <Feature Name>

## Overview
Brief description.

## User Stories
- As a <role>, I want <goal>, so that <benefit>

## Behavior

### Happy Path
1. Given <precondition>
2. When <action>
3. Then <expected outcome>

### Edge Cases
- <edge case> → <behavior>

### Error Cases
- <error condition> → <error response>

## API (if applicable)
- Endpoint: `POST /api/v1/resource`

## Dependencies
- Requires: <dependencies>
- Used by: <consumers>

## Status
- [ ] Spec complete
- [ ] Backend implemented
- [ ] Tests passing
EOF

# Create OpenAPI template
cat > spec/contracts/openapi.yaml << 'EOF'
openapi: 3.0.3
info:
  title: Project API
  version: 1.0.0
  description: API specification

servers:
  - url: /api/v1

paths: {}

components:
  schemas: {}
EOF

echo "Done! Structure created:"
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
echo "1. Copy .claude/ directory with rules and skills"
echo "2. Create your first feature spec"
echo "3. Start development!"
```

Run with:
```bash
chmod +x .claude/init/setup.sh
./.claude/init/setup.sh
```

---

## Verification

After setup, verify structure:

```bash
tree -L 2 spec/
# spec/
# ├── README.md
# ├── acceptance/
# ├── contracts/
# │   └── openapi.yaml
# └── features/
#     ├── README.md
#     └── _template.md

tree -L 2 .claude/
# .claude/
# ├── AGENTS.md
# ├── README.md
# ├── checklists/
# ├── init/
# ├── rules/
# ├── skills/
# └── workflows/
```

---

## First Feature

After setup, create your first feature:

```bash
# 1. Create feature directory
mkdir -p spec/features/user-registration

# 2. Copy template
cp spec/features/_template.md spec/features/user-registration/registration.md

# 3. Edit the spec
# Fill in the template with your feature details

# 4. Update feature index
# Add entry to spec/features/README.md

# 5. Start development
# Follow workflow: spec → test → implement → verify
```
