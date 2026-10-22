---
name: gha-reusable-deploy-pipeline
description: Centralise build-once-deploy-many in a reusable workflow_call. Build a Docker image once as a tar artifact, push per AWS account via OIDC, gate prod with a manual approval driven by a GitHub App to...
origin: ECC
triggers: workflowcall, reusable workflow, secrets inherit, manual-approval, MANUALAPPROVERAPPID, docker save image.tar, build-once-push-many, GHA pipeline, deploy-service.yml
paths:
  - "**/.github/workflows/*.yml"
  - "**/.github/actions/**"
---
# GHA Reusable Deploy Pipeline

A typical "deploy.yml" in every app repo grows to 400 lines — checkout, setup-java, build, login-to-ecr, push, render-task-def, deploy-ecs, repeat for prod. Multiplied across N services it's an unmaintainable blob. This skill describes the alternative: **one reusable workflow in the IaC repo, called from every app repo with five lines of config**.

## When to use

- A monorepo of CDK + multiple application repos sharing one deploy convention.
- Every app builds a Docker image and deploys to ECS Fargate via OIDC.
- You want prod approvals enforced centrally, not bolted onto each repo individually.
- You want to upgrade `aws-actions/configure-aws-credentials` once, not in 30 repos.

## When NOT to use

- Each app deploys differently (one to ECS, one to Lambda, one to EKS). Reusable workflows can carry it but the parameter list explodes.
- The IaC repo and app repos are owned by different orgs / cannot share workflow visibility.
- Single-app projects. Inline the steps.

## The pattern

### 1. Two reusable workflows: `pipeline-service.yml` and `deploy-service.yml`

The full pipeline (build → push-dev → deploy-dev → approve → push-prod → deploy-prod) lives in `pipeline-service.yml`. The "just deploy what's already in ECR" step lives in `deploy-service.yml`. The pipeline calls the deploy workflow internally; app repos can call either.

`.github/workflows/pipeline-service.yml`:

```yaml
on:
  workflow_call:
    inputs:
      service_name:        { required: true,  type: string }
      java_version:        { required: false, type: string, default: '' }
      node_version:        { required: false, type: string, default: '' }
      maven_build_command: { required: true,  type: string }
      default_docker_image_tag: { required: true, type: string }
      aws_region:          { required: false, type: string, default: 'eu-west-1' }
      approvers:           { required: false, type: string, default: 'devops' }
```

App repos call it:

```yaml
jobs:
  test: { ... }   # app-specific tests
  pipeline:
    needs: test
    if: github.ref == 'refs/heads/main' || github.event_name == 'workflow_dispatch'
    uses: your-org/infra/.github/workflows/pipeline-service.yml@main
    with:
      service_name: ${{ vars.SERVICE_NAME }}
      java_version: '25'
      maven_build_command: |
        ./mvnw --batch-mode install -pl app -am -DskipTests
      default_docker_image_tag: app:0.1.0-SNAPSHOT
    secrets: inherit
```

`secrets: inherit` is required — reusable workflows do not see the calling repo's secrets unless inherited. With it, the called workflow has access to the caller's `MANUAL_APPROVER_APP_ID` and `MANUAL_APPROVER_APP_PRIVATE_KEY` org-level secrets transparently.

### 2. Build once, push many — Docker tar artifact

The naive approach builds the image twice: once for dev, once for prod. The result is "we deployed two different images that both passed CI". Build once, push the same artifact to every account.

```yaml
build:
  steps:
    - run: ${{ inputs.maven_build_command }}
    - name: Save image to tar
      run: docker save "${{ inputs.default_docker_image_tag }}" -o image.tar
    - uses: actions/upload-artifact@... # v7
      with:
        name: docker-image-${{ github.sha }}
        path: image.tar
        retention-days: 1

push-dev:
  needs: build
  environment: dev
  permissions: { contents: read, id-token: write }
  steps:
    - uses: actions/download-artifact@v4
      with: { name: docker-image-${{ github.sha }} }
    - run: docker load -i image.tar
    - uses: aws-actions/configure-aws-credentials@... # v6 — assumes dev OIDC role
      with:
        role-to-assume: ${{ vars.GHA_DEPLOY_ROLE }}
    - uses: aws-actions/amazon-ecr-login@... # v2
    - run: |
        IMAGE=${{ vars.ECR_REGISTRY }}/app/${{ inputs.service_name }}-dev:${{ github.sha }}
        docker tag "${{ inputs.default_docker_image_tag }}" "$IMAGE"
        docker push "$IMAGE"
```

### 3. Manual approval — via GitHub App, not default token

`trstringer/manual-approval@v1` posts an issue and waits for an approver from a GitHub team to comment. Listing org team members **requires the `read:org` scope**. The default `GITHUB_TOKEN` doesn't have it. Approvals silently fail with "user not in approver list" until you switch to a GitHub App token.

```yaml
approve-prod:
  needs: deploy-dev
  permissions: { issues: write }
  steps:
    - id: generate_token
      uses: actions/create-github-app-token@v3
      with:
        app-id:      ${{ secrets.MANUAL_APPROVER_APP_ID }}
        private-key: ${{ secrets.MANUAL_APPROVER_APP_PRIVATE_KEY }}
    - uses: trstringer/manual-approval@v1
      with:
        secret:            ${{ steps.generate_token.outputs.token }}
        approvers:         ${{ inputs.approvers }}
        minimum-approvals: 1
```

The GitHub App needs:
- Repository: `Issues: Read & write`.
- Organization: `Members: Read-only` (this is the bit `GITHUB_TOKEN` lacks).

### 4. Per-env concurrency groups

Without concurrency, two simultaneous merges to `main` race ECS deploys. With concurrency keyed by env, the second waits for the first.

Inside `deploy-service.yml` the job-level `environment: ${{ inputs.env_name }}` ties the deploy to a GitHub Environment, which gives free serialization (one in-progress deployment per environment).

### 5. SHA-pinned actions

`aws-actions/configure-aws-credentials@a89a83ec143615402a01f672b6e172b7b1875000 # v6`. Tags move; SHAs don't. A supply-chain attacker who pushes a malicious `v6` tag to `aws-actions/configure-aws-credentials` cannot poison your workflow if you're SHA-pinned.

## Common gotchas / variants

**`secrets: inherit` is necessary for org secrets.** Without it, the reusable workflow can't see `MANUAL_APPROVER_APP_*`. With it, all caller secrets are exposed — review what the called workflow reads.

**ECR repo per env is the simpler trust model.** `app/<service>-dev` in the dev account, `app/<service>-prod` in the prod account. No cross-account image pulls; no replication. The pipeline pushes to whichever ECR matches the assumed role's account.

**The render-task-definition pattern preserves CDK-managed bits.** GHA mutates only the image; the rest of the task definition (CPU, memory, secrets, IAM) comes from what CDK registered. `aws-actions/amazon-ecs-render-task-definition` reads the family's latest revision, swaps the image, and emits a new revision JSON. `aws-actions/amazon-ecs-deploy-task-definition` registers it.

**Strip the placeholder command before deploy.** See the `ecs-cdk-image-drift-prevention` skill — the workflow runs `jq '... |= del(.command)'` so the real image's `CMD` runs, not the busybox `httpd`.

**Required app-repo configuration.** Document this in the IaC repo's README so app authors know what to set up:
- Org-level secrets: `MANUAL_APPROVER_APP_ID`, `MANUAL_APPROVER_APP_PRIVATE_KEY`.
- Per-env vars: `ECR_REGISTRY`, `GHA_DEPLOY_ROLE`.
- Per-env GitHub Environment with required reviewers (extra defence on top of `manual-approval`).

**Variant: `workflow_dispatch` for ad-hoc deploys.** Add `workflow_dispatch` triggers + an `image_tag` input to deploy a specific build out of order. Useful for rollbacks.

## Verification

```bash
# Confirm reusable workflow is syntactically valid:
act -W .github/workflows/pipeline-service.yml --list

# In the app repo, trigger a dry run and watch:
# - build job uploads image.tar
# - push-dev assumes dev role, push to dev ECR
# - deploy-dev calls deploy-service.yml as a nested workflow
# - approve-prod waits with a GitHub App token (verify: comment from app account, not user)
# - push-prod tags + pushes the SAME tar to prod ECR (no rebuild)
# - deploy-prod registers a new task def revision
```

## References

- `trstringer/manual-approval`: <https://github.com/trstringer/manual-approval>
- `actions/create-github-app-token`: <https://github.com/actions/create-github-app-token>
- GitHub docs: <https://docs.github.com/en/actions/using-workflows/reusing-workflows>
