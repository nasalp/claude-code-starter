---
name: ecs-cdk-image-drift-prevention
description: Stop CDK from regressing an ECS service to a placeholder image after GHA deployed the real one. At synth time, query DescribeServices and DescribeTaskDefinition for the active image; feed it back i...
origin: ECC
triggers: cdk deploy regresses image, busybox placeholder, image drift, fetchCurrentImage, DescribeTaskDefinition, ECS service stuck on placeholder, GHA vs CDK image conflict, FargateTaskDefinition image
paths:
  - "**/cdk.json"
  - "**/*.ts"
---
# ECS CDK Image Drift Prevention

The textbook split is "CDK manages infrastructure, GitHub Actions deploys code." Reality: CDK's `FargateTaskDefinition` *includes* the container image as part of the infrastructure. Every `cdk deploy` reads the image from your TypeScript and writes it back to ECS — even if you didn't touch the image, even if GHA already deployed `:abc123`. The next CDK deploy regresses the service to whatever placeholder is in the source.

This skill is the workaround pattern: **read what's running before you synthesise**.

## When to use

- ECS Fargate (or ECS EC2) services where image lifecycle is owned by a separate CI pipeline (GHA).
- A bootstrap problem on first deploy: the task definition needs an image, but the real image isn't built yet.
- You've ever seen `cdk deploy ExampleService-dev-foo` flip the running image back to busybox or `:latest`.

## When NOT to use

- CDK fully owns the image lifecycle (rare — works only if your build runs *inside* `cdk deploy`).
- You use `BlueGreenDeployment` / CodeDeploy with full immutable task definitions per release. Different pattern.
- Lambda — Lambda function code is more stateful, different mechanics.

## The pattern

### 1. At synth time, async-fetch the live image from ECS

`bin/app.ts:30-73`:

```typescript
async function fetchCurrentImage(region: string, family: string, containerName: string): Promise<string | undefined> {
  const client = new ECSClient({ region });
  try {
    const parts   = family.split('-');           // ["app", "<env>", "<service>", ...]
    const cluster = parts.slice(0, 2).join('-'); // "app-<env>"

    const svcResponse = await client.send(new DescribeServicesCommand({
      cluster,
      services: [family],
    }));
    const service = svcResponse.services?.[0];
    if (!service) {
      return undefined; // service doesn't exist yet — first deploy
    }

    // If a deployment is in progress, prefer the ACTIVE (stable) task definition
    // over the PRIMARY (new) one that hasn't finished rolling out yet.
    const deployments    = service.deployments ?? [];
    const isRollingOut   = deployments.some(d => d.status === 'PRIMARY' && d.rolloutState === 'IN_PROGRESS');
    const activeDeployment = isRollingOut
      ? deployments.find(d => d.status === 'ACTIVE')
      : deployments.find(d => d.status === 'PRIMARY');
    const activeTaskDefArn = activeDeployment?.taskDefinition ?? service.taskDefinition;
    if (!activeTaskDefArn) {
      return undefined;
    }

    const response = await client.send(new DescribeTaskDefinitionCommand({ taskDefinition: activeTaskDefArn }));
    const container = response.taskDefinition?.containerDefinitions?.find(c => c.name === containerName);
    return container?.image;
  } catch (e: any) {
    if (
      e.name === 'ClusterNotFoundException' ||
      e.name === 'ServiceNotFoundException' ||
      (e.name === 'ClientException' && e?.message?.includes('Unable to describe task definition'))
    ) {
      return undefined; // resource doesn't exist yet — first deploy
    }
    throw e; // unexpected error (credentials, throttling, network) — surface it
  }
}
```

Critical details:

- **`bin/app.ts` is async.** CDK supports an async entry point as long as `app.synth()` is called inside it. The default scaffold isn't async — you have to refactor.
- **Cluster name is derived, not configured.** Convention: `app-${env}` and family `app-${env}-${service}`. If the convention drifts, fix the convention, don't hard-code another input.
- **First-deploy failures are *not* errors.** `ClusterNotFoundException` and `ServiceNotFoundException` mean "this is the first deploy — there is no live image yet". The function returns `undefined` and synth proceeds.

### 2. Pass the live image into the task definition

`bin/app.ts:120`:

```typescript
const family       = `app-${envName}-${service.name}`;
const currentImage = await fetchCurrentImage(envConfig.region, family, service.containerName);

const serviceStack = new ServiceStack(app, `ExampleService-${envName}-${service.name}`, {
  // ...
  currentImage,
});
```

### 3. The construct uses live image OR falls back to a placeholder

`lib/constructs/ecs-service.ts:140-151`:

```typescript
// If a real image is already running (fetched from ECS at synth time in bin/app.ts),
// use it so cdk deploy doesn't regress the service to the placeholder.
// On first deploy currentImage is undefined → fall back to busybox placeholder.
const placeholderImage = 'public.ecr.aws/docker/library/busybox:stable';
const healthCheckDir = healthCheckPath.substring(0, healthCheckPath.lastIndexOf('/'));
const placeholderCommand = ['sh', '-c', `mkdir -p /tmp${healthCheckDir} && echo ok > /tmp${healthCheckPath} && httpd -f -p $PORT -h /tmp`];
const image   = currentImage ?? placeholderImage;
const isPlaceholder = image === placeholderImage;

this.taskDefinition.addContainer(containerName, {
  image:   ecs.ContainerImage.fromRegistry(image),
  command: isPlaceholder ? placeholderCommand : undefined,
  // ...
});
```

The placeholder is `busybox` running an `httpd` that serves `200 OK` at the health-check path. ALB targets stay healthy on first deploy. GHA's first push to ECR + ECS service update replaces it. CDK's next deploy reads the new image back via `fetchCurrentImage` and the cycle is stable.

The `command` override is critical: when CDK *isn't* using the placeholder, `command: undefined` lets the real image's `CMD` instruction run. If you accidentally leave the placeholder command in place, every real deploy starts an `httpd` instead of your application — and the bug is silent because health checks pass.

## Common gotchas / variants

**`bin/app.ts` becomes async — synth time goes up.** One ECS API call per service per synth. For a fleet of 30 services across 3 envs, that's 90 calls. Run synth on a CDK CLI with reasonable AWS credentials; it's still a few seconds.

**Synth needs read access to ECS in every account.** The user (or CI role) running `cdk synth` must have `ecs:DescribeServices` and `ecs:DescribeTaskDefinition`. For local dev with read-only credentials, this is fine. For CI, the deploy role already has these.

**Cross-region — pass the right region.** `fetchCurrentImage(envConfig.region, ...)` not `process.env.AWS_REGION`. The latter would be wrong if the developer has a `eu-central-1` profile and is synthesising a `eu-west-1` env.

**Rollouts in progress.** If a GHA deploy is mid-roll when CDK synthesises, the service has *two* deployments: `PRIMARY` (the new one, rolling out) and `ACTIVE` (the previous stable one). Picking `PRIMARY` and writing it back is harmless. Picking `ACTIVE` would mean CDK occasionally rolls the service back. The pattern explicitly prefers `ACTIVE` when `PRIMARY` is `IN_PROGRESS` to avoid CDK racing GHA into half-done state.

**ECS task definition family rename.** If you rename a service, `family` changes and `fetchCurrentImage` returns `undefined`. The next CDK deploy serves the placeholder until GHA pushes the next image. Plan a one-shot redeploy via GHA right after rename.

**The strip-command counterpart in GHA.** `.github/workflows/deploy-service.yml` runs `jq '... |= del(.command)'` on the rendered task definition before deploying. Because if CDK ever wrote the placeholder `command` and GHA rendered it without removing it, the new image would inherit `httpd -f` as its entrypoint. Defence in depth.

## Verification

```bash
# Drift-free deploy.
git diff --quiet                  # no source changes
npx cdk diff --context env=dev    # should report "no differences"

# After GHA deploys :abc123:
aws ecs describe-services --cluster app-dev --services app-dev-foo \
  --query 'services[0].deployments[?status==`PRIMARY`].taskDefinition'

# Re-run cdk diff:
npx cdk diff --context env=dev ExampleService-dev-foo
# Should still be "no differences" — the image is fed back in.
```

## References

- AWS SDK docs: <https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/client/ecs/command/DescribeTaskDefinitionCommand/>
