# Rationale — java/transactional-boundaries.md

## Cross-references

- `java-spring.md` — broader Spring conventions.
- `../no-mutable-state-in-beans.md` — beans hold only collaborators; transactional
  boundaries don't change that.
- `../prefer-existing-library-blocks.md` — the repository's built-in transaction
  is the existing block; don't re-wrap it.
