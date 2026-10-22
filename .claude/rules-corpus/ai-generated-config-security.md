# AI-Generated Config Security

## Rule

**Every PR adding/modifying infra / deployment / build / runtime config MUST pass six-class security review before merge.** Classes from 6-month audit of 5,000 AI-generated configs (three security firms, 2026); failure rates:

| Class | Failure rate in AI-generated configs | What it looks like |
|---|---|---|
| **Missing SAST/SCA** | 89% | No static-analysis or dependency-scan gate in CI; container images deployed without vulnerability scan |
| **Root privileges** | 78% | Containers running as UID 0, K8s `privileged: true`, missing `runAsNonRoot`, ECS task roles with managed policies like `AdministratorAccess` |
| **Wildcard permissions** | 62% | IAM `Action: "*"` / `Resource: "*"`, K8s RBAC `verbs: ["*"]`, GitHub Actions `permissions: write-all` |
| **No input validation** | 45% | Controller methods without `@Valid` on `@RequestBody`, raw `String` path/query params without constraints, SQL with string concat |
| **Hardcoded secrets** | 37% | `password=`, `api_key=`, `token=` literals in source/config; AWS access keys (`AKIA…`) committed |
| **Lateral-move surface** | (implied) | Service account with read access to other tenants' data; service-to-service auth disabled "for now" |

AI agents MEASURABLY worse at these than humans. Rule gives agent loop stop-the-bus check firing every time config touches attack surface.

## What is required

### 1. Six-class checklist per config PR

Every PR touching these file types MUST be reviewed against all six classes by adversarial-review subagent BEFORE merge:

- `Dockerfile`, `**/Dockerfile.*`, `compose*.yml`, `docker-compose.*.yml`
- `**/*.yaml`, `**/*.yml` under `k8s/`, `manifests/`, `helm/`, `kustomize/`
- IaC sources: `**/*.tf`, `**/*.tf.json`, `cdk.json`, `cdk/**/*.{ts,py,java}`, `serverless.{yml,json}`, `sam.{yml,yaml,json}`, CloudFormation templates
- IAM policies: anything under `policies/`, `iam/`, `**/policy*.json`
- CI/CD: `.github/workflows/**`, `.gitlab-ci.yml`, `Jenkinsfile`, `buildkite/`, `.circleci/`
- Application runtime config: `application.yml`, `application*.properties`, `appsettings*.json`, `config/*.{yml,toml,json}`
- Security configs: `SecurityFilterChain` / Spring Security bean methods, CORS configs, CSRF configs, OAuth2 client registration files

Adversarial reviewer's prompt MUST explicitly enumerate six classes, require verdict for each.

### 2. Concrete patterns reviewer MUST detect

#### Missing SAST/SCA
- CI workflow does NOT run dependency scan (OWASP dep-check, Snyk, Trivy, `cargo audit`, `npm audit --audit-level=high`, `pip-audit`, `govulncheck`)
- Container image build step has NO scan step before push
- Newly added Maven module has NO `dependency-check-maven` in its profile chain

#### Root privileges
- `Dockerfile` lacks `USER <non-root-uid>` directive (defaults to root)
- K8s pod/container spec lacks `securityContext.runAsNonRoot: true` AND `runAsUser: <non-zero>`
- K8s `privileged: true` or `allowPrivilegeEscalation: true`
- K8s missing `readOnlyRootFilesystem: true`
- ECS task role attached to `AdministratorAccess` or other catch-all managed policy
- AWS Lambda execution role with `*:*` permissions

#### Wildcard permissions
- IAM policy JSON: `"Action": "*"`, `"Resource": "*"`, or both
- K8s RBAC `Role`/`ClusterRole`: `verbs: ["*"]`, `resources: ["*"]`, `apiGroups: ["*"]`
- GitHub Actions workflow: `permissions: write-all` or no `permissions:` block at all (defaults to write-all on `${{ github.token }}`)
- GitHub Actions step using `pull_request_target` without explicit checkout-by-SHA
- AWS S3 bucket policy `Principal: "*"` without IP/condition restrictions
- Spring `@CrossOrigin(origins = "*")` on a non-public endpoint

#### No input validation
- Spring controller `@RequestBody Foo body` without `@Valid`
- `@PathVariable String x` or `@RequestParam String x` without size / format constraint (no `@Pattern`, no `@Size`, no enum)
- SQL with string concatenation: `"SELECT ... WHERE id = '" + userId + "'"`
- JPQL/Criteria with un-parameterized concatenation
- Shell exec / `ProcessBuilder` with user-provided string segments
- File-path construction from user input without normalization (`..` traversal)

#### Hardcoded secrets
- Literal patterns in source: `password\s*=\s*"[^"]+"`, `api_key\s*=`, `secret\s*=`, `token\s*=` outside test fixtures with obviously-fake values
- AWS access keys: `AKIA[A-Z0-9]{16}`
- Private keys: `-----BEGIN [A-Z ]+ PRIVATE KEY-----`
- `application.yml` with non-placeholder values for secrets (any concrete string where `${ENV:default}` would be expected)
- `.env` file committed (even if `.env.example` is the convention)

#### Lateral-move surface
- Service-to-service auth disabled (`@Profile("test")` carved into production code path)
- Tenant ID derived from request header without verification against the authenticated principal
- Cross-tenant queries without a `WHERE tenant_id = :principalTenant` clause

### 3. Reviewer verdict format

Adversarial reviewer MUST produce per-class verdict:

```
### AI-Generated Config Security Audit (6 classes)

| Class | Verdict | Evidence |
|---|---|---|
| Missing SAST/SCA | PASS / FAIL / N/A | file:line citation |
| Root privileges | PASS / FAIL / N/A | … |
| Wildcard permissions | PASS / FAIL / N/A | … |
| No input validation | PASS / FAIL / N/A | … |
| Hardcoded secrets | PASS / FAIL / N/A | … |
| Lateral-move surface | PASS / FAIL / N/A | … |

Overall: APPROVE / REJECT
```

Any `FAIL` blocks. PR does not merge until each `FAIL` becomes `PASS` or downgraded to `N/A` with explicit file:line-cited reason.

`N/A` allowed when diff genuinely doesn't touch class (e.g. docs-only PR = `N/A` for everything). `N/A` FORBIDDEN as hand-wave; if class plausibly in scope, reviewer audits, returns `PASS` or `FAIL`.

### 4. CI-level enforcement (safety net)

Reviewer = per-PR gate. CI = safety net. Each repo's CI pipeline MUST include:

- SAST: static-analysis step failing on high-severity findings
  (SpotBugs+FindSecBugs for Java, `semgrep` baseline for polyglot,
  Bandit for Python, etc.)
- SCA: dependency-scan step failing on known CVEs above agreed
  severity (OWASP dependency-check / Trivy / Snyk / Dependabot)
- Secret scan: `gitleaks` or `trufflehog` on every PR diff
- Container scan: Trivy (or equivalent) on every image build, blocking
  on `HIGH`/`CRITICAL` CVEs

Repo without these gates is itself config-security defect to fix.

## What is forbidden

- Merging config PR without six-class verdict from reviewer.
- `N/A` on a class the diff plausibly touches.
- Suppressing scanner finding with TODO ("we'll fix later").
- Using `# noqa`, `// gitleaks:ignore`, `# nosec`, `@SuppressFBWarnings`
  on a finding from these six classes without documented
  justification approved by security-aware reviewer.
- Bypassing CI's security gates with `--admin`.

> Rationale (Why/Calibration/Cross-refs): `docs/rule-rationale/ai-generated-config-security.md`
