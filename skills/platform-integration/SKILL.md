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
