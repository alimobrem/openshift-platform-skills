# platform-mesh

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| OSSM 3.0 setup | 10/10 (100%) |
| Rollout + Istio canary traffic mgmt | 12/12 (100%) |
| Blue-green + Istio header preview | 12/12 (100%) |
| **Overall** | **34/34 (100%)** |

**Key behaviors observed:**
- OSSM: Istio CR (sailoperator.io/v1) + IstioCNI + strict mTLS PeerAuthentication + Kiali/OpenTelemetry/Prometheus
- Canary: Rollout + VirtualService weight splitting + DestinationRule subsets + Prometheus AnalysisTemplate on istio_requests_total
- Blue-green: header-based preview routing (x-preview: true) + prePromotionAnalysis + manual promote flow

### claude-sonnet-4-6

| Eval | Score |
|------|-------|
| OSSM 3.0 setup | 9/10 (90%) |
| **Overall** | **9/10 (90%)** |

Sonnet miss: put all 3 services in one namespace instead of enrolling
3 separate namespaces with `istio-injection=enabled`.
