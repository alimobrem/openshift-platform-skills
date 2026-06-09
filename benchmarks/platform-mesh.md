# platform-mesh

## v0.1.0 (2026-06-04) — pre-split baseline

Results from the monolithic `platform-engineering` skill (evals now owned by this skill):

| Eval | Opus 4.6 | Sonnet 4.6 |
|------|----------|------------|
| OSSM 3.0 setup | 10/10 (100%) | 9/10 (90%) |
| Canary Rollout + Istio traffic mgmt | 12/12 (100%) | — |
| Blue-green + Istio header preview | 12/12 (100%) | — |

## v0.2.0 (2026-06-09) — post-split

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| OSSM 3.0 setup | — |
| Rollout + Istio canary traffic mgmt | — |
| Blue-green + Istio header preview | — |
| **Overall** | **—** |

_Run `make test-mesh` to populate results._
