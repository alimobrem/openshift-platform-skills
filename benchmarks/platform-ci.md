# platform-ci

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| Shipwright build setup | 10/10 (100%) |
| Tekton CI pipeline | 10/10 (100%) |
| Tekton Triggers with EventListener | 10/10 (100%) |
| Diagnose broken PipelineRun | 8/8 (100%) |
| Shipwright vs Tekton Buildah trade-off | 6/7 (86%) |
| **Overall** | **44/45 (98%)** |

**Key behaviors observed:**
- Shipwright: correct Build + ClusterBuildStrategy with Buildah, Git SHA tags, registry auth, timeout, retention
- Tekton: full 5-task pipeline with runAfter chain, workspaces, Trivy severity filtering, gitops-update task
- Triggers: EventListener + GitHub ClusterInterceptor with secretRef + eventTypes filter, TriggerBinding/Template, RBAC scoped to PipelineRun creation
- Diagnose: identified all 3 bugs (missing workspaces, deprecated v1alpha1, missing runAfter), prioritized by severity (BLOCKER > HIGH)
- Trade-off: nuanced "yes but not all at once" with pilot-then-batch migration path. Miss: didn't mention Shipwright can be triggered from within a Tekton Pipeline (composable, not mutually exclusive)

### claude-sonnet-4-6

| Eval | Score |
|------|-------|
| Shipwright build setup | 10/10 (100%) |
| Tekton CI pipeline | 10/10 (100%) |
| **Overall** | **20/20 (100%)** |
