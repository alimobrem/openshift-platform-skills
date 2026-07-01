# platform-ci

## v0.3.0 (2026-07-01)

### claude-opus-4-6

| Eval | Type | Score |
|------|------|-------|
| Shipwright build setup | YAML gen | 10/10 (100%) |
| Tekton CI pipeline | YAML gen | 10/10 (100%) |
| Tekton Triggers with EventListener | YAML gen | 10/10 (100%) |
| Diagnose broken PipelineRun | Diagnose | 8/8 (100%) |
| Shipwright vs Tekton Buildah trade-off | Trade-off | 6/7 (86%) |
| Will this fix work? Wrong fix cluster-admin | Hard: wrong fix | 8/8 (100%) |
| **Overall** | | **52/53 (98%)** |

### claude-sonnet-4-6

| Eval | Type | Score |
|------|------|-------|
| Shipwright build setup | YAML gen | 10/10 (100%) |
| Tekton CI pipeline | YAML gen | 10/10 (100%) |
| Will this fix work? Wrong fix cluster-admin | Hard: wrong fix | 7/8 (88%) |
| **Overall** | | **27/28 (96%)** |

### Cross-model notes

- **Wrong fix:** Both refused cluster-admin. Opus additionally recommended GitOps handoff (pipeline shouldn't kubectl apply to prod at all). Sonnet provided the scoped RBAC fix but missed the architectural recommendation.
- **Trade-off (Shipwright vs Buildah):** Opus missed that Shipwright can be triggered from within Tekton Pipelines (composable, not mutually exclusive)
