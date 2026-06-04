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
| Canary Rollout + Istio traffic mgmt | 12/12 (100%) |
| Blue-green + Istio header preview | 12/12 (100%) |
| **Overall** | **124/124 (100%)** |

**Key behaviors observed:**
- Shipwright: correct Build + ClusterBuildStrategy with Buildah, Git SHA tags, registry auth, timeout, retention
- Tekton: full 5-task pipeline with runAfter chain, workspaces, Trivy severity filtering, gitops-update task
- OSSM: Istio CR (sailoperator.io/v1) + IstioCNI + strict mTLS PeerAuthentication + Kiali/OpenTelemetry/Prometheus
- E2E: all 8 layers wired (Shipwright → Tekton → Quay → ESO → Argo CD → Istio → Rollout → Promoter)
- Onboarding: complete team setup (namespace, quota, NetworkPolicy, RBAC, pipeline, AppProject, mesh)
- DORA: PromQL for all 4 metrics + Grafana dashboard JSON + PrometheusRule alerts
- Debug: 9-step cross-layer trace with CLI commands per layer
- Health: all 7 controllers checked with CRD verification
- Quay: QuayRegistry CR + Clair + robot accounts + scanning policies + Tekton integration
- ESO: ClusterSecretStore + Vault K8s auth + 3 ExternalSecrets with 1h refresh
- Canary: Rollout + VirtualService weight splitting + DestinationRule subsets + Prometheus AnalysisTemplate on istio_requests_total
- Blue-green: header-based preview routing (x-preview: true) + prePromotionAnalysis + manual promote flow

**All operators use `redhat-operators` catalog:**
openshift-pipelines-operator-rh, servicemeshoperator3, openshift-builds-operator,
external-secrets-operator, quay-operator, kiali-ossm, opentelemetry-product

### claude-sonnet-4-6

| Eval | Score |
|------|-------|
| Shipwright build setup | 10/10 (100%) |
| Tekton CI pipeline | 10/10 (100%) |
| OSSM setup | 9/10 (90%) |
| End-to-end delivery flow | 10/10 (100%) |
| Platform onboarding | 10/10 (100%) |
| DORA metrics | 10/10 (100%) |
| Cross-layer debug | 10/10 (100%) |
| Platform health check | 10/10 (100%) |
| Quay registry setup | 10/10 (100%) |
| ESO + Vault | 10/10 (100%) |
| **Overall** | **99/100 (99%)** |

Sonnet's only miss: OSSM eval — put all 3 services in one namespace instead of enrolling
3 separate namespaces with `istio-injection=enabled`.

### Cross-Model Summary

| Model | Core (10 evals) | Rollout+Istio (2 evals) | Total |
|-------|-----------------|------------------------|-------|
| Opus 4.6 | 100/100 (100%) | 24/24 (100%) | **124/124 (100%)** |
| Sonnet 4.6 | 99/100 (99%) | — | **99/100 (99%)** |

Both models perform nearly identically with the skill loaded. Sonnet is a strong
cost-effective option — 99% accuracy at lower cost.
