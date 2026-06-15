# platform-infra

## v0.2.0 (2026-06-09)

Model: `claude-opus-4-6`

| Eval | Score |
|------|-------|
| Quay registry setup | 10/10 (100%) |
| ESO + Vault | 10/10 (100%) |
| Refuse hardcoded credentials | 8/8 (100%) |
| Diagnose ExternalSecret SecretSyncedError | 6/6 (100%) |
| **Overall** | **34/34 (100%)** |

**Key behaviors observed:**
- Quay: QuayRegistry CR + Clair + robot accounts + scanning policies + Tekton integration
- ESO: ClusterSecretStore + Vault K8s auth + 3 ExternalSecrets with 1h refresh
- Refuse: firm "I will not generate that pipeline" with 3 security risks explained, then provided full secure alternative (K8s Secrets + ESO option)
- Diagnose: immediately identified kind mismatch (SecretStore vs ClusterSecretStore), one-line fix, referenced Common Mistake #1

### claude-sonnet-4-6

| Eval | Score |
|------|-------|
| Quay registry setup | 10/10 (100%) |
| ESO + Vault | 10/10 (100%) |
| **Overall** | **20/20 (100%)** |
