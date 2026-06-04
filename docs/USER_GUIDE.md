# User Guide

## Quick Start

```shell
/plugin marketplace add alimobrem/openshift-platform-skills
/plugin install openshift-platform-skills@platform-engineering
# Then ask: "Audit this repo for platform engineering best practices"
```

## What You Can Ask

The agent routes your question to the right layer automatically. Below are example prompts for each layer.

### Build (Shipwright)

```text
Create a Shipwright Build for my Go app using the buildah ClusterBuildStrategy.
Why is my BuildRun stuck in pending?
Set up a multi-arch build pipeline for linux/amd64 and linux/arm64.
What's the difference between buildah and S2I ClusterBuildStrategies?
Generate a Build that tags images with the Git SHA and pushes to Quay.
```

### Pipeline (Tekton)

```text
Generate a Tekton Pipeline that clones, builds, scans, and deploys a Java app.
Create an EventListener with a GitHub push trigger and CEL filter.
Why did my PipelineRun fail at the build-image step?
How do I cache Maven dependencies across PipelineRuns using workspaces?
Set up a Tekton Pipeline that runs Trivy and gates on HIGH/CRITICAL CVEs.
```

### Registry (Quay)

```text
Configure Quay mirror registry for air-gapped deployment.
Set up image signing with cosign in a Tekton task.
Create a robot account for CI pull/push access to the payments repo.
Set up tag expiration policies for dev images older than 30 days.
Audit all image repositories for unsigned images.
```

### Secrets (External Secrets Operator)

```text
Set up ExternalSecretOperator to sync secrets from AWS Secrets Manager.
Create a ClusterSecretStore for HashiCorp Vault with Kubernetes auth.
Rotate the database credentials in namespace production.
Audit all ExternalSecrets for sync failures across the cluster.
Create an ExternalSecret that refreshes every 15 minutes from AWS SSM.
```

### Mesh (Istio / OSSM 3.0)

```text
Install OSSM 3.0 using the Sail operator with an Istio CR and openshift profile.
Enable strict mTLS mesh-wide using PeerAuthentication.
Create a VirtualService with 90/10 canary traffic split.
Why is my service getting 503s after enabling mTLS?
Configure request timeouts and circuit breakers for the API gateway.
```

### Delivery (Rollouts + Istio Traffic Management, Promoter)

```text
Create a canary Rollout with Istio traffic splitting and Prometheus analysis.
Set up blue-green deployment with header-based preview routing.
Promote the canary rollout in production after analysis passes.
Abort the failing rollout and roll back to the stable revision.
Configure a GitOps promoter that updates the image tag in the staging overlay.
```

### Onboarding

```text
Create a new namespace with standard quotas and network policies.
Set up RBAC for the data-science team across dev/staging/prod.
Review quota utilization across all team namespaces.
Onboard the payments team with namespace, pipeline, mesh enrollment, and RBAC.
Check for namespaces missing network policies or LimitRanges.
```

### Metrics (DORA)

```text
Calculate DORA metrics from our Tekton PipelineRuns and ArgoCD deployments.
What's our deployment frequency and lead time for the payments service?
Our change failure rate is 15%. What should we focus on?
Generate PromQL queries for all four DORA metrics.
Create a Grafana dashboard JSON for DORA metrics with PrometheusRule alerts.
```

### Debug (Cross-Layer)

```text
The app deployed but isn't reachable. What's wrong?
Debug the full path from build to deployment for the checkout service.
Run a platform health check across all layers.
Why did the canary rollout pause? Check the AnalysisRun and mesh config.
Trace the commit through Tekton, Quay signing, ArgoCD sync, and Rollout.
```

## Swappable Components

The skill supports multiple implementations at each layer. The agent detects which components are installed on your cluster and adapts.

| Layer | Primary | Alternatives |
|-------|---------|-------------|
| Build | Shipwright | Buildah, S2I, Kaniko |
| Pipeline | Tekton | -- |
| Registry | Quay | OpenShift internal registry |
| Secrets | External Secrets Operator | Sealed Secrets, Vault CSI |
| Mesh | Istio / OSSM 3.0 (Sail) | -- |
| Delivery | Argo Rollouts | OpenShift DeploymentConfig |

## Make Targets

```shell
make test-evals    # Run platform-engineering skill evals
make help          # Show available targets
```

## GitHub Actions

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `ci.yml` | Push / PR | Lint, validate fixtures, run tests |
| `evals.yml` | Manual / schedule | Run full eval suite and publish scorecard |
| `release.yml` | Tag push | Package and publish release |

## Tips

- **Use `oc` not `kubectl`** -- the agent generates `oc` commands for OpenShift clusters. `oc` handles routes, DeploymentConfigs, and image streams that `kubectl` cannot.
- **Red Hat operators** -- the skill uses Red Hat-certified operators (Sail for OSSM 3.0, Red Hat Pipelines for Tekton, etc.) instead of community upstream installs.
- **Safety model** -- the agent follows generate-preview-confirm for all mutating operations. Read-only commands skip confirmation. Destructive operations require typing the resource name.
