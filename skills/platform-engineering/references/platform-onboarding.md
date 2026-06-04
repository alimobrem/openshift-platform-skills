# Platform Onboarding Reference — Team and Application Setup

What "onboard a team" means on the platform, complete YAML templates, self-service
patterns, and guard rails that keep teams safe without slowing them down.

---

## What Gets Created

Onboarding a team or application means provisioning every resource needed for a team
to go from zero to first deploy. The checklist:

| # | Resource | Purpose |
|---|----------|---------|
| 1 | Namespace | Isolation boundary for the team's workloads |
| 2 | ResourceQuota | Caps CPU, memory, pods, PVCs — prevents runaway consumption |
| 3 | LimitRange | Default container requests/limits so nothing runs unbounded |
| 4 | NetworkPolicy | Deny-all baseline + allow mesh traffic + allow ingress |
| 5 | Quay organization + robot account | Image registry namespace + push/pull credentials |
| 6 | ESO SecretStore | Team-scoped secret backend access (Vault path, AWS region) |
| 7 | ExternalSecrets | Quay creds, Git SSH keys, pipeline tokens provisioned into namespace |
| 8 | Tekton Pipeline | Team-specific CI pipeline wired to their repo and registry |
| 9 | Tekton EventListener + Triggers | Webhook-driven pipeline execution |
| 10 | Argo CD AppProject | Scoped RBAC — what repos, clusters, and namespaces the team can deploy to |
| 11 | Argo CD Application | GitOps deployment for the team's first app |
| 12 | Namespace label `istio-injection=enabled` | Enrolls the namespace into the mesh for mTLS and traffic management |
| 13 | RoleBinding | Binds the team's group to namespace admin role |
| 14 | Pipeline ServiceAccount | SA with linked secrets for registry push, git access |

---

## Complete YAML Template

### Namespace + ResourceQuota + LimitRange

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: "{{ team }}-{{ app }}-dev"
  labels:
    team: "{{ team }}"
    app: "{{ app }}"
    env: dev
    managed-by: platform-onboarding
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: default-quota
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    pods: "40"
    persistentvolumeclaims: "10"
    requests.storage: 50Gi
---
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  limits:
    - type: Container
      default:
        cpu: 500m
        memory: 256Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: "4"
        memory: 8Gi
    - type: Pod
      max:
        cpu: "8"
        memory: 16Gi
```

### NetworkPolicy (Deny-All + Allow Mesh)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-mesh
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow traffic from Istio sidecar and control plane
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
    # Allow traffic from same namespace (pod-to-pod via mesh)
    - from:
        - podSelector: {}
  egress:
    # Allow DNS resolution
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Allow traffic to mesh control plane
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
    # Allow traffic within namespace
    - to:
        - podSelector: {}
    # Allow traffic to Kubernetes API
    - to:
        - ipBlock:
            cidr: 172.30.0.1/32
      ports:
        - protocol: TCP
          port: 443
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-gateway
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  podSelector:
    matchLabels:
      app: "{{ app }}"
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
          podSelector:
            matchLabels:
              istio: ingressgateway
      ports:
        - protocol: TCP
          port: 8080
```

### Quay Organization + Robot Account Config

Quay resources are managed via the Quay API, not CRDs. The platform pipeline or
bootstrap script calls the Quay API to create the org and robot account, then
stores the credentials in Vault for ESO to sync.

```bash
# Create Quay organization for the team
QUAY_API="https://quay.io/api/v1"
QUAY_TOKEN="${QUAY_ADMIN_TOKEN}"

# 1. Create organization
curl -s -X POST "${QUAY_API}/organization/" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "{{ team }}", "email": "{{ team }}@example.com"}'

# 2. Create robot account for CI pushes
curl -s -X PUT "${QUAY_API}/organization/{{ team }}/robots/ci-push" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"description": "CI pipeline push account for {{ team }}"}'

# 3. Extract robot token and store in Vault
ROBOT_TOKEN=$(curl -s "${QUAY_API}/organization/{{ team }}/robots/ci-push" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" | jq -r '.token')

vault kv put ci/{{ team }}/quay-robot \
  username="{{ team }}+ci-push" \
  token="${ROBOT_TOKEN}" \
  auth="$(echo -n '{{ team }}+ci-push:'"${ROBOT_TOKEN}" | base64)"

# 4. Create repository
curl -s -X POST "${QUAY_API}/repository" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"namespace": "{{ team }}", "repository": "{{ app }}", "visibility": "private", "description": "{{ app }} images"}'

# 5. Grant robot account write access to the repo
curl -s -X PUT "${QUAY_API}/repository/{{ team }}/{{ app }}/permissions/user/{{ team }}+ci-push" \
  -H "Authorization: Bearer ${QUAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"role": "write"}'
```

### ESO SecretStore for the Team

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: team-vault
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  provider:
    vault:
      server: https://vault.example.com
      path: secret
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: "{{ team }}-eso"
          serviceAccountRef:
            name: eso-sa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eso-sa
  namespace: "{{ team }}-{{ app }}-dev"
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: quay-push-creds
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: team-vault
    kind: SecretStore
  target:
    name: quay-push-creds
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {"auths":{"quay.io":{"username":"{{ .username }}","password":"{{ .token }}","auth":"{{ .auth }}"}}}
  data:
    - secretKey: username
      remoteRef:
        key: ci/{{ team }}/quay-robot
        property: username
    - secretKey: token
      remoteRef:
        key: ci/{{ team }}/quay-robot
        property: token
    - secretKey: auth
      remoteRef:
        key: ci/{{ team }}/quay-robot
        property: auth
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: git-pat-token
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: team-vault
    kind: SecretStore
  target:
    name: git-pat-token
  data:
    - secretKey: token
      remoteRef:
        key: ci/{{ team }}/github
        property: pat
```

### Tekton Pipeline (Team-Specific CI)

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: "{{ app }}-ci"
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  params:
    - name: git-url
      type: string
    - name: git-revision
      type: string
      default: main
    - name: image
      type: string
      default: "quay.io/{{ team }}/{{ app }}"
  workspaces:
    - name: source
    - name: git-credentials
  tasks:
    - name: clone
      taskRef:
        resolver: cluster
        params:
          - name: kind
            value: task
          - name: name
            value: git-clone
          - name: namespace
            value: openshift-pipelines
      params:
        - name: url
          value: $(params.git-url)
        - name: revision
          value: $(params.git-revision)
      workspaces:
        - name: output
          workspace: source
        - name: ssh-directory
          workspace: git-credentials
    - name: build-and-push
      runAfter: [clone]
      taskRef:
        resolver: cluster
        params:
          - name: kind
            value: task
          - name: name
            value: buildah
          - name: namespace
            value: openshift-pipelines
      params:
        - name: IMAGE
          value: "$(params.image):$(params.git-revision)"
      workspaces:
        - name: source
          workspace: source
    - name: gitops-update
      runAfter: [build-and-push]
      taskSpec:
        params:
          - name: image
          - name: tag
        steps:
          - name: update-tag
            image: alpine/git:latest
            env:
              - name: GIT_PAT
                valueFrom:
                  secretKeyRef:
                    name: git-pat-token
                    key: token
            script: |
              git clone https://x-access-token:${GIT_PAT}@github.com/org/gitops-repo.git /tmp/gitops
              cd /tmp/gitops/environments/dev
              kustomize edit set image $(params.image):$(params.tag)
              git config user.email "pipeline@ci.local"
              git config user.name "Tekton Pipeline"
              git add .
              git commit -m "chore: update {{ app }} to $(params.tag)"
              git push origin main
      params:
        - name: image
          value: $(params.image)
        - name: tag
          value: $(params.git-revision)
```

### Argo CD AppProject + Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: "{{ team }}"
  namespace: argocd
spec:
  description: "Project for {{ team }} team"
  sourceRepos:
    - "https://github.com/org/gitops-repo.git"
  destinations:
    - namespace: "{{ team }}-*"
      server: https://kubernetes.default.svc
  clusterResourceWhitelist: []    # No cluster-scoped resources allowed
  namespaceResourceBlacklist:
    - group: ""
      kind: ResourceQuota        # Platform team manages quotas
    - group: ""
      kind: LimitRange           # Platform team manages limits
    - group: networking.k8s.io
      kind: NetworkPolicy        # Platform team manages network policies
  roles:
    - name: team-admin
      description: "{{ team }} team members"
      policies:
        - "p, proj:{{ team }}:team-admin, applications, get, {{ team }}/*, allow"
        - "p, proj:{{ team }}:team-admin, applications, sync, {{ team }}/*, allow"
        - "p, proj:{{ team }}:team-admin, applications, action/*, {{ team }}/*, allow"
        - "p, proj:{{ team }}:team-admin, logs, get, {{ team }}/*, allow"
      groups:
        - "{{ team }}-developers"
  orphanedResources:
    warn: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: "{{ app }}-dev"
  namespace: argocd
  labels:
    team: "{{ team }}"
    app: "{{ app }}"
    env: dev
spec:
  project: "{{ team }}"
  source:
    repoURL: https://github.com/org/gitops-repo.git
    targetRevision: main
    path: "environments/dev"
  destination:
    server: https://kubernetes.default.svc
    namespace: "{{ team }}-{{ app }}-dev"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false    # Namespace created by onboarding, not Argo CD
      - RespectIgnoreDifferences=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 1m
```

### Mesh Enrollment (Namespace Label)

```bash
# OSSM 3.0 uses the standard Istio label for namespace enrollment
oc label namespace "{{ team }}-{{ app }}-dev" istio-injection=enabled

# Or declaratively in the Namespace manifest:
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: "{{ team }}-{{ app }}-dev"
  labels:
    team: "{{ team }}"
    app: "{{ app }}"
    env: dev
    managed-by: platform-onboarding
    istio-injection: enabled
```

### RBAC (RoleBinding for Team Group)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: "{{ team }}-admin"
  namespace: "{{ team }}-{{ app }}-dev"
subjects:
  - kind: Group
    name: "{{ team }}-developers"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pipeline
  namespace: "{{ team }}-{{ app }}-dev"
secrets:
  - name: quay-push-creds
imagePullSecrets:
  - name: quay-push-creds
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pipeline-edit
  namespace: "{{ team }}-{{ app }}-dev"
subjects:
  - kind: ServiceAccount
    name: pipeline
    namespace: "{{ team }}-{{ app }}-dev"
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
```

---

## Self-Service Pattern

Teams should not file tickets to get onboarded. The platform team maintains an
ApplicationSet that reads a config file from a Git repo. Adding a new team entry
to the config file triggers onboarding automatically.

### Config File (teams.yaml)

```yaml
# gitops-platform/teams.yaml
teams:
  - name: payments
    apps:
      - name: payment-api
        repo: https://github.com/org/payment-api.git
        namespace: payments-payment-api-dev
      - name: payment-worker
        repo: https://github.com/org/payment-worker.git
        namespace: payments-payment-worker-dev
  - name: catalog
    apps:
      - name: product-service
        repo: https://github.com/org/product-service.git
        namespace: catalog-product-service-dev
```

### ApplicationSet (Generates Onboarding Resources)

The ApplicationSet uses a Git generator to read `teams.yaml` and produce one
Application per team-app combination. Each Application points to a Kustomize
overlay that renders all onboarding resources.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-onboarding
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - matrix:
        generators:
          - git:
              repoURL: https://github.com/org/gitops-platform.git
              revision: main
              files:
                - path: teams.yaml
          - list:
              elementsYaml: "{{ .teams | toJson }}"
  template:
    metadata:
      name: "onboard-{{ .name }}"
    spec:
      project: platform-admin
      source:
        repoURL: https://github.com/org/gitops-platform.git
        targetRevision: main
        path: "onboarding/overlays/{{ .name }}"
        kustomize:
          commonLabels:
            team: "{{ .name }}"
            managed-by: platform-onboarding
      destination:
        server: https://kubernetes.default.svc
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Kustomize Overlay per Team

```
gitops-platform/
├── teams.yaml
├── onboarding/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── resourcequota.yaml
│   │   ├── limitrange.yaml
│   │   ├── networkpolicy.yaml
│   │   ├── rolebinding.yaml
│   │   ├── pipeline-sa.yaml
│   │   ├── secretstore.yaml
│   │   ├── externalsecrets.yaml
│   │   ├── appproject.yaml
│   │   └── pipeline.yaml
│   └── overlays/
│       ├── payments/
│       │   └── kustomization.yaml   # namePrefix, namespace, vars
│       └── catalog/
│           └── kustomization.yaml
```

**Base kustomization.yaml:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - resourcequota.yaml
  - limitrange.yaml
  - networkpolicy.yaml
  - rolebinding.yaml
  - pipeline-sa.yaml
  - secretstore.yaml
  - externalsecrets.yaml
  - appproject.yaml
  - pipeline.yaml
```

**Team overlay kustomization.yaml (payments example):**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: payments-payment-api-dev
patches:
  - target:
      kind: Namespace
      name: TEAM_PLACEHOLDER
    patch: |
      - op: replace
        path: /metadata/name
        value: payments-payment-api-dev
      - op: replace
        path: /metadata/labels/team
        value: payments
  - target:
      kind: AppProject
      name: TEAM_PLACEHOLDER
    patch: |
      - op: replace
        path: /metadata/name
        value: payments
      - op: replace
        path: /spec/destinations/0/namespace
        value: "payments-*"
      - op: replace
        path: /spec/sourceRepos/0
        value: "https://github.com/org/payment-api.git"
  - target:
      kind: RoleBinding
      name: TEAM_PLACEHOLDER-admin
    patch: |
      - op: replace
        path: /subjects/0/name
        value: payments-developers
  - target:
      kind: SecretStore
      name: team-vault
    patch: |
      - op: replace
        path: /spec/provider/vault/auth/kubernetes/role
        value: payments-eso
  - target:
      kind: Namespace
      name: TEAM_PLACEHOLDER
    patch: |
      - op: add
        path: /metadata/labels/istio-injection
        value: enabled
```

---

## Guard Rails

Guard rails prevent teams from consuming unbounded resources, bypassing network
isolation, or deploying outside their designated namespaces.

### Resource Quotas

Every namespace gets a ResourceQuota. The platform team sets defaults per tier:

| Tier | CPU Requests | Memory Requests | Pods | PVCs | Storage |
|------|-------------|----------------|------|------|---------|
| small | 4 | 8Gi | 20 | 5 | 20Gi |
| medium | 8 | 16Gi | 40 | 10 | 50Gi |
| large | 16 | 32Gi | 80 | 20 | 100Gi |

Teams request a tier in `teams.yaml`. The overlay patches the quota accordingly.
Exceeding quota causes pod scheduling failures — the platform team reviews
requests for tier upgrades.

### Network Policies

Every namespace starts with deny-all ingress and egress. Explicit policies open:

| Policy | Allows |
|--------|--------|
| `deny-all` | Nothing — baseline lockdown |
| `allow-mesh` | Ingress/egress to `istio-system` and same namespace |
| `allow-ingress-gateway` | Ingress from Istio ingress gateway on app port |
| `allow-dns` | Egress UDP/TCP 53 to kube-dns |
| `allow-kube-api` | Egress to Kubernetes API server |

Teams cannot create or modify NetworkPolicy — it is blacklisted in the AppProject.
Only the platform onboarding overlay manages network rules.

### Mesh Policies

```yaml
# Strict mTLS for the namespace — no plaintext service-to-service traffic
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: strict-mtls
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  mtls:
    mode: STRICT
---
# Default AuthorizationPolicy — deny all traffic not explicitly allowed
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: "{{ team }}-{{ app }}-dev"
spec: {}
---
# Allow traffic from the team's own namespace
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-same-namespace
  namespace: "{{ team }}-{{ app }}-dev"
spec:
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces:
              - "{{ team }}-{{ app }}-dev"
```

### AppProject Restrictions

The AppProject is the primary RBAC boundary for Argo CD. Key restrictions:

```yaml
spec:
  # Teams can only deploy to their own namespace pattern
  destinations:
    - namespace: "{{ team }}-*"
      server: https://kubernetes.default.svc

  # Teams can only deploy from their own repos
  sourceRepos:
    - "https://github.com/org/gitops-repo.git"

  # No cluster-scoped resources (no ClusterRole, no CRDs, no Nodes)
  clusterResourceWhitelist: []

  # Platform-managed resources are off-limits
  namespaceResourceBlacklist:
    - group: ""
      kind: ResourceQuota
    - group: ""
      kind: LimitRange
    - group: networking.k8s.io
      kind: NetworkPolicy
    - group: sailoperator.io
      kind: Istio
    - group: security.istio.io
      kind: PeerAuthentication

  # Warn about resources in the namespace not managed by Argo CD
  orphanedResources:
    warn: true
```

**What this prevents:**
- Teams cannot modify their own quotas or limits
- Teams cannot punch holes in network policies
- Teams cannot change mesh membership or mTLS settings
- Teams cannot deploy cluster-scoped resources
- Teams cannot deploy to namespaces outside their `{{ team }}-*` pattern
- Teams cannot pull manifests from unauthorized Git repos
