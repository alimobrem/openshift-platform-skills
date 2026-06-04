# External Secrets Operator Reference

Default secrets management for the platform. Swappable with HashiCorp Vault
(direct), Sealed Secrets, or SOPS. See the swap guide table at the end.

**CRDs:** SecretStore, ClusterSecretStore, ExternalSecret, ClusterExternalSecret
(all `external-secrets.io/v1`)

---

## Operator Install

### OLM Subscription (Red Hat — recommended for OpenShift)

The **External Secrets Operator for Red Hat OpenShift** is GA and included with OCP 4.19+.
Use the Red Hat-supported operator, not the community version.

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: external-secrets-operator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: external-secrets-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

After install, create the `OperatorConfig` CR to deploy ESO:

```yaml
apiVersion: operator.external-secrets.io/v1
kind: OperatorConfig
metadata:
  name: cluster
  namespace: external-secrets
spec: {}
```

Verify:

```bash
oc get csv -n openshift-operators | grep external-secrets
oc get crd secretstores.external-secrets.io
oc get crd externalsecrets.external-secrets.io
oc get pods -n external-secrets
```

### Helm Install (non-OpenShift clusters only)

For vanilla Kubernetes without OLM:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --wait --timeout 5m
```

**Do not use Helm on OpenShift** — use the Red Hat operator above.

---

## SecretStore Configuration

### HashiCorp Vault

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: cluster-vault
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

Vault setup prerequisites:

```bash
# Enable Kubernetes auth in Vault
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

# Create policy
vault policy write external-secrets - <<EOF
path "secret/data/platform/*" {
  capabilities = ["read"]
}
EOF

# Create role bound to ESO ServiceAccount
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=1h
```

### AWS Secrets Manager

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-credentials
            namespace: external-secrets
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-credentials
            namespace: external-secrets
            key: secret-access-key
```

For IRSA (IAM Roles for Service Accounts) on EKS — omit `auth.secretRef` and
annotate the ESO ServiceAccount with the IAM role ARN instead.

### Azure Key Vault

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault
spec:
  provider:
    azurekv:
      tenantId: "<tenant-id>"
      vaultUrl: "https://platform-kv.vault.azure.net"
      authType: ManagedIdentity
      identityId: "<managed-identity-client-id>"
```

For Service Principal auth, replace `authType` with `ServicePrincipal` and add:

```yaml
      authSecretRef:
        clientId:
          name: azure-sp-credentials
          namespace: external-secrets
          key: client-id
        clientSecret:
          name: azure-sp-credentials
          namespace: external-secrets
          key: client-secret
```

### GCP Secret Manager

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-manager
spec:
  provider:
    gcpsm:
      projectID: "my-gcp-project"
      auth:
        secretRef:
          secretAccessKeySecretRef:
            name: gcp-credentials
            namespace: external-secrets
            key: service-account-key.json
```

For Workload Identity on GKE — omit `auth.secretRef` and annotate the ESO
ServiceAccount with the GCP service account email.

---

## ExternalSecret Patterns

### Single Key

Pull one secret value and create a Kubernetes Secret:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: db-password
  namespace: app-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: cluster-vault
    kind: ClusterSecretStore
  target:
    name: db-password
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: platform/databases/postgres
        property: password
```

### Templated Secret

Transform remote values into a specific Secret format (e.g., dockerconfigjson,
connection string, TLS):

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

### dataFrom — Pull All Keys

Pull all key-value pairs from a single remote secret path:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-config
  namespace: app-prod
spec:
  refreshInterval: 30m
  secretStoreRef:
    name: cluster-vault
    kind: ClusterSecretStore
  target:
    name: app-config
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: platform/apps/order-service/config
```

All key-value pairs under the remote path become keys in the Kubernetes Secret.

### ClusterExternalSecret

Replicate a Secret across multiple namespaces:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterExternalSecret
metadata:
  name: shared-registry-creds
spec:
  namespaceSelectors:
    - matchLabels:
        platform.example.com/tier: application
  refreshInterval: 1h
  externalSecretSpec:
    secretStoreRef:
      name: cluster-vault
      kind: ClusterSecretStore
    target:
      name: registry-pull-secret
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
          property: pull_auth_b64
```

---

## Integration Matrix

Which secrets feed which platform layer:

| Secret | Backend Path (Vault example) | Target Namespace | Consumer | Secret Type |
|--------|------------------------------|-----------------|----------|-------------|
| Registry push creds | `platform/quay/robot-auth` | `ci-pipelines` | Pipeline ServiceAccount | `kubernetes.io/dockerconfigjson` |
| Registry pull creds | `platform/quay/pull-auth` | app namespaces | Deployment imagePullSecrets | `kubernetes.io/dockerconfigjson` |
| Git SSH key | `platform/git/ssh-key` | `ci-pipelines` | Tekton git-clone task | `kubernetes.io/ssh-auth` |
| Git HTTPS token | `platform/git/https-token` | `ci-pipelines` | Tekton gitops-update task | `Opaque` |
| Argo CD repo creds | `platform/argocd/repo-creds` | `argocd` | Argo CD repo-server | `Opaque` (labeled `argocd.argoproj.io/secret-type: repository`) |
| Mesh TLS certs | `platform/mesh/tls-cert` | `istio-system` | Istio ingress gateway | `kubernetes.io/tls` |
| Quay robot tokens | `platform/quay/robot-token` | `ci-pipelines` | Pipeline push step | `Opaque` (consumed by template) |
| GitHub App key | `platform/promoter/github-app` | `gitops-promoter-system` | gitops-promoter controller | `Opaque` |
| Database creds | `platform/databases/<name>` | app namespaces | Application pods | `Opaque` |

### Argo CD Repository Credentials via ESO

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-repo-creds
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: cluster-vault
    kind: ClusterSecretStore
  target:
    name: repo-creds-github
    template:
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repo-creds
      data:
        type: "git"
        url: "https://github.com/my-org"
        password: "{{ .token }}"
        username: "x-access-token"
  data:
    - secretKey: token
      remoteRef:
        key: platform/argocd/github-token
        property: token
```

---

## Rotation — refreshInterval

ESO polls the backend at `refreshInterval` and updates the Kubernetes Secret
if the remote value has changed.

| Use Case | Recommended Interval | Rationale |
|----------|---------------------|-----------|
| Database passwords | `1h` | Balance between freshness and API rate limits |
| Registry robot tokens | `1h` | Tokens are long-lived; hourly check is sufficient |
| TLS certificates | `12h` | Certs rotate infrequently; reduce Vault API calls |
| Git tokens (PAT) | `30m` | Detect revocation quickly |
| Short-lived cloud tokens | `15m` | Catch expiration before consumers fail |

### Verify Rotation Works

```bash
# Check ExternalSecret sync status
kubectl get externalsecret -n ci-pipelines quay-push-secret -o jsonpath='{.status.conditions}'

# Expected: type=Ready, status=True, reason=SecretSynced
# Check last sync time
kubectl get externalsecret -n ci-pipelines quay-push-secret \
  -o jsonpath='{.status.refreshTime}'

# Force immediate refresh
kubectl annotate externalsecret -n ci-pipelines quay-push-secret \
  force-sync=$(date +%s) --overwrite
```

### Monitoring Sync Failures

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: eso-alerts
  namespace: external-secrets
spec:
  groups:
    - name: external-secrets
      rules:
        - alert: ExternalSecretSyncFailed
          expr: |
            externalsecret_status_condition{condition="Ready", status="False"} == 1
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "ExternalSecret {{ $labels.name }} in {{ $labels.namespace }} failed to sync"
```

---

## RBAC — ServiceAccount SecretStore Access

### Namespace-scoped SecretStore

A namespace-scoped SecretStore restricts which namespaces can read from a backend path:

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: team-vault
  namespace: team-payments
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "team-payments"
          serviceAccountRef:
            name: eso-team-payments
```

The Vault role `team-payments` is scoped to `secret/data/teams/payments/*` only.

### RBAC for ESO Controller

The ESO controller needs access to read Secrets referenced in SecretStore auth:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: eso-auth-reader
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
    # Scoped by the ClusterRoleBinding to specific namespaces
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: eso-auth-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: eso-auth-reader
subjects:
  - kind: ServiceAccount
    name: external-secrets
    namespace: external-secrets
```

### Multi-Tenant Pattern

For multi-tenant clusters, use namespace-scoped SecretStores with per-team
Vault roles. Each team's ServiceAccount authenticates to Vault with a role
that only grants access to their secrets path:

```
Vault paths:
  secret/data/teams/payments/*    → role: team-payments    → ns: team-payments
  secret/data/teams/shipping/*    → role: team-shipping    → ns: team-shipping
  secret/data/platform/*          → role: platform-admin   → ns: external-secrets (ClusterSecretStore)
```

Teams cannot read each other's secrets. Platform-wide secrets (registry creds,
mesh TLS) use a ClusterSecretStore accessible to all namespaces.

---

## Swap Guide — Secrets Management Alternatives

When the user specifies a different secrets manager, adapt using this table.

| Feature | ESO (default) | Vault Agent Injector | Sealed Secrets | SOPS |
|---------|--------------|---------------------|----------------|------|
| **Install method** | OLM Subscription or Helm chart | Helm chart (`hashicorp/vault`) with injector enabled | Helm chart (`bitnami-labs/sealed-secrets`) + `kubeseal` CLI | Argo CD Kustomize plugin + `sops` binary in repo-server |
| **CRDs** | SecretStore, ClusterSecretStore, ExternalSecret, ClusterExternalSecret | None (uses annotations on Pods) | SealedSecret | None (encrypted files in Git) |
| **How secrets reach pods** | ESO creates native K8s Secrets; pods mount normally | Vault Agent sidecar injects secrets as files into pod at runtime | Controller decrypts SealedSecret into native K8s Secret | Argo CD decrypts SOPS files during `kustomize build` into native K8s Secrets |
| **Rotation support** | `refreshInterval` polls backend; auto-updates K8s Secret | Agent sidecar watches Vault lease; rotates in-pod files automatically | No automatic rotation; must re-encrypt and commit new SealedSecret | No automatic rotation; must re-encrypt and commit |
| **GitOps compatibility** | ExternalSecret CRDs are committed to Git; secrets stay in backend | Pod annotations committed to Git; no secret material in Git | SealedSecret (encrypted blob) committed to Git; safe to store | Encrypted files committed to Git; safe to store |
| **Multi-backend support** | Yes (Vault, AWS SM, Azure KV, GCP SM, many more) | Vault only | N/A (encrypts with cluster-scoped key) | Age, PGP, AWS KMS, GCP KMS, Azure KV |
| **Namespace isolation** | SecretStore per namespace; ClusterSecretStore for shared | Vault policy per K8s namespace/SA | One controller key per cluster (no namespace isolation) | Per-file `.sops.yaml` rules can scope by path |
| **Failure mode** | ExternalSecret status shows sync errors; Secret not updated | Pod fails to start if Vault is unreachable (init container blocks) | SealedSecret stays encrypted; controller logs decryption errors | Argo CD sync fails if decryption fails |
| **Observability** | `externalsecret_status_condition` Prometheus metric | Vault Agent logs in sidecar container | Controller logs + events on SealedSecret | Argo CD sync status / repo-server logs |

### Vault Agent Injector Pattern (Alternative to ESO)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "team-payments"
        vault.hashicorp.com/agent-inject-secret-db-password: "secret/data/teams/payments/db"
        vault.hashicorp.com/agent-inject-template-db-password: |
          {{- with secret "secret/data/teams/payments/db" -}}
          {{ .Data.data.password }}
          {{- end -}}
    spec:
      serviceAccountName: order-service
      containers:
        - name: app
          # Secret available at /vault/secrets/db-password
```

### Sealed Secrets Pattern

```bash
# Install kubeseal CLI
brew install kubeseal   # or download from GitHub releases

# Encrypt a secret
kubectl create secret generic db-password \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace sealed-secrets \
           --format yaml > sealed-db-password.yaml
```

```yaml
# sealed-db-password.yaml — safe to commit to Git
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-password
  namespace: app-prod
spec:
  encryptedData:
    password: AgBY8z...  # encrypted blob
  template:
    metadata:
      name: db-password
      namespace: app-prod
```

### SOPS with Argo CD

```yaml
# .sops.yaml in GitOps repo root
creation_rules:
  - path_regex: ".*secrets.*\\.yaml$"
    age: "age1abc..."    # Public key for encryption
```

Argo CD repo-server must have SOPS + age/gpg keys available:

```yaml
# Argo CD values.yaml
repoServer:
  env:
    - name: SOPS_AGE_KEY_FILE
      value: /sops/age/keys.txt
  volumes:
    - name: sops-age
      secret:
        secretName: sops-age-key
  volumeMounts:
    - name: sops-age
      mountPath: /sops/age
  initContainers:
    - name: install-sops
      image: alpine:latest
      command: ["/bin/sh", "-c"]
      args:
        - wget -O /custom-tools/sops https://github.com/getsops/sops/releases/download/v3.9.0/sops-v3.9.0.linux.amd64 && chmod +x /custom-tools/sops
      volumeMounts:
        - name: custom-tools
          mountPath: /custom-tools
configs:
  cm:
    kustomize.buildOptions: "--enable-alpha-plugins --enable-exec"
```

### Switching Secrets Managers Checklist

When swapping from ESO to an alternative:

1. Identify all ExternalSecret resources: `kubectl get externalsecret -A`
2. For each ExternalSecret, determine the target Secret name and consuming workloads
3. Generate equivalent config in the new tool (Vault annotations, SealedSecrets, SOPS files)
4. Deploy the new tool's controller/operator
5. Create new secrets through the new tool and verify they match the old Secret data
6. Update workload references if Secret names or mount paths change
7. Remove ESO ExternalSecrets and SecretStores after verification
8. Update GitOps repo to commit new secret format (SealedSecrets or SOPS-encrypted files)
