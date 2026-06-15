# platform-mesh

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| OSSM 3.0 setup | 10/10 (100%) |
| Rollout + Istio canary traffic mgmt | 12/12 (100%) |
| Blue-green + Istio header preview | 12/12 (100%) |
| Canary vs blue-green for payments API | 2/7 (29%) |
| Diagnose 503s after strict mTLS | 7/8 (88%) |
| **Overall** | **43/49 (88%)** |

**Key behaviors observed:**
- OSSM: Istio CR (sailoperator.io/v1) + IstioCNI + strict mTLS PeerAuthentication + Kiali/OpenTelemetry/Prometheus
- Canary: Rollout + VirtualService weight splitting + DestinationRule subsets + Prometheus AnalysisTemplate on istio_requests_total
- Blue-green: header-based preview routing (x-preview: true) + prePromotionAnalysis + manual promote flow
- Trade-off MISS: recommended canary instead of blue-green for payments API. Reasoning was technically defensible (canary with header-based dark launch + 5% weight) but missed the domain judgment — for financial transactions, blue-green's zero-real-traffic-before-validation model is safer
- mTLS diagnose: correctly identified root cause (Prometheus without sidecar can't do mTLS), recommended per-port PERMISSIVE (least privilege). Miss: didn't mention Istio built-in metrics endpoint as alternative scrape source

### claude-sonnet-4-6

| Eval | Score |
|------|-------|
| OSSM 3.0 setup | 9/10 (90%) |
| **Overall** | **9/10 (90%)** |

Sonnet miss: put all 3 services in one namespace instead of enrolling
3 separate namespaces with `istio-injection=enabled`.
