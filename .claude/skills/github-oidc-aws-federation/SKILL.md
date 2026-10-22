---
name: github-oidc-aws-federation
description: Eliminate long-lived AWS access keys from GitHub Actions. One iam.OpenIdConnectProvider per AWS account, per-repo iam.WebIdentityPrincipal roles scoped via token.actions.githubusercontent.com:sub r...
origin: ECC
triggers: github actions oidc, configure-aws-credentials, OpenIdConnectProvider, WebIdentityPrincipal, id-token, role-to-assume, AWS access keys, GHA federation
paths:
  - "**/cdk.json"
  - "**/*.ts"
  - "**/.github/workflows/*.yml"
---
# GitHub OIDC AWS Federation

GitHub Actions stored as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` is the most common credential leak vector in cloud-native repos. This skill replaces it with **OIDC federation**: GitHub mints a short-lived JWT, AWS STS exchanges it for short-lived credentials, scoped to a specific repo and specific environment. Nothing long-lived touches GitHub secrets.

## When to use

- Any GitHub Actions workflow that needs AWS credentials.
- You operate multiple AWS accounts and want a per-account, per-repo trust boundary.
- You're rotating long-lived `AWS_*` secrets (or want to stop having to).
- You need the trust policy to differ per environment (e.g. only `main` branch can deploy to prod).

## When NOT to use

- Workflows running on self-hosted runners inside a VPC that already has an IAM role attached. Use the instance role.
- One-off scripts that aren't in a GHA workflow. OIDC is GHA-specific. For local dev, use SSO + assume-role.

## The pattern

### 1. One OIDC provider per AWS account

AWS allows exactly one OIDC provider per `(account, URL)`. Create it once in `PlatformStack`, expose its ARN, reference it from every role.

`lib/stacks/platform-stack.ts:93-97`:

```typescript
const oidcProvider = new iam.OpenIdConnectProvider(this, 'GithubOidcProvider', {
  url:       'https://token.actions.githubusercontent.com',
  clientIds: ['sts.amazonaws.com'],
});
this.oidcProviderArn = oidcProvider.openIdConnectProviderArn;
```

Note: no `thumbprints` — CDK / AWS handle TLS validation natively for `token.actions.githubusercontent.com` since 2023. Hard-coding thumbprints is now an anti-pattern.

### 2. Per-repo IAM role with subject-scoped trust

Every repo that needs AWS gets its own role. The trust policy uses two conditions:

- `aud: sts.amazonaws.com` — proves the JWT was minted *for* AWS.
- `sub: repo:<org>/<repo>:*` — proves the JWT was minted *by* a workflow in that specific repo.

`lib/constructs/github-oidc.ts:46-64`:

```typescript
this.role = new iam.Role(this, 'GithubActionsRole', {
  roleName:    `github-actions-${envName}-${githubRepo}`,
  description: `Assumed by GitHub Actions for ${githubOrg}/${githubRepo} (${envName})`,
  assumedBy: new iam.WebIdentityPrincipal(
    provider.openIdConnectProviderArn,
    {
      StringEquals: {
        'token.actions.githubusercontent.com:aud': 'sts.amazonaws.com',
      },
      StringLike: {
        // Allows all branches + pull requests on the repo.
        // Tighten per-env if needed, e.g. prod: 'repo:org/repo:ref:refs/heads/main'
        'token.actions.githubusercontent.com:sub':
          `repo:${githubOrg}/${githubRepo}:*`,
      },
    },
  ),
  maxSessionDuration: cdk.Duration.hours(1),
});
```

Tightening the `sub` pattern is the production hardening lever:

- `repo:org/repo:*` — any ref, any event (dev convenience).
- `repo:org/repo:ref:refs/heads/main` — only pushes to main (prod hardening).
- `repo:org/repo:environment:prod` — only when the workflow declares `environment: prod` (best for approval-gated deploys; combine with GitHub environment protection rules).

### 3. The CDK-deploy role is a special case in PlatformStack

The `infra` repo itself needs to assume a role to deploy CDK. That role is bootstrapped *by* a `PlatformStack` deploy, but it has to exist *before* any subsequent deploy can run via OIDC. Solve with: human-credentialed first deploy, OIDC for everything after.

`lib/stacks/platform-stack.ts:99-115`:

```typescript
const cdkDeployRole = new iam.Role(this, 'CdkDeployRole', {
  roleName:    `cdk-deploy-${envName}`,
  description: `Assumed by infra GitHub Actions to run cdk deploy (${envName})`,
  assumedBy: new iam.WebIdentityPrincipal(oidcProvider.openIdConnectProviderArn, {
    StringEquals: {
      'token.actions.githubusercontent.com:aud': 'sts.amazonaws.com',
    },
    StringLike: {
      'token.actions.githubusercontent.com:sub': `repo:${githubOrg}/infra:*`,
    },
  }),
  maxSessionDuration: cdk.Duration.hours(1),
});
cdkDeployRole.addManagedPolicy(
  iam.ManagedPolicy.fromAwsManagedPolicyName('AdministratorAccess'),
);
```

### 4. The GitHub Actions workflow assumes the role

`.github/workflows/deploy-service.yml:58-67`:

```yaml
jobs:
  deploy:
    permissions:
      contents: read
      id-token: write           # <— mints the OIDC JWT

    steps:
      - name: Authenticate to AWS
        uses: aws-actions/configure-aws-credentials@a89a83ec143615402a01f672b6e172b7b1875000 # v6
        with:
          role-to-assume: ${{ vars.GHA_DEPLOY_ROLE }}
          role-session-name: ecs-deploy-${{ inputs.env_name }}
          aws-region: ${{ inputs.aws_region }}
```

`id-token: write` is the magic that lets the workflow mint OIDC tokens. Without it, the action fails with `Unable to get ACTIONS_ID_TOKEN_REQUEST_URL`. `role-to-assume` is the role ARN — stored as a *vars* (not secrets) value because role ARNs are not sensitive.

## Common gotchas / variants

**Action SHA pinning is mandatory.** `aws-actions/configure-aws-credentials@v6` lets a tag move under you. Pin the commit SHA: `aws-actions/configure-aws-credentials@a89a83ec...` then add `# v6` as a comment. Dependabot updates the SHA via PR.

**The role won't assume — `Not authorized to perform: sts:AssumeRoleWithWebIdentity`.** Three checks:
1. The OIDC provider ARN in the trust policy matches the actual provider in the account.
2. The `sub` condition matches the workflow's `github.repository` — case-sensitive, full `org/repo`.
3. The `aud` condition is `sts.amazonaws.com` (default for `configure-aws-credentials`).

**Per-env tightening.** Prod role should *not* trust `repo:org/repo:*`. Tighten to `repo:org/repo:environment:prod` and configure GitHub environment protection rules (required reviewers, wait timer). The deploy can no longer fire without going through the GitHub approval gate.

**Cross-account role chaining is unnecessary.** Don't build a "central" account that assumes into "spoke" accounts. Each environment account has its own OIDC provider and its own role. GHA assumes directly into each. Simpler trust graph, fewer cross-account permissions.

**Don't use `aws-actions/configure-aws-credentials@v1`.** Old versions used static keys. v2+ supports OIDC; v4+ is current.

## Verification

```bash
# Confirm provider exists in the account.
aws iam list-open-id-connect-providers

# Confirm role trust policy.
aws iam get-role --role-name github-actions-dev-orders-api \
  --query 'Role.AssumeRolePolicyDocument'

# In a workflow run, confirm the JWT is minted (look for the masked Token in logs).
# In CloudTrail, confirm AssumeRoleWithWebIdentity events with the right principal.
```

## References

- AWS docs: <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html>
- GitHub docs: <https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect>
