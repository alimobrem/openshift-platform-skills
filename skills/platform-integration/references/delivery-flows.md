# Delivery Flows Reference — End-to-End Integration

How all platform layers wire together from Git push to production traffic. Covers
the golden path, variant flows, secrets wiring, and a complete 3-environment example.

---

## The Golden Path

The full-stack delivery flow uses every layer: Tekton triggers a pipeline on push,
Shipwright builds the image, Tekton pushes to Quay, commits the tag to the GitOps
repo, Argo CD syncs, Istio routes traffic, Argo Rollouts shifts weight, and
gitops-promoter gates promotion to the next environment.

### Wiring Diagram

```
  Developer pushes to app repo
        |
        v
  +------------------------------+
  | Tekton EventListener         |  <-- GitHub/GitLab webhook
  | (triggers.tekton.dev/v1beta1)|
  +------------------------------+
        |  TriggerTemplate creates
        v
  +------------------------------+
  | Tekton PipelineRun           |  <-- clone -> test -> build -> scan -> push -> gitops-update
  | (tekton.dev/v1)              |
  +------------------------------+
        |  Pipeline task invokes
        v
  +------------------------------+
  | Shipwright BuildRun           |  <-- Buildah strategy, outputs to Quay
  | (shipwright.io/v1beta1)       |
  +------------------------------+
        |  Image pushed with tag
        v
  +------------------------------+
  | Quay Registry                |  <-- quay.io/org/app:sha-abc1234
  | (quay.redhat.com/v1)         |
  +------------------------------+
        |  Tekton gitops-update task commits new tag
        v
  +------------------------------+
  | GitOps Repo (environments/)  |  <-- kustomization.yaml images updated
  |   dev/   staging/   prod/    |
  +------------------------------+
        |  Argo CD detects drift
        v
  +------------------------------+
  | Argo CD Application          |  <-- syncs manifests to cluster (argo-skills)
  | (argoproj.io/v1alpha1)       |
  +------------------------------+
        |  Rollout spec updated
        v
  +------------------------------+
  | Argo Rollout                 |  <-- canary strategy with Istio trafficRouting
  | (argoproj.io/v1alpha1)       |
  +------------------------------+
        |  Shifts VirtualService weights
        v
  +------------------------------+
  | Istio VirtualService         |  <-- 10% -> 30% -> 60% -> 100% canary
  | (networking.istio.io/v1)     |
  +------------------------------+
        |  Rollout completes, CommitStatus reports success
        v
  +------------------------------+
  | gitops-promoter              |  <-- PromotionStrategy gates promotion
  | (promoter.argoproj.io/v1alpha1)|     dev -> staging -> prod
  +------------------------------+
```

### CRD Cross-References

| Source CRD | References | Target CRD | How |
|-----------|------------|------------|-----|
| EventListener | `triggerRef` | TriggerTemplate | Names the template to instantiate |
| TriggerTemplate | `resourcetemplates` | PipelineRun | Embeds PipelineRun spec |
| Pipeline (task) | `taskRef` or inline `taskSpec` | Shipwright BuildRun | Task creates BuildRun via `kubectl create` |
| BuildRun | `spec.build.name` | Build | References the Build definition |
| Build | `spec.output.image` | Quay registry | Push destination URL |
| Pipeline (gitops-update task) | git commit | GitOps repo | Writes image tag to kustomization.yaml |
| Argo CD Application | `spec.source.path` | GitOps repo | Watches the path Tekton committed to |
| Argo CD Application | synced manifests | Rollout | Deploys the Rollout resource |
| Rollout | `spec.strategy.canary.trafficRouting.istio` | VirtualService | Names the VS to manage |
| Rollout | `spec.strategy.canary.trafficRouting.istio` | DestinationRule | Names the DR for subsets |
| PromotionStrategy | `spec.environments[].autoMerge` | GitOps repo branches | Merges between environment branches |
| CommitStatus | `spec.sha` | PromotionStrategy | Reports pipeline/health status to gate promotion |

---

## Variant Flows

### Variant 1: Full Stack (All Layers)

As described in the golden path above. Every component is present:
Tekton + Shipwright + Quay + ESO + Argo CD + Istio + Rollouts + gitops-promoter.

**When to use:** Teams with full OSSM and progressive delivery requirements.

### Variant 2: No Shipwright (Tekton Buildah Task Does the Build)

```
  EventListener -> PipelineRun -> [buildah task builds image directly] -> Quay -> gitops-update
                                     (no BuildRun)
```

**Differences from golden path:**
- Pipeline includes an inline `buildah` task instead of a task that creates a BuildRun
- No Build, BuildRun, or BuildStrategy CRDs needed
- Build parameters (Dockerfile path, context, build args) live in the Pipeline task params
- Simpler — fewer CRDs to manage. Loses Shipwright's build strategy abstraction.

**Pipeline task replacement:**

```yaml
# Instead of a task that creates a Shipwright BuildRun:
- name: build-image
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
      value: "$(params.image-registry)/$(params.image-name):$(params.image-tag)"
    - name: DOCKERFILE
      value: ./Dockerfile
  workspaces:
    - name: source
      workspace: shared-workspace
```

### Variant 3: No Istio (Replica-Based Rollout Canary)

```
  EventListener -> PipelineRun -> Shipwright BuildRun -> Quay -> gitops-update
      -> Argo CD syncs -> Rollout shifts replicas (no VirtualService)
```

**Differences from golden path:**
- No VirtualService, DestinationRule, or Gateway CRDs
- No Istio CR, IstioCNI, or `istio-injection` namespace labels
- Rollout uses replica-based canary instead of traffic-weighted canary
- Canary accuracy depends on replica count (5 replicas = 20% granularity minimum)
- No header/cookie-based routing for testing

**Rollout without trafficRouting:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  replicas: 5
  strategy:
    canary:
      steps:
        - setWeight: 20    # 1 of 5 replicas runs canary
        - pause: { duration: 5m }
        - setWeight: 40
        - pause: { duration: 5m }
        - setWeight: 60
        - pause: { duration: 5m }
        - setWeight: 80
        - pause: { duration: 5m }
      # No trafficRouting block — uses replica scaling
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: app
          image: quay.io/myorg/my-app:v1.0.0
          ports:
            - containerPort: 8080
```

### Variant 4: No Promoter (Manual Argo CD Sync for Promotion)

```
  EventListener -> PipelineRun -> Shipwright BuildRun -> Quay -> gitops-update
      -> Argo CD syncs to dev -> [MANUAL] user syncs staging -> [MANUAL] user syncs prod
```

**Differences from golden path:**
- No PromotionStrategy, ChangeTransferPolicy, or CommitStatus CRDs
- Each environment has a separate Argo CD Application with `syncPolicy: {}` (manual)
- Promotion is a human action: `argocd app sync my-app-staging`
- No automated gating based on pipeline results or mesh error rates
- Simpler but slower — suitable for teams not ready for full automation

**Application with manual sync:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-staging
  namespace: argocd
spec:
  project: my-team
  source:
    repoURL: https://github.com/org/gitops-repo.git
    targetRevision: main
    path: environments/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app-staging
  # No syncPolicy.automated — requires manual sync
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

---

## Secrets Flow

Every tool in the platform needs credentials. This table shows which ServiceAccount
or Secret feeds which component and how to provision it.

| Consumer | Secret Name | Secret Type | Contents | Provisioned By | Mounted Via |
|----------|------------|-------------|----------|---------------|-------------|
| Tekton Pipeline SA | `quay-push-creds` | `kubernetes.io/dockerconfigjson` | Quay robot account token | ESO ExternalSecret | SA `imagePullSecrets` + `secrets` |
| Tekton Pipeline SA | `git-ssh-key` | `kubernetes.io/ssh-auth` | Git SSH private key | ESO ExternalSecret | Pipeline workspace |
| Tekton gitops-update task | `git-pat-token` | Opaque | GitHub PAT or App token | ESO ExternalSecret | Task env var |
| Shipwright Build | `quay-push-creds` | `kubernetes.io/dockerconfigjson` | Same Quay robot token | Shared with pipeline SA | `spec.output.credentials.name` |
| Argo CD repo credential | `repo-creds-gitops` | Opaque | Git URL + SSH key or PAT | ArgoCD `credentialTemplates` | Argo CD Secret with label |
| Argo CD Image Updater | `quay-pull-creds` | `kubernetes.io/dockerconfigjson` | Quay read-only token | ESO ExternalSecret | Image Updater config |
| Istio Gateway | `gateway-tls` | `kubernetes.io/tls` | TLS cert + key | ESO ExternalSecret or cert-manager | Gateway `credentialName` |
| gitops-promoter | `promoter-github-app` | Opaque | GitHub App private key + ID | ESO ExternalSecret | Promoter controller config |
| ESO SecretStore | `vault-approle` | Opaque | Vault AppRole role_id + secret_id | Manual or bootstrap script | SecretStore `spec.provider.vault.auth` |

### ESO ExternalSecret for Pipeline Credentials

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: quay-push-creds
  namespace: my-app-dev
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: quay-push-creds
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {"auths":{"quay.io":{"username":"{{ .robot_user }}","password":"{{ .robot_token }}","auth":"{{ .robot_auth }}"}}}
  data:
    - secretKey: robot_user
      remoteRef:
        key: ci/quay-robot
        property: username
    - secretKey: robot_token
      remoteRef:
        key: ci/quay-robot
        property: token
    - secretKey: robot_auth
      remoteRef:
        key: ci/quay-robot
        property: auth
```

---

## Complete 3-Environment Example

A comprehensive delivery flow for an application `order-service` deployed across
dev, staging, and prod. This example includes every resource needed for the golden
path.

### GitOps Repo Structure

```
gitops-repo/
├── environments/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   ├── rollout.yaml
│   │   ├── service.yaml
│   │   ├── virtualservice.yaml
│   │   └── destinationrule.yaml
│   ├── staging/
│   │   └── kustomization.yaml      # patches from dev
│   └── prod/
│       └── kustomization.yaml      # patches from dev
├── base/
│   ├── kustomization.yaml
│   ├── rollout.yaml
│   ├── service.yaml
│   ├── virtualservice.yaml
│   └── destinationrule.yaml
└── pipeline/
    ├── pipeline.yaml
    ├── eventlistener.yaml
    ├── triggerbinding.yaml
    └── triggertemplate.yaml
```

### Tekton Pipeline

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: order-service-ci
  namespace: order-service-dev
spec:
  params:
    - name: git-url
      type: string
    - name: git-revision
      type: string
      default: main
    - name: image-name
      type: string
      default: quay.io/myorg/order-service
  workspaces:
    - name: shared-workspace
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
          workspace: shared-workspace
        - name: ssh-directory
          workspace: git-credentials

    - name: test
      runAfter: [clone]
      taskSpec:
        workspaces:
          - name: source
        steps:
          - name: run-tests
            image: golang:1.22
            workingDir: $(workspaces.source.path)
            script: |
              go test ./... -v -count=1
      workspaces:
        - name: source
          workspace: shared-workspace

    - name: build-image
      runAfter: [test]
      taskSpec:
        params:
          - name: build-name
        workspaces:
          - name: source
        steps:
          - name: trigger-build
            image: quay.io/openshift/origin-cli:latest
            script: |
              cat <<YAML | kubectl create -f -
              apiVersion: shipwright.io/v1beta1
              kind: BuildRun
              metadata:
                generateName: order-service-build-
                namespace: order-service-dev
              spec:
                build:
                  name: order-service
              YAML
              # Wait for BuildRun to complete
              kubectl wait buildrun -l build.shipwright.io/name=order-service \
                --for=condition=Succeeded --timeout=600s -n order-service-dev
        params:
          - name: build-name
            value: order-service
      workspaces:
        - name: source
          workspace: shared-workspace

    - name: scan-image
      runAfter: [build-image]
      taskRef:
        resolver: cluster
        params:
          - name: kind
            value: task
          - name: name
            value: trivy-scanner
          - name: namespace
            value: openshift-pipelines
      params:
        - name: IMAGE
          value: $(params.image-name):$(params.git-revision)
        - name: SEVERITY
          value: "CRITICAL,HIGH"

    - name: gitops-update
      runAfter: [scan-image]
      taskSpec:
        params:
          - name: image
          - name: tag
          - name: gitops-repo
        workspaces:
          - name: git-creds
        steps:
          - name: update-image-tag
            image: alpine/git:latest
            env:
              - name: GIT_PAT
                valueFrom:
                  secretKeyRef:
                    name: git-pat-token
                    key: token
            script: |
              git clone https://x-access-token:${GIT_PAT}@github.com/$(params.gitops-repo).git /tmp/gitops
              cd /tmp/gitops/environments/dev
              kustomize edit set image $(params.image):$(params.tag)
              git config user.email "pipeline@ci.local"
              git config user.name "Tekton Pipeline"
              git add .
              git commit -m "chore: update order-service to $(params.tag)"
              git push origin main
      params:
        - name: image
          value: $(params.image-name)
        - name: tag
          value: $(params.git-revision)
        - name: gitops-repo
          value: org/gitops-repo
      workspaces:
        - name: git-creds
          workspace: git-credentials
```

### Tekton Triggers

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: order-service-listener
  namespace: order-service-dev
spec:
  serviceAccountName: pipeline
  triggers:
    - name: github-push
      bindings:
        - ref: order-service-binding
      template:
        ref: order-service-template
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: order-service-binding
  namespace: order-service-dev
spec:
  params:
    - name: git-url
      value: $(body.repository.clone_url)
    - name: git-revision
      value: $(body.head_commit.id)
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: order-service-template
  namespace: order-service-dev
spec:
  params:
    - name: git-url
    - name: git-revision
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata:
        generateName: order-service-ci-
      spec:
        pipelineRef:
          name: order-service-ci
        params:
          - name: git-url
            value: $(tt.params.git-url)
          - name: git-revision
            value: $(tt.params.git-revision)
        workspaces:
          - name: shared-workspace
            volumeClaimTemplate:
              spec:
                accessModes: [ReadWriteOnce]
                resources:
                  requests:
                    storage: 1Gi
          - name: git-credentials
            secret:
              secretName: git-ssh-key
```

### Shipwright Build

```yaml
apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: order-service
  namespace: order-service-dev
spec:
  source:
    type: Git
    git:
      url: https://github.com/org/order-service.git
      revision: main
    contextDir: .
  strategy:
    name: buildah
    kind: ClusterBuildStrategy
  paramValues:
    - name: dockerfile
      value: Dockerfile
  output:
    image: quay.io/myorg/order-service:latest
    credentials:
      name: quay-push-creds
```

### Quay Push Secret (via ESO)

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: quay-push-creds
  namespace: order-service-dev
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
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
        key: ci/quay-robot
        property: username
    - secretKey: token
      remoteRef:
        key: ci/quay-robot
        property: token
    - secretKey: auth
      remoteRef:
        key: ci/quay-robot
        property: auth
```

### Argo CD ApplicationSet (3 Environments)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: order-service
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - list:
        elements:
          - env: dev
            namespace: order-service-dev
            autoSync: true
          - env: staging
            namespace: order-service-staging
            autoSync: false
          - env: prod
            namespace: order-service-prod
            autoSync: false
  template:
    metadata:
      name: "order-service-{{ .env }}"
    spec:
      project: order-service
      source:
        repoURL: https://github.com/org/gitops-repo.git
        targetRevision: main
        path: "environments/{{ .env }}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{ .namespace }}"
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
          - RespectIgnoreDifferences=true
```

### Rollout with Istio Canary

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: order-service
spec:
  replicas: 3
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app: order-service
  strategy:
    canary:
      canaryService: order-service-canary
      stableService: order-service-stable
      trafficRouting:
        istio:
          virtualServices:
            - name: order-service-vs
              routes:
                - primary
          destinationRule:
            name: order-service-dr
            canarySubsetName: canary
            stableSubsetName: stable
      steps:
        - setWeight: 10
        - pause: { duration: 2m }
        - setWeight: 30
        - pause: { duration: 2m }
        - setWeight: 60
        - pause: { duration: 5m }
      analysis:
        templates:
          - templateName: istio-success-rate
        startingStep: 1
        args:
          - name: service-name
            value: order-service-canary
  template:
    metadata:
      labels:
        app: order-service
      annotations:
        sidecar.istio.io/inject: "true"
    spec:
      containers:
        - name: order-service
          image: quay.io/myorg/order-service:v1.0.0
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: order-service-stable
spec:
  selector:
    app: order-service
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: order-service-canary
spec:
  selector:
    app: order-service
  ports:
    - port: 80
      targetPort: 8080
```

### Istio Traffic Resources

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: order-service-vs
spec:
  hosts:
    - order-service
  http:
    - name: primary
      route:
        - destination:
            host: order-service-stable
            subset: stable
          weight: 100
        - destination:
            host: order-service-canary
            subset: canary
          weight: 0
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: order-service-dr
spec:
  host: order-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: DEFAULT
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
  subsets:
    - name: stable
      labels:
        app: order-service
    - name: canary
      labels:
        app: order-service
```

### AnalysisTemplate for Canary Validation

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: istio-success-rate
spec:
  args:
    - name: service-name
  metrics:
    - name: success-rate
      interval: 60s
      successCondition: result[0] >= 0.95
      failureLimit: 3
      provider:
        prometheus:
          address: http://prometheus.istio-system:9090
          query: |
            sum(rate(istio_requests_total{
              reporter="destination",
              destination_service=~"{{args.service-name}}.*",
              response_code!~"5.*"
            }[2m])) /
            sum(rate(istio_requests_total{
              reporter="destination",
              destination_service=~"{{args.service-name}}.*"
            }[2m]))
```

### gitops-promoter PromotionStrategy

```yaml
apiVersion: promoter.argoproj.io/v1alpha1
kind: PromotionStrategy
metadata:
  name: order-service
  namespace: argocd
spec:
  repositoryReference:
    owner: org
    name: gitops-repo
    scmProviderRef:
      name: github-scm
  activeCommitStatuses:
    - key: pipeline-status
    - key: argocd-health
    - key: canary-analysis
  proposedCommitStatuses:
    - key: preview-healthy
  environments:
    - branch: environment/dev
      autoMerge: true
      activeCommitStatuses:
        - key: pipeline-status
    - branch: environment/staging
      autoMerge: true
      activeCommitStatuses:
        - key: pipeline-status
        - key: argocd-health
        - key: canary-analysis
    - branch: environment/prod
      autoMerge: false
      activeCommitStatuses:
        - key: pipeline-status
        - key: argocd-health
        - key: canary-analysis
---
apiVersion: promoter.argoproj.io/v1alpha1
kind: CommitStatus
metadata:
  name: order-service-pipeline-dev
  namespace: argocd
spec:
  repositoryReference:
    owner: org
    name: gitops-repo
    scmProviderRef:
      name: github-scm
  sha: ""   # Updated by Tekton pipeline task
  name: pipeline-status
  phase: success
  url: ""   # Link to PipelineRun
```

### Pipeline ServiceAccount RBAC

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pipeline
  namespace: order-service-dev
secrets:
  - name: quay-push-creds
  - name: git-ssh-key
imagePullSecrets:
  - name: quay-push-creds
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pipeline-shipwright
  namespace: order-service-dev
rules:
  - apiGroups: [shipwright.io]
    resources: [buildruns]
    verbs: [create, get, list, watch]
  - apiGroups: [tekton.dev]
    resources: [pipelineruns, taskruns]
    verbs: [create, get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pipeline-shipwright
  namespace: order-service-dev
subjects:
  - kind: ServiceAccount
    name: pipeline
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pipeline-shipwright
```
