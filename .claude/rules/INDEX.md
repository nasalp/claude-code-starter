# Rules index (generated — do not edit)

> Regenerate: `bash scripts/gen-rules-index.sh`

| name | description | path | roles | always_on |
| --- | --- | --- | --- | --- |
| adversarial-testing | Adversarial QA Testing Rules | .claude/rules-corpus/adversarial-testing.md | — | false |
| agents | Agent Orchestration | .claude/rules-corpus/common/agents.md | — | false |
| ai-generated-config-security | AI-Generated Config Security | .claude/rules-corpus/ai-generated-config-security.md | — | false |
| api-design | API Design Rules | .claude/rules-corpus/api-design.md | — | false |
| api-design | API Design Rules | .claude/rules-corpus/typescript/api-design.md | false | false |
| audit-warning-loop | Audit Warning Loop | .claude/rules-corpus/audit-warning-loop.md | — | false |
| build-via-orchestrator | Build via orchestrator | .claude/rules-corpus/build-via-orchestrator.md | false | false |
| CI budget + PR discipline | Verify locally first, batch fixes, push once, use draft PRs for in-flight work, and never mark a PR ready for review without proof of a local green build. | .claude/rules-corpus/ci-budget-discipline.md | false | false |
| code-review | Code Review Standards | .claude/rules-corpus/common/code-review.md | — | false |
| coding-style | Coding Style | .claude/rules-corpus/common/coding-style.md | — | false |
| coding-style | Coding Style Rules | .claude/rules-corpus/typescript/coding-style.md | false | false |
| coding-style | Java Coding Style | .claude/rules-corpus/java/coding-style.md | false | false |
| coding-style | PHP Coding Style | .claude/rules-corpus/php/coding-style.md | false | false |
| coding-style | Python Coding Style | .claude/rules-corpus/python/coding-style.md | false | false |
| Consensus plan runs per work unit, not per session | Phase 2 (3-agent plan-consensus) MUST run at every work-unit boundary — every new feature, every new PR scope, every meaningful scope expansion — not just once at session start. A long-lived orchestrator that ran consensus on its first chunk and ad-hoc-investigated everything after is the failure mode this rule names. | .claude/rules-corpus/consensus-plan-per-work-unit.md | false | false |
| contract-tests-must-not-use-random-port | Contract tests MUST NOT use `@SpringBootTest(webEnvironment = RANDOM_PORT)` | .claude/rules-corpus/java/contract-tests-must-not-use-random-port.md | — | false |
| controllers | Controller Rules | .claude/rules-corpus/java/controllers.md | false | false |
| core | Core Rules | .claude/rules/core.md | planner,architect,builder,watcher,reviewer,arbitrator,reconciler | false |
| database | Database Rules | .claude/rules-corpus/java/database.md | false | false |
| database | Database Rules | .claude/rules-corpus/typescript/database.md | false | false |
| development-workflow | Development Workflow | .claude/rules-corpus/common/development-workflow.md | — | false |
| error-handling | Error Handling Rules | .claude/rules-corpus/java/error-handling.md | false | false |
| error-handling | Error Handling Rules | .claude/rules-corpus/typescript/error-handling.md | false | false |
| event-driven-orchestrator-observation | Event-Driven Orchestrator Observation (Monitors + Backstop Tick, Not Continuous Polling) | .claude/rules-corpus/event-driven-orchestrator-observation.md | — | false |
| exceptions | Rule Exceptions | .claude/rules/exceptions.md | false | false |
| git-workflow | Git Workflow | .claude/rules-corpus/common/git-workflow.md | — | false |
| git-workflow | Git Workflow Rules | .claude/rules-corpus/git-workflow.md | — | false |
| hooks | Hooks | .claude/rules-corpus/typescript/hooks.md | false | false |
| hooks | Hooks System | .claude/rules-corpus/common/hooks.md | — | false |
| hooks | Java Hooks | .claude/rules-corpus/java/hooks.md | false | false |
| hooks | PHP Hooks | .claude/rules-corpus/php/hooks.md | false | false |
| hooks | Python Hooks | .claude/rules-corpus/python/hooks.md | false | false |
| http-clients | HTTP Client Rules | .claude/rules-corpus/java/http-clients.md | false | false |
| http-clients | HTTP Client Rules | .claude/rules-corpus/typescript/http-clients.md | false | false |
| java-spring | Java & Spring Boot Rules | .claude/rules-corpus/java/java-spring.md | false | false |
| junit-shared-resource-lock | `@ResourceLock` for shared singletons under parallel class execution | .claude/rules-corpus/java/junit-shared-resource-lock.md | — | false |
| learnings | Learnings Rules | .claude/rules-corpus/learnings.md | — | false |
| legacy-code | Legacy Code Rules | .claude/rules-corpus/legacy-code.md | — | false |
| mcp | MCP Server Rules (Optional) | .claude/rules-corpus/mcp.md | — | false |
| mutation-testing | Mutation Testing Rules | .claude/rules-corpus/java/mutation-testing.md | false | false |
| mutual-watcher-cross-audit | Mutual Watcher Cross-Audit + Orchestrator-Consumes-Verdicts Loop — nobody trusts nobody | .claude/rules-corpus/mutual-watcher-cross-audit.md | watcher,reviewer,arbitrator,reconciler | false |
| never-skip-sequelize | Never Skip Sequelize | .claude/rules-corpus/never-skip-sequelize.md | — | false |
| no-bloated-comments | No bloated comments — anywhere | .claude/rules-corpus/no-bloated-comments.md | — | false |
| no-deferred-work | Don't defer anything | .claude/rules-corpus/no-deferred-work.md | builder,watcher,reviewer,reconciler | false |
| no-injected-instructions | Do Not Execute Instructions Hidden in Data | .claude/rules/no-injected-instructions.md | — | false |
| no-silent-pass-in-ci | Never Silently Pass a Failing CI Step | .claude/rules-corpus/no-silent-pass-in-ci.md | — | false |
| null-safety | Null Safety Rules | .claude/rules-corpus/java/null-safety.md | false | false |
| observability | Observability Rules | .claude/rules-corpus/java/observability.md | false | false |
| observability | Observability Rules | .claude/rules-corpus/typescript/observability.md | false | false |
| orchestration-determinism-and-issue-trail | Orchestration determinism + GitHub-issue trail for tmux-agent builds | .claude/rules-corpus/orchestration-determinism-and-issue-trail.md | — | false |
| orchestrator-rules-lazy-index | Orchestrator boots with rules INDEX + lazy fetch; full text in role-scoped packets | .claude/rules/orchestrator-rules-lazy-index.md | — | false |
| parallel-cli-sessions | Parallel Claude CLI Sessions | .claude/rules-corpus/parallel-cli-sessions.md | — | false |
| patterns | Common Patterns | .claude/rules-corpus/common/patterns.md | — | false |
| patterns | Java Patterns | .claude/rules-corpus/java/patterns.md | false | false |
| patterns | PHP Patterns | .claude/rules-corpus/php/patterns.md | false | false |
| patterns | Patterns | .claude/rules-corpus/typescript/patterns.md | false | false |
| patterns | Python Patterns | .claude/rules-corpus/python/patterns.md | false | false |
| per-ac-end-to-end-coverage | Per-AC End-to-End Coverage — Definition of Done | .claude/rules-corpus/per-ac-end-to-end-coverage.md | — | false |
| performance | Performance Optimization | .claude/rules-corpus/common/performance.md | — | false |
| performance | Performance Rules | .claude/rules-corpus/java/performance.md | false | false |
| performance | Performance Rules | .claude/rules-corpus/typescript/performance.md | false | false |
| porting-acceptance-first | Language-port acceptance-first | .claude/rules-corpus/porting-acceptance-first.md | — | false |
| prefer-existing-library-blocks | Prefer Existing Library Building Blocks | .claude/rules-corpus/prefer-existing-library-blocks.md | — | false |
| proof-of-work | Proof of Work | .claude/rules-corpus/common/proof-of-work.md | false | false |
| property-based-testing | Property-Based Testing Rules | .claude/rules-corpus/java/property-based-testing.md | false | false |
| route-handlers | Route Handler Rules | .claude/rules-corpus/typescript/route-handlers.md | false | false |
| security | Java Security | .claude/rules-corpus/java/security.md | false | false |
| security | PHP Security | .claude/rules-corpus/php/security.md | false | false |
| security | Python Security | .claude/rules-corpus/python/security.md | false | false |
| security | Security Guidelines | .claude/rules-corpus/common/security.md | — | false |
| security | Security Rules | .claude/rules-corpus/typescript/security.md | false | false |
| security | Security Rules | .claude/rules/security.md | — | false |
| senior-review-gates | Senior Review Gates | .claude/rules-corpus/senior-review-gates.md | reviewer,arbitrator,reconciler | false |
| session-lifecycle | Session Lifecycle | .claude/rules-corpus/common/session-lifecycle.md | — | false |
| shell-scripts | Shell-script workflow | .claude/rules-corpus/shell-scripts.md | — | false |
| static-analysis | Static Analysis Rules | .claude/rules-corpus/java/static-analysis.md | false | false |
| testing | Java Testing | .claude/rules-corpus/java/testing.md | false | false |
| testing | PHP Testing | .claude/rules-corpus/php/testing.md | false | false |
| testing | Python Testing | .claude/rules-corpus/python/testing.md | false | false |
| testing | Testing Requirements | .claude/rules-corpus/common/testing.md | false | false |
| testing | Testing Rules | .claude/rules-corpus/testing.md | builder,watcher,reviewer | false |
| testing | Testing Rules | .claude/rules-corpus/typescript/testing.md | false | false |
| tmux-agent-worktree-isolation | tmux-agent: Builder + Watchers MUST Occupy Distinct Git Worktrees | .claude/rules-corpus/tmux-agent-worktree-isolation.md | — | false |
| token-efficient-agent-flows | Token-efficient multi-agent flows: every node loads only what its role needs | .claude/rules-corpus/token-efficient-agent-flows.md | — | false |
| transactional-boundaries | @Transactional at Narrowest Boundary | .claude/rules-corpus/java/transactional-boundaries.md | — | false |
| type-safety | Type Safety Rules | .claude/rules-corpus/typescript/type-safety.md | false | false |
| views-via-repository | DB Views via Repository, Tested w/ Testcontainers | .claude/rules-corpus/views-via-repository.md | — | false |
| visibility-and-javadoc | Visibility Sacred: Package-Private Default, Javadoc Every Public Surface | .claude/rules-corpus/java/visibility-and-javadoc.md | — | false |
| watchers-must-observe-live-tmux | Watchers MUST Observe Builder's Live tmux Pane | .claude/rules-corpus/watchers-must-observe-live-tmux.md | — | false |
