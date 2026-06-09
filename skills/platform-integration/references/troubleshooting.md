# Troubleshooting Reference — Cross-Layer Debug Guide

Step-by-step trace procedures, symptom-cause tables, and debug commands for diagnosing
delivery failures across Tekton, Shipwright, Quay, Argo CD, Istio, Argo Rollouts,
and gitops-promoter.

---

## "My Change Isn't in Production" — End-to-End Trace

Walk through each layer in order. Stop at the first failure.

### Step 1: Is the commit in the Git repo?

```bash
# Check if the commit exists on the target branch
git log --oneline -10 origin/main

# If using a PR workflow, verify the PR was merged
gh pr list --state merged --limit 5
```

**If NO:** The code was never merged. Check PR status, approval gates, CI checks.

### Step 2: Did the pipeline trigger?

```bash
# List recent PipelineRuns for the pipeline
oc get pipelinerun -l tekton.dev/pipeline=<pipeline-name> \
  --sort-by=.metadata.creationTimestamp -n <namespace> | tail -5

# If using Pipeline-as-Code, check the Repository CR
oc get repository -n <namespace>
oc describe repository <name> -n <namespace> | grep -A5 "Status"

# Check EventListener logs for webhook delivery
oc logs deployment/el-<eventlistener-name> -n <namespace> --tail=50
```

**If NO PipelineRun exists:**
- Webhook not configured or not firing (check GitHub/GitLab webhook delivery logs)
- EventListener not matching the event (wrong TriggerBinding filter)
- Pipeline-as-Code not installed or Repository CR missing

### Step 3: Did the build succeed?

```bash
# Shipwright BuildRun
oc get buildrun -n <namespace> --sort-by=.metadata.creationTimestamp | tail -5
oc describe buildrun <name> -n <namespace> | grep -A10 "Conditions"

# If using Tekton buildah task instead
oc get taskrun -l tekton.dev/task=buildah -n <namespace> | tail -5
oc logs <taskrun-pod> -c step-build -n <namespace> --tail=100
```

**Common build failures:**
- Push denied — wrong registry credentials or expired robot account token
- OOM killed — increase resource limits on BuildStrategy or Task step
- Source clone failed — SSH key not mounted, wrong branch reference

### Step 4: Is the image in the registry?

```bash
# Inspect image in Quay / any OCI registry
skopeo inspect docker://<registry>/<org>/<repo>:<tag> --tls-verify=false

# Check OpenShift ImageStream (if using internal registry)
oc get imagestream <name> -n <namespace> -o jsonpath='{.status.tags[*].tag}'

# Verify the exact tag that the pipeline produced
oc get buildrun <name> -n <namespace> \
  -o jsonpath='{.status.output.digest}'
```

**If image is missing:** Build pushed to a different tag or registry URL. Compare
the BuildRun/TaskRun output parameters with the expected image reference.

### Step 5: Did the GitOps repo get updated?

```bash
# Check the manifests repo for the new image tag
git -C /path/to/gitops-repo log --oneline -5

# If pipeline updates the repo, check the git-cli TaskRun
oc get taskrun -l tekton.dev/task=git-cli -n <namespace> | tail -3
oc logs <taskrun-pod> -c step-git -n <namespace> --tail=50

# Check if Argo CD Image Updater updated the tag (if used instead of pipeline)
oc logs deployment/argocd-image-updater -n openshift-gitops --tail=50 \
  | grep <app-name>
```

**If NOT updated:**
- Pipeline `git-cli` task failed silently (check its logs)
- Git credentials expired or wrong permissions
- Image Updater not configured for this Application or tag pattern not matching

### Step 6: Did Argo CD sync?

```bash
# CLI (if argocd is configured)
argocd app get <app-name> --output json | jq '{sync: .status.sync, health: .status.health}'

# kubectl fallback
oc get application <app-name> -n openshift-gitops \
  -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'

# Check sync history
oc get application <app-name> -n openshift-gitops \
  -o jsonpath='{range .status.history[*]}{.id} {.revision} {.deployedAt}{"\n"}{end}'

# Check for sync errors
oc get application <app-name> -n openshift-gitops \
  -o jsonpath='{.status.conditions[*].message}'
```

**If not synced:**
- Auto-sync disabled and no manual sync triggered
- Webhook from Git to Argo CD not configured (Argo CD polls every 3 min by default)
- Application path doesn't match where the image tag was updated
- Sync failed — check `.status.conditions` for the error

### Step 7: Is the mesh routing traffic?

```bash
# Check VirtualService weights
oc get virtualservice <name> -n <namespace> \
  -o jsonpath='{range .spec.http[*].route[*]}{.destination.host}:{.weight}{"\n"}{end}'

# Verify the sidecar is injected
oc get pod -l app=<app> -n <namespace> -o jsonpath='{.items[0].spec.containers[*].name}'
# Should include "istio-proxy"

# Check if namespace has the istio-injection label
oc get namespace <namespace> -o jsonpath='{.metadata.labels.istio-injection}'
```

**If traffic not routing:**
- VirtualService weight still at 0 for the new version (Rollout hasn't progressed)
- Namespace missing `istio-injection=enabled` label — sidecar not injected
- DestinationRule subsets don't match pod labels

### Step 8: Is the Rollout progressing?

```bash
# Argo Rollouts CLI
kubectl argo rollouts get rollout <name> -n <namespace>

# kubectl fallback
oc get rollout <name> -n <namespace> \
  -o jsonpath='{.status.phase} {.status.message}{"\n"}'

# Check AnalysisRun results
oc get analysisrun -l rollouts-pod-template-hash -n <namespace> \
  --sort-by=.metadata.creationTimestamp | tail -5
oc get analysisrun <name> -n <namespace> -o jsonpath='{.status.phase}'
```

**If Rollout is paused or aborted:**
- AnalysisRun failed — check its metric results and queries
- Manual approval gate not granted
- Rollout aborted due to error rate threshold exceeded

### Step 9: Is the promoter advancing?

```bash
# Check PromotionStrategy status
oc get promotionstrategy <name> -n <namespace> -o yaml | grep -A20 "status:"

# Check CommitStatus CRs
oc get commitstatus -n <namespace>

# Check if the required commit statuses have reported
oc get promotionstrategy <name> -n <namespace> \
  -o jsonpath='{.spec.environments[*].autoMerge.commitStatuses[*]}'
```

**If promoter is not advancing:**
- Required commit status not reported (pipeline didn't push status, or wrong context key)
- CommitStatus CR key name doesn't match what the pipeline reports
- Previous environment's health gate not met

---

## Per-Layer Symptom-Cause Table

### Tekton / Pipelines

| Symptom | Likely Cause | Debug Command |
|---------|-------------|---------------|
| PipelineRun stuck `Running` | Task waiting on workspace PVC binding | `oc describe pipelinerun <name> -n <ns>` |
| PipelineRun `Failed` immediately | ServiceAccount missing or RBAC insufficient | `oc get sa <sa> -n <ns>; oc auth can-i --as=system:serviceaccount:<ns>:<sa> create pods` |
| Task `step-git-clone` fails | SSH key not mounted or Git URL wrong | `oc logs <pod> -c step-clone -n <ns> --tail=50` |
| EventListener returns 404 | TriggerBinding/TriggerTemplate names don't match | `oc logs deployment/el-<name> -n <ns> --tail=50` |
| PipelineRun not created on push | Webhook delivery failing or CEL filter rejecting | Check GitHub webhook delivery tab; `oc logs deployment/el-<name>` |

### Shipwright / Builds

| Symptom | Likely Cause | Debug Command |
|---------|-------------|---------------|
| BuildRun `Failed` with push error | Registry credentials missing or expired | `oc get secret <push-secret> -n <ns> -o jsonpath='{.data.\.dockerconfigjson}' \| base64 -d` |
| BuildRun OOM killed | BuildStrategy resource limits too low | `oc describe buildrun <name> -n <ns> \| grep -A5 Resources` |
| BuildRun stuck `Pending` | No node capacity or PVC not bound | `oc describe pod <buildrun-pod> -n <ns> \| grep Events -A20` |
| Source clone fails | Wrong Git ref or missing SSH key | `oc describe buildrun <name> -n <ns> \| grep -A5 Source` |

### Argo CD / GitOps

| Symptom | Likely Cause | Debug Command |
|---------|-------------|---------------|
| Application `OutOfSync` but won't sync | Auto-sync disabled or sync error | `argocd app get <name>` or `oc get app <name> -n openshift-gitops -o jsonpath='{.status.conditions}'` |
| Sync `Error` | Invalid manifests or CRD not installed | `argocd app sync <name> --dry-run` or check `.status.sync.comparedTo.source` |
| Application `Missing` | Namespace doesn't exist or RBAC prevents creation | `oc get ns <target-ns>; oc auth can-i create deployments -n <target-ns> --as=system:serviceaccount:openshift-gitops:argocd-application-controller` |
| Application `Unknown` health | No health check defined for CRD | Check `argocd-cm` for `resource.customizations.health` |
| Sync succeeds but old pods running | Image pull policy `IfNotPresent` with same tag | Use digest-based references or unique tags |

### Istio / Service Mesh

| Symptom | Likely Cause | Debug Command |
|---------|-------------|---------------|
| 503 errors | Sidecar not injected or namespace missing `istio-injection=enabled` label | `oc get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].name}'` |
| Connection refused | PeerAuthentication strict but client has no sidecar | `oc get peerauthentication -n <ns>` |
| mTLS handshake failure | Certificate expired or root CA mismatch | `istioctl proxy-config secret <pod> -n <ns>` |
| Traffic not shifting | VirtualService not applied or subset labels wrong | `oc get vs -n <ns> -o yaml; oc get dr -n <ns> -o yaml` |
| Kiali shows red edges | Upstream returning errors, not mesh issue | Check application logs directly |

### Argo Rollouts

| Symptom | Likely Cause | Debug Command |
|---------|-------------|---------------|
| Rollout `Paused` | Waiting for manual promotion or analysis | `kubectl argo rollouts get rollout <name> -n <ns>` |
| Rollout `Degraded` | New ReplicaSet pods crashing | `oc get pods -l rollouts-pod-template-hash -n <ns>; oc logs <pod> -n <ns>` |
| AnalysisRun `Failed` | Metric query returned error or value exceeded threshold | `oc get analysisrun <name> -n <ns> -o yaml \| grep -A20 metricResults` |
| Rollout aborted | Error rate exceeded abort threshold | `kubectl argo rollouts get rollout <name> -n <ns> --watch` |
| Traffic not shifting with Istio | VirtualService not owned by Rollout | Check `spec.strategy.canary.trafficRouting.istio` in Rollout spec |

### gitops-promoter

| Symptom | Likely Cause | Debug Command |
|---------|-------------|---------------|
| Promotion not advancing | Required commit status not reported | `oc get commitstatus -n <ns>` |
| Wrong environment promoted | Environment order wrong in PromotionStrategy | `oc get promotionstrategy <name> -n <ns> -o yaml \| grep -A30 environments` |
| PR not created | Git credentials invalid or branch protection rules | Check promoter controller logs: `oc logs deployment/promoter-controller -n <ns>` |

---

## Cross-Layer Issues

These are the most common multi-tool problems where the failure is in the handoff
between layers, not within a single tool.

### 1. Pipeline succeeds but GitOps repo not updated

**Cause:** The `git-cli` task at the end of the pipeline is missing, misconfigured,
or using expired Git credentials.

```bash
# Check if the pipeline has a git-cli task
oc get pipeline <name> -n <ns> -o jsonpath='{.spec.tasks[*].taskRef.name}' | tr ' ' '\n'

# Check the git-cli TaskRun
oc get taskrun -l tekton.dev/pipelineTask=update-gitops -n <ns> | tail -3
oc logs <taskrun-pod> -c step-git -n <ns> --tail=50

# Verify Git credentials
oc get secret git-credentials -n <ns> -o jsonpath='{.data.password}' | base64 -d | wc -c
```

**Fix:** Ensure the pipeline includes a `git-cli` or custom task that commits the
new image tag to the GitOps repo. Verify the Git token has write access to the
manifests repository (not just the source repo).

### 2. GitOps repo updated but Argo CD doesn't sync

**Cause:** Argo CD webhook not configured (relying on polling, which defaults to
3-minute interval), or Application `spec.source.path` doesn't match where the
image tag was updated.

```bash
# Check if webhook is configured
oc get secret argocd-github-webhook -n openshift-gitops 2>/dev/null && echo "Webhook secret exists" || echo "No webhook configured"

# Verify the Application source path
oc get application <name> -n openshift-gitops \
  -o jsonpath='{.spec.source.repoURL} {.spec.source.path} {.spec.source.targetRevision}'

# Force a refresh
argocd app get <name> --refresh
```

**Fix:** Configure a Git webhook to Argo CD (recommended) or reduce the poll interval.
Ensure `spec.source.path` matches the directory where the pipeline updated the image tag.

### 3. Argo CD syncs but pods not updated

**Cause:** Image pull policy set to `IfNotPresent` with a mutable tag (e.g., `latest`),
so Kubernetes uses the cached image. Or the image tag in the Deployment doesn't match
what was pushed.

```bash
# Check the image in the running pod vs the Deployment spec
oc get deployment <name> -n <ns> -o jsonpath='{.spec.template.spec.containers[0].image}'
oc get pod -l app=<name> -n <ns> -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'

# Check pull policy
oc get deployment <name> -n <ns> -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}'
```

**Fix:** Use unique, immutable tags (SHA-based or semantic versions, never `latest`).
Set `imagePullPolicy: Always` if you must use mutable tags. Prefer digest-based
references: `image: quay.io/org/app@sha256:abc123...`.

### 4. Mesh configured but 503 errors

**Cause:** Namespace missing `istio-injection=enabled` label, so sidecar proxy is not
injected. Or PeerAuthentication is set to `STRICT` mTLS but the calling service
has no sidecar.

```bash
# Check namespace injection label
oc get namespace <namespace> -o jsonpath='{.metadata.labels.istio-injection}'
# Should return "enabled"

# Check sidecar presence
oc get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.containers[*].name}{"\n"}{end}' | grep -v istio-proxy

# Check PeerAuthentication mode
oc get peerauthentication -n <namespace> -o jsonpath='{.items[*].spec.mtls.mode}'
```

**Fix:** Label the namespace with `oc label namespace <ns> istio-injection=enabled`.
If using strict mTLS, ensure all communicating services have sidecars injected.

### 5. Rollout healthy but promoter doesn't advance

**Cause:** The commit status key that the pipeline reports doesn't match the key
expected in the PromotionStrategy `commitStatuses` list. Or the pipeline doesn't
report commit status at all.

```bash
# Check what commit statuses the promoter expects
oc get promotionstrategy <name> -n <ns> \
  -o jsonpath='{range .spec.environments[*]}{.branch}: {.autoMerge.commitStatuses[*]}{"\n"}{end}'

# Check what commit statuses exist
oc get commitstatus -n <ns> -o custom-columns=NAME:.metadata.name,KEY:.spec.key,PHASE:.spec.phase

# Compare the keys
```

**Fix:** Ensure the pipeline's finally task creates a CommitStatus CR with the exact
`spec.key` value that the PromotionStrategy expects. Check for typos, namespace
mismatches, and trailing whitespace in the key name.

### 6. Build pushes but pipeline can't find image

**Cause:** Registry URL mismatch between the build output and the deployment spec.
The Shipwright Build pushes to one URL format while the Tekton task or Deployment
references a different format.

```bash
# Check where the build pushed the image
oc get buildrun <name> -n <ns> -o jsonpath='{.spec.output.image}'

# Check where the deployment expects it
oc get deployment <name> -n <ns> -o jsonpath='{.spec.template.spec.containers[0].image}'

# Common mismatches:
# - quay.io/org/app vs quay-quay-quay.apps.cluster.example.com/org/app
# - image-registry.openshift-image-registry.svc:5000/ns/app vs internal short form
```

**Fix:** Standardize on a single registry URL across all CRDs. Use a parameter or
workspace in the pipeline to pass the exact image reference from the build step to
the gitops-update step. Never hardcode registry URLs in multiple places.

---

## Debug Commands Quick Reference

### Tekton

| Action | CLI Command | `oc`/`kubectl` Fallback |
|--------|------------|------------------------|
| List PipelineRuns | `tkn pipelinerun list -n <ns>` | `oc get pipelinerun -n <ns>` |
| Describe PipelineRun | `tkn pipelinerun describe <name> -n <ns>` | `oc describe pipelinerun <name> -n <ns>` |
| View task logs | `tkn taskrun logs <name> -n <ns>` | `oc logs <taskrun-pod> -c step-<name> -n <ns>` |
| List failed runs | `tkn pipelinerun list --status=Failed -n <ns>` | `oc get pipelinerun -n <ns> --field-selector=status.conditions[0].reason=Failed` |
| Cancel a run | `tkn pipelinerun cancel <name> -n <ns>` | `oc patch pipelinerun <name> -n <ns> --type=merge -p '{"spec":{"status":"CancelledRunFinally"}}'` |

### Shipwright

| Action | CLI Command | `oc`/`kubectl` Fallback |
|--------|------------|------------------------|
| List BuildRuns | `shp buildrun list -n <ns>` | `oc get buildrun -n <ns>` |
| Describe BuildRun | `shp buildrun logs <name> -n <ns>` | `oc describe buildrun <name> -n <ns>` |
| View build logs | `shp buildrun logs <name> -n <ns>` | `oc logs <buildrun-pod> -c step-build -n <ns>` |
| Check Build status | `shp build list -n <ns>` | `oc get build.shipwright.io -n <ns>` |

### Argo CD

| Action | CLI Command | `oc`/`kubectl` Fallback |
|--------|------------|------------------------|
| Get app status | `argocd app get <name>` | `oc get application <name> -n openshift-gitops -o jsonpath='{.status.sync.status} {.status.health.status}'` |
| Sync app | `argocd app sync <name>` | `oc annotate application <name> -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite` |
| View sync history | `argocd app history <name>` | `oc get application <name> -n openshift-gitops -o jsonpath='{.status.history}'` |
| Diff app | `argocd app diff <name>` | (no direct fallback — compare Git manifest to live resource manually) |
| List apps | `argocd app list` | `oc get application -n openshift-gitops` |
| View app logs | `argocd app logs <name>` | `oc logs deployment/<app-deployment> -n <target-ns>` |

### Istio / OSSM

| Action | CLI Command | `oc`/`kubectl` Fallback |
|--------|------------|------------------------|
| Check proxy status | `istioctl proxy-status` | `oc get pods -l istio.io/rev -n <ns>` |
| Inspect proxy config | `istioctl proxy-config routes <pod> -n <ns>` | `oc exec <pod> -c istio-proxy -n <ns> -- pilot-agent request GET config_dump` |
| Analyze mesh config | `istioctl analyze -n <ns>` | (no direct fallback — review VirtualService and DestinationRule manually) |
| Check mTLS status | `istioctl authn tls-check <pod> -n <ns>` | `oc get peerauthentication -n <ns> -o yaml` |
| View Envoy access logs | (configure in Istio CR meshConfig) | `oc logs <pod> -c istio-proxy -n <ns> --tail=100` |

### Argo Rollouts

| Action | CLI Command | `oc`/`kubectl` Fallback |
|--------|------------|------------------------|
| Get rollout status | `kubectl argo rollouts get rollout <name> -n <ns>` | `oc get rollout <name> -n <ns> -o jsonpath='{.status.phase} {.status.message}'` |
| Promote rollout | `kubectl argo rollouts promote <name> -n <ns>` | `oc patch rollout <name> -n <ns> --type=merge -p '{"status":{"pauseConditions":null}}'` |
| Abort rollout | `kubectl argo rollouts abort <name> -n <ns>` | `oc patch rollout <name> -n <ns> --type=merge -p '{"spec":{"abortRollout":true}}'` (check CRD version) |
| Retry rollout | `kubectl argo rollouts retry rollout <name> -n <ns>` | `oc patch rollout <name> -n <ns> --type=merge -p '{"spec":{"restartAt":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}}'` |
| Watch rollout | `kubectl argo rollouts get rollout <name> -n <ns> --watch` | `oc get rollout <name> -n <ns> -o yaml -w` |
| List AnalysisRuns | `kubectl argo rollouts list analysisruns -n <ns>` | `oc get analysisrun -n <ns>` |

### gitops-promoter

| Action | CLI Command | `oc`/`kubectl` Fallback |
|--------|------------|------------------------|
| Check promotion status | — | `oc get promotionstrategy <name> -n <ns> -o yaml` |
| List commit statuses | — | `oc get commitstatus -n <ns>` |
| View promoter logs | — | `oc logs deployment/promoter-controller -n <ns> --tail=100` |
| Check proposed commits | — | `oc get proposedcommit -n <ns>` |

---

## Quick Triage Script

Run this to quickly check all layers for a given application:

```bash
#!/bin/bash
# Usage: ./triage.sh <app-name> <namespace> <gitops-namespace>
APP=${1:?Usage: triage.sh <app> <ns> <gitops-ns>}
NS=${2:?}
GITOPS_NS=${3:-openshift-gitops}

echo "=== Tekton PipelineRuns ==="
oc get pipelinerun -n "$NS" --sort-by=.metadata.creationTimestamp | tail -5

echo -e "\n=== Shipwright BuildRuns ==="
oc get buildrun -n "$NS" --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -5

echo -e "\n=== Argo CD Application ==="
oc get application "$APP" -n "$GITOPS_NS" \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status} revision={.status.sync.revision}{"\n"}' 2>/dev/null

echo -e "\n=== Rollout ==="
oc get rollout "$APP" -n "$NS" \
  -o jsonpath='phase={.status.phase} message={.status.message}{"\n"}' 2>/dev/null

echo -e "\n=== VirtualService Weights ==="
oc get virtualservice "$APP" -n "$NS" \
  -o jsonpath='{range .spec.http[*].route[*]}{.destination.host}:{.weight} {end}{"\n"}' 2>/dev/null

echo -e "\n=== Pod Status ==="
oc get pods -l app="$APP" -n "$NS" -o wide 2>/dev/null

echo -e "\n=== PromotionStrategy ==="
oc get promotionstrategy -n "$NS" 2>/dev/null | head -5

echo -e "\n=== CommitStatus ==="
oc get commitstatus -n "$NS" 2>/dev/null | head -5
```
