# Rationale — java/null-safety.md

## Why: JPA entity exclusion

- JPA requires no-arg constructors
- Hibernate populates fields via reflection after construction
- NullAway sees uninitialized non-null fields in the no-arg constructor
