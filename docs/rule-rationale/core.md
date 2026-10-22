# Rationale — rules/core.md

## Why Specs Matter

**Specs enable technology independence.** Complete specs → you can:
- Rewrite entire system in new language/framework
- Migrate monolith to microservices
- Onboard new teams without archaeology

**Spec defines WHAT system does. Code defines HOW.**

```
Specs are permanent → Code is replaceable
```

## Mermaid diagrams (calibration)

Every user story MUST have a Mermaid sequence diagram showing happy-path flow. Diagram = **visual contract** between business and engineering: business person reads diagram first to confirm flow matches expectation, then the Gherkin scenarios fill testable details. Scenarios without picture force every reviewer to assemble flow from prose; diagram makes shape obvious in three seconds.
