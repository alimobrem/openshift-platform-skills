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

## Use Cases (29 total)

### Build Layer (5)
1. Set up container builds with Shipwright
2. Create BuildRun from Git source
3. Custom BuildStrategy (tests before build)
4. Debug failing builds
5. Migrate BuildConfig → Shipwright

### Pipeline Layer (6)
6. Create CI pipeline (clone→test→build→scan→push→gitops-update)
7. Event-driven triggers (GitHub webhook → PipelineRun)
8. Pipeline-to-GitOps handoff (commit image tag or trigger sync)
9. Reusable task catalog (ClusterTasks from Tekton Hub)
10. Debug pipeline failures
11. Pipeline RBAC (ServiceAccount, registry push, Git write)

### Registry Layer (4)
30. Set up Quay on OpenShift with robot accounts for pipeline push
31. Configure image scanning and vulnerability policies
32. Set up registry mirroring for air-gapped clusters
33. Swap registry — generate equivalent config for Harbor/ECR/internal

### Secrets Layer (4)
34. Set up External Secrets Operator with Vault backend
35. Create ExternalSecrets for pipeline credentials, registry auth, Git tokens
36. Configure secret rotation with refreshInterval
37. Swap secrets manager — generate equivalent for Sealed Secrets or SOPS

### GitOps Layer (3, delegates to argo-skills)
12. Pipeline → GitOps integration
13. Image updater as alternative
14. ApplicationSet per pipeline output

### Mesh Layer (7)
15. Install and configure OSSM
16. mTLS enforcement
17. Traffic routing (VirtualService weight/header)
18. Rollout + Istio canary
19. Observability (Kiali, Jaeger)
20. Debug mesh issues (503s, connection refused)
21. Circuit breaking + retries

### Delivery & Promotion (5)
22. End-to-end delivery flow setup
23. Environment promotion with gitops-promoter
24. DORA metrics setup
25. Platform onboarding (new team/app)
26. Disaster recovery

### Audit & Debug (3)
27. Platform health check (all components)
28. Security audit (pipelines, mesh, GitOps)
29. Trace delivery failure across layers

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
