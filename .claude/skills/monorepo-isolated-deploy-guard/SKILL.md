---
name: monorepo-isolated-deploy-guard
description: Stop file:../ cross-package deps from breaking isolated CodeDeploy/Lambda installs by combining a CI guard, vendor-bundling, hardened install scripts, and a strict ValidateService HTTP 2xx hook
origin: ECC
triggers: file:../, file:./vendor, npm ci, npm i -f, npm install --force, CodeDeploy, codepipeline, appspec.yml, ValidateService, afterinstall.sh, sync-vendor-observability.sh, check-file-deps.sh
paths:
  - "**/package.json"
  - "**/.github/workflows/*.yml"
---
# Monorepo Isolated-Deploy Guard

Monorepos make `file:../../packages/x` look harmless because CI always sees the parent directories. EC2 CodeDeploy (and any per-service Lambda zip) sees only one service directory, so `file:../` resolves to nothing and `npm install --force` will silently warn instead of failing. In one production monorepo this exact pattern shipped a broken observability bundle to five services on 2026-04-16. This skill encodes the seven defenses we now require.

## When to use

- Your monorepo has shared internal packages and any service deploys in isolation (CodeDeploy on EC2, per-service Lambda zip, container build that copies one service dir).
- You are tempted to `npm install` a sibling workspace as `file:../../packages/foo`.
- You are reviewing a PR that adds a new shared package or wires a new service to a monorepo dependency.

## When NOT to use

- Pure single-service repos with no monorepo structure.
- Workspaces where every deploy artifact is the entire monorepo tar (the `file:` path resolves on the target host too).

## The pattern

Seven layered defenses. None alone is sufficient — the incident proved each one separately was bypassable.

### 1. Vendor-bundle into the service directory

Every service that consumes a shared internal package must own a copy of it under `services/<svc>/vendor/<pkg>/` and reference it as `file:./vendor/<pkg>` — never `file:../`. The directory layout makes the dependency self-contained inside the deploy zip.

### 2. CI guard blocks `file:../` at PR time

`scripts/check-file-deps.sh` auto-discovers EC2 services (any service directory containing `.codepipeline/`) and parses every `package.json` with Node:

```bash
EC2_SERVICES=()
for svc_dir in "$REPO_ROOT"/services/*/; do
  svc_name=$(basename "$svc_dir")
  [[ " $EXEMPT_SERVICES " == *" $svc_name "* ]] && continue
  if [ -d "$svc_dir/.codepipeline" ]; then
    EC2_SERVICES+=("$svc_name")
  fi
done
```

The Node check fails closed on parse error, so a malformed package.json fails the build instead of passing silently. The guard reports any spec starting with `file:../` and exits 1.

### 3. Vendor sync script keeps copies fresh

`scripts/sync-vendor-observability.sh` auto-discovers any service that already has `vendor/observability/` and replaces it with a fresh copy from `packages/observability/`. Discovery prevents drift: opting a service in is a one-time `mkdir vendor/observability`; after that the script handles updates.

```bash
for dest in "$REPO_ROOT"/services/*/vendor/observability; do
  [ -d "$dest" ] || continue
  rm -rf "$dest"
  mkdir -p "$dest/src"
  cp "$SRC/package.json" "$dest/"
  cp "$SRC/index.js"     "$dest/"
  cp -r "$SRC/src/."     "$dest/src/"
done
```

### 4. Deploy scripts must `set -euo pipefail` and use `npm ci`

The old `after_install.sh` had no `set -e` and ran `npm install --force`, which downgrades errors to warnings. The fixed scripts begin with:

```bash
#!/bin/bash
set -euo pipefail
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

and use `npm ci` (which fails when the lockfile is unsatisfiable) instead of `npm i -f`.

### 5. `ValidateService` hook in `appspec.yml`

CodeDeploy considers a deploy successful as soon as `ApplicationStart` exits zero. Without a `ValidateService` hook a process that crashes on first request gets marked green. Every EC2 service's `appspec.yml` must register one:

```yaml
ValidateService:
  - location: ./.codepipeline/validate_service.sh
    timeout: 120
    runas: ubuntu
```

### 6. Health check requires HTTP 2xx, not "any response"

Patterns like `curl -s URL | grep -q .` accept HTTP 500 error pages as healthy. The validator must capture the status:

```bash
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  "http://localhost:${HEALTH_PORT}/healthz" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then HEALTH_OK=true; fi
```

The full check additionally verifies the PM2 process is `online`, the symlink target is a real directory, `node_modules` exists, `ecosystem.config.js` is present, and the `pm2-ubuntu` systemd service is enabled.

### 7. Prod-parity isolated-install test

`tests/deploy-parity/test-isolated-install.sh` simulates the EC2 layout: copy a single service directory into a clean tmpdir without parents, run the same `after_install.sh`, and assert it succeeds and the health endpoint returns 2xx. CI runs this on every PR. It is the only check that catches `file:../` resolution failures, because regular CI sees the full monorepo and they always resolve there.

## Common gotchas / variants

- A pre-push hook that's been "committed already commented out" is not a defense. Re-enable it and treat it as belt-and-braces only.
- Branch protection on `main` must require the `check-file-deps.sh` and isolated-install statuses; CodePipeline is webhook-driven and ignores GitHub Actions status by default.
- `npm i -f` and `--legacy-peer-deps` both mask resolution failures. Disallow both in deploy scripts; reserve them for local triage with explicit comments.
- AllAtOnce CodeDeploy + no auto-rollback compounds the blast radius. Move to OneAtATime + auto-rollback in the AWS console.
- Lambda-deployed services don't deploy in isolation in the same way; the guard maintains a `EXEMPT_SERVICES` allowlist for them.
- Don't add a `vendor/<pkg>` directory and forget to add the package to the sync script's expected list — auto-discovery handles the sync, but make sure the original `package.json` has been updated to `file:./vendor/<pkg>` at the same time.

## Verification

- `bash scripts/check-file-deps.sh` from repo root — must print `OK: All N EC2 services have clean dependency references.`
- `bash tests/deploy-parity/test-isolated-install.sh dashboard-v2` — exits 0 and the simulated service answers a 2xx on `/healthz`.
- `bash scripts/sync-vendor-observability.sh` is idempotent; running it twice should produce no diff.
- `aws deploy get-deployment --deployment-id ...` reports `LifecycleEvents[ValidateService] = Succeeded` after a real deploy.
