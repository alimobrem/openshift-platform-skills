# platform-ci

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| Shipwright build setup | 10/10 (100%) |
| Tekton CI pipeline | 10/10 (100%) |
| Tekton Triggers with EventListener | 10/10 (100%) |
| **Overall** | **30/30 (100%)** |

**Key behaviors observed:**
- Shipwright: correct Build + ClusterBuildStrategy with Buildah, Git SHA tags, registry auth, timeout, retention
- Tekton: full 5-task pipeline with runAfter chain, workspaces, Trivy severity filtering, gitops-update task
- Triggers: EventListener + GitHub ClusterInterceptor with secretRef + eventTypes filter, TriggerBinding/Template, RBAC scoped to PipelineRun creation

### claude-sonnet-4-6

| Eval | Score |
|------|-------|
| Shipwright build setup | 10/10 (100%) |
| Tekton CI pipeline | 10/10 (100%) |
| **Overall** | **20/20 (100%)** |
