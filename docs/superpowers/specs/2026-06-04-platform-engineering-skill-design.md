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
how each layer connects to the next. It covers 29 use cases across 6 layers: Build,
Pipeline, GitOps (delegates to argo-skills), Mesh, Delivery/Promotion, and Audit/Debug.

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
│       │   ├── shipwright.md           # ~400 lines
│       │   ├── tekton.md              # ~500 lines
│       │   ├── istio.md               # ~500 lines
│       │   ├── delivery-flows.md      # ~400 lines
│       │   ├── platform-onboarding.md # ~300 lines
│       │   ├── dora-metrics.md        # ~250 lines
│       │   └── troubleshooting.md     # ~350 lines
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
| Mesh, mTLS, traffic, VirtualService, Kiali, OSSM | `istio.md` | Mesh |
| Full flow, end-to-end, "set up everything" | `delivery-flows.md` | Integration |
| New team, onboarding, namespace setup | `platform-onboarding.md` | Onboarding |
| DORA, metrics, dashboards, deployment frequency | `dora-metrics.md` | Metrics |
| Debug, trace, "why isn't my change in prod" | `troubleshooting.md` | Debug |
| Argo CD, Applications, Rollouts, Workflows | Redirect to `argo-skills` | GitOps |

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

## Evals (8 scenarios)

1. **Shipwright build setup** — generate Build + BuildStrategy for Go app with Buildah
2. **Tekton CI pipeline** — full pipeline with clone, test, build, scan, gitops-update tasks
3. **OSSM setup** — ServiceMeshControlPlane + mTLS + add namespace to mesh
4. **End-to-end delivery flow** — wire Tekton → Shipwright → GitOps → Istio → Rollout
5. **Platform onboarding** — onboard new team with namespace, pipeline, app, mesh
6. **DORA metrics** — PromQL queries + Grafana dashboard for 4 metrics
7. **Cross-layer debug** — "my change isn't in production" trace
8. **Platform health check** — check all components across all layers

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
