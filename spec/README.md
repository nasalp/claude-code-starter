# Specifications

Feature specs, architecture decisions, and durable learnings.

## Structure

```
spec/
├── features/       one file per feature (user stories + acceptance criteria)
├── decisions/      Architecture Decision Records
└── learnings/      key findings about the codebase
```

API contracts, domain models, and integration boundaries are **derived from code**
(OpenAPI generation, REST Docs, Spring Cloud Contract, DDL, classes).
Do not maintain separate prose documents for these.

## Rules

1. **One file per feature** — everything in one markdown file (overview, user stories, ACs, scope)
2. **Spec before code** — every behavior change needs a spec first
3. **User stories wrap ACs** — `As a <who>, I want <what>, so that <why>` with acceptance criteria written as Gherkin scenarios (`@AC-<PREFIX>-N` tags)
4. **Technology-independent** — a spec must be implementable in any language
5. **Record learnings** — key findings go in `learnings/`
