---
name: platform-mesh
description: >
  OpenShift Service Mesh skill covering Istio/OSSM installation, mTLS enforcement,
  traffic management, and progressive delivery with Istio. Generates, reviews, debugs,
  and explains Istio, IstioCNI, VirtualService, DestinationRule, Gateway,
  PeerAuthentication, and AuthorizationPolicy CRDs. Use when users ask about service
  mesh, mTLS, traffic routing, canary/blue-green with Istio, VirtualService, Kiali,
  circuit breakers, or fault injection on OpenShift.
license: MIT
compatibility: Requires oc or kubectl; optionally istioctl
---

# OpenShift Service Mesh — Istio & Traffic Management

Skill for service mesh configuration and Istio-based traffic management on OpenShift.

## Rules

1. **Always use correct apiVersion and kind.** Every CRD example must use the real
   apiVersion from the CRD table below. Never invent CRDs or apiVersions.
2. **Load references on-demand.** Only read reference files when the user's question
   requires detailed field-level knowledge. Do not preload all references.
3. **Validate YAML before presenting.** Every YAML example must be syntactically valid
   and use real field names from the CRD schemas.
4. **Prefer canonical patterns.** Use patterns from reference docs as starting points.
   Adapt to the user's specifics rather than inventing from scratch.
5. **State trade-offs.** When recommending a traffic strategy (canary vs blue-green,
   weight-based vs header-based), briefly note what you give up.

## How This Skill Works

| User asks about | Reference | Topic |
|-----------------|-----------|-------|
| Mesh, mTLS, Istio, OSSM, VirtualService, DestinationRule, Gateway, Kiali, traffic, canary+Istio, blue-green+Istio, circuit breaker, fault injection | `references/istio.md` | Mesh |

Load `references/istio.md` before answering.

## CRD Reference Table

| Kind | apiVersion | Project |
|------|-----------|---------|
| Istio | sailoperator.io/v1 | OSSM |
| IstioCNI | sailoperator.io/v1 | OSSM |
| VirtualService | networking.istio.io/v1 | Istio |
| DestinationRule | networking.istio.io/v1 | Istio |
| Gateway | networking.istio.io/v1 | Istio |
| PeerAuthentication | security.istio.io/v1 | Istio |
| AuthorizationPolicy | security.istio.io/v1 | Istio |

## Safety Model

**Every write operation follows a 3-step protocol: Generate, Preview, Confirm.**

**Read-only operations** (mesh status, proxy check, Kiali queries) do NOT require confirmation.

| Step | What happens |
|------|-------------|
| Generate | Produce YAML manifest or CLI command, show in a code block |
| Preview | `kubectl apply --dry-run=client -f <file>` or `kubectl diff -f <file>` |
| Confirm | Ask "Apply this? (yes/no)" — do NOT proceed without affirmative response |

For destructive operations (delete VirtualService, remove namespace from mesh),
require the user to type the resource name to confirm.

## Common Mistakes

1. **Namespace missing `istio-injection=enabled` label.** Without this label,
   Istio sidecars will not be injected into pods in the namespace.

2. **VirtualService host mismatch.** The VirtualService `hosts` field must match the
   Kubernetes Service name exactly. Mismatches cause 404s with no obvious error.

3. **DestinationRule subsets referencing wrong labels.** If the subset selector does not
   match pod labels, Istio routes to an empty subset and returns 503.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Not an OpenShift cluster (vanilla K8s) | Skip OSSM-specific CRDs (Istio CR via sailoperator.io, IstioCNI). Use upstream Istio CRDs directly. Replace `oc` with `kubectl`. |
| No mesh (replica-based canary only) | Generate Argo Rollouts without `trafficRouting`. Warn that canary is replica-based, not traffic-based. |
| Missing OSSM operator | Check: `kubectl api-resources --api-group=sailoperator.io`. If missing, report and provide operator install instructions. |
| Strict mTLS breaks legacy services | Suggest PeerAuthentication in PERMISSIVE mode for the target namespace as a migration step. |

## Reference Index

| Topic | Reference File | When to Load |
|-------|---------------|-------------|
| OSSM install, Istio CR, mTLS, traffic routing, Kiali, circuit breaking, canary/blue-green with Istio | `references/istio.md` | All mesh questions |
