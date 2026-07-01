# platform-mesh

## v0.3.0 (2026-07-01)

### claude-opus-4-6

| Eval | Type | Score |
|------|------|-------|
| OSSM 3.0 setup | YAML gen | 10/10 (100%) |
| Rollout + Istio canary traffic mgmt | YAML gen | 12/12 (100%) |
| Blue-green + Istio header preview | YAML gen | 12/12 (100%) |
| Canary vs blue-green for payments API | Trade-off | 2/7 (29%) |
| Diagnose 503s after strict mTLS | Diagnose | 7/8 (88%) |
| Red herring: 503s not caused by mTLS | Hard: red herring | 6/6 (100%) |
| Conflicting: strict mTLS + external non-TLS service | Hard: conflict | 8/8 (100%) |
| **Overall** | | **57/63 (90%)** |

### claude-sonnet-4-6

| Eval | Type | Score |
|------|------|-------|
| OSSM 3.0 setup | YAML gen | 9/10 (90%) |
| Red herring: 503s not caused by mTLS | Hard: red herring | 6/6 (100%) |
| Conflicting: strict mTLS + external non-TLS service | Hard: conflict | 7/8 (88%) |
| **Overall** | | **22/24 (92%)** |

### Cross-model notes

- **Red herring:** Both models correctly avoided blaming mTLS and identified the DestinationRule label mismatch
- **mTLS + external:** Opus included compensating controls (AuthorizationPolicy, egress audit); Sonnet provided the working fix but missed defense-in-depth
- **Trade-off (canary vs blue-green):** Opus recommended canary (expected: blue-green) — a domain judgment miss, not a technical error
