---
name: platform-infra
description: >
  OpenShift infrastructure skill covering container image registries (Quay) and
  secrets management (External Secrets Operator). Generates, reviews, debugs, and
  explains QuayRegistry, SecretStore, ClusterSecretStore, ExternalSecret, and
  ClusterExternalSecret CRDs. Supports swappable components — adapts to Harbor,
  Sealed Secrets, or Vault CSI when specified. Use when users ask about image
  registries, Quay, robot accounts, vulnerability scanning, secrets, Vault, ESO,
  ExternalSecret, credential rotation, or air-gapped registry setup.
license: MIT
compatibility: Requires oc or kubectl; optionally skopeo
---

# OpenShift Infrastructure — Registry & Secrets

Skill for container image registries (Quay) and secrets management (External Secrets Operator)
on OpenShift.

## Rules

1. **Always use correct apiVersion and kind.** Every CRD example must use the real
   apiVersion from the CRD table below. Never invent CRDs or apiVersions.
2. **Load references on-demand.** Only read reference files when the user's question
   requires detailed field-level knowledge. Do not preload all references.
3. **Validate YAML before presenting.** Every YAML example must be syntactically valid
   and use real field names from the CRD schemas.
4. **Prefer canonical patterns.** Use patterns from reference docs as starting points.
   Adapt to the user's specifics rather than inventing from scratch.
5. **Ask about optional components when ambiguous.** If the user's prompt does not
   specify which registry or secrets tool they use, ask before generating YAML with
   defaults.

## How This Skill Works

| User asks about | Reference | Topic |
|-----------------|-----------|-------|
| Registry, Quay, Harbor, image push, robot accounts, scanning, Clair | `references/quay.md` | Registry |
| Secrets, Vault, ESO, ExternalSecret, credentials, rotation, SecretStore | `references/external-secrets.md` | Secrets |

Load the matching reference file before answering. Max 1 reference file per request.

## Swappable Components

| Layer | Default | Alternatives |
|-------|---------|-------------|
| Registry | **Quay** | Harbor, OpenShift internal registry, ECR, GCR, GHCR, Docker Hub |
| Secrets | **External Secrets Operator** | Vault (direct), Sealed Secrets, SOPS, AWS Secrets Manager, Vault CSI |

**Ask which components the user has if the prompt is ambiguous.** Do not assume defaults
without checking. When the user says "we use Harbor," generate Harbor-specific push secrets,
robot accounts, and registry URLs instead of Quay equivalents.

## CRD Reference Table

| Kind | apiVersion | Project |
|------|-----------|---------|
| QuayRegistry | quay.redhat.com/v1 | Quay |
| SecretStore | external-secrets.io/v1 | ESO |
| ClusterSecretStore | external-secrets.io/v1 | ESO |
| ExternalSecret | external-secrets.io/v1 | ESO |
| ClusterExternalSecret | external-secrets.io/v1 | ESO |

## Safety Model

**Every write operation follows a 3-step protocol: Generate, Preview, Confirm.**

**Read-only operations** (scan results, secret sync status) do NOT require confirmation.

| Step | What happens |
|------|-------------|
| Generate | Produce YAML manifest or CLI command, show in a code block |
| Preview | `kubectl apply --dry-run=client -f <file>` or `kubectl diff -f <file>` |
| Confirm | Ask "Apply this? (yes/no)" — do NOT proceed without affirmative response |

**NEVER modify Secrets containing credentials directly.** Generate the Secret manifest
and let the user apply it, or use `kubectl create secret --dry-run=client`.

## Common Mistakes

1. **ESO ExternalSecret with wrong SecretStore kind.** Using `kind: SecretStore` when
   the store is `ClusterSecretStore` (or vice versa) causes "store not found" errors.

2. **Quay robot account secret not linked to pipeline ServiceAccount.** The pipeline
   runs as a ServiceAccount that needs `imagePullSecrets` and registry push credentials.
   Without linking, builds succeed but pushes fail with 401.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Air-gapped / disconnected cluster | Adjust registry URLs to use internal mirrors. Generate `ImageDigestMirrorSet` for OCP 4.13+. Ensure all images reference the internal registry. |
| Not an OpenShift cluster (vanilla K8s) | Quay operator may not be available — suggest Harbor or ECR. ESO works the same. |
| SOPS-encrypted secrets (not ESO) | Generate Kustomize `secretGenerator` with SOPS-encrypted files. Do not mix SOPS and ESO in the same namespace without explicit user intent. |
| Missing operators | Check for CRDs: `kubectl api-resources --api-group=quay.redhat.com` and `kubectl api-resources --api-group=external-secrets.io`. Report missing with install instructions. |

## Reference Index

| Topic | Reference File | When to Load |
|-------|---------------|-------------|
| Quay operator, orgs, robot accounts, Clair scanning, mirroring, swap guide | `references/quay.md` | Questions about image registry, scanning, registry auth |
| ESO install, SecretStore backends, ExternalSecret patterns, rotation, swap guide | `references/external-secrets.md` | Questions about secrets management, Vault, sealed secrets |
