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
