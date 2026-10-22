# Command: /adr

Create or list Architecture Decision Records.

## Usage

```
/adr                     # List all ADRs
/adr new <title>         # Create new ADR
/adr show <number>       # Show specific ADR
```

## ADR Location

```
spec/decisions/
├── README.md
├── 0001-use-vertical-slices.md
├── 0002-flyway-for-migrations.md
└── ...
```

## Create New ADR

Creates `spec/decisions/NNNN-<title>.md`:

```markdown
# ADR-NNNN: <Title>

## Status

Proposed | Accepted | Deprecated | Superseded by [ADR-XXXX](XXXX-title.md)

## Context

What is the issue that we're seeing that motivates this decision?

## Decision

What is the change that we're proposing and/or doing?

## Consequences

### Positive
- <benefit>

### Negative
- <drawback>

### Neutral
- <observation>

## Alternatives Considered

### Alternative 1: <Name>
- Pros: ...
- Cons: ...
- Why rejected: ...

## References

- [Link to relevant documentation]
```

## Update Index

After creating ADR, update `spec/decisions/README.md`:

```markdown
# Architecture Decision Records

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0001](0001-use-vertical-slices.md) | Use Vertical Slices | Accepted | 2024-01-15 |
```

## When to Write an ADR

- Choosing between technologies
- Architectural patterns
- Significant library choices
- Breaking changes to conventions
- Security-related decisions
