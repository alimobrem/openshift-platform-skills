# Quay Registry Reference

Default image registry for the platform. Swappable with Harbor, OpenShift internal
registry, ECR, GCR, or GHCR. See the swap guide table at the end of this document.

---

## Operator Install

### OLM Subscription

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: quay-operator
  namespace: openshift-operators
spec:
  channel: stable-3.12
  installPlanApproval: Automatic
  name: quay-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

Verify the operator is ready:

```bash
kubectl get csv -n openshift-operators | grep quay
kubectl get crd quayregistries.quay.redhat.com
```

### QuayRegistry CR

```yaml
apiVersion: quay.redhat.com/v1
kind: QuayRegistry
metadata:
  name: platform-registry
  namespace: quay-system
spec:
  configBundleSecret: quay-config-bundle
  components:
    - kind: clair
      managed: true
    - kind: postgres
      managed: true
    - kind: redis
      managed: true
    - kind: objectstorage
      managed: true           # Uses ODF/NooBaa; set false + provide S3 config for external storage
    - kind: horizontalpodautoscaler
      managed: true
    - kind: mirror
      managed: true
    - kind: monitoring
      managed: true
    - kind: tls
      managed: true           # Uses cluster default ingress cert
    - kind: route
      managed: true
```

After the operator reconciles (~5 min):

```bash
kubectl get quayregistry platform-registry -n quay-system -o jsonpath='{.status.registryEndpoint}'
# Example: https://platform-registry-quay-system.apps.cluster.example.com
```

---

## Organizations and Repositories

### Create an Organization

```bash
QUAY_API="https://platform-registry-quay-system.apps.cluster.example.com/api/v1"
QUAY_TOKEN="<oauth-token>"

curl -s -X POST "${QUAY_API}/organization/" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "team-payments", "email": "payments@example.com"}'
```

### Create a Repository

```bash
curl -s -X POST "${QUAY_API}/repository" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "repository": "order-service",
    "namespace": "team-payments",
    "visibility": "private",
    "description": "Order service container image"
  }'
```

### Robot Accounts

Robot accounts are service credentials for automated push/pull. One robot per
team or per pipeline is the recommended pattern.

```bash
# Create robot account
curl -s -X PUT "${QUAY_API}/organization/team-payments/robots/ci-push" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"description": "Pipeline push credentials"}'

# Grant write permission to specific repo
curl -s -X PUT "${QUAY_API}/repository/team-payments/order-service/permissions/user/team-payments+ci-push" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"role": "write"}'
```

The robot token is returned in the create response at `.token`. Store it in
your secrets backend (ESO, Vault, etc.) immediately.

---

## Registry Auth Secrets

### dockerconfigjson Secret for Kubernetes

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: quay-push-secret
  namespace: ci-pipelines
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {
      "auths": {
        "platform-registry-quay-system.apps.cluster.example.com": {
          "auth": "<base64(team-payments+ci-push:robot-token)>",
          "email": ""
        }
      }
    }
```

Generate from CLI:

```bash
kubectl create secret docker-registry quay-push-secret \
  --docker-server=platform-registry-quay-system.apps.cluster.example.com \
  --docker-username='team-payments+ci-push' \
  --docker-password='<robot-token>' \
  -n ci-pipelines \
  --dry-run=client -o yaml
```

Link to pipeline ServiceAccount:

```bash
kubectl patch serviceaccount pipeline -n ci-pipelines \
  -p '{"secrets": [{"name": "quay-push-secret"}], "imagePullSecrets": [{"name": "quay-push-secret"}]}'
```

### ESO-managed Registry Secret

When using External Secrets Operator, the robot token lives in Vault/AWS/etc.
and ESO creates the dockerconfigjson Secret automatically:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: quay-push-secret
  namespace: ci-pipelines
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: cluster-vault
    kind: ClusterSecretStore
  target:
    name: quay-push-secret
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {"auths":{"{{ .registry }}":{"auth":"{{ .auth }}","email":""}}}
  data:
    - secretKey: registry
      remoteRef:
        key: platform/quay
        property: registry_url
    - secretKey: auth
      remoteRef:
        key: platform/quay
        property: robot_auth_b64
```

---

## Image Scanning — Clair Integration

Clair is deployed automatically when `managed: true` in the QuayRegistry CR.

### Vulnerability Report API

```bash
# Get scan results for a specific manifest
REPO="team-payments/order-service"
TAG="v1.2.3"
DIGEST=$(curl -s -H "Authorization: Bearer ${QUAY_TOKEN}" \
  "${QUAY_API}/repository/${REPO}/tag/?specificTag=${TAG}" | jq -r '.tags[0].manifest_digest')

curl -s -H "Authorization: Bearer ${QUAY_TOKEN}" \
  "${QUAY_API}/repository/${REPO}/manifest/${DIGEST}/security?vulnerabilities=true"
```

### Block Deployments on Critical Vulnerabilities

Use an Argo CD resource hook or OPA/Kyverno policy to gate deployments:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-unscanned-images
spec:
  validationFailureAction: Enforce
  rules:
    - name: require-scan-pass
      match:
        any:
          - resources:
              kinds: ["Deployment", "StatefulSet"]
      verifyImages:
        - imageReferences: ["platform-registry-quay-system.apps.cluster.example.com/*"]
          attestations:
            - type: https://cosign.sigstore.dev/attestation/vuln/v1
              conditions:
                - all:
                    - key: "{{ scanner.result.summary.criticalCount }}"
                      operator: Equals
                      value: "0"
```

---

## Mirroring for Air-Gapped Clusters

### Repository Mirroring Rule

Configure Quay to mirror upstream images into the internal registry:

```bash
# Enable mirroring on a repo
curl -s -X PUT "${QUAY_API}/repository/team-payments/ubi-base/mirror" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "is_enabled": true,
    "external_reference": "registry.redhat.io/ubi9/ubi",
    "external_registry_username": "<rh-registry-sa>",
    "external_registry_password": "<rh-registry-token>",
    "sync_interval": 86400,
    "sync_start_date": "2026-01-01T00:00:00Z",
    "robot_username": "team-payments+mirror-bot",
    "root_rule": {
      "rule_kind": "tag_glob_csv",
      "rule_value": ["latest", "9.*"]
    }
  }'
```

### ImageContentSourcePolicy (OCP < 4.14)

```yaml
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: quay-mirror
spec:
  repositoryDigestMirrors:
    - mirrors:
        - platform-registry-quay-system.apps.cluster.example.com/team-payments/ubi-base
      source: registry.redhat.io/ubi9/ubi
```

### ImageDigestMirrorSet (OCP 4.14+)

```yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: quay-mirror
spec:
  imageDigestMirrors:
    - mirrors:
        - platform-registry-quay-system.apps.cluster.example.com/team-payments/ubi-base
      source: registry.redhat.io/ubi9/ubi
      mirrorSourcePolicy: AllowContactingSource
```

---

## Geo-Replication for Multi-Cluster

Quay supports storage-level geo-replication across regions. All Quay instances
share the same database but replicate blob storage.

### Config Bundle for Geo-Replication

```yaml
# quay-config.yaml (stored in configBundleSecret)
FEATURE_STORAGE_REPLICATION: true
DISTRIBUTED_STORAGE_CONFIG:
  us-east-1:
    - S3Storage
    - host: s3.us-east-1.amazonaws.com
      s3_bucket: quay-storage-us-east
      s3_access_key: <access-key>
      s3_secret_key: <secret-key>
      storage_path: /datastorage/registry
  eu-west-1:
    - S3Storage
    - host: s3.eu-west-1.amazonaws.com
      s3_bucket: quay-storage-eu-west
      s3_access_key: <access-key>
      s3_secret_key: <secret-key>
      storage_path: /datastorage/registry
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS:
  - us-east-1
  - eu-west-1
DISTRIBUTED_STORAGE_PREFERENCE:
  - us-east-1
  - eu-west-1
```

Each cluster pulls from its nearest Quay endpoint. DNS-based routing (Route53,
Global Load Balancer) directs clients to the closest region.

---

## Integration with Pipelines and GitOps

### Shipwright Build — Push to Quay

```yaml
apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: order-service
  namespace: ci-pipelines
spec:
  source:
    type: Git
    git:
      url: https://github.com/team-payments/order-service
      revision: main
  strategy:
    name: buildah
    kind: ClusterBuildStrategy
  output:
    image: platform-registry-quay-system.apps.cluster.example.com/team-payments/order-service:latest
    pushSecret: quay-push-secret
```

### Tekton Task — Push to Quay

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: buildah-push-quay
  namespace: ci-pipelines
spec:
  params:
    - name: IMAGE
      type: string
  workspaces:
    - name: source
    - name: dockerconfig
      description: Registry credentials
  steps:
    - name: build-push
      image: quay.io/buildah/stable:latest
      script: |
        #!/usr/bin/env bash
        buildah bud --storage-driver=vfs -t $(params.IMAGE) $(workspaces.source.path)
        buildah push --storage-driver=vfs \
          --authfile=$(workspaces.dockerconfig.path)/.dockerconfigjson \
          $(params.IMAGE)
      securityContext:
        capabilities:
          add: ["SETFCAP"]
```

### Argo CD Image Updater — Poll from Quay

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: order-service
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: "order=platform-registry-quay-system.apps.cluster.example.com/team-payments/order-service"
    argocd-image-updater.argoproj.io/order.update-strategy: semver
    argocd-image-updater.argoproj.io/order.pull-secret: pullsecret:argocd/quay-pull-secret
spec:
  # ... Application spec (see argo-skills)
```

Image Updater ConfigMap for Quay:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  registries.conf: |
    registries:
      - name: Quay
        api_url: https://platform-registry-quay-system.apps.cluster.example.com
        prefix: platform-registry-quay-system.apps.cluster.example.com
        credentials: pullsecret:argocd/quay-pull-secret
        defaultns: library
```

---

## Swap Guide — Registry Alternatives

When the user specifies a different registry, adapt push URLs, auth secrets,
and integration config using this table.

| Feature | Quay (default) | Harbor | OpenShift Internal Registry | ECR (AWS) | GCR / Artifact Registry (GCP) | GHCR |
|---------|---------------|--------|---------------------------|-----------|-------------------------------|------|
| **Push URL format** | `<quay-route>/<org>/<repo>:<tag>` | `<harbor-host>/project/<repo>:<tag>` | `image-registry.openshift-image-registry.svc:5000/<namespace>/<name>:<tag>` | `<account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>` | `<region>-docker.pkg.dev/<project>/<repo>/<image>:<tag>` | `ghcr.io/<owner>/<repo>:<tag>` |
| **Secret type** | `kubernetes.io/dockerconfigjson` | `kubernetes.io/dockerconfigjson` | Managed by OpenShift (auto-mounted SA token) | `kubernetes.io/dockerconfigjson` (short-lived token) | `kubernetes.io/dockerconfigjson` (service account key) | `kubernetes.io/dockerconfigjson` (PAT) |
| **Auth method** | Robot account token | Robot account or OIDC | ServiceAccount token (auto) | `aws ecr get-login-password` (12h TTL) | `gcloud auth print-access-token` or SA key JSON | Personal Access Token (PAT) |
| **Auth renewal** | Static token (rotate manually or via ESO) | Static token or OIDC refresh | Automatic (SA token) | Must refresh every 12h (use ECR credential helper or CronJob) | SA key is static; OAuth token is 1h | Static PAT (rotate via ESO) |
| **Scanning** | Clair (built-in) | Trivy (built-in) | No built-in scanning | ECR native scanning or Inspector | Artifact Analysis (on-demand or auto) | No built-in (use GitHub Advanced Security) |
| **Mirroring** | Repository mirror rules (API) | Replication rules (UI/API) | `ImageContentSourcePolicy` / `ImageDigestMirrorSet` | ECR pull-through cache | Artifact Registry remote repositories | Not supported natively |
| **Geo-replication** | Storage-level replication (S3 multi-region) | Replication between Harbor instances | N/A (single cluster) | Cross-region replication | Multi-region Artifact Registry | N/A |
| **Image Updater pull-secret** | `pullsecret:argocd/<secret-name>` | `pullsecret:argocd/<secret-name>` | `pullsecret:argocd/<secret-name>` (or use SA) | `ext:/scripts/ecr-login.sh` (script-based) | `pullsecret:argocd/<secret-name>` | `pullsecret:argocd/<secret-name>` |
| **OLM install** | `quay-operator` from `redhat-operators` | Helm chart (`goharbor/harbor-helm`) | Pre-installed on OpenShift | N/A (AWS managed) | N/A (GCP managed) | N/A (GitHub managed) |

### ECR Token Refresh CronJob

ECR tokens expire after 12 hours. Use a CronJob to keep the Secret current:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ecr-token-refresh
  namespace: ci-pipelines
spec:
  schedule: "0 */10 * * *"   # Every 10 hours
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: ecr-refresher
          containers:
            - name: refresh
              image: amazon/aws-cli:latest
              command:
                - /bin/sh
                - -c
                - |
                  TOKEN=$(aws ecr get-login-password --region us-east-1)
                  kubectl create secret docker-registry ecr-push-secret \
                    --docker-server=123456789.dkr.ecr.us-east-1.amazonaws.com \
                    --docker-username=AWS \
                    --docker-password="${TOKEN}" \
                    -n ci-pipelines \
                    --dry-run=client -o yaml | kubectl apply -f -
          restartPolicy: OnFailure
```

### Switching Registries Checklist

When swapping from Quay to an alternative registry:

1. Update all `Build.spec.output.image` references (Shipwright)
2. Update all `params.IMAGE` values in Tekton Pipelines
3. Replace the `dockerconfigjson` Secret (or update the ESO ExternalSecret remote ref)
4. Patch the pipeline ServiceAccount with the new Secret name
5. Update Argo CD Image Updater `registries.conf` and Application annotations
6. If air-gapped: update `ImageDigestMirrorSet` / `ImageContentSourcePolicy` sources
7. Verify push: `buildah push --authfile=<new-auth> <test-image>`
8. Verify pull: `kubectl run test --image=<new-registry>/<image> --rm -it -- echo ok`
