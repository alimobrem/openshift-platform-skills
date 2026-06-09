# Design: Split openshift-platform-skills into 4 Focused Skills

**Date:** 2026-06-09
**Status:** Proposed

## Goal

Replace the monolithic `platform-engineering` skill with 4 focused skills, add executable
tooling (3 shell scripts), expand evals from 2 to 12, and prepare for cross-model benchmarks.
Modeled after the argo-skills repo pattern.

## Motivation

The current monolithic skill has 9 reference files (6,114 lines) behind a single 309-line
SKILL.md. This causes:

1. **Imprecise triggering** — one description must cover builds, pipelines, mesh, secrets,
   metrics, and more. A question about Tekton loads the same skill as a question about DORA.
2. **Large context loads** — the SKILL.md routes to references, but the agent must parse the
   full routing table every time.
3. **No executable tooling** — unlike argo-repo-audit (which has discover.sh, validate.sh,
   and 7 CRD schemas), platform-skills is purely reference-based.
4. **Thin eval coverage** — 2 evals for 9 reference areas vs argo-skills' 8 evals across 4 skills.

## Directory Structure After Split

```
skills/
├── platform-ci/
│   ├── SKILL.md
│   ├── references/
│   │   ├── shipwright.md
│   │   └── tekton.md
│   └── evals/evals.json
├── platform-mesh/
│   ├── SKILL.md
│   ├── references/
│   │   └── istio.md
│   └── evals/evals.json
├── platform-infra/
│   ├── SKILL.md
│   ├── references/
│   │   ├── quay.md
│   │   └── external-secrets.md
│   └── evals/evals.json
├── platform-integration/
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
│   ├── assets/schemas/
│   │   ├── pipeline-tekton-v1.json
│   │   ├── task-tekton-v1.json
│   │   ├── build-shipwright-v1beta1.json
│   │   ├── buildstrategy-shipwright-v1beta1.json
│   │   ├── virtualservice-networking-istio-v1.json
│   │   ├── destinationrule-networking-istio-v1.json
│   │   ├── externalsecret-external-secrets-v1.json
│   │   └── secretstore-external-secrets-v1.json
│   └── evals/evals.json
```

The old `skills/platform-engineering/` directory is deleted entirely.

## Skill Definitions

### platform-ci

**Triggers on:** builds, images, Buildah, Shipwright, pipelines, Tasks, Triggers, CI,
PipelineRun, BuildRun, OpenShift Pipelines, container build

**References:** shipwright.md, tekton.md

**CRDs owned:**

| Kind | apiVersion |
|------|-----------|
| Build | shipwright.io/v1beta1 |
| BuildRun | shipwright.io/v1beta1 |
| BuildStrategy | shipwright.io/v1beta1 |
| ClusterBuildStrategy | shipwright.io/v1beta1 |
| Pipeline | tekton.dev/v1 |
| PipelineRun | tekton.dev/v1 |
| Task | tekton.dev/v1 |
| TaskRun | tekton.dev/v1 |
| EventListener | triggers.tekton.dev/v1beta1 |
| TriggerBinding | triggers.tekton.dev/v1beta1 |
| TriggerTemplate | triggers.tekton.dev/v1beta1 |

**SKILL.md contents:**
- Frontmatter with focused description
- Rules 1 (correct apiVersion), 2 (load references on-demand), 4 (validate YAML), 5 (canonical patterns)
- CRD reference table (above)
- Reference index: shipwright.md for build questions, tekton.md for pipeline questions
- Common mistakes: #1 (v1alpha1 vs v1beta1), #2 (missing workspace bindings), #5 (pipeline without gitops-update), #6 (robot account not linked)
- Safety model (generate → preview → confirm for BuildRun/PipelineRun creation)
- Edge cases: vanilla K8s (no OpenShift Pipelines operator), mixed build tooling

**Evals (3):**
1. Shipwright build setup (existing eval #1 — 10 expectations)
2. Tekton CI pipeline (existing eval #2 — 10 expectations)
3. NEW: Tekton Triggers with EventListener — generate EventListener + TriggerBinding +
   TriggerTemplate for GitHub webhook, with RBAC and ServiceAccount

### platform-mesh

**Triggers on:** mesh, mTLS, traffic, VirtualService, Kiali, OSSM, service mesh, Istio,
canary with Istio, blue-green with Istio, circuit breaker, fault injection, DestinationRule

**References:** istio.md

**CRDs owned:**

| Kind | apiVersion |
|------|-----------|
| Istio | sailoperator.io/v1 |
| IstioCNI | sailoperator.io/v1 |
| VirtualService | networking.istio.io/v1 |
| DestinationRule | networking.istio.io/v1 |
| Gateway | networking.istio.io/v1 |
| PeerAuthentication | security.istio.io/v1 |
| AuthorizationPolicy | security.istio.io/v1 |

**SKILL.md contents:**
- Frontmatter with focused description
- Rules 1, 2, 4, 5, 6 (state trade-offs for traffic strategies)
- CRD reference table
- Reference index: istio.md for all mesh questions
- Common mistakes: #4 (missing istio-injection label), #7 (VirtualService host mismatch),
  #8 (DestinationRule subset wrong labels)
- Safety model for VirtualService/DestinationRule changes
- Edge cases: no mesh (replica-based canary only), vanilla K8s (upstream Istio vs OSSM)

**Evals (3):**
1. OSSM 3.0 setup (existing eval #3 — 10 expectations)
2. Canary Rollout + Istio (existing eval #11 — 12 expectations)
3. Blue-green + Istio preview (existing eval #12 — 12 expectations)

### platform-infra

**Triggers on:** registry, Quay, Harbor, image push, robot accounts, scanning, secrets,
Vault, ESO, ExternalSecret, credentials, SecretStore, rotation

**References:** quay.md, external-secrets.md

**CRDs owned:**

| Kind | apiVersion |
|------|-----------|
| QuayRegistry | quay.redhat.com/v1 |
| SecretStore | external-secrets.io/v1 |
| ClusterSecretStore | external-secrets.io/v1 |
| ExternalSecret | external-secrets.io/v1 |
| ClusterExternalSecret | external-secrets.io/v1 |

**SKILL.md contents:**
- Frontmatter with focused description
- Rules 1, 2, 4, 5, 7 (ask about optional components when ambiguous — registry and secrets
  are the most commonly swapped layers)
- CRD reference table
- Reference index: quay.md for registry, external-secrets.md for secrets
- Swappable components table: Quay vs Harbor vs internal registry; ESO vs Sealed Secrets vs Vault CSI
- Common mistakes: #3 (wrong SecretStore kind), #6 (robot account not linked)
- Safety model for Secret creation and registry operations
- Edge cases: air-gapped clusters (ImageDigestMirrorSet), non-OpenShift (no Quay operator)

**Evals (2):**
1. Quay registry setup (existing eval #9 — 10 expectations)
2. ESO + Vault (existing eval #10 — 11 expectations)

### platform-integration

**Triggers on:** full flow, end-to-end, onboarding, DORA, metrics, health check, debug,
platform audit, "why isn't X in prod", "set up everything", team provisioning, deployment
frequency, lead time, MTTR

**References:** delivery-flows.md, platform-onboarding.md, dora-metrics.md, troubleshooting.md

**CRDs owned:**

| Kind | apiVersion |
|------|-----------|
| PromotionStrategy | promoter.argoproj.io/v1alpha1 |
| ChangeTransferPolicy | promoter.argoproj.io/v1alpha1 |
| CommitStatus | promoter.argoproj.io/v1alpha1 |

**Also references CRDs from other skills** (Build, Pipeline, VirtualService, ExternalSecret, etc.)
when wiring end-to-end flows. Does not duplicate those CRD tables — refers to the owning skill.

**SKILL.md contents:**
- Frontmatter with focused description
- Rules 1, 2, 4, 5, 6, 8 (redirect Argo CD questions to argo-skills)
- CRD reference table (promoter CRDs only, cross-references other skills)
- Reference index: 4 files mapped by topic
- Delivery lifecycle diagram (the existing code→build→pipeline→sync→mesh→rollout→promote flow)
- Script integration: when to run health-check.sh, discover.sh, validate.sh
- Common mistakes: #5 (pipeline without gitops-update), #9 (promoter without CommitStatus),
  #10 (mixing kustomize and helm)
- Safety model (full generate → preview → confirm, plus destructive operations checklist)
- Edge cases: mixed tooling, cluster not reachable, air-gapped, multiple Argo CD instances

**Scripts:**

`scripts/health-check.sh` — Operator pre-flight:
- Checks 7 operators: openshift-pipelines, openshift-builds, servicemeshoperator3,
  quay-operator, external-secrets-operator, kiali, opentelemetry
- For each: pod status, CRD registered, CSV phase
- Outputs structured JSON: `{"operator": "...", "status": "healthy|degraded|missing", "version": "...", "namespace": "..."}`
- Exit codes: 0 = all healthy, 1 = degraded, 2 = missing required operator

`scripts/discover.sh` — Repo pattern scan:
- Finds YAML files containing platform CRDs (Build, Pipeline, VirtualService, ExternalSecret,
  QuayRegistry, Istio, PromotionStrategy, etc.)
- Groups by kind, namespace, and directory
- Detects: wrong apiVersions (v1alpha1 vs v1beta1), missing required fields
- Outputs JSON inventory: `{"files": [...], "kinds": {...}, "issues": [...]}`

`scripts/validate.sh` — Schema validation:
- Validates discovered YAML against JSON schemas in `assets/schemas/`
- Schemas for 8 CRDs: Pipeline, Task, Build, BuildStrategy, VirtualService,
  DestinationRule, ExternalSecret, SecretStore
- Uses `kubeconform` if available, falls back to `yq` field checks
- Outputs per-file results: `{"file": "...", "kind": "...", "valid": true|false, "errors": [...]}`

**Evals (4):**
1. End-to-end delivery flow (existing eval #4 — 10 expectations)
2. Platform onboarding (existing eval #5 — 10 expectations)
3. DORA metrics (existing eval #6 — 10 expectations)
4. Cross-layer debug (existing eval #7 — 10 expectations)

The existing "Platform health check" eval (#8) becomes a script-based test under `test-scripts`
in the Makefile. The test runs `health-check.sh` against mock `oc`/`kubectl` output fixtures
in `tests/platform-integration/` and validates the JSON output structure and exit codes.
This is not an LLM eval — it's a shell script unit test.

## Plugin Registry Updates

`.claude-plugin/marketplace.json` changes from:

```json
"skills": ["./skills/platform-engineering"]
```

to:

```json
"skills": [
  "./skills/platform-ci",
  "./skills/platform-mesh",
  "./skills/platform-infra",
  "./skills/platform-integration"
]
```

Similarly update `.codex-plugin/plugin.json` if it exists.

## Agent Updates

`agents/claude-code/platform.md` — update to list all 4 skills and describe when each triggers.
`agents/codex/platform.toml` — same.
`agents/github-copilot/platform.agent.md` — same.

## Makefile Updates

Replace single `test-evals` target with per-skill targets:

```makefile
test-ci:          ## Run platform-ci evals
test-mesh:        ## Run platform-mesh evals
test-infra:       ## Run platform-infra evals
test-integration: ## Run platform-integration evals
test-all:         ## Run all skill evals
test-scripts:     ## Run health-check, discover, validate against test fixtures
```

## Benchmark Files

One per skill, replacing the single `benchmarks/platform-engineering.md`:

- `benchmarks/platform-ci.md`
- `benchmarks/platform-mesh.md`
- `benchmarks/platform-infra.md`
- `benchmarks/platform-integration.md`

Cross-model benchmarks (Sonnet results) added after initial Opus eval run.

## README Updates

- Usage Guide section reorganized with 4 skill headings instead of 9 layer headings
- Benchmark table shows per-skill scores
- Install section unchanged (plugin name stays `openshift-platform-skills`)
- Quick Start examples updated to reflect new skill names

## AGENTS.md Updates

- Repository Layout section updated to show multi-skill structure
- "Adding a New Skill" section unchanged (already generic)

## Migration

1. Create new skill directories with SKILL.md files
2. Move reference files from `platform-engineering/references/` to new locations
3. Split evals.json into 4 per-skill eval files
4. Write 3 shell scripts + download 8 CRD schemas
5. Update marketplace.json, agent files, Makefile
6. Delete `skills/platform-engineering/`
7. Update README, AGENTS.md, benchmarks
8. Run all evals to validate
9. Run Sonnet cross-model benchmarks

## What Does NOT Change

- Repository name (`openshift-platform-skills`)
- Plugin name in marketplace
- License, CODE_OF_CONDUCT, SECURITY, CONTRIBUTING
- Reference file content (moved, not rewritten)
- The companion relationship with argo-skills
- Test fixtures directory structure
