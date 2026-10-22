---
name: aws-cdk-multi-account-fleet
description: One CDK app, env=AWS-account model. Discover envs from config/envs/*.ts, scope synthesis via --context env=<name>, suffix every CfnOutput exportName with the env, and survive the first-deploy boots...
origin: ECC
triggers: cdk multi-account, --context env=, CfnOutput exportName, listEnvs, cdk bootstrap, GHA OIDC bootstrap, dev staging prod accounts, cdk app entry point, account-per-env, bin/app.ts
paths:
  - "**/cdk.json"
  - "**/*.ts"
  - "**/*.py"
---
# AWS CDK Multi-Account Fleet

The natural failure mode of a CDK codebase that grows past one AWS account is a fork: a `dev/` directory, a `prod/` directory, two `cdk.json` files, and a slow drift in conventions. This skill describes the alternative pattern: **one CDK app, one synth graph, environments as data**. The mapping is `env name` → `AWS account ID`. Adding `staging` is a new file, not a new project.

## When to use

- You operate two or more AWS accounts and want the same CDK author to own all of them.
- You want CI to be able to deploy to one account without needing credentials for the others.
- You want `cdk diff` against prod from a developer laptop with read-only prod credentials, never deploy.
- You want CloudFormation exports that survive having multiple environments share an account temporarily (e.g. `dev` and `staging` in the same sandbox).

## When NOT to use

- A single-account, single-region project. The overhead of the loader and exportName suffixes is not earned.
- Each environment runs a fundamentally different stack topology. The pattern assumes the *shape* is shared and the *parameters* differ.
- The team prefers Terraform workspaces or per-env state files. Don't fight your tool.

## The pattern

### 1. Entry point reads `--context env=<name>` and falls through to all envs in CI

`bin/app.ts:75-145`:

```typescript
async function main() {
  const app = new cdk.App();

  // Pass --context env=<name> to synthesize a single environment (e.g. local diff/deploy).
  // Without it, all environments are synthesized — used by CI/CD.
  const envFilter = app.node.tryGetContext('env') as string | undefined;
  const envNames  = listEnvs().filter(e => !envFilter || e === envFilter);

  for (const envName of envNames) {
    const envConfig = loadEnvConfig(envName);
    const services  = loadServices(envName);

    const platform = new PlatformStack(app, `ExamplePlatform-${envName}`, {
      env: { account: envConfig.accountId, region: envConfig.region },
      envName, envConfig, githubOrg: GITHUB_ORG,
    });
    // ...
  }
}
```

The same `bin/app.ts` produces a global synth graph in CI (`cdk ls` shows every stack across every account) and a single-account graph on a developer laptop (`cdk diff --context env=dev`). No `if (env === 'prod')` branches.

### 2. Loader discovers envs by directory listing, not enums

`config/loader.ts:11-17`:

```typescript
export function listEnvs(): EnvName[] {
  const envsDir = path.join(__dirname, 'envs');
  return fs
    .readdirSync(envsDir)
    .filter((f) => /\.(ts|js)$/.test(f) && !f.endsWith('.d.ts'))
    .map((f) => f.replace(/\.(ts|js)$/, '') as EnvName);
}
```

Adding `staging` is `touch config/envs/staging.ts`. No registration step, no array to update, no constant to bump. The TypeScript union `EnvName` is the only thing that needs editing if you want type narrowing.

### 3. Every `CfnOutput` exportName is suffixed with the env

CloudFormation export names are global within an account. The instant two environments share an account — sandbox, accidental cross-tenancy, a temporary staging in the dev account — collisions surface as deploy failures.

`lib/stacks/platform-stack.ts:117-121`:

```typescript
new cdk.CfnOutput(this, 'CdkDeployRoleArn', {
  value:       cdkDeployRole.roleArn,
  description: 'CDK_DEPLOY_ROLE — set as GitHub Actions secret in the infra repo',
  exportName:  `CdkDeployRoleArn-${envName}`,
});
```

The logical ID stays env-free (`CdkDeployRoleArn`) so unit tests can match by stable name. Only the *export name* — the cross-stack key — gets `-${envName}`.

### 4. Stack IDs encode the env

`ExamplePlatform-${envName}`, `ExampleService-${envName}-${service.name}`. CDK uses these as CloudFormation stack names. The env appears in every AWS console search, every CloudTrail event, every Slack alert.

## Common gotchas / variants

**First deploy bootstrap is a chicken-and-egg.** `cdk deploy` needs an IAM role to assume. The role is created by `cdk deploy`. Two ways out:

1. **Bootstrap with admin credentials once.** `cdk bootstrap aws://<account>/<region>` from a workstation using human SSO credentials. After that first deploy of `PlatformStack`, the GHA OIDC role exists and CI takes over.
2. **`cdk bootstrap --trust <existing-role-arn>`** if you already have a federation role.

Once the OIDC provider and `cdk-deploy-${envName}` role exist (created in `PlatformStack`), GHA can assume them on every subsequent deploy. This is *not* a continuous problem — it happens once per account.

**Don't mix `env: { account, region }` with `process.env.CDK_DEFAULT_ACCOUNT`.** If the user has `AWS_PROFILE=prod` set and `--context env=dev` is passed, CDK will fail synth because the explicit `env.account` doesn't match the CLI credentials. This is the desired behaviour — never deploy to the wrong account silently — but the error message is confusing. Document it.

**`cdk diff` against an env you don't have credentials for.** Pass `--context env=dev` so synthesis only walks the dev stacks. Without the filter, CDK will try to read CloudFormation state from every account and fail.

**SSM parameter lookups in CI.** Don't use `ssm.StringParameter.valueFromLookup()` for cross-account values — they're cached in `cdk.context.json` and that cache is account-specific. Pass the value through `EnvConfig` instead.

## Verification

```bash
# Single env, single account — local diff/deploy.
npx cdk ls     --context env=dev
npx cdk diff   --context env=dev ExamplePlatform-dev

# All envs, all accounts — CI sanity check.
npx cdk ls

# Confirm exports are env-suffixed.
npx cdk synth --context env=dev | grep -A1 'Export:' | head
# Expected: Name: CdkDeployRoleArn-dev (not CdkDeployRoleArn)
```

A passing test of the pattern: drop a sibling `staging.ts` next to `dev.ts`, run `npx cdk ls`, confirm `ExamplePlatform-staging` appears with no other code changes.

## References

- AWS CDK env contexts: <https://docs.aws.amazon.com/cdk/v2/guide/environments.html>
