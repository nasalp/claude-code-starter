# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for significant technical decisions.

## What is an ADR?

An ADR captures an important architectural decision along with its context and consequences.

## ADR Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0001](0001-project-structure.md) | Project Structure | Accepted | 2024-01-01 |

## Creating a New ADR

1. Copy `_template.md` to `NNNN-<title>.md`
2. Fill in the sections
3. Update this index
4. Commit with the related code changes

Or use: `/adr new <title>`

## Statuses

- **Proposed** — Under discussion
- **Accepted** — Approved and in effect
- **Deprecated** — No longer recommended
- **Superseded** — Replaced by another ADR

## When to Write an ADR

Write an ADR when:
- Choosing between technologies or libraries
- Defining architectural patterns
- Making security-related decisions
- Changing established conventions
- Making decisions that are hard to reverse
