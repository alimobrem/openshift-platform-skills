---
name: platform-engineering
description: >
  Unified platform engineering skill for OpenShift delivery pipelines covering
  Shipwright builds, Tekton pipelines, Quay registry, External Secrets Operator,
  Istio/OSSM service mesh, Argo Rollouts progressive delivery, and gitops-promoter
  environment promotion. Generates, reviews, debugs, and explains CRDs across all
  layers. Routes Argo CD questions to argo-skills. Optional components (registry,
  secrets, build, mesh) are swappable — defaults adapt when the user specifies
  alternatives. Use when users ask about container builds, CI/CD pipelines, service
  mesh configuration, platform onboarding, DORA metrics, end-to-end delivery flows,
  or cross-layer debugging on OpenShift.
license: MIT
compatibility: Requires oc or kubectl; optionally tkn, kn, istioctl, helm
---

# OpenShift Platform Engineering

A unified skill for designing, building, and operating a complete delivery platform
on OpenShift. Covers the full lifecycle from source code to production traffic: container
builds (Shipwright), CI/CD pipelines (Tekton), image registry (Quay), secrets management
(External Secrets Operator), GitOps sync (delegates to argo-skills), service mesh
(Istio/OSSM), progressive delivery (Argo Rollouts), environment promotion (gitops-promoter),
and DORA metrics. Each layer has its own reference doc; the skill routes questions to the
right one and understands how the layers connect.

## Delivery Lifecycle

```
Code pushed ──> Shipwright builds image ──> Tekton pipeline runs tests/scans
                                              |
                                              v
                              Tekton updates GitOps repo (image tag)
                                              |
                                              v
                              Argo CD syncs to cluster (argo-skills)
                                              |
                                              v
                              Istio routes traffic (VirtualService)
                                              |
                                              v
                              Argo Rollouts shifts weight (canary/blue-green)
                                              |
                                              v
                              gitops-promoter gates promotion to next env
                                              |
                                              v
                              DORA metrics track delivery performance
```

## Rules

1. **Always use correct apiVersion and kind.** Every CRD example must use the real
   apiVersion from the CRD table below. Never invent CRDs or apiVersions.
2. **Load references on-demand.** Only read reference files when the user's question
   requires detailed field-level knowledge. Do not preload all references.
3. **Max 1-2 reference files per question.** Keep context focused. If a question spans
   more than two reference areas, answer the primary question first and offer to elaborate.
4. **Validate YAML before presenting.** Every YAML example must be syntactically valid
   and use real field names from the CRD schemas.
5. **Prefer canonical patterns.** Use patterns from reference docs as starting points.
   Adapt to the user's specifics rather than inventing from scratch.
6. **State trade-offs.** When recommending an approach, briefly note what you give up.
7. **Ask about optional components when ambiguous.** If the user's prompt does not
   specify registry, secrets, build, or mesh tooling, ask which they use before
   generating YAML with defaults.
8. **Redirect Argo CD questions to argo-skills.** This skill does not duplicate Argo CD
   Application, ApplicationSet, or AppProject reference material.

## How This Skill Works

| User asks about | Reference | Layer |
|-----------------|-----------|-------|
| Builds, images, Buildah, BuildConfig, Shipwright | `references/shipwright.md` | Build |
| Pipelines, Tasks, Triggers, CI, OpenShift Pipelines | `references/tekton.md` | Pipeline |
| Registry, Quay, Harbor, image push, robot accounts | `references/quay.md` | Registry |
| Secrets, Vault, ESO, ExternalSecret, credentials | `references/external-secrets.md` | Secrets |
| Mesh, mTLS, traffic, VirtualService, Kiali, OSSM | `references/istio.md` | Mesh |
| Full flow, end-to-end, "set up everything" | `references/delivery-flows.md` | Integration |
| New team, onboarding, namespace setup | `references/platform-onboarding.md` | Onboarding |
| DORA, metrics, dashboards, deployment frequency | `references/dora-metrics.md` | Metrics |
| Debug, trace, "why isn't my change in prod" | `references/troubleshooting.md` | Debug |
| Argo CD, Applications, Rollouts, Workflows | Redirect to `argo-skills` | GitOps |

Load the matching reference file before answering. Max 1-2 reference files per request.

## Optional Components

The skill has a default stack but supports swapping components. When the user specifies
an alternative, the skill adapts YAML and integration patterns accordingly.

| Layer | Default | Alternatives |
|-------|---------|-------------|
| Registry | **Quay** | Harbor, OpenShift internal registry, ECR, GCR, GHCR, Docker Hub |
| Secrets | **External Secrets Operator** | Vault (direct), Sealed Secrets, SOPS, AWS Secrets Manager |
| Build | **Shipwright** | Tekton Buildah task, BuildConfig (legacy), Kaniko |
| Mesh | **Istio / OSSM** | No mesh (replica-based canary only) |

**The skill asks which components the user has if the prompt is ambiguous.** It does not
assume defaults without checking. When the user says "we use Harbor," generate
Harbor-specific push secrets, robot accounts, and registry URLs instead of Quay equivalents.
When the user says "no mesh," generate Rollouts without `trafficRouting`.

## Relationship to argo-skills

- **argo-skills** = GitOps engine (Argo CD, Rollouts, Workflows, Events)
- **openshift-platform-skills** = platform wrapper (builds, pipelines, mesh, metrics, onboarding)
- When the user asks an Argo CD question, this skill redirects to argo-skills.
- When the user asks "set up the full delivery flow," this skill orchestrates across all layers.
- Both repos can be installed as separate plugins -- they complement, not conflict.

## Prerequisites

Before any cluster operation, check the environment:

```bash
# Required
command -v kubectl >/dev/null && echo "kubectl: $(kubectl version --client -o json 2>/dev/null | grep gitVersion)" || echo "kubectl: MISSING"

# Platform detection
kubectl api-resources --api-group=route.openshift.io 2>/dev/null && echo "OpenShift" || echo "Kubernetes"

# Optional -- enhances capabilities
command -v oc >/dev/null && echo "oc: $(oc version --client 2>/dev/null)" || echo "oc: not installed"
command -v tkn >/dev/null && echo "tkn: $(tkn version 2>/dev/null | head -1)" || echo "tkn: not installed"
command -v istioctl >/dev/null && echo "istioctl: $(istioctl version --remote=false 2>/dev/null)" || echo "istioctl: not installed"
command -v helm >/dev/null && echo "helm: $(helm version --short 2>/dev/null)" || echo "helm: not installed"
command -v argocd >/dev/null && echo "argocd: $(argocd version --client -o json 2>/dev/null | grep Version)" || echo "argocd: not installed"

# Cluster context
kubectl config current-context
kubectl cluster-info --request-timeout=5s 2>/dev/null || echo "WARN: cluster not reachable"
```

If the cluster is not reachable, stop and report the error. Do not generate apply commands
for a cluster you cannot validate against.

## Safety Model

**Every write operation follows a 3-step protocol: Generate, Preview, Confirm.**

**Read-only operations** (health checks, audits, metrics queries, DORA dashboards) do NOT
require confirmation -- execute them and report results. The safety model applies only to
operations that modify cluster or repo state.

### Step 1: Generate

Produce the YAML manifest or CLI command for the requested operation. Show it to the
user in a fenced code block. Do not execute anything yet.

### Step 2: Preview

Show what the operation would change on the cluster before applying:

| Operation | Preview Command |
|-----------|----------------|
| Create resource | `kubectl apply --dry-run=client -f <file> -o yaml` |
| Create resource (server-validated) | `kubectl apply --dry-run=server -f <file> -o yaml` |
| Update resource | `kubectl diff -f <file>` or `oc diff -f <file>` |
| Helm install/upgrade | `helm template` or `helm upgrade --dry-run` |
| Delete resource | `kubectl get <kind> <name> -n <ns>` (show what exists) |
| Pipeline run | `tkn pipeline start --dry-run` (show PipelineRun YAML) |
| Build run | `kubectl apply --dry-run=client -f <buildrun>` |

Show the preview output to the user. Explain what will change in plain language.

### Step 3: Confirm

Ask the user explicitly: **"Apply this? (yes/no)"**

Do not proceed without an affirmative response. Acceptable confirmations: "yes", "y",
"apply", "do it", "go ahead", "ship it". Anything else is a no.

### Safety Rules

1. **NEVER apply without showing the user what will change first.** No silent writes.
2. **NEVER delete resources without listing what will be removed.** Show kind, name,
   namespace, and age of each resource before deletion.
3. **For destructive operations (delete, prune, rollback), require the user to type
   the resource name.** Do not accept "yes" alone. Ask:
   "Type the resource name `<name>` to confirm deletion."
4. **Log every applied change.** After each successful apply, report:
   `[APPLIED] <timestamp> <kind>/<namespace>/<name> -- <action>`
5. **If a command fails, show the error and suggest recovery.** Do not retry
   automatically. Let the user decide.
6. **NEVER modify Secrets containing credentials directly.** Generate the Secret
   manifest and let the user apply it, or use `kubectl create secret --dry-run=client`.
7. **NEVER run `kubectl delete --all` or `kubectl delete ns` without explicit
   confirmation of the namespace name and a list of resources that will be destroyed.**

### Destructive Operations Checklist

Before executing any destructive operation, verify:

- [ ] The current cluster context is correct (`kubectl config current-context`)
- [ ] The target namespace is correct
- [ ] The resource exists and is the right one
- [ ] The user has explicitly confirmed with the resource name
- [ ] A preview of what will be removed has been shown

## CRD Reference Table

| Kind | apiVersion | Project |
|------|-----------|---------|
| Build | shipwright.io/v1beta1 | Shipwright |
| BuildRun | shipwright.io/v1beta1 | Shipwright |
| BuildStrategy | shipwright.io/v1beta1 | Shipwright |
| ClusterBuildStrategy | shipwright.io/v1beta1 | Shipwright |
| Pipeline | tekton.dev/v1 | Tekton Pipelines |
| PipelineRun | tekton.dev/v1 | Tekton Pipelines |
| Task | tekton.dev/v1 | Tekton Pipelines |
| TaskRun | tekton.dev/v1 | Tekton Pipelines |
| EventListener | triggers.tekton.dev/v1beta1 | Tekton Triggers |
| TriggerBinding | triggers.tekton.dev/v1beta1 | Tekton Triggers |
| TriggerTemplate | triggers.tekton.dev/v1beta1 | Tekton Triggers |
| ServiceMeshControlPlane | maistra.io/v2 | OSSM |
| ServiceMeshMemberRoll | maistra.io/v1 | OSSM |
| VirtualService | networking.istio.io/v1 | Istio |
| DestinationRule | networking.istio.io/v1 | Istio |
| Gateway | networking.istio.io/v1 | Istio |
| PeerAuthentication | security.istio.io/v1 | Istio |
| AuthorizationPolicy | security.istio.io/v1 | Istio |
| QuayRegistry | quay.redhat.com/v1 | Quay |
| SecretStore | external-secrets.io/v1beta1 | ESO |
| ClusterSecretStore | external-secrets.io/v1beta1 | ESO |
| ExternalSecret | external-secrets.io/v1beta1 | ESO |
| ClusterExternalSecret | external-secrets.io/v1beta1 | ESO |
| PromotionStrategy | promoter.argoproj.io/v1alpha1 | gitops-promoter |
| ChangeTransferPolicy | promoter.argoproj.io/v1alpha1 | gitops-promoter |
| CommitStatus | promoter.argoproj.io/v1alpha1 | gitops-promoter |

## Reference Index

| Topic | Reference File | When to Load |
|-------|---------------|-------------|
| Build strategies, BuildRun, source types, registry auth, BuildConfig migration | `references/shipwright.md` | Questions about container builds, image building, Shipwright CRDs |
| Pipelines, Tasks, Triggers, Pipeline-as-Code, CI patterns, RBAC | `references/tekton.md` | Questions about CI/CD pipelines, Tekton CRDs, OpenShift Pipelines |
| Quay operator, orgs, robot accounts, Clair scanning, mirroring, swap guide | `references/quay.md` | Questions about image registry, scanning, registry auth |
| ESO install, SecretStore backends, ExternalSecret patterns, rotation, swap guide | `references/external-secrets.md` | Questions about secrets management, Vault, sealed secrets |
| OSSM install, SMCP, mTLS, traffic routing, Kiali, circuit breaking | `references/istio.md` | Questions about service mesh, traffic management, mTLS |
| Golden path, variant flows, wiring diagram, secrets flow, 3-env delivery | `references/delivery-flows.md` | Questions about end-to-end delivery, full platform setup |
| Team onboarding, namespace setup, self-service, guard rails | `references/platform-onboarding.md` | Questions about onboarding teams or applications |
| DORA definitions, PromQL queries, Grafana dashboards, PrometheusRule alerts | `references/dora-metrics.md` | Questions about metrics, deployment frequency, MTTR |
| End-to-end trace, per-layer symptoms, cross-layer debug, CLI commands | `references/troubleshooting.md` | Questions about failures, debugging, "why isn't X in prod" |

## Common Mistakes

1. **Using `shipwright.io/v1alpha1` instead of `v1beta1`.** Shipwright graduated to
   v1beta1. Alpha CRDs are removed in recent operator versions.

2. **Tekton Pipeline with no workspace binding.** If the Pipeline declares workspaces
   but the PipelineRun omits `workspaces`, all tasks fail with volume mount errors.

3. **ESO ExternalSecret with wrong SecretStore kind.** Using `kind: SecretStore` when
   the store is `ClusterSecretStore` (or vice versa) causes "store not found" errors.

4. **OSSM ServiceMeshMemberRoll missing the application namespace.** The namespace
   must appear in the SMMR `members` list or Istio sidecars will not be injected.

5. **Pipeline pushes image but doesn't update the GitOps repo.** The pipeline succeeds
   but no deployment happens because the image tag in Git is stale. Always include a
   gitops-update task that commits the new tag.

6. **Quay robot account secret not linked to pipeline ServiceAccount.** The pipeline
   runs as a ServiceAccount that needs `imagePullSecrets` and registry push credentials.
   Without linking, builds succeed but pushes fail with 401.

7. **VirtualService host mismatch.** The VirtualService `hosts` field must match the
   Kubernetes Service name exactly. Mismatches cause 404s with no obvious error.

8. **DestinationRule subsets referencing wrong labels.** If the subset selector does not
   match pod labels, Istio routes to an empty subset and returns 503.

9. **gitops-promoter PromotionStrategy with no CommitStatus source.** Without a
   CommitStatus feeding pipeline results, the promoter never gates promotions and
   auto-promotes everything.

10. **Mixing `kustomize build` and `helm template` in the same Argo CD Application.**
    Use multi-source Applications or pick one. Mixing them in a single source causes
    Argo CD to ignore one renderer silently.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Not an OpenShift cluster (vanilla K8s) | Detect with `kubectl api-resources --api-group=route.openshift.io`. If missing, skip OSSM-specific CRDs (SMCP, SMMR), use upstream Istio CRDs directly, replace `oc` with `kubectl`, and warn that Quay operator may not be available (suggest Harbor or ECR). |
| Missing operators | Check for CRDs before generating YAML: `kubectl api-resources --api-group=<group>`. If the operator is not installed, report which operator is missing and provide install instructions before proceeding. |
| Mixed tooling (e.g., Shipwright + Tekton Buildah in same cluster) | Ask the user which build method to use for the target application. Do not assume. If both exist, note the overlap and recommend consolidating. |
| SOPS-encrypted secrets (not ESO) | Generate Kustomize `secretGenerator` with SOPS-encrypted files. Configure Argo CD with `kustomize.buildOptions: --enable-alpha-plugins --enable-exec` and the SOPS decryption plugin. Do not mix SOPS and ESO in the same namespace without explicit user intent. |
| Helm charts instead of Kustomize | Adapt pipeline YAML to use `helm template` or `helm upgrade` instead of `kustomize build`. Adjust GitOps repo structure to use `Chart.yaml` + `values-<env>.yaml` per environment. |
| Cluster not reachable | Report the error, do not generate apply commands. Ask user to fix connectivity. |
| Insufficient RBAC | Run `kubectl auth can-i` to identify missing permissions. Report what is needed. |
| Multiple Argo CD instances | Detect by checking for ArgoCD CRs or argocd-labeled pods in multiple namespaces. Ask which instance to target. |
| Air-gapped / disconnected cluster | Adjust registry URLs to use internal mirrors. Generate `ImageContentSourcePolicy` or `ImageDigestMirrorSet` for OCP 4.13+. Ensure all images reference the internal registry. |
