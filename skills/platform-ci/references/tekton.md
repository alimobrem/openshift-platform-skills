# Tekton Pipelines Reference

## CRDs

| CRD | API Group | Description |
|-----|-----------|-------------|
| Pipeline | tekton.dev/v1 | Ordered series of Tasks with dependency graph |
| PipelineRun | tekton.dev/v1 | Single execution of a Pipeline |
| Task | tekton.dev/v1 | Sequence of steps running in a single pod |
| TaskRun | tekton.dev/v1 | Single execution of a Task |
| EventListener | triggers.tekton.dev/v1beta1 | HTTP endpoint that receives webhook events |
| TriggerBinding | triggers.tekton.dev/v1beta1 | Extracts fields from event payload into params |
| TriggerTemplate | triggers.tekton.dev/v1beta1 | Template that creates resources (PipelineRun) from trigger params |

## OpenShift Pipelines Operator Install

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

Verify installation:

```bash
# Check operator pod
oc get pods -n openshift-pipelines -l app=tekton-pipelines-controller

# Check CRDs installed
oc get crd | grep tekton.dev

# Check tkn CLI
tkn version
```

## Pipeline-as-Code (PaC)

PaC lets you define pipelines in your source repo (`.tekton/` directory) and trigger them
automatically on pull requests and pushes.

### Setup

```bash
# Install PaC (included with OpenShift Pipelines 1.9+)
# Configure GitHub App or webhook for your repo

# Create Repository CR to link Git repo to PaC
cat <<EOF | oc apply -f -
apiVersion: pipelinesascode.tekton.dev/v1alpha1
kind: Repository
metadata:
  name: my-app
  namespace: team-alpha
spec:
  url: "https://github.com/org/my-app"
  git_provider:
    secret:
      name: github-app-secret
      key: github-private-key
    application_id: "12345"
EOF
```

### Pipeline in Repo

Place pipeline definition at `.tekton/pull-request.yaml` in your source repo:

```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: my-app-pr
  annotations:
    pipelinesascode.tekton.dev/on-event: "[pull_request]"
    pipelinesascode.tekton.dev/on-target-branch: "[main]"
    pipelinesascode.tekton.dev/task: "[git-clone, buildah]"
    pipelinesascode.tekton.dev/max-keep-runs: "3"
spec:
  pipelineSpec:
    # Inline pipeline definition
    tasks:
      - name: clone
        taskRef:
          name: git-clone
        workspaces:
          - name: output
            workspace: source
        params:
          - name: url
            value: "{{ repo_url }}"
          - name: revision
            value: "{{ revision }}"
      - name: build
        runAfter: [clone]
        taskRef:
          name: buildah
        workspaces:
          - name: source
            workspace: source
        params:
          - name: IMAGE
            value: "quay.io/org/my-app:{{ revision }}"
    workspaces:
      - name: source
  workspaces:
    - name: source
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 1Gi
```

PaC variables: `{{ repo_url }}`, `{{ revision }}`, `{{ pull_request_number }}`, `{{ target_branch }}`.

## Common Tasks

### git-clone

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: git-clone
spec:
  params:
    - name: url
      type: string
    - name: revision
      type: string
      default: main
    - name: depth
      type: string
      default: "1"
  results:
    - name: commit
      description: The commit SHA that was cloned
  workspaces:
    - name: output
      description: Cloned repo contents
    - name: ssh-credentials
      optional: true
  steps:
    - name: clone
      image: gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/git-init:latest
      script: |
        #!/bin/sh
        set -eu
        git clone --depth=$(params.depth) \
          --branch=$(params.revision) \
          $(params.url) \
          $(workspaces.output.path)/source
        cd $(workspaces.output.path)/source
        echo -n "$(git rev-parse HEAD)" > $(results.commit.path)
```

### buildah

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: buildah
spec:
  params:
    - name: IMAGE
      type: string
    - name: DOCKERFILE
      type: string
      default: ./Dockerfile
    - name: CONTEXT
      type: string
      default: .
    - name: TLSVERIFY
      type: string
      default: "true"
  results:
    - name: IMAGE_DIGEST
    - name: IMAGE_URL
  workspaces:
    - name: source
    - name: dockerconfig
      description: Registry auth
      optional: true
  steps:
    - name: build
      image: quay.io/containers/buildah:v1.35
      securityContext:
        runAsUser: 0
      script: |
        #!/bin/bash
        set -euo pipefail

        [[ -f "$(workspaces.dockerconfig.path)/config.json" ]] && \
          export DOCKER_CONFIG=$(workspaces.dockerconfig.path)

        buildah --storage-driver=vfs bud \
          --format=oci \
          --tls-verify=$(params.TLSVERIFY) \
          --layers \
          -f $(params.DOCKERFILE) \
          -t $(params.IMAGE) \
          $(workspaces.source.path)/source/$(params.CONTEXT)

        buildah --storage-driver=vfs push \
          --tls-verify=$(params.TLSVERIFY) \
          --digestfile=/tmp/image-digest \
          $(params.IMAGE)

        echo -n "$(cat /tmp/image-digest)" > $(results.IMAGE_DIGEST.path)
        echo -n "$(params.IMAGE)" > $(results.IMAGE_URL.path)
```

### trivy-scanner

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: trivy-scanner
spec:
  params:
    - name: IMAGE
      type: string
    - name: SEVERITY
      type: string
      default: "CRITICAL,HIGH"
    - name: EXIT_CODE
      type: string
      default: "1"                        # Fail the task on findings
  workspaces:
    - name: dockerconfig
      optional: true
  steps:
    - name: scan
      image: docker.io/aquasec/trivy:latest
      script: |
        #!/bin/sh
        set -eu

        [[ -f "$(workspaces.dockerconfig.path)/config.json" ]] && \
          export DOCKER_CONFIG=$(workspaces.dockerconfig.path)

        trivy image \
          --severity $(params.SEVERITY) \
          --exit-code $(params.EXIT_CODE) \
          --no-progress \
          --format table \
          $(params.IMAGE)
```

### openshift-client

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: openshift-client
spec:
  params:
    - name: SCRIPT
      type: string
      description: oc commands to run
    - name: VERSION
      type: string
      default: "latest"
  steps:
    - name: oc
      image: quay.io/openshift/origin-cli:$(params.VERSION)
      script: |
        #!/bin/bash
        set -euo pipefail
        $(params.SCRIPT)
```

## CI Pipeline Pattern

Complete pipeline: clone, test, build, scan, push, update GitOps repo.

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: ci-pipeline
  namespace: team-alpha
spec:
  params:
    - name: git-url
      type: string
    - name: git-revision
      type: string
      default: main
    - name: image-name
      type: string
      default: quay.io/org/my-app
    - name: gitops-repo-url
      type: string
      default: https://github.com/org/gitops-config.git
    - name: environment
      type: string
      default: dev

  workspaces:
    - name: shared-workspace
    - name: git-credentials
    - name: registry-credentials

  tasks:
    # 1. Clone source
    - name: clone
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
      params:
        - name: url
          value: $(params.git-url)
        - name: revision
          value: $(params.git-revision)

    # 2. Run tests
    - name: test
      runAfter: [clone]
      taskRef:
        name: run-tests
      workspaces:
        - name: source
          workspace: shared-workspace

    # 3. Build image
    - name: build
      runAfter: [test]
      taskRef:
        name: buildah
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: dockerconfig
          workspace: registry-credentials
      params:
        - name: IMAGE
          value: "$(params.image-name):$(tasks.clone.results.commit)"

    # 4. Scan image
    - name: scan
      runAfter: [build]
      taskRef:
        name: trivy-scanner
      workspaces:
        - name: dockerconfig
          workspace: registry-credentials
      params:
        - name: IMAGE
          value: "$(params.image-name):$(tasks.clone.results.commit)"
        - name: SEVERITY
          value: "CRITICAL,HIGH"

    # 5. Update GitOps repo
    - name: gitops-update
      runAfter: [scan]
      taskRef:
        name: git-update-image-tag
      workspaces:
        - name: git-credentials
          workspace: git-credentials
      params:
        - name: image
          value: "$(params.image-name)@$(tasks.build.results.IMAGE_DIGEST)"
        - name: gitops-repo-url
          value: $(params.gitops-repo-url)
        - name: environment
          value: $(params.environment)
        - name: app-name
          value: my-app
```

### PipelineRun

```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: ci-pipeline-run-
  namespace: team-alpha
spec:
  pipelineRef:
    name: ci-pipeline
  params:
    - name: git-url
      value: https://github.com/org/my-app.git
    - name: git-revision
      value: abc123def
    - name: image-name
      value: quay.io/org/my-app
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 5Gi
    - name: git-credentials
      secret:
        secretName: git-write-token
    - name: registry-credentials
      secret:
        secretName: quay-push-secret
  serviceAccountName: pipeline-sa
  timeouts:
    pipeline: 1h
    tasks: 30m
```

## Trigger Pattern

GitHub webhook fires EventListener, which extracts params via TriggerBinding and creates
a PipelineRun via TriggerTemplate.

### EventListener

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-listener
  namespace: team-alpha
spec:
  serviceAccountName: trigger-sa
  triggers:
    - name: github-push
      interceptors:
        - ref:
            name: github
            kind: ClusterInterceptor
          params:
            - name: secretRef
              value:
                secretName: github-webhook-secret
                secretKey: webhook-secret
            - name: eventTypes
              value: ["push"]
        - ref:
            name: cel
            kind: ClusterInterceptor
          params:
            - name: filter
              value: "body.ref == 'refs/heads/main'"   # Only trigger on main branch
      bindings:
        - ref: github-push-binding
      template:
        ref: github-push-template
  resources:
    kubernetesResource:
      spec:
        template:
          spec:
            serviceAccountName: trigger-sa
            containers: []
```

Expose the EventListener externally:

```bash
# OpenShift Route (auto-created by the operator, or create manually)
oc get route -n team-alpha el-github-listener

# Configure this URL as the webhook URL in GitHub:
# https://el-github-listener-team-alpha.apps.cluster.example.com
```

### TriggerBinding

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: github-push-binding
  namespace: team-alpha
spec:
  params:
    - name: git-url
      value: $(body.repository.clone_url)
    - name: git-revision
      value: $(body.after)                # Commit SHA after push
    - name: git-ref
      value: $(body.ref)
```

### TriggerTemplate

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: github-push-template
  namespace: team-alpha
spec:
  params:
    - name: git-url
    - name: git-revision
    - name: git-ref
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata:
        generateName: ci-pipeline-run-
      spec:
        pipelineRef:
          name: ci-pipeline
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
                    storage: 5Gi
          - name: git-credentials
            secret:
              secretName: git-write-token
          - name: registry-credentials
            secret:
              secretName: quay-push-secret
        serviceAccountName: pipeline-sa
        timeouts:
          pipeline: 1h
```

## Pipeline-to-GitOps Handoff

Tekton task that commits the new image tag to the GitOps repo so Argo CD picks it up.

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: git-update-image-tag
spec:
  params:
    - name: image
      type: string
      description: "Full image reference (repo@sha256:digest or repo:tag)"
    - name: gitops-repo-url
      type: string
    - name: environment
      type: string
      default: dev
    - name: app-name
      type: string
    - name: git-user-name
      type: string
      default: tekton-bot
    - name: git-user-email
      type: string
      default: tekton-bot@example.com
  workspaces:
    - name: git-credentials
      description: Secret with Git write token
  steps:
    - name: update-and-push
      image: docker.io/alpine/git:latest
      script: |
        #!/bin/sh
        set -eu

        # Configure git auth
        cp $(workspaces.git-credentials.path)/.gitconfig ~/.gitconfig 2>/dev/null || true
        git config --global credential.helper store
        echo "https://git:$(cat $(workspaces.git-credentials.path)/token)@github.com" \
          > ~/.git-credentials

        git config --global user.name "$(params.git-user-name)"
        git config --global user.email "$(params.git-user-email)"

        # Clone gitops repo
        git clone $(params.gitops-repo-url) /tmp/gitops
        cd /tmp/gitops

        # Update image in kustomization.yaml
        KUSTOMIZE_PATH="apps/$(params.app-name)/overlays/$(params.environment)"

        # Using kustomize edit (if available) or sed
        cd "${KUSTOMIZE_PATH}"
        if command -v kustomize &> /dev/null; then
          kustomize edit set image "$(params.app-name)=$(params.image)"
        else
          # Fallback: update image tag in kustomization.yaml
          sed -i "s|newTag:.*|newTag: $(echo $(params.image) | cut -d: -f2)|" \
            kustomization.yaml
        fi

        # Commit and push
        git add -A
        git commit -m "chore($(params.environment)): update $(params.app-name) to $(params.image)

        Triggered by Tekton pipeline"
        git push origin main
```

## Workspace Patterns

### PersistentVolumeClaim (Shared Across Tasks)

```yaml
# Pre-created PVC — reused across PipelineRuns
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pipeline-workspace
  namespace: team-alpha
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp3-csi
---
# PipelineRun referencing existing PVC
spec:
  workspaces:
    - name: shared-workspace
      persistentVolumeClaim:
        claimName: pipeline-workspace
```

### VolumeClaimTemplate (Ephemeral, Per-Run)

```yaml
# Created automatically per PipelineRun, deleted after completion
spec:
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 5Gi
          storageClassName: gp3-csi       # Optional — uses default SC if omitted
```

This is the recommended approach. Each PipelineRun gets its own volume, no contention.

### emptyDir (Fast, Non-Persistent)

```yaml
# In-memory or node-local ephemeral storage. Lost when pod terminates.
spec:
  workspaces:
    - name: temp-workspace
      emptyDir: {}

    # With memory backing (faster, limited by node memory)
    - name: fast-workspace
      emptyDir:
        medium: Memory
        sizeLimit: 256Mi
```

Use for: caches, temp files, small intermediate artifacts. Not suitable for sharing data
between tasks (each task runs in its own pod).

### Secret as Workspace

```yaml
spec:
  workspaces:
    - name: git-credentials
      secret:
        secretName: git-write-token
    - name: registry-credentials
      secret:
        secretName: quay-push-secret
```

## RBAC

### Pipeline ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pipeline-sa
  namespace: team-alpha
secrets:
  - name: quay-push-secret               # Registry push credentials
  - name: git-write-token                 # Git write access for GitOps updates
```

### RoleBinding for Registry Push

```yaml
# For OpenShift internal registry: grant image-pusher role
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pipeline-image-pusher
  namespace: team-alpha
subjects:
  - kind: ServiceAccount
    name: pipeline-sa
    namespace: team-alpha
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:image-pusher
```

### RoleBinding for Pipeline Resources

```yaml
# Allow pipeline SA to create/watch TaskRuns, PipelineRuns, etc.
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pipeline-tekton-access
  namespace: team-alpha
subjects:
  - kind: ServiceAccount
    name: pipeline-sa
    namespace: team-alpha
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-pipelines-clusterrole      # Installed by operator
```

### Trigger ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: trigger-sa
  namespace: team-alpha
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: trigger-sa-binding
  namespace: team-alpha
subjects:
  - kind: ServiceAccount
    name: trigger-sa
    namespace: team-alpha
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-eventlistener-roles
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: trigger-sa-interceptors
subjects:
  - kind: ServiceAccount
    name: trigger-sa
    namespace: team-alpha
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-eventlistener-clusterroles
```

### Git Write Access Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: git-write-token
  namespace: team-alpha
type: Opaque
stringData:
  token: ghp_xxxxxxxxxxxxxxxxxxxx         # GitHub PAT with repo write scope
  .gitconfig: |
    [credential "https://github.com"]
      helper = store
```

## Common Mistakes

### Task Results Exceed Size Limit

Tekton results are stored in the termination message (max 4096 bytes total per pod).
Large outputs silently truncate or fail the task.

```yaml
# WRONG — dumping large output into a result
- name: full-scan-report
  description: Complete scan results     # Can exceed 4KB easily

# CORRECT — write large outputs to workspace, store only summary/digest in results
- name: scan-digest
  description: SHA of scan report file
```

### Workspace Not Shared Between Tasks

Each task in a Pipeline runs in its own pod. Data sharing requires explicit workspaces.

```yaml
# WRONG — task B can't see task A's files without a shared workspace
tasks:
  - name: clone
    taskRef: { name: git-clone }
    # No workspace binding — clone goes to emptyDir, lost when pod exits
  - name: build
    runAfter: [clone]
    taskRef: { name: buildah }
    # Can't access cloned source

# CORRECT — both tasks bind the same workspace
tasks:
  - name: clone
    taskRef: { name: git-clone }
    workspaces:
      - name: output
        workspace: shared-workspace
  - name: build
    runAfter: [clone]
    taskRef: { name: buildah }
    workspaces:
      - name: source
        workspace: shared-workspace       # Same workspace, different binding name
```

### PipelineRun Stuck Pending (No PVC)

`PipelineRun` hangs in `Pending` state — usually a workspace PVC issue.

```bash
# Check PipelineRun status
tkn pipelinerun describe <name> -n team-alpha

# Common causes:
# 1. StorageClass doesn't exist or can't provision
# 2. PVC accessMode mismatch (ReadWriteOnce can't be shared across nodes)
# 3. PVC storage quota exceeded
oc get pvc -n team-alpha
oc describe pvc <pvc-name> -n team-alpha
```

### Wrong EventListener URL

```bash
# WRONG — using the Service, not the Route (not accessible externally)
# Webhook URL: http://el-github-listener.team-alpha.svc:8080

# CORRECT — use the OpenShift Route
oc get route -n team-alpha el-github-listener -o jsonpath='{.spec.host}'
# Webhook URL: https://el-github-listener-team-alpha.apps.cluster.example.com
```

### TriggerTemplate Param Syntax

```yaml
# WRONG — using PipelineRun param syntax in TriggerTemplate
params:
  - name: git-url
    value: $(params.git-url)              # This resolves in Pipeline context, not trigger

# CORRECT — use tt.params prefix in TriggerTemplate
params:
  - name: git-url
    value: $(tt.params.git-url)           # Resolves from TriggerBinding params
```

### Missing Interceptor Secret

EventListener rejects all webhooks with 403:

```yaml
# Webhook secret must match what's configured in GitHub
apiVersion: v1
kind: Secret
metadata:
  name: github-webhook-secret
  namespace: team-alpha
type: Opaque
stringData:
  webhook-secret: <same-value-as-github-webhook-settings>
```

### ServiceAccount Missing in PipelineRun

```yaml
# WRONG — no SA specified, uses "default" SA which lacks permissions
spec:
  pipelineRef:
    name: ci-pipeline
  # serviceAccountName not set

# CORRECT — specify SA with required secrets and RBAC
spec:
  pipelineRef:
    name: ci-pipeline
  serviceAccountName: pipeline-sa         # SA with registry + git secrets
```

### Pipeline Timeout vs Task Timeout

```yaml
# Pipeline-level timeout must be >= sum of sequential task timeouts
spec:
  timeouts:
    pipeline: 1h                          # Total pipeline timeout
    tasks: 30m                            # Per-task timeout
    finally: 10m                          # Timeout for finally tasks
```

If `pipeline` timeout is shorter than the sum of `tasks` timeouts, the pipeline is
cancelled mid-execution without running `finally` tasks.

### runAfter Missing Causes Parallel Execution

```yaml
# WRONG — build runs in parallel with clone (no dependency)
tasks:
  - name: clone
    taskRef: { name: git-clone }
  - name: build
    taskRef: { name: buildah }            # Starts immediately, source not cloned yet

# CORRECT — explicit dependency
tasks:
  - name: clone
    taskRef: { name: git-clone }
  - name: build
    runAfter: [clone]                     # Waits for clone to finish
    taskRef: { name: buildah }
```

### Finally Tasks Can't Reference Task Results

```yaml
# WRONG — finally tasks can't use results from tasks that may have failed
finally:
  - name: notify
    params:
      - name: digest
        value: $(tasks.build.results.IMAGE_DIGEST)  # Fails if build was skipped/failed

# CORRECT — guard with when expressions or use aggregate status
finally:
  - name: notify
    params:
      - name: status
        value: $(tasks.status)            # "Succeeded", "Failed", "Completed", "None"
```
