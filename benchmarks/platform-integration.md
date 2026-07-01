# platform-integration

## v0.3.0 (2026-07-01)

### claude-opus-4-6

| Eval | Type | Score |
|------|------|-------|
| End-to-end delivery flow | YAML gen | 10/10 (100%) |
| Platform onboarding | YAML gen | 10/10 (100%) |
| DORA metrics | YAML gen | 10/10 (100%) |
| Cross-layer debug | Diagnose | 10/10 (100%) |
| Rollout paused vs Argo CD Synced | Diagnose | 8/8 (100%) |
| Multi-bug: pipeline + promoter interaction | Hard: multi-bug | 7/7 (100%) |
| **Overall** | | **55/55 (100%)** |

### claude-sonnet-4-6

| Eval | Type | Score |
|------|------|-------|
| End-to-end delivery flow | YAML gen | 10/10 (100%) |
| Platform onboarding | YAML gen | 10/10 (100%) |
| DORA metrics | YAML gen | 10/10 (100%) |
| Cross-layer debug | Diagnose | 10/10 (100%) |
| Multi-bug: pipeline + promoter interaction | Hard: multi-bug | 7/7 (100%) |
| **Overall** | | **47/47 (100%)** |

### Cross-model notes

- **Multi-bug:** Both models found all issues (4 each) including the autoMerge:true on prod that wasn't in the original expectations. Both explained why fixing one issue is insufficient.
