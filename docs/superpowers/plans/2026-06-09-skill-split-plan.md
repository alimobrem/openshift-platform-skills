# Skill Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic `platform-engineering` skill with 4 focused skills (`platform-ci`, `platform-mesh`, `platform-infra`, `platform-integration`), add 3 shell scripts, expand evals from 2 to 12, and update all supporting files.

**Architecture:** Move (not rewrite) existing reference files into new skill directories. Write 4 new SKILL.md files following the argo-skills pattern (frontmatter → rules → CRD table → reference index → common mistakes → safety model → edge cases). Add executable shell scripts to `platform-integration`. Split the existing monolithic evals.json into per-skill eval files and add 1 new eval.

**Tech Stack:** Bash shell scripts (discover.sh, validate.sh, health-check.sh), JSON schemas (kubeconform), YAML/Markdown skill definitions.

**Spec:** `docs/superpowers/specs/2026-06-09-skill-split-design.md`

---

## Task 1: Create platform-ci skill

**Files:**
- Create: `skills/platform-ci/SKILL.md`
- Create: `skills/platform-ci/evals/evals.json`
- Create: `skills/platform-ci/references/.gitkeep` (placeholder — files moved in Task 5)

- [ ] **Step 1: Create skill directory structure**

```bash
mkdir -p skills/platform-ci/references skills/platform-ci/evals
```

- [ ] **Step 2: Write platform-ci SKILL.md**

Create `skills/platform-ci/SKILL.md` with this content:

```markdown
---
name: platform-ci
description: >
  OpenShift CI/CD skill covering Shipwright container builds and Tekton pipelines.
  Generates, reviews, debugs, and explains Build, BuildRun, Pipeline, PipelineRun,
  Task, EventListener, TriggerBinding, and TriggerTemplate CRDs. Use when users ask
  about container builds, CI/CD pipelines, Shipwright, Tekton, BuildConfig migration,
  OpenShift Pipelines, or build/pipeline debugging on OpenShift.
license: MIT
compatibility: Requires oc or kubectl; optionally tkn
---

# OpenShift CI/CD — Builds & Pipelines

Skill for container image builds (Shipwright) and CI/CD pipelines (Tekton) on OpenShift.

## Rules

1. **Always use correct apiVersion and kind.** Every CRD example must use the real
   apiVersion from the CRD table below. Never invent CRDs or apiVersions.
2. **Load references on-demand.** Only read reference files when the user's question
   requires detailed field-level knowledge. Do not preload all references.
3. **Validate YAML before presenting.** Every YAML example must be syntactically valid
   and use real field names from the CRD schemas.
4. **Prefer canonical patterns.** Use patterns from reference docs as starting points.
   Adapt to the user's specifics rather than inventing from scratch.

## How This Skill Works

| User asks about | Reference | Topic |
|-----------------|-----------|-------|
| Builds, images, Buildah, BuildConfig, Shipwright, BuildRun | `references/shipwright.md` | Build |
| Pipelines, Tasks, Triggers, CI, OpenShift Pipelines, PipelineRun | `references/tekton.md` | Pipeline |

Load the matching reference file before answering. Max 1 reference file per request.

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

## Safety Model

**Every write operation follows a 3-step protocol: Generate, Preview, Confirm.**

**Read-only operations** (status checks, log inspection) do NOT require confirmation.

| Step | What happens |
|------|-------------|
| Generate | Produce YAML manifest or CLI command, show in a code block |
| Preview | `kubectl apply --dry-run=client -f <file>` or `tkn pipeline start --dry-run` |
| Confirm | Ask "Apply this? (yes/no)" — do NOT proceed without affirmative response |

For destructive operations (delete BuildRun, delete PipelineRun), require the user to type
the resource name to confirm.

## Common Mistakes

1. **Using `shipwright.io/v1alpha1` instead of `v1beta1`.** Shipwright graduated to
   v1beta1. Alpha CRDs are removed in recent operator versions.

2. **Tekton Pipeline with no workspace binding.** If the Pipeline declares workspaces
   but the PipelineRun omits `workspaces`, all tasks fail with volume mount errors.

3. **Pipeline pushes image but doesn't update the GitOps repo.** The pipeline succeeds
   but no deployment happens because the image tag in Git is stale. Always include a
   gitops-update task that commits the new tag.

4. **Quay robot account secret not linked to pipeline ServiceAccount.** The pipeline
   runs as a ServiceAccount that needs `imagePullSecrets` and registry push credentials.
   Without linking, builds succeed but pushes fail with 401.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Not an OpenShift cluster (vanilla K8s) | Replace `oc` with `kubectl`. Warn that OpenShift Pipelines operator may not be available — suggest upstream Tekton install. |
| Missing operators | Check for CRDs: `kubectl api-resources --api-group=shipwright.io` and `kubectl api-resources --api-group=tekton.dev`. Report missing operator with install instructions. |
| Mixed build tooling (Shipwright + Tekton Buildah) | Ask the user which build method to use. Do not assume. Note the overlap and recommend consolidating. |
| Helm charts instead of Kustomize | Adapt pipeline gitops-update task to use `helm` commands instead of `kustomize build`. |

## Reference Index

| Topic | Reference File | When to Load |
|-------|---------------|-------------|
| Build strategies, BuildRun, source types, registry auth, BuildConfig migration | `references/shipwright.md` | Questions about container builds, image building, Shipwright CRDs |
| Pipelines, Tasks, Triggers, Pipeline-as-Code, CI patterns, RBAC | `references/tekton.md` | Questions about CI/CD pipelines, Tekton CRDs, OpenShift Pipelines |
```

- [ ] **Step 3: Write platform-ci evals.json**

Create `skills/platform-ci/evals/evals.json` with 3 evals. Evals 1 and 2 are copied from the existing `skills/platform-engineering/evals/evals.json` (ids 1 and 2). Eval 3 is new.

```json
{
  "skill_name": "platform-ci",
  "evals": [
    {
      "id": 1,
      "name": "Shipwright build setup",
      "prompt": "Generate a Shipwright Build and ClusterBuildStrategy for a Go application called 'inventory-svc'. Use Buildah as the build strategy with multi-stage support. The source is at https://github.com/acme-corp/inventory-svc.git (branch main). Push the built image to quay.io/acme/inventory-svc with a tag based on the Git SHA. Include registry auth via a Secret reference. Set a 20-minute timeout and retention limits.",
      "expectations": [
        "Output contains kind: ClusterBuildStrategy with apiVersion: shipwright.io/v1beta1",
        "ClusterBuildStrategy uses Buildah (image reference contains buildah)",
        "Output contains kind: Build with apiVersion: shipwright.io/v1beta1",
        "Build has spec.source.type: Git with url: https://github.com/acme-corp/inventory-svc.git",
        "Build has spec.strategy referencing the ClusterBuildStrategy by name",
        "Build output image is quay.io/acme/inventory-svc with a dynamic tag (not :latest)",
        "Build output has pushSecret or credentials.name referencing a registry auth Secret",
        "Build has spec.timeout set to 20m or equivalent duration",
        "Build has spec.retention with succeededLimit and failedLimit values",
        "ClusterBuildStrategy step includes resource limits for CPU and memory"
      ]
    },
    {
      "id": 2,
      "name": "Tekton CI pipeline",
      "prompt": "Create a complete Tekton CI pipeline called 'webapp-ci' for a Node.js application. The pipeline should have 5 tasks in order: git-clone, test (npm test), build (using Shipwright BuildRun), scan (Trivy vulnerability scanner with HIGH,CRITICAL severity), and gitops-update (commit new image tag to a GitOps repo at https://github.com/acme-corp/gitops-config.git). Include proper workspaces for source code and credentials. Create the ServiceAccount with registry push and Git write secrets.",
      "expectations": [
        "Output contains kind: Pipeline with apiVersion: tekton.dev/v1",
        "Pipeline has exactly 5 tasks: git-clone, test, build, scan, gitops-update",
        "Tasks are ordered with proper runAfter dependencies forming a sequential chain",
        "Pipeline defines workspaces for shared source and credentials",
        "git-clone task uses a ClusterTask or Task reference for git-clone",
        "scan task references Trivy scanner with severity parameter set to HIGH,CRITICAL",
        "gitops-update task commits the new image tag to the GitOps repo",
        "Output includes a ServiceAccount with secrets for registry and Git access",
        "ServiceAccount has a RoleBinding scoped to the namespace (not cluster-admin)",
        "Pipeline params include repo-url, revision, and image-tag"
      ]
    },
    {
      "id": 3,
      "name": "Tekton Triggers with EventListener",
      "prompt": "Set up Tekton Triggers for a GitHub webhook on push events. Create an EventListener called 'github-push-listener' in namespace 'ci' that receives GitHub push webhooks, extracts the repo URL, branch, and commit SHA from the payload, and triggers the 'webapp-ci' Pipeline. Include: a TriggerBinding that maps GitHub webhook fields (body.repository.clone_url, body.ref, body.after) to parameters, a TriggerTemplate that creates a PipelineRun referencing the webapp-ci Pipeline with those parameters, the EventListener with a GitHub interceptor that validates the webhook secret and filters for push events only, a ServiceAccount for the EventListener with RBAC to create PipelineRuns, and a Secret for the GitHub webhook token.",
      "expectations": [
        "Output contains kind: EventListener with apiVersion: triggers.tekton.dev/v1beta1",
        "EventListener has a trigger with a GitHub interceptor",
        "GitHub interceptor has a secretRef for webhook token validation",
        "GitHub interceptor filters for push events (eventTypes contains push)",
        "Output contains kind: TriggerBinding with apiVersion: triggers.tekton.dev/v1beta1",
        "TriggerBinding maps body.repository.clone_url, body.ref, and body.after to parameters",
        "Output contains kind: TriggerTemplate with apiVersion: triggers.tekton.dev/v1beta1",
        "TriggerTemplate creates a PipelineRun referencing the webapp-ci Pipeline",
        "Output includes a ServiceAccount with a RoleBinding granting permissions to create PipelineRuns",
        "Output includes a Secret for the GitHub webhook token"
      ]
    }
  ]
}
```

- [ ] **Step 4: Commit**

```bash
git add skills/platform-ci/
git commit -m "feat: add platform-ci skill with SKILL.md and 3 evals"
```

---

## Task 2: Create platform-mesh skill

**Files:**
- Create: `skills/platform-mesh/SKILL.md`
- Create: `skills/platform-mesh/evals/evals.json`
- Create: `skills/platform-mesh/references/.gitkeep`

- [ ] **Step 1: Create skill directory structure**

```bash
mkdir -p skills/platform-mesh/references skills/platform-mesh/evals
```

- [ ] **Step 2: Write platform-mesh SKILL.md**

Create `skills/platform-mesh/SKILL.md`:

```markdown
---
name: platform-mesh
description: >
  OpenShift Service Mesh skill covering Istio/OSSM installation, mTLS enforcement,
  traffic management, and progressive delivery with Istio. Generates, reviews, debugs,
  and explains Istio, IstioCNI, VirtualService, DestinationRule, Gateway,
  PeerAuthentication, and AuthorizationPolicy CRDs. Use when users ask about service
  mesh, mTLS, traffic routing, canary/blue-green with Istio, VirtualService, Kiali,
  circuit breakers, or fault injection on OpenShift.
license: MIT
compatibility: Requires oc or kubectl; optionally istioctl
---

# OpenShift Service Mesh — Istio & Traffic Management

Skill for service mesh configuration and Istio-based traffic management on OpenShift.

## Rules

1. **Always use correct apiVersion and kind.** Every CRD example must use the real
   apiVersion from the CRD table below. Never invent CRDs or apiVersions.
2. **Load references on-demand.** Only read reference files when the user's question
   requires detailed field-level knowledge. Do not preload all references.
3. **Validate YAML before presenting.** Every YAML example must be syntactically valid
   and use real field names from the CRD schemas.
4. **Prefer canonical patterns.** Use patterns from reference docs as starting points.
   Adapt to the user's specifics rather than inventing from scratch.
5. **State trade-offs.** When recommending a traffic strategy (canary vs blue-green,
   weight-based vs header-based), briefly note what you give up.

## How This Skill Works

| User asks about | Reference | Topic |
|-----------------|-----------|-------|
| Mesh, mTLS, Istio, OSSM, VirtualService, DestinationRule, Gateway, Kiali, traffic, canary+Istio, blue-green+Istio, circuit breaker, fault injection | `references/istio.md` | Mesh |

Load `references/istio.md` before answering.

## CRD Reference Table

| Kind | apiVersion | Project |
|------|-----------|---------|
| Istio | sailoperator.io/v1 | OSSM |
| IstioCNI | sailoperator.io/v1 | OSSM |
| VirtualService | networking.istio.io/v1 | Istio |
| DestinationRule | networking.istio.io/v1 | Istio |
| Gateway | networking.istio.io/v1 | Istio |
| PeerAuthentication | security.istio.io/v1 | Istio |
| AuthorizationPolicy | security.istio.io/v1 | Istio |

## Safety Model

**Every write operation follows a 3-step protocol: Generate, Preview, Confirm.**

**Read-only operations** (mesh status, proxy check, Kiali queries) do NOT require confirmation.

| Step | What happens |
|------|-------------|
| Generate | Produce YAML manifest or CLI command, show in a code block |
| Preview | `kubectl apply --dry-run=client -f <file>` or `kubectl diff -f <file>` |
| Confirm | Ask "Apply this? (yes/no)" — do NOT proceed without affirmative response |

For destructive operations (delete VirtualService, remove namespace from mesh),
require the user to type the resource name to confirm.

## Common Mistakes

1. **Namespace missing `istio-injection=enabled` label.** Without this label,
   Istio sidecars will not be injected into pods in the namespace.

2. **VirtualService host mismatch.** The VirtualService `hosts` field must match the
   Kubernetes Service name exactly. Mismatches cause 404s with no obvious error.

3. **DestinationRule subsets referencing wrong labels.** If the subset selector does not
   match pod labels, Istio routes to an empty subset and returns 503.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Not an OpenShift cluster (vanilla K8s) | Skip OSSM-specific CRDs (Istio CR via sailoperator.io, IstioCNI). Use upstream Istio CRDs directly. Replace `oc` with `kubectl`. |
| No mesh (replica-based canary only) | Generate Argo Rollouts without `trafficRouting`. Warn that canary is replica-based, not traffic-based. |
| Missing OSSM operator | Check: `kubectl api-resources --api-group=sailoperator.io`. If missing, report and provide operator install instructions. |
| Strict mTLS breaks legacy services | Suggest PeerAuthentication in PERMISSIVE mode for the target namespace as a migration step. |

## Reference Index

| Topic | Reference File | When to Load |
|-------|---------------|-------------|
| OSSM install, Istio CR, mTLS, traffic routing, Kiali, circuit breaking, canary/blue-green with Istio | `references/istio.md` | All mesh questions |
```

- [ ] **Step 3: Write platform-mesh evals.json**

Create `skills/platform-mesh/evals/evals.json` with 3 evals. These are existing evals #3, #11, and #12 from the monolithic evals.json, renumbered.

```json
{
  "skill_name": "platform-mesh",
  "evals": [
    {
      "id": 1,
      "name": "OSSM 3.0 setup",
      "prompt": "Set up OpenShift Service Mesh 3.0 for a production environment. Install the Red Hat operator (servicemeshoperator3 from redhat-operators), create an IstioCNI and Istio CR in istio-system with the openshift profile, enforce strict mTLS everywhere via PeerAuthentication, and enroll namespaces 'payments', 'orders', and 'notifications' into the mesh. Also install the Kiali operator for the dashboard.",
      "expectations": [
        "Operator Subscription uses name: servicemeshoperator3 with source: redhat-operators",
        "Output contains kind: IstioCNI with apiVersion: sailoperator.io/v1 and profile: openshift",
        "Output contains kind: Istio with apiVersion: sailoperator.io/v1",
        "Istio CR has profile: openshift and namespace: istio-system",
        "IstioCNI is created before the Istio CR (correct install order)",
        "Output contains kind: PeerAuthentication with spec.mtls.mode: STRICT",
        "Namespaces payments, orders, and notifications have label istio-injection: enabled",
        "Does NOT use ServiceMeshControlPlane or ServiceMeshMemberRoll (those are OSSM 2.x)",
        "Kiali operator Subscription uses source: redhat-operators",
        "Output includes verification commands (oc get pods, oc wait)"
      ]
    },
    {
      "id": 2,
      "name": "Rollout + Istio canary traffic management",
      "prompt": "Set up a canary rollout for 'payments-api' in the 'payments' namespace using Argo Rollouts with Istio for traffic management. The image is quay.io/acme/payments-api:v3.0.0 with 5 replicas. Canary steps: 10% traffic, pause 2 minutes, 30% with Prometheus analysis checking error rate < 1%, 60%, pause 5 minutes, then 100%. Create the Rollout, stable and canary Services, VirtualService, DestinationRule with stable and canary subsets, and an AnalysisTemplate that queries Prometheus at http://prometheus.istio-system:9090 for the istio_requests_total error rate. Show how the Rollouts controller automatically updates VirtualService weights during progression.",
      "expectations": [
        "Output includes kind: Rollout with strategy.canary containing trafficRouting.istio",
        "Rollout trafficRouting references the VirtualService by name and the stable/canary Services",
        "Canary steps include setWeight 10, pause 2m, setWeight 30 with analysis, setWeight 60, pause 5m",
        "Analysis step references an AnalysisTemplate by name",
        "Output includes two Services: one for stable traffic and one for canary traffic",
        "Both Services select the same app label but Rollouts manages the pod-template-hash selector",
        "Output includes a VirtualService with route entries for stable and canary destinations with initial weights",
        "Output includes a DestinationRule with two subsets (stable and canary) using pod-template-hash labels or matching labels",
        "Output includes an AnalysisTemplate with Prometheus provider querying istio_requests_total for error rate",
        "AnalysisTemplate has successCondition checking error rate < 0.01 or success rate >= 0.99",
        "Explains that the Rollouts controller automatically updates VirtualService weights as canary progresses through steps",
        "VirtualService and DestinationRule use networking.istio.io/v1 apiVersion"
      ]
    },
    {
      "id": 3,
      "name": "Blue-green rollout with Istio traffic switching",
      "prompt": "Set up a blue-green deployment for 'checkout-svc' in the 'checkout' namespace using Argo Rollouts with Istio. Active service 'checkout-active', preview service 'checkout-preview'. Do NOT auto-promote — require manual approval. Add a prePromotionAnalysis that checks the preview's error rate via Istio metrics (istio_requests_total) before allowing promotion. Configure the VirtualService to route all production traffic to active and a header-based rule (x-preview: true) to route to preview for testing. Generate Rollout, both Services, VirtualService, DestinationRule, and AnalysisTemplate.",
      "expectations": [
        "Output includes kind: Rollout with strategy.blueGreen",
        "Blue-green config has activeService and previewService references",
        "autoPromotionEnabled is false for manual approval",
        "prePromotionAnalysis references an AnalysisTemplate",
        "Output includes two Services: checkout-active and checkout-preview",
        "Output includes a VirtualService with default route to active service",
        "VirtualService has a header-based match rule for x-preview: true routing to preview",
        "Output includes a DestinationRule with subsets or host references for active and preview",
        "AnalysisTemplate queries Prometheus using istio_requests_total for the preview service error rate",
        "AnalysisTemplate successCondition checks error rate threshold",
        "VirtualService and DestinationRule use networking.istio.io/v1",
        "Explains the promotion flow: preview deployed → prePromotionAnalysis runs → manual promote → active switches"
      ]
    }
  ]
}
```

- [ ] **Step 4: Commit**

```bash
git add skills/platform-mesh/
git commit -m "feat: add platform-mesh skill with SKILL.md and 3 evals"
```

---

## Task 3: Create platform-infra skill

**Files:**
- Create: `skills/platform-infra/SKILL.md`
- Create: `skills/platform-infra/evals/evals.json`
- Create: `skills/platform-infra/references/.gitkeep`

- [ ] **Step 1: Create skill directory structure**

```bash
mkdir -p skills/platform-infra/references skills/platform-infra/evals
```

- [ ] **Step 2: Write platform-infra SKILL.md**

Create `skills/platform-infra/SKILL.md`:

```markdown
---
name: platform-infra
description: >
  OpenShift infrastructure skill covering container image registries (Quay) and
  secrets management (External Secrets Operator). Generates, reviews, debugs, and
  explains QuayRegistry, SecretStore, ClusterSecretStore, ExternalSecret, and
  ClusterExternalSecret CRDs. Supports swappable components — adapts to Harbor,
  Sealed Secrets, or Vault CSI when specified. Use when users ask about image
  registries, Quay, robot accounts, vulnerability scanning, secrets, Vault, ESO,
  ExternalSecret, credential rotation, or air-gapped registry setup.
license: MIT
compatibility: Requires oc or kubectl; optionally skopeo
---

# OpenShift Infrastructure — Registry & Secrets

Skill for container image registries (Quay) and secrets management (External Secrets Operator)
on OpenShift.

## Rules

1. **Always use correct apiVersion and kind.** Every CRD example must use the real
   apiVersion from the CRD table below. Never invent CRDs or apiVersions.
2. **Load references on-demand.** Only read reference files when the user's question
   requires detailed field-level knowledge. Do not preload all references.
3. **Validate YAML before presenting.** Every YAML example must be syntactically valid
   and use real field names from the CRD schemas.
4. **Prefer canonical patterns.** Use patterns from reference docs as starting points.
   Adapt to the user's specifics rather than inventing from scratch.
5. **Ask about optional components when ambiguous.** If the user's prompt does not
   specify which registry or secrets tool they use, ask before generating YAML with
   defaults.

## How This Skill Works

| User asks about | Reference | Topic |
|-----------------|-----------|-------|
| Registry, Quay, Harbor, image push, robot accounts, scanning, Clair | `references/quay.md` | Registry |
| Secrets, Vault, ESO, ExternalSecret, credentials, rotation, SecretStore | `references/external-secrets.md` | Secrets |

Load the matching reference file before answering. Max 1 reference file per request.

## Swappable Components

| Layer | Default | Alternatives |
|-------|---------|-------------|
| Registry | **Quay** | Harbor, OpenShift internal registry, ECR, GCR, GHCR, Docker Hub |
| Secrets | **External Secrets Operator** | Vault (direct), Sealed Secrets, SOPS, AWS Secrets Manager, Vault CSI |

**Ask which components the user has if the prompt is ambiguous.** Do not assume defaults
without checking. When the user says "we use Harbor," generate Harbor-specific push secrets,
robot accounts, and registry URLs instead of Quay equivalents.

## CRD Reference Table

| Kind | apiVersion | Project |
|------|-----------|---------|
| QuayRegistry | quay.redhat.com/v1 | Quay |
| SecretStore | external-secrets.io/v1 | ESO |
| ClusterSecretStore | external-secrets.io/v1 | ESO |
| ExternalSecret | external-secrets.io/v1 | ESO |
| ClusterExternalSecret | external-secrets.io/v1 | ESO |

## Safety Model

**Every write operation follows a 3-step protocol: Generate, Preview, Confirm.**

**Read-only operations** (scan results, secret sync status) do NOT require confirmation.

| Step | What happens |
|------|-------------|
| Generate | Produce YAML manifest or CLI command, show in a code block |
| Preview | `kubectl apply --dry-run=client -f <file>` or `kubectl diff -f <file>` |
| Confirm | Ask "Apply this? (yes/no)" — do NOT proceed without affirmative response |

**NEVER modify Secrets containing credentials directly.** Generate the Secret manifest
and let the user apply it, or use `kubectl create secret --dry-run=client`.

## Common Mistakes

1. **ESO ExternalSecret with wrong SecretStore kind.** Using `kind: SecretStore` when
   the store is `ClusterSecretStore` (or vice versa) causes "store not found" errors.

2. **Quay robot account secret not linked to pipeline ServiceAccount.** The pipeline
   runs as a ServiceAccount that needs `imagePullSecrets` and registry push credentials.
   Without linking, builds succeed but pushes fail with 401.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Air-gapped / disconnected cluster | Adjust registry URLs to use internal mirrors. Generate `ImageDigestMirrorSet` for OCP 4.13+. Ensure all images reference the internal registry. |
| Not an OpenShift cluster (vanilla K8s) | Quay operator may not be available — suggest Harbor or ECR. ESO works the same. |
| SOPS-encrypted secrets (not ESO) | Generate Kustomize `secretGenerator` with SOPS-encrypted files. Do not mix SOPS and ESO in the same namespace without explicit user intent. |
| Missing operators | Check for CRDs: `kubectl api-resources --api-group=quay.redhat.com` and `kubectl api-resources --api-group=external-secrets.io`. Report missing with install instructions. |

## Reference Index

| Topic | Reference File | When to Load |
|-------|---------------|-------------|
| Quay operator, orgs, robot accounts, Clair scanning, mirroring, swap guide | `references/quay.md` | Questions about image registry, scanning, registry auth |
| ESO install, SecretStore backends, ExternalSecret patterns, rotation, swap guide | `references/external-secrets.md` | Questions about secrets management, Vault, sealed secrets |
```

- [ ] **Step 3: Write platform-infra evals.json**

Create `skills/platform-infra/evals/evals.json` with 2 evals (existing #9 and #10, renumbered):

```json
{
  "skill_name": "platform-infra",
  "evals": [
    {
      "id": 1,
      "name": "Quay registry setup",
      "prompt": "Set up a Quay registry on OpenShift for our organization. Install the Quay operator from the Red Hat catalog. Create the QuayRegistry CR with all managed components including Clair for vulnerability scanning. Set up a robot account for the CI pipeline to push images. Create the dockerconfigjson Secret for pipeline authentication. Configure image scanning policies to block images with critical vulnerabilities. Show how to integrate with Tekton pipelines for image push.",
      "expectations": [
        "Quay operator Subscription uses source: redhat-operators (not community)",
        "Output includes kind: QuayRegistry with apiVersion: quay.redhat.com/v1",
        "QuayRegistry has Clair component with managed: true",
        "Output includes configuration or instructions for creating a robot account",
        "Output includes a dockerconfigjson Secret or ExternalSecret for pipeline registry auth",
        "Output includes scanning policy configuration or Clair vulnerability threshold settings",
        "Output shows how Tekton pipeline references the registry push Secret",
        "QuayRegistry has essential components enabled (postgres, redis, objectstorage, route)",
        "Registry auth Secret is in the correct namespace for the pipeline ServiceAccount",
        "Output addresses blocking or alerting on critical vulnerabilities from scans"
      ]
    },
    {
      "id": 2,
      "name": "External Secrets with Vault",
      "prompt": "Set up External Secrets Operator on OpenShift with a HashiCorp Vault backend. Install the Red Hat ESO operator from redhat-operators. Create a ClusterSecretStore that authenticates to Vault at https://vault.internal:8200 using Kubernetes auth. Then create ExternalSecrets for: registry-auth (dockerconfigjson for Quay), git-credentials (SSH key for GitOps repo), and tls-cert (TLS certificate for the mesh gateway). All secrets should have a 1-hour refresh interval. Use the v2 KV secrets engine at path 'secret'.",
      "expectations": [
        "ESO operator Subscription uses source: redhat-operators (not community-operators)",
        "Output includes kind: ClusterSecretStore with apiVersion: external-secrets.io/v1",
        "ClusterSecretStore has provider.vault with server: https://vault.internal:8200",
        "Vault auth uses Kubernetes auth method with mountPath and role",
        "Vault config specifies version: v2 and path: secret for KV engine",
        "Output includes ExternalSecret for registry-auth with target type kubernetes.io/dockerconfigjson",
        "Output includes ExternalSecret for git-credentials with SSH key data",
        "Output includes ExternalSecret for tls-cert with TLS certificate and key",
        "All ExternalSecrets have refreshInterval: 1h",
        "All ExternalSecrets reference the ClusterSecretStore via secretStoreRef",
        "ExternalSecrets use remoteRef with key paths pointing to Vault KV v2 paths"
      ]
    }
  ]
}
```

- [ ] **Step 4: Commit**

```bash
git add skills/platform-infra/
git commit -m "feat: add platform-infra skill with SKILL.md and 2 evals"
```

---

## Task 4: Create platform-integration skill (SKILL.md + evals)

**Files:**
- Create: `skills/platform-integration/SKILL.md`
- Create: `skills/platform-integration/evals/evals.json`
- Create: `skills/platform-integration/references/.gitkeep`
- Create: `skills/platform-integration/scripts/.gitkeep`
- Create: `skills/platform-integration/assets/schemas/.gitkeep`

- [ ] **Step 1: Create skill directory structure**

```bash
mkdir -p skills/platform-integration/references skills/platform-integration/evals skills/platform-integration/scripts skills/platform-integration/assets/schemas
```

- [ ] **Step 2: Write platform-integration SKILL.md**

Create `skills/platform-integration/SKILL.md`:

```markdown
---
name: platform-integration
description: >
  Cross-layer platform integration skill covering end-to-end delivery flows, team
  onboarding, DORA metrics, cross-layer debugging, and platform health checks.
  Orchestrates across all platform layers (build, pipeline, registry, secrets, mesh,
  GitOps, progressive delivery) and owns gitops-promoter CRDs (PromotionStrategy,
  ChangeTransferPolicy, CommitStatus). Includes executable scripts for operator
  health checks, repo discovery, and schema validation. Routes Argo CD questions to
  argo-skills. Use when users ask about end-to-end delivery, platform onboarding,
  DORA metrics, cross-layer debugging, platform health checks, or "why isn't X in prod".
license: MIT
compatibility: Requires oc or kubectl; optionally tkn, istioctl, argocd, yq, kubeconform
---

# OpenShift Platform Integration

Cross-layer skill for end-to-end delivery orchestration, team onboarding, observability,
and platform health on OpenShift.

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
3. **Validate YAML before presenting.** Every YAML example must be syntactically valid
   and use real field names from the CRD schemas.
4. **Prefer canonical patterns.** Use patterns from reference docs as starting points.
   Adapt to the user's specifics rather than inventing from scratch.
5. **State trade-offs.** When recommending an approach, briefly note what you give up.
6. **Redirect Argo CD questions to argo-skills.** This skill does not duplicate Argo CD
   Application, ApplicationSet, or AppProject reference material.

## How This Skill Works

| User asks about | Reference | Topic |
|-----------------|-----------|-------|
| Full flow, end-to-end, "set up everything", delivery pipeline | `references/delivery-flows.md` | Integration |
| New team, onboarding, namespace setup, self-service | `references/platform-onboarding.md` | Onboarding |
| DORA, metrics, dashboards, deployment frequency, lead time | `references/dora-metrics.md` | Metrics |
| Debug, trace, "why isn't my change in prod", cross-layer | `references/troubleshooting.md` | Debug |
| Argo CD, Applications, Rollouts, Workflows | Redirect to `argo-skills` | GitOps |

Load the matching reference file before answering. Max 1-2 reference files per request.

## Scripts

Three executable scripts are available for automated platform assessment:

### health-check.sh — Operator Pre-Flight

Checks all required Red Hat operators for status, CRD presence, and controller health.

```bash
bash skills/platform-integration/scripts/health-check.sh
```

Use when: user asks for a platform health check, before first-time setup, or to diagnose
"operator not found" errors.

### discover.sh — Repo Pattern Scan

Finds platform CRD YAML files in a repository and groups by kind.

```bash
bash skills/platform-integration/scripts/discover.sh -d <repo-root>
```

Use when: user asks to audit or review platform YAML in a repository.

### validate.sh — Schema Validation

Validates discovered YAML against JSON schemas for platform CRDs.

```bash
bash skills/platform-integration/scripts/validate.sh -d <repo-root>
```

Use when: user asks to validate YAML, check for schema errors, or as part of a repo audit.

## CRD Reference Table

This skill owns gitops-promoter CRDs. It also references CRDs from sibling skills
(platform-ci, platform-mesh, platform-infra) when wiring end-to-end flows, but does
not duplicate their CRD tables.

| Kind | apiVersion | Project |
|------|-----------|---------|
| PromotionStrategy | promoter.argoproj.io/v1alpha1 | gitops-promoter |
| ChangeTransferPolicy | promoter.argoproj.io/v1alpha1 | gitops-promoter |
| CommitStatus | promoter.argoproj.io/v1alpha1 | gitops-promoter |

## Safety Model

**Every write operation follows a 3-step protocol: Generate, Preview, Confirm.**

**Read-only operations** (health checks, audits, metrics queries, DORA dashboards,
script execution) do NOT require confirmation — execute and report results.

| Step | What happens |
|------|-------------|
| Generate | Produce YAML manifest or CLI command, show in a code block |
| Preview | `kubectl apply --dry-run=client -f <file>` or `kubectl diff -f <file>` |
| Confirm | Ask "Apply this? (yes/no)" — do NOT proceed without affirmative response |

### Destructive Operations Checklist

Before executing any destructive operation, verify:

- [ ] The current cluster context is correct (`kubectl config current-context`)
- [ ] The target namespace is correct
- [ ] The resource exists and is the right one
- [ ] The user has explicitly confirmed with the resource name
- [ ] A preview of what will be removed has been shown

## Prerequisites

**Target platform:** OpenShift Container Platform **4.22 or later**.

**Required Red Hat Operators** (all from `redhat-operators` catalog):

| Operator | Subscription Name |
|----------|------------------|
| Red Hat OpenShift Pipelines | `openshift-pipelines-operator-rh` |
| Builds for Red Hat OpenShift | `openshift-builds-operator` |
| Red Hat OpenShift Service Mesh 3 | `servicemeshoperator3` |
| Red Hat Quay | `quay-operator` |
| External Secrets Operator | `external-secrets-operator` |
| Kiali | `kiali-ossm` |
| Red Hat build of OpenTelemetry | `opentelemetry-product` |

Run `scripts/health-check.sh` to verify all operators are installed and healthy.

## Common Mistakes

1. **Pipeline pushes image but doesn't update the GitOps repo.** The pipeline succeeds
   but no deployment happens because the image tag in Git is stale. Always include a
   gitops-update task that commits the new tag.

2. **gitops-promoter PromotionStrategy with no CommitStatus source.** Without a
   CommitStatus feeding pipeline results, the promoter never gates promotions and
   auto-promotes everything.

3. **Mixing `kustomize build` and `helm template` in the same Argo CD Application.**
   Use multi-source Applications or pick one. Mixing them in a single source causes
   Argo CD to ignore one renderer silently.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Cluster not reachable | Report the error, do not generate apply commands. Ask user to fix connectivity. |
| Insufficient RBAC | Run `kubectl auth can-i` to identify missing permissions. Report what is needed. |
| Multiple Argo CD instances | Detect by checking for ArgoCD CRs or argocd-labeled pods in multiple namespaces. Ask which instance to target. |
| Air-gapped / disconnected cluster | Adjust registry URLs to use internal mirrors. Generate `ImageDigestMirrorSet` for OCP 4.13+. |
| Mixed tooling | Ask the user which tools they use at each layer before generating YAML. |

## Reference Index

| Topic | Reference File | When to Load |
|-------|---------------|-------------|
| Golden path, variant flows, wiring diagram, secrets flow, 3-env delivery | `references/delivery-flows.md` | Questions about end-to-end delivery, full platform setup |
| Team onboarding, namespace setup, self-service, guard rails | `references/platform-onboarding.md` | Questions about onboarding teams or applications |
| DORA definitions, PromQL queries, Grafana dashboards, PrometheusRule alerts | `references/dora-metrics.md` | Questions about metrics, deployment frequency, MTTR |
| End-to-end trace, per-layer symptoms, cross-layer debug, CLI commands | `references/troubleshooting.md` | Questions about failures, debugging, "why isn't X in prod" |
```

- [ ] **Step 3: Write platform-integration evals.json**

Create `skills/platform-integration/evals/evals.json` with 4 evals (existing #4, #5, #6, #7, renumbered):

```json
{
  "skill_name": "platform-integration",
  "evals": [
    {
      "id": 1,
      "name": "End-to-end delivery flow",
      "prompt": "Wire together a complete delivery flow for a microservice called 'checkout-svc'. The flow should cover: Shipwright builds from Git, Tekton pipeline runs tests and scans, pushes image to Quay, updates GitOps repo, Argo CD syncs to dev cluster, Istio manages traffic with VirtualService, and gitops-promoter gates promotion through dev -> staging -> production. Use External Secrets Operator for all credentials. Show all CRDs needed and how they connect.",
      "expectations": [
        "Output includes a Shipwright Build with BuildStrategy for container image building",
        "Output includes a Tekton Pipeline with tasks covering test, build, scan, and gitops-update",
        "Output includes an ExternalSecret or ClusterSecretStore for credential management",
        "Output includes an Argo CD Application or references Argo CD for GitOps sync",
        "Output includes an Istio VirtualService or traffic management resource",
        "Output includes a PromotionStrategy with 3 environments (dev, staging, production)",
        "PromotionStrategy has commit status gating (activeCommitStatuses or proposedCommitStatuses)",
        "Credentials are managed via ExternalSecret (not plain-text Secrets)",
        "The flow shows clear data handoff: pipeline updates GitOps repo with new image tag",
        "Production environment requires manual approval (autoMerge: false or equivalent)"
      ]
    },
    {
      "id": 2,
      "name": "Platform onboarding",
      "prompt": "Onboard a new team called 'analytics' onto the platform. They need: a namespace with ResourceQuota and LimitRange, NetworkPolicies (default-deny plus allow from mesh), RBAC RoleBinding for 'analytics-developers' group, a Tekton pipeline for their Python application, an Argo CD AppProject restricting them to their namespace and repos, an Application for their service, and mesh membership via ServiceMeshMemberRoll update.",
      "expectations": [
        "Output includes a Namespace for the analytics team",
        "Output includes a ResourceQuota with CPU, memory, and pod limits",
        "Output includes a default-deny NetworkPolicy and at least one allow policy",
        "Output includes a RoleBinding for the analytics-developers group",
        "RoleBinding uses ClusterRole edit or a custom role (not cluster-admin)",
        "Output includes a Tekton Pipeline with tasks appropriate for Python",
        "Output includes an Argo CD AppProject with destination restricted to the analytics namespace",
        "AppProject has sourceRepos restricted to the team's repositories",
        "Output includes an Argo CD Application referencing the AppProject",
        "Output includes ServiceMeshMemberRoll addition or a ServiceMeshMember for the namespace"
      ]
    },
    {
      "id": 3,
      "name": "DORA metrics",
      "prompt": "Set up DORA metrics tracking for our platform. Generate PromQL queries for all 4 DORA metrics (deployment frequency, lead time for changes, change failure rate, mean time to recovery) using data from Argo CD sync events, Tekton PipelineRun completions, and Istio error rates. Also generate a Grafana dashboard JSON model with panels for each metric and a PrometheusRule with alerts for when metrics degrade below the 'high performer' thresholds.",
      "expectations": [
        "Output includes PromQL for deployment frequency using Argo CD sync or Tekton PipelineRun metrics",
        "Output includes PromQL for lead time for changes measuring commit-to-deploy duration",
        "Output includes PromQL for change failure rate using Istio error rates or rollback events",
        "Output includes PromQL for MTTR using Argo CD sync recovery or incident resolution time",
        "Output includes a Grafana dashboard JSON with panels for each DORA metric",
        "Grafana dashboard has at least 4 panels corresponding to the 4 DORA metrics",
        "Output includes a PrometheusRule with alert definitions",
        "Alerts reference DORA threshold values (e.g., deployment frequency, lead time targets)",
        "PromQL queries reference real metric names from Argo CD, Tekton, or Istio exporters",
        "Dashboard includes time range selectors or variable templates for filtering"
      ]
    },
    {
      "id": 4,
      "name": "Cross-layer debug",
      "prompt": "My commit abc123 to the payments service was merged 2 hours ago but the change isn't visible in production. Help me trace where it's stuck. Walk me through the debugging steps across all platform layers: check if the pipeline ran, if the image was built and pushed, if the GitOps repo was updated, if Argo CD synced, if the mesh is routing traffic correctly, and if the promoter approved promotion to production.",
      "expectations": [
        "Response includes steps to check Tekton PipelineRun status for the commit",
        "Response includes steps to verify Shipwright BuildRun completed and image was pushed",
        "Response includes steps to check the GitOps repo for the updated image tag",
        "Response includes steps to check Argo CD Application sync status",
        "Response includes steps to verify Istio VirtualService traffic routing",
        "Response includes steps to check gitops-promoter PromotionStrategy and commit statuses",
        "Debug steps follow the delivery flow order (pipeline -> build -> registry -> gitops -> sync -> mesh -> promotion)",
        "Response includes specific CLI commands (tkn, oc/kubectl, argocd, istioctl or equivalent)",
        "Response identifies common failure points at each layer boundary",
        "Response covers checking if the change is stuck in a non-production environment awaiting promotion"
      ]
    }
  ]
}
```

- [ ] **Step 4: Commit**

```bash
git add skills/platform-integration/
git commit -m "feat: add platform-integration skill with SKILL.md and 4 evals"
```

---

## Task 5: Move reference files from platform-engineering to new skills

**Files:**
- Move: `skills/platform-engineering/references/shipwright.md` → `skills/platform-ci/references/`
- Move: `skills/platform-engineering/references/tekton.md` → `skills/platform-ci/references/`
- Move: `skills/platform-engineering/references/istio.md` → `skills/platform-mesh/references/`
- Move: `skills/platform-engineering/references/quay.md` → `skills/platform-infra/references/`
- Move: `skills/platform-engineering/references/external-secrets.md` → `skills/platform-infra/references/`
- Move: `skills/platform-engineering/references/delivery-flows.md` → `skills/platform-integration/references/`
- Move: `skills/platform-engineering/references/platform-onboarding.md` → `skills/platform-integration/references/`
- Move: `skills/platform-engineering/references/dora-metrics.md` → `skills/platform-integration/references/`
- Move: `skills/platform-engineering/references/troubleshooting.md` → `skills/platform-integration/references/`

- [ ] **Step 1: Move reference files using git mv**

```bash
# platform-ci
git mv skills/platform-engineering/references/shipwright.md skills/platform-ci/references/shipwright.md
git mv skills/platform-engineering/references/tekton.md skills/platform-ci/references/tekton.md

# platform-mesh
git mv skills/platform-engineering/references/istio.md skills/platform-mesh/references/istio.md

# platform-infra
git mv skills/platform-engineering/references/quay.md skills/platform-infra/references/quay.md
git mv skills/platform-engineering/references/external-secrets.md skills/platform-infra/references/external-secrets.md

# platform-integration
git mv skills/platform-engineering/references/delivery-flows.md skills/platform-integration/references/delivery-flows.md
git mv skills/platform-engineering/references/platform-onboarding.md skills/platform-integration/references/platform-onboarding.md
git mv skills/platform-engineering/references/dora-metrics.md skills/platform-integration/references/dora-metrics.md
git mv skills/platform-engineering/references/troubleshooting.md skills/platform-integration/references/troubleshooting.md
```

- [ ] **Step 2: Remove .gitkeep files from new reference dirs (files now present)**

```bash
rm -f skills/platform-ci/references/.gitkeep
rm -f skills/platform-mesh/references/.gitkeep
rm -f skills/platform-infra/references/.gitkeep
```

- [ ] **Step 3: Commit**

```bash
git add -A skills/
git commit -m "refactor: move reference files from platform-engineering to new skill directories"
```

---

## Task 6: Delete old platform-engineering skill

**Files:**
- Delete: `skills/platform-engineering/` (entire directory)

- [ ] **Step 1: Remove the old skill directory**

```bash
git rm -r skills/platform-engineering/
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "refactor: remove monolithic platform-engineering skill"
```

---

## Task 7: Write health-check.sh script

**Files:**
- Create: `skills/platform-integration/scripts/health-check.sh`

- [ ] **Step 1: Write health-check.sh**

Create `skills/platform-integration/scripts/health-check.sh`. Model after argo-skills' discover.sh pattern (bash, set -o errexit/pipefail, usage function, getopts, structured JSON output):

```bash
#!/usr/bin/env bash
set -o errexit
set -o pipefail

# -----------------------------------------------------------------------
# health-check.sh — Check OpenShift platform operator health.
#
# Checks 7 required Red Hat operators for: pod status, CRD presence,
# CSV phase. Outputs structured JSON.
#
# Exit codes: 0 = all healthy, 1 = degraded, 2 = missing required operator
# -----------------------------------------------------------------------

CLI="oc"
command -v oc >/dev/null 2>&1 || CLI="kubectl"
command -v "$CLI" >/dev/null 2>&1 || { echo '{"error":"neither oc nor kubectl found"}'; exit 2; }

OPERATORS=(
  "openshift-pipelines-operator-rh|tekton.dev|openshift-pipelines"
  "openshift-builds-operator|shipwright.io|openshift-builds"
  "servicemeshoperator3|sailoperator.io|istio-system"
  "quay-operator|quay.redhat.com|openshift-operators"
  "external-secrets-operator|external-secrets.io|openshift-operators"
  "kiali-ossm|kiali.io|openshift-operators"
  "opentelemetry-product|opentelemetry.io|openshift-operators"
)

EXIT_CODE=0
RESULTS=()

for entry in "${OPERATORS[@]}"; do
  IFS='|' read -r sub_name api_group default_ns <<< "$entry"

  # Check CSV phase
  csv_phase=$($CLI get csv -n openshift-operators --no-headers 2>/dev/null \
    | grep -i "$sub_name" | awk '{print $NF}' | head -1)
  csv_version=$($CLI get csv -n openshift-operators --no-headers 2>/dev/null \
    | grep -i "$sub_name" | awk '{print $1}' | head -1)

  # Check CRDs
  crd_count=$($CLI api-resources --api-group="$api_group" --no-headers 2>/dev/null | wc -l | tr -d ' ')

  # Determine status
  if [[ -z "$csv_phase" ]]; then
    status="missing"
    EXIT_CODE=2
  elif [[ "$csv_phase" != "Succeeded" ]]; then
    status="degraded"
    [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
  elif [[ "$crd_count" -eq 0 ]]; then
    status="degraded"
    [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
  else
    status="healthy"
  fi

  RESULTS+=("{\"operator\":\"$sub_name\",\"status\":\"$status\",\"version\":\"${csv_version:-unknown}\",\"crd_count\":$crd_count,\"csv_phase\":\"${csv_phase:-not_found}\"}")
done

# Output JSON
echo -n '{"operators":['
first=true
for r in "${RESULTS[@]}"; do
  $first || echo -n ','
  echo -n "$r"
  first=false
done
echo "],"
echo "\"exit_code\":$EXIT_CODE,"
echo "\"summary\":\"$([ $EXIT_CODE -eq 0 ] && echo 'all healthy' || ([ $EXIT_CODE -eq 1 ] && echo 'degraded' || echo 'missing operators'))\"}"

exit $EXIT_CODE
```

- [ ] **Step 2: Make executable**

```bash
chmod +x skills/platform-integration/scripts/health-check.sh
```

- [ ] **Step 3: Commit**

```bash
git add skills/platform-integration/scripts/health-check.sh
git commit -m "feat: add health-check.sh for operator pre-flight validation"
```

---

## Task 8: Write discover.sh script

**Files:**
- Create: `skills/platform-integration/scripts/discover.sh`

- [ ] **Step 1: Write discover.sh**

Create `skills/platform-integration/scripts/discover.sh`:

```bash
#!/usr/bin/env bash
set -o errexit
set -o pipefail

# -----------------------------------------------------------------------
# discover.sh — Scan a directory tree for OpenShift platform CRDs.
#
# Finds YAML files containing Shipwright, Tekton, Istio, ESO, Quay, and
# gitops-promoter resources. Groups by kind and directory. Detects common
# issues (wrong apiVersions, missing fields).
#
# Output: JSON inventory.
# -----------------------------------------------------------------------

ROOT_DIR=""
EXCLUDE_DIRS=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Scan a directory for OpenShift platform CRDs.

Options:
  -d <dir>    Root directory to scan (required)
  -e <dir>    Comma-separated directories to exclude (relative to root)
  -h          Show this help message

Output:
  JSON object with platformResources grouped by kind and by directory,
  plus an issues array for detected problems.

Example:
  $(basename "$0") -d /path/to/repo
  $(basename "$0") -d . -e vendor,tmp
EOF
  exit 0
}

while getopts ":d:e:h" opt; do
  case $opt in
    d) ROOT_DIR="$OPTARG" ;;
    e) EXCLUDE_DIRS="$OPTARG" ;;
    h) usage ;;
    \?) echo "Error: Unknown option -$OPTARG" >&2; exit 1 ;;
    :) echo "Error: Option -$OPTARG requires an argument" >&2; exit 1 ;;
  esac
done

if [[ -z "$ROOT_DIR" ]]; then
  echo "Error: -d <dir> is required" >&2
  exit 1
fi

if [[ ! -d "$ROOT_DIR" ]]; then
  echo "Error: '$ROOT_DIR' is not a directory" >&2
  exit 1
fi

# Build find exclude args
FIND_EXCLUDES=(-path '*/.git' -prune)
if [[ -n "$EXCLUDE_DIRS" ]]; then
  IFS=',' read -ra DIRS <<< "$EXCLUDE_DIRS"
  for d in "${DIRS[@]}"; do
    FIND_EXCLUDES+=(-o -path "*/$d" -prune)
  done
fi

# Platform API groups to detect
PLATFORM_GROUPS="shipwright.io|tekton.dev|triggers.tekton.dev|sailoperator.io|networking.istio.io|security.istio.io|quay.redhat.com|external-secrets.io|promoter.argoproj.io"

# Deprecated/wrong apiVersions to flag
DEPRECATED_VERSIONS="shipwright.io/v1alpha1"

FILES_JSON="[]"
KINDS_JSON="{}"
ISSUES_JSON="[]"

file_count=0
issue_count=0

while IFS= read -r -d '' file; do
  # Extract apiVersion and kind pairs using awk
  while IFS='|' read -r api_version kind; do
    [[ -z "$kind" || -z "$api_version" ]] && continue

    # Check if this is a platform resource
    if echo "$api_version" | grep -qE "$PLATFORM_GROUPS"; then
      rel_path="${file#"$ROOT_DIR"/}"
      dir_path=$(dirname "$rel_path")

      file_count=$((file_count + 1))

      # Check for deprecated apiVersions
      if echo "$api_version" | grep -qE "$DEPRECATED_VERSIONS"; then
        issue_count=$((issue_count + 1))
        ISSUES_JSON=$(echo "$ISSUES_JSON" | sed 's/]$//')
        [[ "$issue_count" -gt 1 ]] && ISSUES_JSON="${ISSUES_JSON},"
        ISSUES_JSON="${ISSUES_JSON}{\"file\":\"$rel_path\",\"kind\":\"$kind\",\"issue\":\"deprecated apiVersion $api_version\",\"severity\":\"error\"}]"
      fi
    fi
  done < <(awk '/^apiVersion:/{api=$2} /^kind:/{if(api) print api"|"$2; api=""}' "$file")
done < <(find "$ROOT_DIR" \( "${FIND_EXCLUDES[@]}" \) -o -name '*.yaml' -print0 -o -name '*.yml' -print0)

echo "{\"file_count\":$file_count,\"issue_count\":$issue_count,\"issues\":$ISSUES_JSON}"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x skills/platform-integration/scripts/discover.sh
```

- [ ] **Step 3: Commit**

```bash
git add skills/platform-integration/scripts/discover.sh
git commit -m "feat: add discover.sh for platform CRD repo scanning"
```

---

## Task 9: Write validate.sh script

**Files:**
- Create: `skills/platform-integration/scripts/validate.sh`

- [ ] **Step 1: Write validate.sh**

Create `skills/platform-integration/scripts/validate.sh`:

```bash
#!/usr/bin/env bash
set -o errexit
set -o pipefail

# -----------------------------------------------------------------------
# validate.sh — Validate YAML syntax and schemas for platform CRDs.
#
# Prerequisites: yq >= 4.50, kubeconform >= 0.7
# -----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_SCHEMAS_DIR="$SKILL_DIR/assets/schemas"
ROOT_DIR=""
EXCLUDE_DIRS=""
ERROR_COUNT=0
WARN_COUNT=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Validate YAML files containing platform CRDs.

Options:
  -d <dir>    Root directory to validate (required)
  -e <dir>    Comma-separated directories to exclude (relative to root)
  -h          Show this help message

Validation passes:
  1. YAML syntax check (yq)
  2. Schema validation against platform CRD schemas (kubeconform)

Prerequisites:
  yq          >= 4.50    https://github.com/mikefarah/yq
  kubeconform >= 0.7     https://github.com/yannh/kubeconform

Example:
  $(basename "$0") -d /path/to/repo
  $(basename "$0") -d . -e vendor,tmp
EOF
  exit 0
}

while getopts ":d:e:h" opt; do
  case $opt in
    d) ROOT_DIR="$OPTARG" ;;
    e) EXCLUDE_DIRS="$OPTARG" ;;
    h) usage ;;
    \?) echo "Error: Unknown option -$OPTARG" >&2; exit 1 ;;
    :) echo "Error: Option -$OPTARG requires an argument" >&2; exit 1 ;;
  esac
done

if [[ -z "$ROOT_DIR" ]]; then
  echo "Error: -d <dir> is required" >&2
  exit 1
fi

# Check prerequisites
HAS_YQ=false
HAS_KUBECONFORM=false
command -v yq >/dev/null 2>&1 && HAS_YQ=true
command -v kubeconform >/dev/null 2>&1 && HAS_KUBECONFORM=true

if ! $HAS_YQ && ! $HAS_KUBECONFORM; then
  echo '{"error":"neither yq nor kubeconform found — install at least one","results":[]}'
  exit 1
fi

# Build find exclude args
FIND_EXCLUDES=(-path '*/.git' -prune)
if [[ -n "$EXCLUDE_DIRS" ]]; then
  IFS=',' read -ra DIRS <<< "$EXCLUDE_DIRS"
  for d in "${DIRS[@]}"; do
    FIND_EXCLUDES+=(-o -path "*/$d" -prune)
  done
fi

RESULTS="["
first=true

while IFS= read -r -d '' file; do
  rel_path="${file#"$ROOT_DIR"/}"
  valid=true
  errors=""

  # Pass 1: YAML syntax
  if $HAS_YQ; then
    if ! yq_err=$(yq eval '.' "$file" 2>&1 >/dev/null); then
      valid=false
      errors="YAML syntax error: $yq_err"
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
  fi

  # Pass 2: Schema validation (only if syntax passed)
  if $valid && $HAS_KUBECONFORM && [[ -d "$ASSETS_SCHEMAS_DIR" ]]; then
    if ! kc_err=$(kubeconform -schema-location "$ASSETS_SCHEMAS_DIR/{{ .ResourceKind }}-{{ .Group }}-{{ .ResourceAPIVersion }}.json" \
         -schema-location 'default' -strict -output json "$file" 2>&1); then
      # Parse kubeconform output for errors
      kc_status=$(echo "$kc_err" | grep -o '"status":"[^"]*"' | head -1)
      if echo "$kc_status" | grep -q "statusError\|statusInvalid"; then
        valid=false
        errors="Schema validation failed"
        ERROR_COUNT=$((ERROR_COUNT + 1))
      fi
    fi
  fi

  $first || RESULTS="${RESULTS},"
  RESULTS="${RESULTS}{\"file\":\"$rel_path\",\"valid\":$valid,\"errors\":\"$errors\"}"
  first=false

done < <(find "$ROOT_DIR" \( "${FIND_EXCLUDES[@]}" \) -o \( -name '*.yaml' -o -name '*.yml' \) -print0)

RESULTS="${RESULTS}]"

echo "{\"error_count\":$ERROR_COUNT,\"warn_count\":$WARN_COUNT,\"results\":$RESULTS}"

[[ $ERROR_COUNT -eq 0 ]] && exit 0 || exit 1
```

- [ ] **Step 2: Make executable**

```bash
chmod +x skills/platform-integration/scripts/validate.sh
```

- [ ] **Step 3: Commit**

```bash
git add skills/platform-integration/scripts/validate.sh
git commit -m "feat: add validate.sh for platform CRD schema validation"
```

---

## Task 10: Download CRD schemas

**Files:**
- Create: `skills/platform-integration/assets/schemas/pipeline-tekton-v1.json`
- Create: `skills/platform-integration/assets/schemas/task-tekton-v1.json`
- Create: `skills/platform-integration/assets/schemas/build-shipwright-v1beta1.json`
- Create: `skills/platform-integration/assets/schemas/buildstrategy-shipwright-v1beta1.json`
- Create: `skills/platform-integration/assets/schemas/virtualservice-networking-istio-v1.json`
- Create: `skills/platform-integration/assets/schemas/destinationrule-networking-istio-v1.json`
- Create: `skills/platform-integration/assets/schemas/externalsecret-external-secrets-v1.json`
- Create: `skills/platform-integration/assets/schemas/secretstore-external-secrets-v1.json`

- [ ] **Step 1: Add a Makefile target for schema download**

Add a `download-schemas` target to the project Makefile. The schemas come from the
kubeconform JSON schema store and upstream CRD definitions. Use the naming convention
that matches kubeconform's `{{ .ResourceKind }}-{{ .Group }}-{{ .ResourceAPIVersion }}.json`
template (all lowercase):

```makefile
SCHEMAS_DIR := skills/platform-integration/assets/schemas
KUBECONFORM_BASE := https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master

download-schemas: ## Download CRD JSON schemas for platform validation
	@mkdir -p $(SCHEMAS_DIR)
	@echo "Downloading platform CRD schemas..."
	curl -sL "https://json.schemastore.org/tekton-pipeline.json" -o "$(SCHEMAS_DIR)/pipeline-tekton.dev-v1.json"
	curl -sL "https://json.schemastore.org/tekton-task.json" -o "$(SCHEMAS_DIR)/task-tekton.dev-v1.json"
	curl -sL "https://raw.githubusercontent.com/shipwright-io/build/main/deploy/crds/shipwright.io_builds.yaml" | yq eval '.spec.versions[] | select(.name == "v1beta1") | .schema.openAPIV3Schema' - > "$(SCHEMAS_DIR)/build-shipwright.io-v1beta1.json" 2>/dev/null || echo '{}' > "$(SCHEMAS_DIR)/build-shipwright.io-v1beta1.json"
	curl -sL "https://raw.githubusercontent.com/shipwright-io/build/main/deploy/crds/shipwright.io_buildstrategies.yaml" | yq eval '.spec.versions[] | select(.name == "v1beta1") | .schema.openAPIV3Schema' - > "$(SCHEMAS_DIR)/buildstrategy-shipwright.io-v1beta1.json" 2>/dev/null || echo '{}' > "$(SCHEMAS_DIR)/buildstrategy-shipwright.io-v1beta1.json"
	curl -sL "https://raw.githubusercontent.com/istio/istio/master/manifests/charts/base/crds/crd-all.gen.yaml" | yq eval 'select(.metadata.name == "virtualservices.networking.istio.io") | .spec.versions[] | select(.name == "v1") | .schema.openAPIV3Schema' - > "$(SCHEMAS_DIR)/virtualservice-networking.istio.io-v1.json" 2>/dev/null || echo '{}' > "$(SCHEMAS_DIR)/virtualservice-networking.istio.io-v1.json"
	curl -sL "https://raw.githubusercontent.com/istio/istio/master/manifests/charts/base/crds/crd-all.gen.yaml" | yq eval 'select(.metadata.name == "destinationrules.networking.istio.io") | .spec.versions[] | select(.name == "v1") | .schema.openAPIV3Schema' - > "$(SCHEMAS_DIR)/destinationrule-networking.istio.io-v1.json" 2>/dev/null || echo '{}' > "$(SCHEMAS_DIR)/destinationrule-networking.istio.io-v1.json"
	curl -sL "https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml" | yq eval 'select(.metadata.name == "externalsecrets.external-secrets.io") | .spec.versions[] | select(.name == "v1") | .schema.openAPIV3Schema' - > "$(SCHEMAS_DIR)/externalsecret-external-secrets.io-v1.json" 2>/dev/null || echo '{}' > "$(SCHEMAS_DIR)/externalsecret-external-secrets.io-v1.json"
	curl -sL "https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml" | yq eval 'select(.metadata.name == "secretstores.external-secrets.io") | .spec.versions[] | select(.name == "v1") | .schema.openAPIV3Schema' - > "$(SCHEMAS_DIR)/secretstore-external-secrets.io-v1.json" 2>/dev/null || echo '{}' > "$(SCHEMAS_DIR)/secretstore-external-secrets.io-v1.json"
	@echo "Done. $(SCHEMAS_DIR)/ populated."
```

- [ ] **Step 2: Run make download-schemas**

```bash
make download-schemas
```

Verify files exist and are non-empty:

```bash
ls -la skills/platform-integration/assets/schemas/
```

- [ ] **Step 3: Commit schemas**

```bash
git add skills/platform-integration/assets/schemas/ Makefile
git commit -m "feat: add CRD JSON schemas for platform validation"
```

---

## Task 11: Update plugin registries and agent files

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Modify: `.codex-plugin/plugin.json`
- Modify: `agents/claude-code/platform.md`
- Modify: `agents/codex/platform.toml`
- Modify: `agents/github-copilot/platform.agent.md`

- [ ] **Step 1: Update .claude-plugin/marketplace.json**

Change the `skills` array from `["./skills/platform-engineering"]` to:

```json
"skills": [
  "./skills/platform-ci",
  "./skills/platform-mesh",
  "./skills/platform-infra",
  "./skills/platform-integration"
]
```

- [ ] **Step 2: Update agents/claude-code/platform.md**

Replace the entire file with:

```markdown
---
name: platform
description: >
  OpenShift platform engineering agent — manages the full delivery lifecycle
  across Shipwright builds, Tekton pipelines, Quay registry, External Secrets,
  Istio/OSSM service mesh, gitops-promoter delivery flows, DORA metrics,
  and team onboarding. Routes to the matching skill based on context.
skills:
  - platform-ci
  - platform-mesh
  - platform-infra
  - platform-integration
---

# OpenShift Platform Engineering Agent

You are a platform engineering specialist that helps users build and operate
the full delivery lifecycle on OpenShift.

## How to Route Requests

### Build & Pipeline → platform-ci
When users ask about Shipwright builds, Tekton pipelines, CI/CD tasks, triggers,
BuildRun, PipelineRun, or container image building.

### Service Mesh → platform-mesh
When users ask about Istio, OSSM, mTLS, VirtualService, DestinationRule,
traffic management, canary/blue-green with Istio, Kiali, or circuit breakers.

### Registry & Secrets → platform-infra
When users ask about Quay, Harbor, robot accounts, image scanning, External
Secrets Operator, Vault, SecretStore, credential rotation, or air-gapped registries.

### Integration / Onboarding / Metrics / Debug → platform-integration
When users ask about end-to-end delivery flows, team onboarding, DORA metrics,
cross-layer debugging, platform health checks, or "why isn't X in prod".

### Argo CD / GitOps → argo-skills
Redirect to **argo-skills** for Argo CD, Rollouts, Workflows, and Events questions.
```

- [ ] **Step 3: Update agents/codex/platform.toml**

Replace the entire file with:

```toml
name = "platform"
description = "OpenShift platform engineering agent — manages the full delivery lifecycle across Shipwright builds, Tekton pipelines, Quay registry, External Secrets, Istio/OSSM service mesh, gitops-promoter delivery flows, DORA metrics, and team onboarding."

developer_instructions = """
You are a platform engineering specialist. Route requests to the matching skill:

- Build/Pipeline (Shipwright, Tekton, CI/CD): use platform-ci skill
- Service Mesh (Istio, OSSM, mTLS, VirtualService): use platform-mesh skill
- Registry/Secrets (Quay, ESO, Vault, credentials): use platform-infra skill
- Integration (end-to-end, onboarding, DORA, debug): use platform-integration skill
- Argo CD/GitOps: redirect to argo-skills
"""

[[skills.config]]
path = ".agents/skills/platform-ci/SKILL.md"

[[skills.config]]
path = ".agents/skills/platform-mesh/SKILL.md"

[[skills.config]]
path = ".agents/skills/platform-infra/SKILL.md"

[[skills.config]]
path = ".agents/skills/platform-integration/SKILL.md"
```

- [ ] **Step 4: Update agents/github-copilot/platform.agent.md**

Replace the entire file with:

```markdown
---
name: platform
description: >
  OpenShift platform engineering agent — manages the full delivery lifecycle
  across Shipwright builds, Tekton pipelines, Quay registry, External Secrets,
  Istio/OSSM service mesh, gitops-promoter delivery flows, DORA metrics,
  and team onboarding. Use when users ask about OpenShift platform setup,
  CI/CD pipelines, container builds, service mesh, or delivery automation.
tools:
  - read
  - edit
  - search
  - execute
---

# OpenShift Platform Engineering Agent

You are a platform engineering specialist that helps users build and operate
the full delivery lifecycle on OpenShift.

## Loading Skills

Before responding, load the relevant skill by reading its `SKILL.md` file:

- `.skills/platform-ci/SKILL.md` — Shipwright builds, Tekton pipelines
- `.skills/platform-mesh/SKILL.md` — Istio/OSSM, traffic management
- `.skills/platform-infra/SKILL.md` — Quay registry, External Secrets
- `.skills/platform-integration/SKILL.md` — E2E flows, onboarding, DORA, debug

Read the matching skill file first, then follow its workflow.

## How to Route Requests

- **Build/Pipeline** (Shipwright, Tekton, CI/CD) → `platform-ci`
- **Service Mesh** (Istio, OSSM, mTLS, VirtualService) → `platform-mesh`
- **Registry/Secrets** (Quay, ESO, Vault, credentials) → `platform-infra`
- **Integration** (end-to-end, onboarding, DORA, debug) → `platform-integration`
- **Argo CD/GitOps** → redirect to **argo-skills**
```

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json .codex-plugin/plugin.json agents/
git commit -m "refactor: update plugin registries and agents for 4-skill split"
```

---

## Task 12: Update Makefile

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Replace Makefile content**

Replace the entire `Makefile` with:

```makefile
SCHEMAS_DIR := skills/platform-integration/assets/schemas

.PHONY: help test-ci test-mesh test-infra test-integration test-all test-scripts download-schemas

test-ci: ## Run platform-ci evals
	@echo "Running platform-ci evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-ci/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-ci/SKILL.md first, then follows the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

test-mesh: ## Run platform-mesh evals
	@echo "Running platform-mesh evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-mesh/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-mesh/SKILL.md first, then follows the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

test-infra: ## Run platform-infra evals
	@echo "Running platform-infra evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-infra/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-infra/SKILL.md first, then follows the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

test-integration: ## Run platform-integration evals
	@echo "Running platform-integration evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-integration/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-integration/SKILL.md first, then follows the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

test-all: test-ci test-mesh test-infra test-integration ## Run all skill evals

test-scripts: ## Run script tests against fixtures
	@echo "Testing health-check.sh..."
	@bash skills/platform-integration/scripts/health-check.sh 2>/dev/null; echo "Exit code: $$?"
	@echo "Testing discover.sh..."
	@bash skills/platform-integration/scripts/discover.sh -d tests/platform-audit/full-stack
	@echo "Testing validate.sh..."
	@bash skills/platform-integration/scripts/validate.sh -d tests/platform-audit/full-stack; echo "Exit code: $$?"

download-schemas: ## Download CRD JSON schemas for platform validation
	@mkdir -p $(SCHEMAS_DIR)
	@echo "Downloading platform CRD schemas..."
	curl -sL "https://json.schemastore.org/tekton-pipeline.json" -o "$(SCHEMAS_DIR)/pipeline-tekton.dev-v1.json"
	curl -sL "https://json.schemastore.org/tekton-task.json" -o "$(SCHEMAS_DIR)/task-tekton.dev-v1.json"
	@echo "Done. Remaining schemas require yq — see README."

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'
```

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "refactor: update Makefile with per-skill eval targets and script tests"
```

---

## Task 13: Update AGENTS.md

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Update the Repository Layout section**

In `AGENTS.md`, replace the repository layout code block with:

````markdown
```
skills/
├── platform-ci/                      # Build + pipeline skill
│   ├── SKILL.md
│   ├── references/
│   │   ├── shipwright.md
│   │   └── tekton.md
│   └── evals/evals.json
├── platform-mesh/                    # Service mesh skill
│   ├── SKILL.md
│   ├── references/
│   │   └── istio.md
│   └── evals/evals.json
├── platform-infra/                   # Registry + secrets skill
│   ├── SKILL.md
│   ├── references/
│   │   ├── quay.md
│   │   └── external-secrets.md
│   └── evals/evals.json
├── platform-integration/             # Cross-layer integration skill
│   ├── SKILL.md
│   ├── references/
│   │   ├── delivery-flows.md
│   │   ├── platform-onboarding.md
│   │   ├── dora-metrics.md
│   │   └── troubleshooting.md
│   ├── scripts/
│   │   ├── health-check.sh
│   │   ├── discover.sh
│   │   └── validate.sh
│   ├── assets/schemas/               # CRD JSON schemas for validation
│   └── evals/evals.json
tests/{skill-name}/                   # Test fixtures for offline evaluation
agents/                               # Agent configs per platform
├── claude-code/                      # Claude Code agent YAML
├── codex/                            # Codex agent instructions
└── github-copilot/                   # GitHub Copilot agent markdown
.claude-plugin/marketplace.json       # Skill registry for distribution
.codex-plugin/plugin.json             # Codex plugin manifest
Makefile                              # Test and eval targets
```
````

- [ ] **Step 2: Update the "Running Skill Evals" section**

Replace the eval instructions to reference per-skill targets:

```markdown
## Running Skill Evals

Each skill has its own `evals/evals.json` file. Run evals per-skill or all at once:

```bash
make test-ci           # platform-ci evals (3)
make test-mesh         # platform-mesh evals (3)
make test-infra        # platform-infra evals (2)
make test-integration  # platform-integration evals (4)
make test-all          # all 12 evals
make test-scripts      # shell script tests against fixtures
```
```

- [ ] **Step 3: Update "Working on Existing Skills" to reference multi-skill structure**

Change the first instruction from:

```
1. Read the skill's `SKILL.md` to understand its workflow and allowed tools
2. Read all files in `references/` before making changes
```

to:

```
1. Read the target skill's `SKILL.md` to understand its scope and CRD ownership
2. Read the reference files in that skill's `references/` directory before making changes
3. Check sibling skills to avoid duplicating CRD tables or reference content
```

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "docs: update AGENTS.md for 4-skill layout and per-skill eval targets"
```

---

## Task 14: Create per-skill benchmark files

**Files:**
- Create: `benchmarks/platform-ci.md`
- Create: `benchmarks/platform-mesh.md`
- Create: `benchmarks/platform-infra.md`
- Create: `benchmarks/platform-integration.md`
- Delete: `benchmarks/platform-engineering.md`

- [ ] **Step 1: Create platform-ci benchmark placeholder**

Create `benchmarks/platform-ci.md`:

```markdown
# platform-ci

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| Shipwright build setup | — |
| Tekton CI pipeline | — |
| Tekton Triggers with EventListener | — |
| **Overall** | **—** |

_Run `make test-ci` to populate results._
```

- [ ] **Step 2: Create platform-mesh benchmark placeholder**

Create `benchmarks/platform-mesh.md`:

```markdown
# platform-mesh

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| OSSM 3.0 setup | — |
| Rollout + Istio canary traffic mgmt | — |
| Blue-green + Istio header preview | — |
| **Overall** | **—** |

_Run `make test-mesh` to populate results._
```

- [ ] **Step 3: Create platform-infra benchmark placeholder**

Create `benchmarks/platform-infra.md`:

```markdown
# platform-infra

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| Quay registry setup | — |
| ESO + Vault | — |
| **Overall** | **—** |

_Run `make test-infra` to populate results._
```

- [ ] **Step 4: Create platform-integration benchmark placeholder**

Create `benchmarks/platform-integration.md`:

```markdown
# platform-integration

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| End-to-end delivery flow | — |
| Platform onboarding | — |
| DORA metrics | — |
| Cross-layer debug | — |
| **Overall** | **—** |

_Run `make test-integration` to populate results._
```

- [ ] **Step 5: Delete old benchmark file**

```bash
git rm benchmarks/platform-engineering.md
```

- [ ] **Step 6: Commit**

```bash
git add benchmarks/
git commit -m "docs: replace monolithic benchmark with per-skill benchmark files"
```

---

## Task 15: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Quick Start skill reference**

Change:

```shell
/plugin install openshift-platform-skills@platform-engineering
```

to:

```shell
/plugin install openshift-platform-skills@platform
```

(The plugin name stays the same, but the install references the agent which routes to all 4 skills.)

- [ ] **Step 2: Update the "How Routing Works" diagram**

Replace the routing diagram with one showing the 4 skills:

```
 Build an image ─────────► platform-ci       Shipwright / Buildah
 Run a pipeline ─────────► platform-ci       Tekton Pipelines & Triggers
 Configure mesh ─────────► platform-mesh     Istio / OpenShift Service Mesh
 Manage images ──────────► platform-infra    Quay / ImageStreams / signing
 Rotate secrets ─────────► platform-infra    ExternalSecretOperator / Vault
 Ship a release ─────────► platform-integration  Progressive delivery flows
 Onboard a team ─────────► platform-integration  Namespace / quotas / RBAC
 Measure velocity ───────► platform-integration  DORA four keys
 Debug failures ─────────► platform-integration  Cross-layer troubleshooting
```

- [ ] **Step 3: Update the Benchmarks table**

Replace the single benchmark table with per-skill tables:

```markdown
## Benchmarks

Evals test **outcomes** (correct YAML, right CRDs, safety model), not process.

<table>
<thead>
<tr>
<th width="200">Skill</th>
<th width="80">Evals</th>
<th width="80">Score</th>
<th>Highlights</th>
</tr>
</thead>
<tbody>
<tr>
<td><a href="benchmarks/platform-ci.md"><b>platform-ci</b></a></td>
<td>3</td>
<td><b>—</b></td>
<td>Shipwright builds, Tekton pipelines, Triggers with EventListener</td>
</tr>
<tr>
<td><a href="benchmarks/platform-mesh.md"><b>platform-mesh</b></a></td>
<td>3</td>
<td><b>—</b></td>
<td>OSSM 3.0 setup, canary+Istio, blue-green+Istio</td>
</tr>
<tr>
<td><a href="benchmarks/platform-infra.md"><b>platform-infra</b></a></td>
<td>2</td>
<td><b>—</b></td>
<td>Quay registry setup, ESO+Vault</td>
</tr>
<tr>
<td><a href="benchmarks/platform-integration.md"><b>platform-integration</b></a></td>
<td>4</td>
<td><b>—</b></td>
<td>E2E delivery flow, onboarding, DORA, cross-layer debug</td>
</tr>
</tbody>
</table>

<sub>Run <code>make test-all</code> to populate scores. Per-skill: <code>make test-ci</code>, <code>make test-mesh</code>, etc.</sub>
```

- [ ] **Step 4: Update the Development section**

Replace:

```shell
make test-evals
```

with:

```shell
make test-all      # all 12 evals
make test-scripts  # shell script tests
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: update README for 4-skill architecture with per-skill benchmarks"
```

---

## Task 16: Verify everything works

- [ ] **Step 1: Verify directory structure is correct**

```bash
find skills/ -type f | sort
```

Expected: 4 skill directories, each with SKILL.md, evals/evals.json, and references/*.md. platform-integration also has scripts/ and assets/schemas/.

- [ ] **Step 2: Verify no references remain in old location**

```bash
ls skills/platform-engineering 2>&1
```

Expected: "No such file or directory"

- [ ] **Step 3: Verify marketplace.json lists all 4 skills**

```bash
cat .claude-plugin/marketplace.json | grep -c 'platform-'
```

Expected: 4

- [ ] **Step 4: Verify evals total 12**

```bash
for f in skills/*/evals/evals.json; do
  skill=$(echo $f | sed 's|skills/||;s|/evals.*||')
  count=$(python3 -c "import json; d=json.load(open('$f')); print(len(d['evals']))")
  echo "$skill: $count evals"
done
```

Expected: platform-ci: 3, platform-mesh: 3, platform-infra: 2, platform-integration: 4

- [ ] **Step 5: Verify scripts are executable**

```bash
ls -la skills/platform-integration/scripts/
```

Expected: all 3 scripts have execute permission.

- [ ] **Step 6: Run discover.sh against test fixtures**

```bash
bash skills/platform-integration/scripts/discover.sh -d tests/platform-audit/full-stack
```

Expected: JSON output with file_count > 0.

- [ ] **Step 7: Commit any fixups needed**

If any verification step fails, fix and commit.
