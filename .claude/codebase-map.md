# Codebase Map — Global Default

> This file is symlinked into `~/.claude/codebase-map.md` by `setup.sh`. It's a **generic default** — every project should ship its own at `<project>/.claude/codebase-map.md` with real navigation hints for that codebase.
>
> The content below is intentionally generic. If you see "OrderController" or "Order" mentioned, that's a placeholder for "your domain's primary entity" — not a real class.

## What this file is for

A `codebase-map.md` is the agent's navigation aid: where the entry points are, which modules contain what, what data flow looks like, what tables map to what entities. The agent reads it on session start and uses it to decide where to look for a given concept.

When this file is generic, the agent gets generic guidance and wastes turns exploring. When it's project-specific and current, the agent starts close to the answer.

## Your projects (template only — fill per project)

| Project | Stack | Entry Points |
|---|---|---|
| example-web | e.g. TypeScript / React / Vite | `src/main.tsx` |
| example-api | e.g. Java / Spring Boot | `src/main/java/.../Application.java` |
| example-infra | e.g. TypeScript / AWS CDK | `bin/app.ts` |

For real navigation, use the project-level `<project>/.claude/codebase-map.md`.

## Generic Java/Spring template

For Java/Spring projects, the typical layout is:

```
<feature>/
├── api/            # Controllers, DTOs, request/response
├── application/    # Use cases, services, orchestration
├── domain/         # Entities (package-private), value objects, domain services
└── infrastructure/ # Repositories, clients, adapters
```

Conventions:
- Entities are package-private (`@Entity class Order`, never `public`).
- Cross-feature access via DTO-only repository interface in `<feature>/api/` (see `rules/java-spring.md`).
- Tests in `src/test/java/.../<feature>/`. Acceptance tests at `acceptance/`.

## Generic Node/TypeScript template

For Node/TS projects, the typical layout is:

```
src/
├── api/            # Express routes, validators, response shapers
├── services/       # Business logic
├── repositories/   # Sequelize/data-access
├── events/         # Emitters and consumers
└── lib/            # Reusable utilities
```

Conventions:
- One repository per Sequelize model.
- Services depend on repositories, not models directly.
- Tests in `tests/` mirror src structure.

## Generic CDK / IaC template

For an AWS CDK infrastructure repo, a typical layout is:

```
bin/app.ts                   # CDK app entry; iterates env × services
config/
  envs/<env>.ts              # Per-environment config (dev, staging, prod)
  services/<svc>/{base,env}.ts  # Per-service config (split by lifecycle)
  loader.ts                  # Discovers envs and services
lib/
  stacks/                    # CDK stack constructors
  constructs/                # Reusable constructs (ECS, OIDC, ALB)
test/                        # CDK assertions tests
```

## What to put in YOUR project's codebase-map

Every project should override this file at `<project>/.claude/codebase-map.md` with:

1. **One sentence on what the project does.**
2. **Tech stack with concrete versions** (Java 25 vs Java 21, Spring Boot 4.x, etc.).
3. **Module overview** if multi-module — module names + their responsibility + their dependencies.
4. **Entry points** — actual class names, actual paths.
5. **Key tables / entities / domain objects** — real names, real paths.
6. **External services** — real service names + which env vars configure them + which to mock in tests.
7. **Quick navigation commands** — `grep` / `rg` / `find` recipes that work in YOUR repo.

When the project changes, run `/refresh-project` and the harness will flag drift.
