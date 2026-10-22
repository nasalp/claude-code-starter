# Development Workflow

> Extends [common/git-workflow.md](./git-workflow.md) with development pipeline before git ops: research, planning, TDD, code review, then commit.

## Feature Implementation Workflow

0. **Research & Reuse** _(mandatory before any new implementation)_
   - **GitHub code search first:** `gh search repos` and `gh search code` for existing implementations, templates, patterns before writing anything new.
   - **Exa MCP for research:** `exa-web-search` MCP during planning for broader research, data ingestion, prior art.
   - **Check package registries:** npm, PyPI, crates.io, etc. before writing utility code. Prefer battle-tested libraries over hand-rolled.
   - **Search adaptable implementations:** open-source projects solving 80%+ of problem to fork, port, or wrap.
   - Prefer adopting/porting proven approach over net-new code when it meets requirement.

1. **Plan First**
   - Use **planner** agent for implementation plan
   - Generate planning docs before coding: PRD, architecture, system_design, tech_doc, task_list
   - Identify dependencies and risks
   - Break into phases

2. **TDD Approach**
   - Use **tdd-guide** agent
   - Write tests first (RED)
   - Implement to pass tests (GREEN)
   - Refactor (IMPROVE)
   - Verify 80%+ coverage

3. **Code Review**
   - Use **code-reviewer** agent immediately after writing code
   - Address CRITICAL and HIGH issues
   - Fix MEDIUM issues when possible

4. **Commit & Push**
   - Detailed commit messages
   - Follow conventional commits format
   - See [git-workflow.md](./git-workflow.md) for commit message format and PR process
