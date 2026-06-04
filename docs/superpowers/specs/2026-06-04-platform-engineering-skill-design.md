# OpenShift Platform Engineering Skill — Design Spec

**Date:** 2026-06-04
**Status:** Draft
**Repo:** `alimobrem/openshift-platform-skills`

## Problem

Teams running OpenShift need to wire together 5+ tools for a complete delivery platform:
Shipwright (builds), Tekton (pipelines), Argo CD (GitOps), Istio/OSSM (service mesh),
Argo Rollouts (progressive delivery), and gitops-promoter (environment promotion). Each
tool has its own CRDs, patterns, and failure modes. No AI skill covers the integrated
platform — only individual tools in isolation.

## Solution

A single `platform-engineering` skill that understands the full delivery lifecycle and
how each layer connects to the next. It covers 37 use cases across 8 layers: Build,
Pipeline, Registry, Secrets, GitOps (delegates to argo-skills), Mesh, Delivery/Promotion,
and Audit/Debug. Optional components (registry, secrets, build, mesh) are swappable —
defaults to Quay + External Secrets Operator but adapts when the user specifies alternatives.

## Delivery Lifecycle

```
Code pushed ──► Shipwright builds image ──► Tekton pipeline runs tests/scans
                                              │
                                              ▼
                              Tekton updates GitOps repo (image tag)
                                              │
                                              ▼
                              Argo CD syncs to cluster (argo-skills)
                                              │
                                              ▼
                              Istio routes traffic (VirtualService)
                                              │
                                              ▼
                              Argo Rollouts shifts weight (canary/blue-green)
                                              │
                                              ▼
                              gitops-promoter gates promotion to next env
                                              │
                                              ▼
                              DORA metrics track delivery performance
```

## Repo Structure

```
openshift-platform-skills/
├── skills/
│   └── platform-engineering/
│       ├── SKILL.md
│       ├── references/
│       │   ├── shipwright.md           # ~400 lines — Build layer
│       │   ├── tekton.md              # ~500 lines — Pipeline layer
│       │   ├── istio.md               # ~500 lines — Mesh layer
│       │   ├── quay.md               # ~300 lines — Registry (default, swappable)
│       │   ├── external-secrets.md    # ~300 lines — Secrets (default, swappable)
│       │   ├── delivery-flows.md      # ~400 lines — End-to-end integration
│       │   ├── platform-onboarding.md # ~300 lines — Team/app onboarding
│       │   ├── dora-metrics.md        # ~250 lines — Metrics & dashboards
│       │   └── troubleshooting.md     # ~350 lines — Cross-layer debug
│       └── evals/evals.json
├── agents/
│   ├── claude-code/platform.md
│   ├── codex/platform.toml
│   └── github-copilot/platform.agent.md
├── tests/
│   └── platform-audit/
│       ├── full-stack/
│       └── mixed-issues/
├── .claude-plugin/marketplace.json
├── .codex-plugin/plugin.json
├── benchmarks/platform-engineering.md
├── assets/banner.svg
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── LICENSE (MIT)
├── Makefile
├── Brewfile
└── .gitignore
```

## SKILL.md Design

### Routing Table

| User asks about | Reference | Layer |
|----------------|-----------|-------|
| Builds, images, Buildah, BuildConfig, Shipwright | `shipwright.md` | Build |
| Pipelines, Tasks, Triggers, CI, OpenShift Pipelines | `tekton.md` | Pipeline |
| Registry, Quay, Harbor, image push, robot accounts | `quay.md` | Registry |
| Secrets, Vault, ESO, ExternalSecret, credentials | `external-secrets.md` | Secrets |
| Mesh, mTLS, traffic, VirtualService, Kiali, OSSM | `istio.md` | Mesh |
| Full flow, end-to-end, "set up everything" | `delivery-flows.md` | Integration |
| New team, onboarding, namespace setup | `platform-onboarding.md` | Onboarding |
| DORA, metrics, dashboards, deployment frequency | `dora-metrics.md` | Metrics |
| Debug, trace, "why isn't my change in prod" | `troubleshooting.md` | Debug |
| Argo CD, Applications, Rollouts, Workflows | Redirect to `argo-skills` | GitOps |

### Optional Components (Swappable)

The skill has a **default stack** but supports swapping components. When the user
specifies an alternative, the skill adapts YAML and integration patterns accordingly.

| Layer | Default | Alternatives | How to swap |
|-------|---------|-------------|-------------|
| Registry | **Quay** | Harbor, OpenShift internal registry, ECR, GCR, GHCR, Docker Hub | User says "we use Harbor" → skill generates Harbor-specific push secrets, robot accounts, and registry URLs |
| Secrets | **External Secrets Operator** | Vault (direct), Sealed Secrets, SOPS, AWS Secrets Manager | User says "we use Vault" → skill generates Vault SecretStore + ExternalSecret instead of ESO ClusterSecretStore |
| Build | **Shipwright** | Tekton Buildah task, BuildConfig (legacy), Kaniko | User says "build in the pipeline" → skill inlines buildah task instead of Shipwright BuildRun |
| Mesh | **Istio / OSSM** | No mesh (replica-based canary only) | User says "no mesh" → skill generates Rollout without trafficRouting |

The skill asks which components the user has if the prompt is ambiguous. It does not
assume the defaults without checking.

### Safety Model

Same as argo-operations: Generate → Preview → Confirm for all write operations.
Read-only operations (health checks, audits, metrics queries) skip confirmation.

## Reference Docs

### shipwright.md (~400 lines)

**CRDs:** Build, BuildRun, BuildStrategy, ClusterBuildStrategy

**Content:**
- Build strategies: Buildah (default), Buildpacks, Kaniko, ko, S2I
- Source types: Git, local, bundle (OCI)
- Output: image push to Quay, internal registry, ECR/GCR
- OpenShift Builds: migration from BuildConfig → Shipwright
- Integration: pipeline triggers BuildRun, image tag feeds into GitOps repo
- Common patterns: multi-stage builds, build args, caching, registry auth secrets
- Canonical YAML: Build + BuildRun + BuildStrategy examples

### tekton.md (~500 lines)

**CRDs:** Pipeline, PipelineRun, Task, ClusterTask, TaskRun, Trigger, TriggerBinding,
TriggerTemplate, EventListener

**Content:**
- OpenShift Pipelines operator install, `tkn` CLI, Pipeline-as-Code (PaC)
- Common tasks: git-clone, buildah, trivy-scanner, openshift-client, argocd-sync
- Pipeline patterns: CI (clone→test→build→scan→push→gitops-update), CD (sync→verify→promote)
- Trigger patterns: GitHub webhook → EventListener → TriggerTemplate → PipelineRun
- Pipeline-to-GitOps handoff: Tekton task that commits image tag, or Argo CD sync via API
- RBAC: ServiceAccount for registry push, Git write, Argo CD sync
- Workspaces: PVC, VolumeClaimTemplate, emptyDir

### istio.md (~500 lines)

**CRDs:** ServiceMeshControlPlane, ServiceMeshMemberRoll, VirtualService, DestinationRule,
Gateway, PeerAuthentication, AuthorizationPolicy, RequestAuthentication

**Content:**
- OpenShift Service Mesh (OSSM): operator install, SMCP, SMMR
- Traffic management: splitting by weight/header/cookie, mirroring
- Security: strict mTLS, AuthorizationPolicy, JWT validation
- Observability: Kiali, Jaeger, Prometheus (istio_requests_total, istio_request_duration)
- Rollout integration: Argo Rollouts + Istio VirtualService for canary
- Circuit breaking, retries, timeouts on DestinationRule
- Multi-cluster mesh

### quay.md (~300 lines)

**Default registry. Swappable with Harbor, internal registry, ECR, GCR, GHCR.**

**Content:**
- Quay operator install on OpenShift (QuayRegistry CR)
- Organizations, repositories, robot accounts
- Registry auth secrets for Kubernetes (dockerconfigjson)
- Image scanning (Clair integration, vulnerability reports)
- Mirroring rules for upstream images
- Geo-replication for multi-cluster
- Integration: Shipwright/Tekton push to Quay, Argo CD Image Updater polls from Quay
- **Swap guide:** table showing equivalent config for Harbor, internal registry, ECR, GCR
  (Secret format, push URL, auth method, scanning equivalent)

### external-secrets.md (~300 lines)

**Default secrets management. Swappable with Vault, Sealed Secrets, SOPS.**

**CRDs:** SecretStore, ClusterSecretStore, ExternalSecret, ClusterExternalSecret

**Content:**
- ESO operator install
- SecretStore backends: AWS Secrets Manager, HashiCorp Vault, Azure Key Vault, GCP Secret Manager
- ExternalSecret patterns: single key, templated, data-from
- Integration: pipeline ServiceAccount secrets, Argo CD repo credentials, mesh TLS certs,
  registry auth, GitOps promoter GitHub App keys
- Rotation: automatic refresh via refreshInterval
- RBAC: which ServiceAccounts can read which SecretStores
- **Swap guide:** equivalent patterns for Vault Agent Injector, Sealed Secrets (kubeseal),
  and SOPS (Argo CD Kustomize decryption)

### delivery-flows.md (~400 lines)

**Content:**
- The golden path: complete end-to-end flow with all CRDs wired together
- Variant flows: with/without Shipwright, with/without Istio, with/without promoter
- Wiring diagram: which CRD connects to which, triggers and data flow
- Secrets flow: who needs what credentials
- Complete YAML example: 3-environment delivery (dev → staging → prod)

### platform-onboarding.md (~300 lines)

**Content:**
- What "onboard a team" means: namespace, RBAC, pipeline, AppProject, Application,
  mesh membership, registry creds, notifications
- Complete YAML template for new app onboarding
- Self-service pattern: ApplicationSet + Tekton Triggers
- Guard rails: quotas, network policies, mesh policies, AppProject restrictions

### dora-metrics.md (~250 lines)

**Content:**
- 4 DORA metrics with definitions and elite/low thresholds
- Data sources: Argo CD sync events, Tekton PipelineRun, Istio error rates, Rollout timestamps
- PromQL queries for each metric
- Grafana dashboard JSON model
- PrometheusRule alerts for degraded thresholds

### troubleshooting.md (~350 lines)

**Content:**
- "My change isn't in production" end-to-end trace flowchart
- Per-layer symptom → cause mapping
- Cross-layer issues (pipeline succeeds but sync doesn't happen, sync works but traffic doesn't shift)
- Debug commands per tool (CLI + kubectl fallback)

## Use Cases (37 total)

### Build Layer (5)
1. **Set up container builds** — configure Shipwright with Buildah strategy, source-to-image flow
2. **Create BuildRun from source** — build from Git repo, push image to registry with proper auth
3. **Custom BuildStrategy** — create strategy that runs unit tests before building the image
4. **Debug failing builds** — trace BuildRun failures (push denied, OOM, source clone errors)
5. **Migrate BuildConfig → Shipwright** — convert legacy OpenShift BuildConfigs to Shipwright Builds

### Pipeline Layer (6)
6. **Create CI pipeline** — Tekton pipeline: git-clone → test → build (Shipwright) → scan (Trivy) → push (Quay) → gitops-update
7. **Event-driven triggers** — GitHub/GitLab webhook → Tekton EventListener → TriggerTemplate → PipelineRun
8. **Pipeline-to-GitOps handoff** — Tekton task commits new image tag to GitOps repo, Argo CD picks it up
9. **Reusable task catalog** — install ClusterTasks from Tekton Hub (git-clone, buildah, trivy-scanner, argocd-sync)
10. **Debug pipeline failures** — trace stuck/failed PipelineRuns, inspect task logs, workspace issues
11. **Pipeline RBAC** — ServiceAccount with Quay push secret (from ESO), Git write token, Argo CD API access

### Registry Layer (4)
12. **Set up Quay** — install Quay operator, create org, robot accounts, pipeline push secrets
13. **Image scanning policies** — configure Clair scanning, set vulnerability thresholds, block unscanned images
14. **Registry mirroring** — set up Quay mirror for air-gapped clusters, geo-replication for multi-region
15. **Swap registry** — generate equivalent config for Harbor, internal OpenShift registry, ECR, or GCR

### Secrets Layer (4)
16. **Set up External Secrets Operator** — install ESO, create SecretStore with Vault/AWS/Azure/GCP backend
17. **Create ExternalSecrets** — generate secrets for pipeline creds, Quay robot tokens, Git SSH keys, Argo CD repo auth, mesh TLS certs
18. **Configure secret rotation** — set refreshInterval for automatic rotation, verify refresh works
19. **Swap secrets manager** — generate equivalent for Vault Agent Injector, Sealed Secrets (kubeseal), or SOPS

### GitOps Layer (3 — delegates to argo-skills)
20. **Pipeline → GitOps integration** — wire Tekton output to Argo CD sync (image tag commit or API trigger)
21. **Image updater as alternative** — use Argo CD Image Updater to poll Quay instead of pipeline-based updates
22. **ApplicationSet per pipeline output** — generate Applications from pipeline-built artifacts across environments

### Mesh Layer (7)
23. **Install and configure OSSM** — ServiceMeshControlPlane, ServiceMeshMemberRoll, add namespaces to mesh
24. **mTLS enforcement** — PeerAuthentication strict mode, verify all service-to-service traffic is encrypted
25. **Traffic routing** — VirtualService rules for weight-based, header-based, and cookie-based routing
26. **Rollout + Istio canary** — Argo Rollout with Istio VirtualService for progressive traffic shifting
27. **Observability** — configure Kiali dashboard, Jaeger tracing, Prometheus mesh metrics
28. **Debug mesh issues** — diagnose 503s, connection refused, mTLS handshake failures, missing sidecars
29. **Circuit breaking + retries** — DestinationRule connectionPool limits, outlierDetection, retry policies

### Delivery & Promotion (5)
30. **End-to-end delivery flow** — wire all layers: push → Shipwright build → Tekton pipeline → Quay → ESO secrets → Argo CD sync → Istio routing → Rollout canary → promoter gates → production
31. **Environment promotion** — gitops-promoter with commit status gating from pipeline results + Argo CD health + Istio error rate
32. **DORA metrics** — Prometheus queries for deployment frequency, lead time, change failure rate, MTTR from Argo CD + Tekton + Istio data sources
33. **Platform onboarding** — onboard new team: namespace, Quay org + robot account, ESO SecretStore, Tekton pipeline, Argo CD AppProject + Application, mesh membership, RBAC
34. **Disaster recovery** — restore full platform from Git: operators → Quay → ESO → Argo CD → pipelines → mesh → apps

### Audit & Debug (3)
35. **Platform health check** — check all components across all layers: Shipwright controller, Tekton controller, Quay, ESO, Argo CD, Istio control plane, Rollouts controller
36. **Security audit** — audit pipeline RBAC, Quay scanning policies, ESO secret scope, mesh mTLS enforcement, GitOps security gaps
37. **Trace delivery failure** — "my change isn't in production" — trace from Git commit through pipeline → build → registry → GitOps → sync → mesh → rollout → promotion

## Evals (10 scenarios)

1. **Shipwright build setup** — generate Build + BuildStrategy for Go app with Buildah
2. **Tekton CI pipeline** — full pipeline with clone, test, build, scan, gitops-update tasks
3. **OSSM setup** — ServiceMeshControlPlane + mTLS + add namespace to mesh
4. **End-to-end delivery flow** — wire Tekton → Shipwright → GitOps → Istio → Rollout
5. **Platform onboarding** — onboard new team with namespace, pipeline, app, mesh
6. **DORA metrics** — PromQL queries + Grafana dashboard for 4 metrics
7. **Cross-layer debug** — "my change isn't in production" trace
8. **Platform health check** — check all components across all layers
9. **Quay registry setup** — configure Quay with robot accounts, scanning, pipeline push secrets
10. **External Secrets with Vault** — set up ESO + Vault backend + ExternalSecrets for pipeline and app credentials

## Relationship to argo-skills

- **argo-skills** = GitOps engine (Argo CD, Rollouts, Workflows, Events)
- **openshift-platform-skills** = platform wrapper (builds, pipelines, mesh, metrics, onboarding)
- When user asks an Argo CD question, this skill redirects to argo-skills
- When user asks "set up the full delivery flow," this skill orchestrates across all layers
- Both repos can be installed as separate plugins — they complement, not conflict

## Verification

- Run evals on all 8 scenarios
- Test against live OpenShift cluster with Pipelines, Builds, Service Mesh, GitOps operators installed
- Cross-reference CRD field names against latest operator versions
- Validate end-to-end flow YAML can be applied to a real cluster
