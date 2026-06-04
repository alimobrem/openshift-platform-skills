# Shipwright Builds Reference

## CRDs

| CRD | API Group | Description |
|-----|-----------|-------------|
| Build | shipwright.io/v1beta1 | Declarative build definition — source, strategy, output |
| BuildRun | shipwright.io/v1beta1 | Single execution of a Build |
| BuildStrategy | shipwright.io/v1beta1 | Namespaced build strategy (steps to produce an image) |
| ClusterBuildStrategy | shipwright.io/v1beta1 | Cluster-scoped build strategy shared across namespaces |

## Build Spec Structure

```yaml
apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: my-app
  namespace: team-alpha
spec:
  source:
    type: Git                             # Git | Local | OCI
    git:
      url: https://github.com/org/my-app.git
      revision: main                      # Branch, tag, or commit SHA
      cloneSecret: git-credentials        # Secret with SSH key or token (optional)
    contextDir: .                         # Subdirectory containing Dockerfile/source

  strategy:
    name: buildah                         # Reference to BuildStrategy or ClusterBuildStrategy
    kind: ClusterBuildStrategy            # BuildStrategy (namespaced) or ClusterBuildStrategy

  paramValues:                            # Strategy-specific parameters
    - name: dockerfile
      value: Dockerfile

  output:
    image: quay.io/org/my-app:latest      # Destination image reference
    pushSecret: quay-push-secret          # dockerconfigjson Secret for registry auth

  timeout: 30m                            # Build timeout (default: no timeout)
  retention:
    ttlAfterFailed: 48h                   # Auto-delete failed BuildRuns
    ttlAfterSucceeded: 24h               # Auto-delete succeeded BuildRuns
    failedLimit: 5
    succeededLimit: 10
```

## Build Strategies

### Buildah (Default)

The standard strategy for Dockerfile-based builds. Runs rootless Buildah in a pod.

```yaml
apiVersion: shipwright.io/v1beta1
kind: ClusterBuildStrategy
metadata:
  name: buildah
spec:
  steps:
    - name: build-and-push
      image: quay.io/containers/buildah:v1.35
      command:
        - /bin/bash
      args:
        - -c
        - |
          buildah --storage-driver=vfs bud \
            --format=oci \
            --tls-verify=true \
            --layers \
            -f $(params.dockerfile) \
            -t $(params.shp-output-image) \
            $(params.shp-source-context)
          buildah --storage-driver=vfs push \
            --tls-verify=true \
            --digestfile=/tmp/image-digest \
            $(params.shp-output-image)
      securityContext:
        runAsUser: 0                      # Required for buildah on OpenShift
      resources:
        limits:
          cpu: "2"
          memory: 4Gi
        requests:
          cpu: 500m
          memory: 1Gi
  parameters:
    - name: dockerfile
      description: Path to the Dockerfile
      default: Dockerfile
```

### Buildpacks

Cloud Native Buildpacks — no Dockerfile needed. Detects runtime and builds automatically.

```yaml
apiVersion: shipwright.io/v1beta1
kind: ClusterBuildStrategy
metadata:
  name: buildpacks
spec:
  steps:
    - name: build
      image: docker.io/paketobuildpacks/builder-jammy-full:latest
      command:
        - /cnb/lifecycle/creator
      args:
        - -app=$(params.shp-source-context)
        - -cache-dir=/cache
        - -run-image=docker.io/paketobuildpacks/run-jammy-full:latest
        - $(params.shp-output-image)
      resources:
        limits:
          cpu: "2"
          memory: 4Gi
  volumes:
    - name: cache
      emptyDir: {}
```

### Source-to-Image (S2I)

Red Hat's S2I workflow — uses builder images to inject source into a runtime container.

```yaml
apiVersion: shipwright.io/v1beta1
kind: ClusterBuildStrategy
metadata:
  name: source-to-image
spec:
  steps:
    - name: s2i-generate
      image: quay.io/openshift/origin-cli:latest
      command:
        - s2i
      args:
        - build
        - $(params.shp-source-context)
        - $(params.builder-image)
        - --as-dockerfile=/gen/Dockerfile
      volumeMounts:
        - name: gen-source
          mountPath: /gen
    - name: buildah-build
      image: quay.io/containers/buildah:v1.35
      command:
        - buildah
      args:
        - bud
        - --storage-driver=vfs
        - --tls-verify=true
        - -f
        - /gen/Dockerfile
        - -t
        - $(params.shp-output-image)
        - /gen
      volumeMounts:
        - name: gen-source
          mountPath: /gen
      securityContext:
        runAsUser: 0
    - name: push
      image: quay.io/containers/buildah:v1.35
      command:
        - buildah
      args:
        - push
        - --storage-driver=vfs
        - --tls-verify=true
        - $(params.shp-output-image)
      securityContext:
        runAsUser: 0
  parameters:
    - name: builder-image
      description: S2I builder image
      default: registry.access.redhat.com/ubi8/nodejs-18:latest
  volumes:
    - name: gen-source
      emptyDir: {}
```

## Source Configuration

### Git with Authentication

```yaml
# SSH key auth
apiVersion: v1
kind: Secret
metadata:
  name: git-ssh-credentials
  namespace: team-alpha
  annotations:
    build.shipwright.io/referenced.secret: "true"
type: kubernetes.io/ssh-auth
data:
  ssh-privatekey: <base64-encoded-key>
---
# Token auth (GitHub PAT, GitLab token)
apiVersion: v1
kind: Secret
metadata:
  name: git-token-credentials
  namespace: team-alpha
  annotations:
    build.shipwright.io/referenced.secret: "true"
type: kubernetes.io/basic-auth
stringData:
  username: git                           # Literal "git" for token-based auth
  password: ghp_xxxxxxxxxxxxxxxxxxxx      # GitHub PAT or GitLab token
```

```yaml
# Build referencing Git auth
spec:
  source:
    type: Git
    git:
      url: git@github.com:org/private-repo.git   # SSH URL for ssh-auth
      revision: main
      cloneSecret: git-ssh-credentials
```

### Local Source

Upload source from a local directory. Used with `shp` CLI for developer inner-loop.

```bash
# Build from local directory
shp buildrun create my-app-run --buildref-name my-app --source-directory=.
```

### OCI Bundle Source

Package source as an OCI artifact and reference it:

```yaml
spec:
  source:
    type: OCI
    oci:
      image: quay.io/org/my-app-source:latest
      pullSecret: registry-pull-secret
```

## Output Configuration

### Image Push with Registry Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: quay-push-secret
  namespace: team-alpha
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {
      "auths": {
        "quay.io": {
          "auth": "<base64(username:password)>",
          "email": ""
        }
      }
    }
```

```yaml
# Build output referencing push secret
spec:
  output:
    image: quay.io/org/my-app:$(build.name)-$(build.timestamp)
    pushSecret: quay-push-secret
    labels:                               # OCI labels applied to the image
      app.kubernetes.io/name: my-app
      app.kubernetes.io/version: "1.0.0"
    annotations:
      org.opencontainers.image.source: https://github.com/org/my-app
```

## Registry Auth Secrets

### Quay (Robot Account)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: quay-push-secret
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {
      "auths": {
        "quay.io": {
          "auth": "<base64(org+robot_name:token)>"
        }
      }
    }
```

### OpenShift Internal Registry

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: internal-registry-secret
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {
      "auths": {
        "image-registry.openshift-image-registry.svc:5000": {
          "auth": "<base64(serviceaccount:token)>"
        }
      }
    }
```

Use the default route for external pushes:

```yaml
# Get the default route
# oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}'
spec:
  output:
    image: default-route-openshift-image-registry.apps.cluster.example.com/team-alpha/my-app:latest
    pushSecret: internal-registry-secret
```

### AWS ECR

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ecr-push-secret
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {
      "auths": {
        "123456789012.dkr.ecr.us-east-1.amazonaws.com": {
          "auth": "<base64(AWS:ecr-login-token)>"
        }
      }
    }
```

Note: ECR tokens expire every 12 hours. Use External Secrets Operator or a CronJob to rotate.

## BuildRun

Trigger a one-off build execution:

```yaml
apiVersion: shipwright.io/v1beta1
kind: BuildRun
metadata:
  name: my-app-run-001
  namespace: team-alpha
spec:
  build:
    name: my-app                          # Reference to the Build
  serviceAccount: build-sa                # SA with push secret mounted
  timeout: 20m
  paramValues:                            # Override Build params for this run
    - name: dockerfile
      value: Dockerfile.prod
  output:                                 # Override output image for this run
    image: quay.io/org/my-app:v1.2.3
```

### BuildRun Status

```yaml
status:
  conditions:
    - type: Succeeded
      status: "True"                      # "True" | "False" | "Unknown"
      reason: Succeeded
      message: "All steps completed"
  output:
    digest: sha256:abc123...              # Image digest after successful push
    size: 104857600
  startTime: "2026-06-04T10:00:00Z"
  completionTime: "2026-06-04T10:05:30Z"
  taskRunName: my-app-run-001-xxxxx       # Underlying Tekton TaskRun
```

## BuildConfig to Shipwright Migration

### Side-by-Side Comparison

**Legacy BuildConfig (openshift.io/v1):**

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: my-app
  namespace: team-alpha
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/my-app.git
      ref: main
    sourceSecret:
      name: git-credentials
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
      from:
        kind: ImageStreamTag
        name: ubi8:latest
  output:
    to:
      kind: ImageStreamTag
      name: my-app:latest
    pushSecret:
      name: registry-credentials
  triggers:
    - type: ConfigChange
    - type: GitHub
      github:
        secret: webhook-secret
```

**Equivalent Shipwright Build:**

```yaml
apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: my-app
  namespace: team-alpha
spec:
  source:
    type: Git
    git:
      url: https://github.com/org/my-app.git
      revision: main
      cloneSecret: git-credentials
  strategy:
    name: buildah
    kind: ClusterBuildStrategy
  paramValues:
    - name: dockerfile
      value: Dockerfile
  output:
    image: quay.io/org/my-app:latest      # Direct registry ref, not ImageStream
    pushSecret: registry-credentials
```

### Migration Notes

| BuildConfig Feature | Shipwright Equivalent |
|---------------------|----------------------|
| `strategy.type: Docker` | `strategy.name: buildah` with ClusterBuildStrategy |
| `strategy.type: Source` (S2I) | `strategy.name: source-to-image` ClusterBuildStrategy |
| `output.to.kind: ImageStreamTag` | `output.image: <full-registry-url>` (no ImageStreams) |
| `triggers.type: GitHub` | Tekton EventListener + TriggerTemplate that creates BuildRun |
| `triggers.type: ConfigChange` | Not needed — create BuildRun explicitly or via pipeline |
| `source.sourceSecret` | `source.git.cloneSecret` |
| `strategy.dockerStrategy.from` | Base image in Dockerfile `FROM` line or strategy param |
| `runPolicy: Serial` | Managed by pipeline orchestration or BuildRun retention |

### Migration Steps

1. Install Shipwright operator (OpenShift Builds)
2. Create ClusterBuildStrategy matching your build type (buildah, s2i)
3. Convert each BuildConfig to a Build CR using the mapping above
4. Replace ImageStream references with direct registry URLs (e.g., `quay.io/org/app:tag`)
5. Replace webhook triggers with Tekton EventListener + TriggerTemplate
6. Update CI/CD pipelines to create BuildRun instead of `oc start-build`
7. Test builds, then delete old BuildConfigs and ImageStreams

## Integration: Pipeline Triggers BuildRun

Tekton pipeline creates a BuildRun, waits for completion, then uses the output image:

```yaml
# Tekton Task that triggers a Shipwright BuildRun
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: shipwright-build
spec:
  params:
    - name: build-name
      type: string
    - name: image-tag
      type: string
  results:
    - name: image-digest
      description: Built image digest
  steps:
    - name: create-buildrun
      image: quay.io/openshift/origin-cli:latest
      script: |
        #!/bin/bash
        set -euo pipefail
        BUILDRUN_NAME="$(params.build-name)-$(context.taskRun.name)"

        cat <<EOF | oc apply -f -
        apiVersion: shipwright.io/v1beta1
        kind: BuildRun
        metadata:
          name: ${BUILDRUN_NAME}
        spec:
          build:
            name: $(params.build-name)
          output:
            image: quay.io/org/my-app:$(params.image-tag)
        EOF

        # Wait for BuildRun to complete
        oc wait buildrun/${BUILDRUN_NAME} \
          --for=condition=Succeeded \
          --timeout=30m

        # Extract image digest
        DIGEST=$(oc get buildrun ${BUILDRUN_NAME} \
          -o jsonpath='{.status.output.digest}')
        echo -n "${DIGEST}" > $(results.image-digest.path)
```

### Image Tag Feeds GitOps

After the build completes, a subsequent pipeline task updates the GitOps repo:

```yaml
# Pipeline wiring: build → gitops-update
spec:
  tasks:
    - name: build
      taskRef:
        name: shipwright-build
      params:
        - name: build-name
          value: my-app
        - name: image-tag
          value: $(params.git-sha)
    - name: update-gitops
      runAfter: [build]
      taskRef:
        name: git-update-image-tag
      params:
        - name: image
          value: "quay.io/org/my-app@$(tasks.build.results.image-digest)"
        - name: gitops-repo
          value: https://github.com/org/gitops-config.git
        - name: environment
          value: dev
```

## Common Mistakes

### Wrong Strategy Kind

```yaml
# WRONG — BuildStrategy is namespaced, this looks for it in the current namespace
spec:
  strategy:
    name: buildah
    kind: BuildStrategy          # Will fail if "buildah" only exists as ClusterBuildStrategy
```

```yaml
# CORRECT — use ClusterBuildStrategy for cluster-wide strategies
spec:
  strategy:
    name: buildah
    kind: ClusterBuildStrategy
```

### Missing Push Secret

BuildRun fails with `unauthorized: access denied` or `authentication required`:

```yaml
# WRONG — no pushSecret, registry rejects anonymous push
spec:
  output:
    image: quay.io/org/my-app:latest

# CORRECT — always specify pushSecret for authenticated registries
spec:
  output:
    image: quay.io/org/my-app:latest
    pushSecret: quay-push-secret
```

Verify the secret exists and has correct format:

```bash
oc get secret quay-push-secret -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
```

### Wrong Registry URL Format

```yaml
# WRONG — includes https:// prefix
spec:
  output:
    image: https://quay.io/org/my-app:latest

# WRONG — missing org/namespace
spec:
  output:
    image: quay.io/my-app:latest

# CORRECT — registry/org/repo:tag format, no protocol
spec:
  output:
    image: quay.io/org/my-app:latest
```

### Internal Registry URL Errors

```yaml
# WRONG — using external route from inside the cluster
spec:
  output:
    image: default-route-openshift-image-registry.apps.cluster.example.com/ns/app:tag

# CORRECT — use internal service DNS for in-cluster builds
spec:
  output:
    image: image-registry.openshift-image-registry.svc:5000/ns/app:tag
```

### BuildRun ServiceAccount Missing Secrets

The ServiceAccount running the build must have the push secret linked:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: build-sa
  namespace: team-alpha
secrets:
  - name: quay-push-secret               # Push secret must be listed here
  - name: git-ssh-credentials             # Git clone secret if using SSH
```

### Timeout Too Short for Large Images

Multi-stage builds or large base images can exceed default timeouts:

```yaml
# Set appropriate timeout for heavy builds
spec:
  timeout: 45m
```

### Source Context Directory Wrong

```yaml
# WRONG — contextDir doesn't exist in repo
spec:
  source:
    type: Git
    git:
      url: https://github.com/org/monorepo.git
    contextDir: apps/my-app/docker        # Directory must contain Dockerfile

# Verify: clone the repo and check the path exists
```
