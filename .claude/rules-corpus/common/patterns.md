# Common Patterns

## Skeleton Projects

New functionality:
1. Search battle-tested skeleton projects
2. Parallel agents evaluate: security assessment, extensibility analysis, relevance scoring, implementation planning
3. Clone best match as foundation
4. Iterate within proven structure

## Design Patterns

### Repository Pattern

Encapsulate data access behind consistent iface:
- Standard ops: findAll, findById, create, update, delete
- Concrete impls handle storage (DB, API, file, etc.)
- Business logic depends on abstract iface, not storage mechanism
- Swap data sources; simplify testing with mocks

### API Response Format

Consistent envelope for all API responses:
- Success/status indicator
- Data payload (nullable on error)
- Error message field (nullable on success)
- Metadata for paginated responses (total, page, limit)
