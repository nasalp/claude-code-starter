---
name: cdk-assertions-testing
description: Unit-test CDK stacks with Template.fromStack, hasResourceProperties, findOutputs, resourceCountIs. Common gotchas - cross-stack references must share an App, exact CFN resource names, match by Expo...
origin: ECC
triggers: Template.fromStack, hasResourceProperties, findOutputs, resourceCountIs, aws-cdk-lib/assertions, cross-stack reference, fake VPC test, AWS::ElastiCache::CacheCluster, HostHeaderConfig
paths:
  - "**/cdk.json"
  - "**/*.ts"
  - "**/*.py"
---
# CDK Assertions Testing

CDK ships `aws-cdk-lib/assertions` — a powerful but undocumented-by-example unit testing framework. The default examples in the AWS docs leave you stranded as soon as your stack has dependencies on shared infrastructure (VPC, cluster, ALB). This skill is a senior reference: how to test stacks that consume other stacks' outputs, where the pitfalls are, and which CFN resource names trip you up.

## When to use

- Any CDK stack with non-trivial config-driven branching (e.g. `if (envConfig.googleOidc)`).
- Refactoring a CDK construct and you want to lock the synthesized template behaviour.
- Catching CFN resource property drift after a `aws-cdk-lib` upgrade.
- Replacing manual "I deployed it and it worked" with reproducible CI tests.

## When NOT to use

- Integration tests of actually deployed AWS resources. Use `cdk deploy` + a smoke test.
- Property-based explorations of CDK behaviour. Use snapshot tests.
- Performance — assertions are fast, but a `Template.fromStack` of a 200-resource stack still takes a second.

## The pattern

### 1. Build a real `cdk.App`, instantiate the real stack, snapshot via `Template.fromStack`

```typescript
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { PlatformStack } from '../lib/stacks/platform-stack';
import { devEnvConfig, DEV_ACCOUNT, DEV_REGION } from './helpers';

const app   = new cdk.App();
const stack = new PlatformStack(app, 'ExamplePlatform-dev', {
  env:       { account: DEV_ACCOUNT, region: DEV_REGION },
  envName:   'dev',
  envConfig:  devEnvConfig,
  githubOrg: 'your-org',
});
const template = Template.fromStack(stack);

template.hasResourceProperties('AWS::Route53::HostedZone', {
  Name: 'beta.example.com.',
});
template.resourceCountIs('AWS::RDS::DBCluster', 1);
```

`Template.fromStack(stack)` synthesises the stack to its CloudFormation JSON and returns a queryable handle. No AWS credentials, no network — pure local synth.

### 2. Cross-stack references must share an `App`

The single most common mistake. If you write:

```typescript
// BAD — fake VPC in its own stack
const supportApp = new cdk.App();
const supportStack = new cdk.Stack(supportApp, 'Support', { ... });
const fakeVpc = ec2.Vpc.fromVpcAttributes(supportStack, 'FakeVpc', { ... });

const app = new cdk.App();
const stack = new ServiceStack(app, 'Svc', { vpc: fakeVpc, ... });
```

Synth fails with "Cannot reference resources across CDK Apps". CDK builds one cross-stack reference graph per `App`. Cross-graph references can't be resolved.

The fix in `test/helpers.ts:51-99`: every fake helper takes the *stack under test* as its scope:

```typescript
/**
 * All fake AWS resources must live in the same stack as the stack under test
 * to avoid cross-stack reference errors during CDK synthesis.
 * Pass the service stack itself as the `scope` for all stubs.
 */
export function makeFakeVpc(scope: cdk.Stack): ec2.IVpc {
  return ec2.Vpc.fromVpcAttributes(scope, 'FakeVpc', {
    vpcId:             'vpc-12345678',
    availabilityZones: ['eu-west-1a', 'eu-west-1b'],
    publicSubnetIds:   ['subnet-pub00001', 'subnet-pub00002'],
    privateSubnetIds:  ['subnet-priv0001', 'subnet-priv0002'],
  });
}

export function makeFakeListener(scope: cdk.Stack): elbv2.IApplicationListener {
  return elbv2.ApplicationListener.fromApplicationListenerAttributes(scope, 'FakeListener', {
    listenerArn:   `arn:aws:elasticloadbalancing:${DEV_REGION}:${DEV_ACCOUNT}:listener/app/app-dev/abc/def`,
    securityGroup: ec2.SecurityGroup.fromSecurityGroupId(scope, 'ListenerSg', 'sg-00000001'),
    defaultPort:   443,
  });
}
```

A single `cdk.App` holds the stack-under-test; the helpers add stub `Construct`s to that same stack. The from-attributes APIs accept arbitrary IDs / ARNs and return `IVpc`/`IApplicationListener` interfaces — synth doesn't try to resolve the IDs against AWS, it just trusts them.

### 3. Match by `Export.Name`, not logical IDs

CDK generates logical IDs with hash suffixes (`CdkDeployRoleArnAB12CD34`). Hashes are deterministic but brittle — they change if you rename a parent construct. Use the export name (which you control) as the stable key:

```typescript
const outputs = template.findOutputs('*', {
  Export: { Name: 'CdkDeployRoleArn-dev' },
});
expect(Object.keys(outputs)).toHaveLength(1);
```

`findOutputs('*', filter)` searches all outputs matching the filter; the returned object is keyed by logical ID. Don't assert on the logical ID — assert on whatever value/Name property identifies the output uniquely.

### 4. CloudFormation resource type names are exact and unforgiving

The CDK abstracts (`new elasticache.CfnReplicationGroup` vs `new elasticache.CfnCacheCluster`) emit *different* CFN types and the assertions API matches by exact string. Common confusions:

| What you wrote in CDK | CFN type that's emitted |
|--|--|
| `elasticache.CfnCacheCluster` (single-node Redis) | `AWS::ElastiCache::CacheCluster` |
| `elasticache.CfnReplicationGroup` (multi-AZ) | `AWS::ElastiCache::ReplicationGroup` |
| `rds.DatabaseCluster` (Aurora) | `AWS::RDS::DBCluster` |
| `rds.DatabaseInstance` (provisioned PG) | `AWS::RDS::DBInstance` |
| `elbv2.ApplicationListenerRule` | `AWS::ElasticLoadBalancingV2::ListenerRule` |

If a count assertion returns 0 unexpectedly, dump the synthesised template and grep for the actual type:

```bash
npx cdk synth --context env=dev ExamplePlatform-dev > /tmp/template.json
jq -r '.Resources | to_entries[] | .value.Type' /tmp/template.json | sort -u
```

### 5. Listener-rule conditions are nested

ALB listener rules use a polymorphic `Conditions` array. Asserting on host-header rules:

```typescript
// WRONG — top-level Values doesn't exist
template.hasResourceProperties('AWS::ElasticLoadBalancingV2::ListenerRule', {
  Conditions: Match.arrayWith([{ Field: 'host-header', Values: ['dashboard.beta.example.com'] }]),
});

// RIGHT — Values lives under HostHeaderConfig
template.hasResourceProperties('AWS::ElasticLoadBalancingV2::ListenerRule', {
  Conditions: Match.arrayWith([
    Match.objectLike({
      Field: 'host-header',
      HostHeaderConfig: { Values: ['dashboard.beta.example.com'] },
    }),
  ]),
});
```

The CFN spec moved from a flat `Values` to typed sub-config objects (`HostHeaderConfig`, `PathPatternConfig`, etc.) and the CDK emits the new form. Assert on the nested key.

### 6. Test config-driven branching, not happy paths

Snapshot tests of "default config produces 47 resources" don't catch the bug where `googleOidc` is misconfigured and the auth action is silently dropped. Useful tests are:

```typescript
test('platform-stack does not create OIDC auth action when googleOidc is absent', () => {
  const stack = new PlatformStack(app, 'Platform', { envConfig: devEnvConfig, ... });
  const template = Template.fromStack(stack);

  template.resourceCountIs('AWS::SecretsManager::Secret', 0); // no Google secret reference
});

test('platform-stack creates OIDC auth action when googleOidc is configured', () => {
  const stack = new PlatformStack(app, 'Platform', { envConfig: devEnvConfigWithOidc, ... });
  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::ElasticLoadBalancingV2::Listener', {
    DefaultActions: Match.arrayWith([
      Match.objectLike({ Type: 'authenticate-oidc' }),
    ]),
  });
});
```

The most valuable assertions are the *negative* ones — they catch silent misconfigurations where a config knob does nothing.

## Common gotchas / variants

**`Match.objectLike` vs exact match.** `hasResourceProperties` is "the template's resource has these properties (and possibly more)". `Match.objectEquals` requires exact match. Use `objectLike` unless you specifically need exhaustiveness.

**Don't snapshot the whole template.** Jest snapshot tests on `template.toJSON()` flag every cosmetic CDK upgrade as a diff. Assert on the properties you care about.

**Assertions on `Fn::GetAtt` / `Ref`.** Cross-stack references in CFN are intrinsic functions. Use `Match.objectLike({ Ref: 'logicalId' })` or `Match.objectLike({ 'Fn::GetAtt': ['logicalId', 'Arn'] })` to match them.

**Tags are merged automatically.** If your CDK app applies stack-level tags via `Tags.of(app).add(...)`, expect the tag in every resource that supports tagging. Either add it to your matcher or use `Match.objectLike` to ignore.

## Verification

```bash
npm test                           # run all jest tests
npm test -- platform-stack.test    # one test file
npx tsc --noEmit                   # type-check the test code itself

# When a count assertion is suspicious:
npx cdk synth --context env=dev ExamplePlatform-dev > /tmp/t.json
jq '.Resources | to_entries[] | {id: .key, type: .value.Type}' /tmp/t.json
```

## References

- AWS CDK assertions: <https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.assertions-readme.html>
