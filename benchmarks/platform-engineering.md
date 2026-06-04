# platform-engineering

## v0.1.0 (2026-06-04)

Model: `claude-opus-4-6`

**Results**

| Eval | Score |
|------|-------|
| Shipwright build setup | 10/10 (100%) |
| Tekton CI pipeline | 10/10 (100%) |
| OSSM setup | 10/10 (100%) |
| End-to-end delivery flow | 10/10 (100%) |
| Platform onboarding | 10/10 (100%) |
| DORA metrics | 10/10 (100%) |
| Cross-layer debug | 10/10 (100%) |
| Platform health check | 10/10 (100%) |
| Quay registry setup | 10/10 (100%) |
| ESO + Vault | 10/10 (100%) |
| **Overall** | **100/100 (100%)** |

**Key behaviors observed:**
- Shipwright: correct Build + ClusterBuildStrategy with Buildah, Git SHA tags, registry auth, timeout, retention
- Tekton: full 5-task pipeline with runAfter chain, workspaces, Trivy severity filtering, gitops-update task
- OSSM: Istio CR + IstioCNI + strict mTLS PeerAuthentication + Kiali/OpenTelemetry/Prometheus
- E2E: all 8 layers wired (Shipwright → Tekton → Quay → ESO → Argo CD → Istio → Rollout → Promoter)
- Onboarding: complete team setup (namespace, quota, NetworkPolicy, RBAC, pipeline, AppProject, mesh)
- DORA: PromQL for all 4 metrics + Grafana dashboard JSON + PrometheusRule alerts
- Debug: 9-step cross-layer trace with CLI commands per layer
- Health: all 7 controllers checked with CRD verification
- Quay: QuayRegistry CR + Clair + robot accounts + scanning policies + Tekton integration
- ESO: ClusterSecretStore + Vault K8s auth + 3 ExternalSecrets with 1h refresh
