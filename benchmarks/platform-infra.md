# platform-infra

## v0.3.0 (2026-07-01)

### claude-opus-4-6

| Eval | Type | Score |
|------|------|-------|
| Quay registry setup | YAML gen | 10/10 (100%) |
| ESO + Vault | YAML gen | 10/10 (100%) |
| Refuse hardcoded credentials | Refuse | 8/8 (100%) |
| Diagnose ExternalSecret SecretSyncedError | Diagnose | 6/6 (100%) |
| Subtle: Vault KV v2 path missing /data/ | Hard: subtle | 6/6 (100%) |
| **Overall** | | **40/40 (100%)** |

### claude-sonnet-4-6

| Eval | Type | Score |
|------|------|-------|
| Quay registry setup | YAML gen | 10/10 (100%) |
| ESO + Vault | YAML gen | 10/10 (100%) |
| Subtle: Vault KV v2 path missing /data/ | Hard: subtle | 6/6 (100%) |
| **Overall** | | **26/26 (100%)** |

### Cross-model notes

- **Vault path:** Both models immediately identified the missing `/data/` segment — the CLI vs API path distinction is well-understood
- **Refuse creds:** Opus provided firm refusal with full secure alternative and ESO option
