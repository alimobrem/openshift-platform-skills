# platform-integration

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| End-to-end delivery flow | 10/10 (100%) |
| Platform onboarding | 10/10 (100%) |
| DORA metrics | 10/10 (100%) |
| Cross-layer debug | 10/10 (100%) |
| Rollout paused vs Argo CD Synced | 8/8 (100%) |
| **Overall** | **48/48 (100%)** |

**Key behaviors observed:**
- E2E: all 8 layers wired (Shipwright → Tekton → Quay → ESO → Argo CD → Istio → Rollout → Promoter)
- Onboarding: complete team setup (namespace, quota, NetworkPolicy, RBAC, pipeline, AppProject, mesh)
- DORA: PromQL for all 4 metrics + Grafana dashboard JSON + PrometheusRule alerts
- Debug: 9-step cross-layer trace with CLI commands per layer
- Rollout vs Synced: correctly identified Paused Rollout as root cause, explained Argo CD Synced ≠ Rollout progression, distinguished sync status from pod progression, did NOT suggest re-syncing Argo CD

### claude-sonnet-4-6

| Eval | Score |
|------|-------|
| End-to-end delivery flow | 10/10 (100%) |
| Platform onboarding | 10/10 (100%) |
| DORA metrics | 10/10 (100%) |
| Cross-layer debug | 10/10 (100%) |
| **Overall** | **40/40 (100%)** |
