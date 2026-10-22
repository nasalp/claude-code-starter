# Git Workflow Rules

## Priority Levels

| Priority | Meaning |
|----------|---------|
| **CRITICAL** | Blocks deployment, no exceptions |
| **REQUIRED** | Must follow unless explicitly overridden |
| **RECOMMENDED** | Best practice, team can adjust |

---

## Branch Naming

### REQUIRED: Convention

```
<type>/<ticket>-<short-description>

feature/PROJ-123-user-registration
bugfix/PROJ-456-fix-login-timeout
hotfix/PROJ-789-security-patch
refactor/PROJ-101-extract-service
```

**Types:** `feature/` new functionality; `bugfix/` bug fixes; `hotfix/` urgent prod fixes; `refactor/` code improvements; `docs/` documentation only; `test/` test additions/fixes.

---

## Commit Messages

### REQUIRED: Format

```
<type>: <short summary>

<optional body explaining what and why>

<optional footer with ticket reference>
```

**Example:**
```
feat: Add order cancellation endpoint

Implements the cancel order flow per spec. Users can now
cancel pending orders within 24 hours of placement.

Closes PROJ-123
```

**Types:** `feat:` new feature; `fix:` bug fix; `refactor:` neither fixes nor adds; `test:` adding/updating tests; `docs:` documentation; `chore:` maintenance (deps, config).

### RECOMMENDED: Keep Summary Under 72 Characters

```
# ✅ Good
feat: Add user registration endpoint

# ❌ Too long
feat: Add user registration endpoint with email validation and password strength checking
```

---

## When to Commit

### REQUIRED: Atomic Commits

One commit = one logical change.

```bash
# ✅ Good — separate commits
git commit -m "feat: Add Order entity"
git commit -m "feat: Add OrderRepository"
git commit -m "feat: Add OrderService"
git commit -m "test: Add Order acceptance tests"

# ❌ Bad — everything in one
git commit -m "Add order feature"
```

### REQUIRED: Tests Pass Before Commit

```bash
./mvnw test && git commit
```

Never commit with failing tests.

---

## Pull Requests

### REQUIRED: PR Template

```markdown
## Summary
<1-3 sentences describing the change>

## Changes
- <bullet points of what changed>

## Spec
- Link to spec: `spec/features/<feature>/`

## Testing
- [ ] Unit tests added/updated
- [ ] Acceptance tests added/updated
- [ ] All tests pass locally

## Checklist
- [ ] Spec exists and is updated
- [ ] No sensitive data in logs
- [ ] Follows coding standards
```

### REQUIRED: PR Size

- **Target:** < 400 lines changed
- **Maximum:** 800 lines (split if larger)

Large PRs hard to review; often hide bugs.

### RECOMMENDED: Draft PRs for WIP

Use draft PRs for work-in-progress to get early feedback.

---

## Protected Branches

### CRITICAL: main/master Protection

- No direct pushes
- Require PR with approval
- Require passing CI
- Require up-to-date branch

---

## Merge Strategy

### RECOMMENDED: Squash and Merge

Feature branches with messy commit history:
```
Squash and merge → Clean single commit on main
```

### RECOMMENDED: Rebase and Merge

Clean commit history to preserve:
```
Rebase and merge → All commits preserved
```

### REQUIRED: Delete Branch After Merge

Remove merged feature branches to keep repo clean.

---

## Quick Reference

| Rule | Priority |
|------|----------|
| No direct push to main | CRITICAL |
| Tests pass before commit | REQUIRED |
| Branch naming convention | REQUIRED |
| Commit message format | REQUIRED |
| Atomic commits | REQUIRED |
| PR template | REQUIRED |
| PR size < 400 lines | REQUIRED |
| Delete merged branches | REQUIRED |
| Squash messy history | RECOMMENDED |
| Draft PRs for WIP | RECOMMENDED |
