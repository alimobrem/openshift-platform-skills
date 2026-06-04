# OpenShift Platform Engineering Skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `platform-engineering` skill for the `openshift-platform-skills` repo — a unified AI skill covering Shipwright builds, Tekton pipelines, Quay registry, External Secrets, Istio/OSSM mesh, DORA metrics, and end-to-end delivery flows on OpenShift.

**Architecture:** Single skill with 9 reference docs, one SKILL.md routing layer, agent configs for 3 platforms, test fixtures, evals, and full open-source scaffolding. Follows the argo-skills repo patterns exactly.

**Tech Stack:** Markdown (skills), Bash (scripts), JSON (evals, plugin manifests), SVG (banner), YAML (test fixtures)

**Template repo:** `/Users/amobrem/ali/argo-skills` — use for file format, frontmatter, eval structure, agent config format, plugin manifests, CI workflows, README layout.

---

## Task 1: Repo Scaffolding

**Files:**
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `Brewfile`
- Create: `Makefile`
- Create: `CLAUDE.md`
- Create: `CONTRIBUTING.md`
- Create: `CODE_OF_CONDUCT.md`
- Create: `SECURITY.md`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create LICENSE (MIT)**

Copy the MIT license from `/Users/amobrem/ali/argo-skills/LICENSE`, update the copyright line to "The OpenShift Platform Skills authors".

- [ ] **Step 2: Create .gitignore**

```
.env
bin/
dist/
.local/
*-workspace/
workspace/
.playwright-mcp/
```

- [ ] **Step 3: Create Brewfile**

```
# Kubernetes
brew "kubectl"
brew "kustomize"
brew "yq"

# Tekton
brew "tektoncd/tools/tektoncd-cli"

# Argo (for GitOps layer integration)
brew "argocd"

# Istio
brew "istioctl"
```

- [ ] **Step 4: Create Makefile**

```makefile
.PHONY: help test-evals

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'

test-evals: ## Run skill evals
	@echo "Running platform-engineering evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-engineering/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-engineering/SKILL.md first, then answers the eval prompt. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."
```

- [ ] **Step 5: Create CLAUDE.md**

```
Load the skill-creator for tasks in this repo.

@README.md
```

- [ ] **Step 6: Create open-source docs**

Create `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md` — copy structure from `/Users/amobrem/ali/argo-skills/` and update repo name to `alimobrem/openshift-platform-skills`.

- [ ] **Step 7: Create CHANGELOG.md**

```markdown
# Changelog

## [0.1.0] - 2026-06-04

### Added

- Initial release of the `platform-engineering` skill
- 9 reference docs: Shipwright, Tekton, Istio/OSSM, Quay, External Secrets,
  delivery flows, platform onboarding, DORA metrics, troubleshooting
- 37 use cases across 8 layers
- 10 eval scenarios
- Agent configs for Claude Code, GitHub Copilot, Codex
```

- [ ] **Step 8: Create directory structure**

```bash
mkdir -p skills/platform-engineering/{references,evals}
mkdir -p agents/{claude-code,codex,github-copilot}
mkdir -p tests/platform-audit/{full-stack,mixed-issues}
mkdir -p .claude-plugin .codex-plugin
mkdir -p assets/screenshots
mkdir -p benchmarks
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Initial scaffolding: LICENSE, .gitignore, Brewfile, Makefile, open-source docs"
```

---

## Task 2: SKILL.md

**Files:**
- Create: `skills/platform-engineering/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Use the argo-knowledge SKILL.md at `/Users/amobrem/ali/argo-skills/skills/argo-knowledge/SKILL.md` as the format template. The SKILL.md must include:

**Frontmatter:**
```yaml
---
name: platform-engineering
description: >
  Unified platform engineering skill for OpenShift — covers Shipwright builds,
  Tekton/OpenShift Pipelines, Quay registry, External Secrets Operator, Istio/OpenShift
  Service Mesh, DORA metrics, and end-to-end delivery flows. Defaults to Quay + ESO
  but supports swapping registry, secrets, build, and mesh components. Use when users
  ask about CI/CD pipelines, container builds, service mesh configuration, environment
  promotion, platform onboarding, DORA metrics, or end-to-end delivery setup on OpenShift.
license: MIT
compatibility: Requires oc or kubectl; optionally tkn, istioctl, argocd
---
```

**Content sections (in order):**

1. Title and one-paragraph overview
2. Delivery lifecycle diagram (the ASCII flow from the spec)
3. How this skill works — routing table from spec (10 rows mapping user intent → reference file)
4. Optional components table — swappable defaults (registry, secrets, build, mesh)
5. Safety model — Generate → Preview → Confirm (copy pattern from argo-operations SKILL.md at `/Users/amobrem/ali/argo-skills/skills/argo-operations/SKILL.md`)
6. CRD reference table — all CRDs across all layers:
   - Shipwright: Build, BuildRun, BuildStrategy, ClusterBuildStrategy
   - Tekton: Pipeline, PipelineRun, Task, ClusterTask, TaskRun, EventListener, TriggerBinding, TriggerTemplate
   - Istio/OSSM: ServiceMeshControlPlane, ServiceMeshMemberRoll, VirtualService, DestinationRule, Gateway, PeerAuthentication, AuthorizationPolicy
   - Quay: QuayRegistry
   - ESO: SecretStore, ClusterSecretStore, ExternalSecret, ClusterExternalSecret
7. Reference index — table mapping topics to reference files (same as routing table but for internal loading)
8. Edge cases table

Target: ~300 lines. Keep concise — heavy content goes in reference docs.

- [ ] **Step 2: Commit**

```bash
git add skills/platform-engineering/SKILL.md
git commit -m "Add platform-engineering SKILL.md with routing, safety model, CRD reference"
```

---

## Task 3: Reference Docs — Build & Pipeline Layer

**Files:**
- Create: `skills/platform-engineering/references/shipwright.md`
- Create: `skills/platform-engineering/references/tekton.md`

- [ ] **Step 1: Write shipwright.md (~400 lines)**

Content from spec. Must include:
- CRD table (Build, BuildRun, BuildStrategy, ClusterBuildStrategy) with apiVersion/kind
- Build strategies with YAML examples (Buildah default, Buildpacks, S2I)
- Source config (Git, local, bundle)
- Output config (image push with registry auth secret)
- BuildConfig → Shipwright migration guide (side-by-side comparison)
- Integration section: how pipeline triggers BuildRun, how image tag feeds GitOps
- Common mistakes section (wrong strategy name, missing push secret, registry URL format)

- [ ] **Step 2: Write tekton.md (~500 lines)**

Content from spec. Must include:
- CRD table with all Tekton CRDs
- OpenShift Pipelines operator install (Subscription YAML)
- Pipeline-as-Code (PaC) setup
- Common task catalog (git-clone, buildah, trivy-scanner, openshift-client) with YAML
- CI pipeline pattern: complete Pipeline YAML with 6 tasks wired together
- Trigger pattern: EventListener + TriggerBinding + TriggerTemplate YAML
- Pipeline-to-GitOps handoff: Tekton task that commits image tag to GitOps repo
- Workspace patterns (PVC vs VolumeClaimTemplate vs emptyDir)
- RBAC: ServiceAccount + RoleBinding for registry push, Git write

- [ ] **Step 3: Commit**

```bash
git add skills/platform-engineering/references/shipwright.md skills/platform-engineering/references/tekton.md
git commit -m "Add shipwright and tekton reference docs"
```

---

## Task 4: Reference Docs — Registry & Secrets Layer

**Files:**
- Create: `skills/platform-engineering/references/quay.md`
- Create: `skills/platform-engineering/references/external-secrets.md`

- [ ] **Step 1: Write quay.md (~300 lines)**

Content from spec. Must include:
- QuayRegistry CRD + operator install (Subscription YAML)
- Organization, repository, robot account setup
- Registry auth secret (dockerconfigjson) YAML
- Clair image scanning config
- Mirroring rules for air-gapped
- Integration: Shipwright/Tekton push config, Argo CD Image Updater poll config
- **Swap guide table:** columns for Quay, Harbor, internal registry, ECR, GCR — rows for push URL format, Secret type, auth method, scanning, mirroring

- [ ] **Step 2: Write external-secrets.md (~300 lines)**

Content from spec. Must include:
- ESO operator install (Subscription or Helm)
- SecretStore YAML for each backend (Vault, AWS, Azure, GCP)
- ExternalSecret patterns: single key, templated, data-from — with YAML examples
- Integration matrix: which secrets feed which layer (pipeline SA → registry push, Argo CD → repo creds, mesh → TLS certs)
- Rotation: refreshInterval config + verification
- **Swap guide table:** columns for ESO, Vault Agent, Sealed Secrets, SOPS — rows for install method, CRDs, rotation support, GitOps compatibility

- [ ] **Step 3: Commit**

```bash
git add skills/platform-engineering/references/quay.md skills/platform-engineering/references/external-secrets.md
git commit -m "Add quay and external-secrets reference docs with swap guides"
```

---

## Task 5: Reference Docs — Mesh Layer

**Files:**
- Create: `skills/platform-engineering/references/istio.md`

- [ ] **Step 1: Write istio.md (~500 lines)**

Content from spec. Must include:
- OSSM operator install (ServiceMeshControlPlane, ServiceMeshMemberRoll YAML)
- Differences from upstream Istio (OSSM uses Maistra, different CRDs for membership)
- Traffic management: VirtualService with weight-based and header-based routing YAML
- DestinationRule: subsets, circuit breaking (connectionPool, outlierDetection), retries
- Security: PeerAuthentication strict mTLS, AuthorizationPolicy allow/deny, RequestAuthentication JWT
- Observability: Kiali setup, Jaeger config, Prometheus queries (istio_requests_total, istio_request_duration_milliseconds)
- Rollout integration: Argo Rollout with Istio trafficRouting YAML (VirtualService + DestinationRule)
- Gateway config for external traffic
- Common mistakes: missing sidecar injection label, mTLS mode mismatch, VirtualService host mismatch

- [ ] **Step 2: Commit**

```bash
git add skills/platform-engineering/references/istio.md
git commit -m "Add istio/OSSM reference doc"
```

---

## Task 6: Reference Docs — Integration Layer

**Files:**
- Create: `skills/platform-engineering/references/delivery-flows.md`
- Create: `skills/platform-engineering/references/platform-onboarding.md`

- [ ] **Step 1: Write delivery-flows.md (~400 lines)**

Content from spec. Must include:
- **The golden path:** complete end-to-end wiring with all CRDs. Show which resource references which, and what triggers what. Use the delivery lifecycle diagram.
- **Variant flows:** 4 variants:
  1. Full stack (Shipwright + Tekton + Quay + ESO + Argo CD + Istio + Rollouts + Promoter)
  2. No Shipwright (Tekton does the build with buildah task)
  3. No Istio (replica-based Rollout canary)
  4. No promoter (manual promotion via Argo CD sync)
- **Secrets flow diagram:** which ServiceAccount/Secret feeds which tool
- **Complete YAML example:** 3-environment flow (dev → staging → prod) with all resources. This is the showcase — should be comprehensive and correct.

- [ ] **Step 2: Write platform-onboarding.md (~300 lines)**

Content from spec. Must include:
- Onboarding checklist: what gets created for a new team/app
- Complete YAML template: Namespace, ResourceQuota, NetworkPolicy, Quay org config, ESO SecretStore, Tekton Pipeline, Argo CD AppProject + Application, ServiceMeshMember, RBAC
- Self-service pattern: ApplicationSet that generates all onboarding resources from a config file
- Guard rails: what restrictions to enforce (quotas, network policies, mesh policies, AppProject sourceRepos/destinations)

- [ ] **Step 3: Commit**

```bash
git add skills/platform-engineering/references/delivery-flows.md skills/platform-engineering/references/platform-onboarding.md
git commit -m "Add delivery-flows and platform-onboarding reference docs"
```

---

## Task 7: Reference Docs — Metrics & Troubleshooting

**Files:**
- Create: `skills/platform-engineering/references/dora-metrics.md`
- Create: `skills/platform-engineering/references/troubleshooting.md`

- [ ] **Step 1: Write dora-metrics.md (~250 lines)**

Content from spec. Must include:
- 4 DORA metrics table: metric name, definition, elite/low thresholds, data source
- Deployment Frequency PromQL: count Argo CD sync-succeeded events per day
- Lead Time PromQL: time between Git commit timestamp and Argo CD sync completion
- Change Failure Rate PromQL: ratio of failed syncs to total syncs
- MTTR PromQL: duration between Degraded health and Healthy recovery
- Grafana dashboard JSON: complete importable dashboard with 4 panels
- PrometheusRule YAML: alert when DORA metrics drop below thresholds

- [ ] **Step 2: Write troubleshooting.md (~350 lines)**

Content from spec. Must include:
- "My change isn't in production" — step-by-step trace:
  1. Is the commit in the Git repo? (check git log)
  2. Did the pipeline run? (tkn pipelinerun list / oc get pipelinerun)
  3. Did the build succeed? (oc get buildrun)
  4. Is the image in the registry? (skopeo inspect / oc get imagestream)
  5. Did the GitOps repo get updated? (check image tag in manifests)
  6. Did Argo CD sync? (argocd app get / oc get application)
  7. Is the mesh routing traffic? (check VirtualService weights)
  8. Is the Rollout progressing? (kubectl argo rollouts get)
  9. Is the promoter advancing? (oc get promotionstrategy)
- Per-layer symptom → cause table
- Cross-layer issues (5-6 common ones with root cause and fix)
- Debug commands table: per tool, CLI + oc fallback

- [ ] **Step 3: Commit**

```bash
git add skills/platform-engineering/references/dora-metrics.md skills/platform-engineering/references/troubleshooting.md
git commit -m "Add dora-metrics and troubleshooting reference docs"
```

---

## Task 8: Test Fixtures

**Files:**
- Create: `tests/platform-audit/full-stack/` (6-8 YAML files)
- Create: `tests/platform-audit/mixed-issues/` (6-8 YAML files)

- [ ] **Step 1: Create full-stack fixture**

A well-configured platform setup. Create these files:
- `build.yaml` — Shipwright Build + BuildStrategy (Buildah)
- `pipeline.yaml` — Tekton Pipeline with 5 tasks + EventListener + TriggerTemplate
- `quay-config.yaml` — QuayRegistry CR + robot account Secret (placeholder)
- `external-secret.yaml` — ClusterSecretStore (Vault) + ExternalSecret for registry auth
- `mesh.yaml` — ServiceMeshControlPlane + ServiceMeshMemberRoll + PeerAuthentication strict
- `delivery.yaml` — PromotionStrategy with 3 environments + ArgocdCommitStatus
- `onboarding.yaml` — Namespace + ResourceQuota + NetworkPolicy + RBAC

All resources should be correctly configured — this fixture should pass an audit cleanly.

- [ ] **Step 2: Create mixed-issues fixture**

A platform setup with deliberate issues. Create these files:
- `insecure-pipeline.yaml` — Pipeline with ServiceAccount using cluster-admin, no workspace isolation
- `bad-build.yaml` — Build pushing to `latest` tag, no BuildStrategy specified
- `plain-secret.yaml` — plain-text Secret with registry password (should use ESO)
- `weak-mesh.yaml` — PeerAuthentication with mode: PERMISSIVE (should be STRICT for prod)
- `no-scanning.yaml` — QuayRegistry without Clair scanning enabled
- `missing-promotion.yaml` — Applications deployed directly without PromotionStrategy (no gating)
- `no-limits.yaml` — Pipeline Tasks with no resource limits, no activeDeadlineSeconds

- [ ] **Step 3: Commit**

```bash
git add tests/
git commit -m "Add test fixtures: full-stack (clean) and mixed-issues (audit targets)"
```

---

## Task 9: Evals

**Files:**
- Create: `skills/platform-engineering/evals/evals.json`

- [ ] **Step 1: Write evals.json**

10 eval scenarios from the spec. Each eval has 8-12 outcome-based expectations (not process-based). Follow the format from `/Users/amobrem/ali/argo-skills/skills/argo-knowledge/evals/evals.json`.

```json
{
  "skill_name": "platform-engineering",
  "evals": [
    {
      "id": 1,
      "name": "Shipwright build setup",
      "prompt": "Set up Shipwright to build my Go application from a Dockerfile in the 'payments' namespace. Use Buildah strategy, source from https://github.com/acme/payments.git, and push to quay.io/acme/payments. Generate the Build, BuildStrategy, and the registry auth Secret.",
      "expectations": [...]
    },
    ...10 evals total from spec
  ]
}
```

Each eval must have specific, mechanically verifiable expectations that test OUTCOMES:
- "Generates a Build with apiVersion shipwright.io/v1beta1"
- "Push output references quay.io/acme/payments"
- "Registry auth uses dockerconfigjson Secret"
NOT process expectations like "Reads shipwright.md reference file".

- [ ] **Step 2: Commit**

```bash
git add skills/platform-engineering/evals/
git commit -m "Add 10 eval scenarios for platform-engineering skill"
```

---

## Task 10: Agent Configs & Plugin Manifests

**Files:**
- Create: `agents/claude-code/platform.md`
- Create: `agents/codex/platform.toml`
- Create: `agents/github-copilot/platform.agent.md`
- Create: `.claude-plugin/marketplace.json`
- Create: `.codex-plugin/plugin.json`

- [ ] **Step 1: Write Claude Code agent config**

Copy format from `/Users/amobrem/ali/argo-skills/agents/claude-code/argocd.md`. Update:
- Name: `platform`
- Skills list: `platform-engineering`
- Routing section: map Build/Pipeline/Registry/Secrets/Mesh/Integration/Onboarding/Metrics/Debug to the skill
- Add redirect to `argo-skills` for Argo CD questions

- [ ] **Step 2: Write Codex agent config**

Copy format from `/Users/amobrem/ali/argo-skills/agents/codex/argocd.toml`. Update name, description, skill path.

- [ ] **Step 3: Write Copilot agent config**

Copy format from `/Users/amobrem/ali/argo-skills/agents/github-copilot/argocd.agent.md`. Update name, tools, skill paths, routing.

- [ ] **Step 4: Write plugin manifests**

Copy `.claude-plugin/marketplace.json` and `.codex-plugin/plugin.json` from argo-skills. Update:
- Name: `openshift-platform`
- Description: reference OpenShift platform engineering
- Skills path: `./skills/platform-engineering`
- Agent path: `./agents/claude-code/platform.md`

- [ ] **Step 5: Commit**

```bash
git add agents/ .claude-plugin/ .codex-plugin/
git commit -m "Add agent configs (Claude, Copilot, Codex) and plugin manifests"
```

---

## Task 11: CI Workflows

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `.github/workflows/evals.yml`

- [ ] **Step 1: Write CI workflow**

Copy from `/Users/amobrem/ali/argo-skills/.github/workflows/ci.yml`. Update to validate:
- JSON files (evals, plugin manifests)
- SKILL.md frontmatter
- Test fixture YAML syntax (yq validation)

- [ ] **Step 2: Write release workflow**

Copy from `/Users/amobrem/ali/argo-skills/.github/workflows/release.yml`. Update skill name in package step.

- [ ] **Step 3: Write evals workflow**

Copy from `/Users/amobrem/ali/argo-skills/.github/workflows/evals.yml`. Update to single skill `platform-engineering`.

- [ ] **Step 4: Commit**

```bash
git add .github/
git commit -m "Add CI, release, and evals workflows"
```

---

## Task 12: README & Banner

**Files:**
- Create: `assets/banner.svg`
- Create: `README.md`
- Create: `AGENTS.md`

- [ ] **Step 1: Create SVG banner**

Same style as `/Users/amobrem/ali/argo-skills/assets/banner.svg` but update:
- Title: "OpenShift Platform Skills"
- Subtitle: "AI-powered platform engineering for OpenShift"
- Skill pills: `shipwright` (orange), `tekton` (blue), `istio` (purple), `quay` (red), `external-secrets` (green), `dora` (teal)
- Platform line: "Works with Claude Code · GitHub Copilot · Codex"

- [ ] **Step 2: Write README.md**

Follow the structure from `/Users/amobrem/ali/argo-skills/README.md`:
1. Banner centered
2. Badges (MIT, PRs welcome, OpenShift version)
3. Tagline
4. Quick Start (collapsible)
5. Install (collapsible per platform)
6. Usage Guide with routing diagram and per-layer prompt examples
7. Benchmarks section (placeholder — filled after evals run)
8. Contributing (collapsible)
9. Code of Conduct, Security, License links

- [ ] **Step 3: Write AGENTS.md**

Copy from `/Users/amobrem/ali/argo-skills/AGENTS.md`. Update repo layout, skill name, eval instructions.

- [ ] **Step 4: Commit**

```bash
git add assets/ README.md AGENTS.md
git commit -m "Add README with banner, usage guide, and AGENTS.md"
```

---

## Task 13: Final Push & Release

- [ ] **Step 1: Push all commits**

```bash
git push origin main
```

- [ ] **Step 2: Set repo metadata**

```bash
gh repo edit alimobrem/openshift-platform-skills \
  --add-topic openshift \
  --add-topic platform-engineering \
  --add-topic tekton \
  --add-topic shipwright \
  --add-topic istio \
  --add-topic service-mesh \
  --add-topic quay \
  --add-topic external-secrets \
  --add-topic gitops \
  --add-topic ai-agent \
  --add-topic claude-code \
  --add-topic dora-metrics
```

- [ ] **Step 3: Tag and release**

```bash
git tag -a v0.1.0 -m "v0.1.0 — Initial release"
git push origin v0.1.0
gh release create v0.1.0 --title "v0.1.0" --generate-notes
```

- [ ] **Step 4: Verify plugin install**

```
/plugin marketplace add alimobrem/openshift-platform-skills
/plugin install openshift-platform@platform
```
