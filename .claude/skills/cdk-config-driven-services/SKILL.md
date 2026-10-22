---
name: cdk-config-driven-services
description: Add a new ECS service by adding two TypeScript files. Loader discovers config/services/<name>/{base,env}.ts, merges them into a typed MergedServiceConfig, and feeds it to a single ServiceStack cons...
origin: ECC
triggers: add a service, ServiceBaseConfig, ServiceEnvConfig, MergedServiceConfig, config/services, loadServices, vertical slice services, per-env sizing, cpu memoryMiB
paths:
  - "**/cdk.json"
  - "**/*.ts"
---
# CDK Config-Driven Services

A CDK codebase where adding a new service requires editing `bin/app.ts`, registering a class in a `Stacks.ts` index, *and* writing 200 lines of `new XxxStack(...)` boilerplate is a codebase that will accumulate dead services nobody dares delete. This skill replaces all of that with **two files per service per environment**, plus a loader.

## When to use

- You're growing from 1-2 hand-rolled services to N (where N is "we lost count").
- Service infrastructure is mostly the same shape (ECS Fargate behind shared ALB) with sizing differences across envs.
- Non-CDK engineers want to bump CPU on staging without learning CDK.
- You want PR diffs that show "orders-api prod desiredCount: 2 → 4" instead of a 600-line stack rewrite.

## When NOT to use

- Each service is architecturally different (Lambda vs ECS vs EKS). Don't force them through the same loader.
- You only have one or two services. The loader is overkill.
- Service config has cross-cutting validation that's easier expressed in code than in TS objects.

## The pattern

### 1. Two-tier config: invariants vs sizing

`config/types.ts:115-227` splits service config into `ServiceBaseConfig` (port, healthCheckPath, subdomain — these don't change between dev and prod) and `ServiceEnvConfig` (cpu, memoryMiB, desiredCount, secrets — these absolutely change).

```typescript
export interface ServiceBaseConfig {
  name:            string;
  githubRepo:      string;
  port:            number;
  containerName:   string;
  healthCheckPath: string;
  subdomain:       string;
}

export interface ServiceEnvConfig {
  cpu:          number;
  memoryMiB:    number;
  desiredCount: number;
  // ... rds, redis, secrets, healthCheck overrides
}

export type MergedServiceConfig = ServiceBaseConfig & ServiceEnvConfig;
```

The intersection type `ServiceBaseConfig & ServiceEnvConfig` is the contract every CDK construct downstream consumes. Type errors surface at synth time, not deploy time.

### 2. Loader discovers services by directory listing

`config/loader.ts:47-79`:

```typescript
export function loadServices(env: EnvName): MergedServiceConfig[] {
  const servicesDir = path.join(__dirname, 'services');
  if (!fs.existsSync(servicesDir)) return [];

  const serviceFolders = fs
    .readdirSync(servicesDir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name);

  return serviceFolders.map((folder) => {
    const basePath = path.join(servicesDir, folder, 'base');
    const envPath  = path.join(servicesDir, folder, env);

    if (!fs.existsSync(`${basePath}.ts`) && !fs.existsSync(`${basePath}.js`)) {
      throw new Error(`Missing base config for service "${folder}": ${basePath}.ts`);
    }
    if (!fs.existsSync(`${envPath}.ts`) && !fs.existsSync(`${envPath}.js`)) {
      throw new Error(`Missing "${env}" config for service "${folder}": ${envPath}.ts`);
    }

    const base:        ServiceBaseConfig = (require(basePath).default ?? require(basePath));
    const envOverride: ServiceEnvConfig  = (require(envPath).default  ?? require(envPath));

    return { ...base, ...envOverride } as MergedServiceConfig;
  });
}
```

Directory shape:

```
config/services/
  orders-api/
    base.ts         ← invariants
    dev.ts          ← sizing, secrets for dev
    staging.ts
    prod.ts
  web-app/
    base.ts
    dev.ts
    prod.ts
```

### 3. The merge is a spread, not a deep merge

`{ ...base, ...envOverride }`. Top-level only. Per-env config can override anything in base (rare but legal — e.g. a different `subdomain` in prod). Nested objects are *replaced*, not merged. This is intentional: deep-merge libraries hide bugs ("did `extraEnv.FOO` come from base or env?"). With a spread, the answer is always "the last one wins, top-level".

### 4. The loader fails loudly on missing files

If you create `services/new-service/base.ts` but forget `services/new-service/dev.ts`, synth fails with `Missing "dev" config for service "new-service": .../dev.ts`. No silent skip, no default fallback. New services are born complete or they're not born at all.

### 5. The CDK app iterates the loader output

`bin/app.ts:118-144`:

```typescript
for (const [index, service] of services.entries()) {
  const family       = `app-${envName}-${service.name}`;
  const currentImage = await fetchCurrentImage(envConfig.region, family, service.containerName);

  const serviceStack = new ServiceStack(app, `ExampleService-${envName}-${service.name}`, {
    env:             { account: envConfig.accountId, region: envConfig.region },
    envName, githubOrg: GITHUB_ORG, service,
    vpc: platform.vpc, cluster: platform.cluster,
    albListener: platform.albListener, albSg: platform.albSg,
    listenerPriority: (index + 1) * 10,
    currentImage,
    // ...
  });
  serviceStack.addDependency(platform);
}
```

`bin/app.ts` is closed for modification once the loop is in place. Adding `payments-api` is two files in `config/services/payments-api/`. No diff to the entry point.

## Common gotchas / variants

**Listener priorities must be unique per ALB.** The pattern uses `(index + 1) * 10` so priorities are 10, 20, 30, … with gaps of 10 for inserts. Don't use `index` directly — priority `0` is invalid. Don't use `Math.random()` — every synth would shuffle the listener rules.

**The merge is shallow on purpose.** If `base.ts` says `extraEnv: { LOG_LEVEL: 'info' }` and `dev.ts` says `extraEnv: { FEATURE_X: 'on' }`, the merged result is `{ FEATURE_X: 'on' }` — `LOG_LEVEL` is gone. Either (a) repeat in every env file, or (b) do the merge inside the construct: `extraEnv: { ...DEFAULTS, ...service.extraEnv }`.

**Don't put secrets in `base.ts`.** Even if the secret ARN is the same across envs (it shouldn't be, but sometimes prod uses a "shared" provider), keep it in `<env>.ts`. Otherwise renaming the secret in one env requires a base-file edit and a coordinated deploy.

**Variant: schema validation.** If you don't trust authors to write valid `ServiceEnvConfig`, validate with Zod inside the loader before returning. The trade-off is a heavier loader vs runtime errors. The TypeScript compiler catches most violations at build time.

## Verification

```bash
# Confirm new service is discovered.
npx cdk ls --context env=dev | grep <service-name>

# Confirm config merges correctly.
node -e "console.log(require('./config/loader').loadServices('dev'))"

# Confirm missing-file error fires.
rm config/services/<service>/dev.ts
npx cdk synth --context env=dev   # should fail with "Missing dev config for service ..."
```
