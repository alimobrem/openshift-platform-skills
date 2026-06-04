<p align="center">
  <img src="assets/banner.svg" alt="OpenShift Platform Skills" width="900"/>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome"></a>
  <img src="https://img.shields.io/badge/OpenShift-4.14+-EE0000.svg" alt="OpenShift 4.14+">
  <img src="https://img.shields.io/badge/Tekton-v0.60+-2B7DE9.svg" alt="Tekton v0.60+">
  <img src="https://img.shields.io/badge/Istio-1.24+-466BB0.svg" alt="Istio 1.24+">
</p>

<p align="center">
  <b>Give your AI agent deep expertise in OpenShift platform engineering.</b><br>
  Build images, run pipelines, manage registries, rotate secrets, configure service mesh,
  and measure DORA metrics — all from your terminal.
</p>

---

<details>
<summary><b>Quick Start</b></summary>

```shell
# Claude Code
/plugin marketplace add alimobrem/openshift-platform-skills
/plugin install openshift-platform-skills@platform-engineering

# Then try:
# "Audit this repo for platform engineering best practices"
# "Create a Tekton pipeline for my Go microservice"
# "Set up ExternalSecret to pull from AWS Secrets Manager"
```

</details>

## Install

<details>
<summary><b>Claude Code</b></summary>

```shell
/plugin marketplace add alimobrem/openshift-platform-skills
/plugin install openshift-platform-skills@platform-engineering
```

After install, the `platform-engineering` agent appears in `/agents` and skills auto-trigger
based on context. Run `/reload-plugins` if they don't appear immediately.

</details>

<details>
<summary><b>Codex</b></summary>

Add to `$REPO_ROOT/.agents/plugins/marketplace.json` or `~/.agents/plugins/marketplace.json`:

```json
{
  "name": "openshift-platform-skills",
  "category": "Developer Tools",
  "source": {
    "source": "url",
    "url": "https://github.com/alimobrem/openshift-platform-skills.git",
    "ref": "main"
  },
  "policy": {
    "installation": "AVAILABLE",
    "authentication": "ON_INSTALL"
  }
}
```

</details>

<details>
<summary><b>GitHub Copilot</b></summary>

Copy the agent file to your repository:

```shell
mkdir -p .github/copilot
cp agents/github-copilot/platform-engineering.agent.md .github/copilot/
```

</details>

<details>
<summary><b>Prerequisites</b></summary>

Required:
- `kubectl` or `oc` for Kubernetes/OpenShift cluster interaction

Optional (enhances capabilities):
- `tkn` — Tekton pipeline inspection and triggering
- `istioctl` — Istio mesh analysis and debugging
- `yq` — YAML parsing
- `skopeo` — container image inspection
- `cosign` — image signature verification

Install all on macOS:
```shell
brew bundle
```

</details>

## Usage Guide

### How Routing Works

The agent automatically selects the right layer based on what you ask:

```
 Build an image ─────────► Build        Shipwright / Buildah / S2I
 Run a pipeline ─────────► Pipeline     Tekton Pipelines & Triggers
 Manage images ──────────► Registry     Quay / ImageStreams / signing
 Rotate secrets ─────────► Secrets      ExternalSecretOperator / vault
 Configure mesh ─────────► Mesh         Istio / OpenShift Service Mesh
 Ship a release ─────────► Delivery     Progressive rollouts / GitOps promotion
 Onboard a team ─────────► Onboarding   Namespace provisioning / quotas / RBAC
 Measure velocity ───────► Metrics      DORA four keys / lead time / MTTR
 Debug failures ─────────► Debug        Cross-layer troubleshooting
```

You don't need to invoke layers manually — just describe what you need.

### Build — Shipwright & Buildah

Use when you need to build container images on OpenShift.

```text
# Create builds
Create a Shipwright Build for my Go app using the buildah ClusterBuildStrategy.

# Troubleshoot
Why is my BuildRun stuck in pending?
Debug the failing S2I build in namespace myapp.

# Best practices
What's the best way to structure a multi-arch build pipeline?
```

### Pipeline — Tekton Pipelines & Triggers

Use when you need CI/CD pipelines on OpenShift.

```text
# Create pipelines
Generate a Tekton Pipeline that clones, builds, scans, and deploys a Java app.
Create an EventListener with a GitHub push trigger.

# Debug
Why did my PipelineRun fail at the build-image step?
Show me the logs for the last failed TaskRun in namespace ci.

# Optimize
How do I cache Maven dependencies across PipelineRuns?
Set up workspace sharing between tasks.
```

### Registry — Quay & Image Management

Use when managing container images and registries.

```text
# Setup
Configure Quay mirror registry for air-gapped deployment.
Set up image signing with cosign and Tekton.

# Operations
Create a robot account for CI pull/push access.
Set up tag expiration policies for dev images.
```

### Secrets — External Secrets Operator

Use when managing secrets and credentials.

```text
# Setup
Set up ExternalSecretOperator to sync secrets from AWS Secrets Manager.
Create a ClusterSecretStore for HashiCorp Vault.

# Operations
Rotate the database credentials in namespace production.
Audit all ExternalSecrets for sync failures.
```

### Mesh — Istio & OpenShift Service Mesh

Use when configuring service mesh and traffic management.

```text
# Setup
Enable strict mTLS for the payments namespace.
Create a VirtualService with 90/10 canary traffic split.

# Debug
Why is my service getting 503s after enabling mTLS?
Analyze the mesh configuration for security issues.

# Traffic management
Set up fault injection to test resilience.
Configure request timeouts and circuit breakers for the API gateway.
```

### Delivery — Progressive Rollouts

Use when shipping releases safely.

```text
# Deploy
Create a canary rollout with automated analysis for the frontend service.
Set up blue-green deployment with traffic switching.

# Promote
Promote the canary rollout in production.
Abort the failing rollout and roll back.
```

### Onboarding — Team & Namespace Provisioning

Use when onboarding teams or setting up namespaces.

```text
# Provision
Create a new namespace with standard quotas and network policies.
Set up RBAC for the data-science team across dev/staging/prod.

# Audit
Review quota utilization across all team namespaces.
Check for namespaces missing network policies.
```

### Metrics — DORA Four Keys

Use when measuring engineering velocity and reliability.

```text
# Measure
Calculate DORA metrics from our Tekton PipelineRuns and deployments.
What's our deployment frequency and lead time for the payments service?

# Improve
Our change failure rate is 15%. What should we focus on?
How do I set up automated DORA metric collection?
```

### Debug — Cross-Layer Troubleshooting

Use when something is broken and you're not sure which layer is at fault.

```text
# Investigate
The app deployed but isn't reachable. What's wrong?
Debug the full path from build to deployment for the checkout service.

# Health check
Run a platform health check across all layers.
```

<details>
<summary><b>Swappable components</b></summary>

The skill supports multiple implementations at each layer:

| Layer | Primary | Alternatives |
|-------|---------|-------------|
| Build | Shipwright | Buildah, S2I, Kaniko |
| Pipeline | Tekton | — |
| Registry | Quay | OpenShift internal registry |
| Secrets | External Secrets Operator | Sealed Secrets, Vault CSI |
| Mesh | Istio / OSSM | — |
| Delivery | Argo Rollouts | OpenShift DeploymentConfig |

The agent detects which components are installed on your cluster and adapts accordingly.

</details>

<details>
<summary><b>Safety model</b></summary>

| Step | What happens |
|------|-------------|
| Generate | Produces YAML manifest or CLI command, shows it in a code block |
| Preview | Runs `--dry-run=client`, `kubectl diff`, or `oc diff` to show what changes |
| Confirm | Asks "Apply this? (yes/no)" — does NOT proceed without explicit approval |

Read-only operations (status checks, metric queries) skip confirmation.

Destructive operations (delete, scale-to-zero, rollback) require typing the resource name to confirm.

</details>

## Benchmarks

Evals on `claude-opus-4-6`. Tests **outcomes** (correct YAML, right CRDs, safety model), not process.
[Full results](benchmarks/platform-engineering.md)

<table>
<thead>
<tr>
<th width="220">Eval</th>
<th width="80">Score</th>
<th>Highlights</th>
</tr>
</thead>
<tbody>
<tr><td>Shipwright build setup</td><td><b>10/10</b></td><td>Build + ClusterBuildStrategy with Buildah, Git SHA tags, registry auth, timeout, retention</td></tr>
<tr><td>Tekton CI pipeline</td><td><b>10/10</b></td><td>5-task pipeline with runAfter chain, workspaces, Trivy HIGH/CRITICAL, gitops-update</td></tr>
<tr><td>OSSM setup</td><td><b>10/10</b></td><td>Istio control plane + strict mTLS + namespace enrollment + Kiali/tracing/Prometheus</td></tr>
<tr><td>End-to-end delivery flow</td><td><b>10/10</b></td><td>All 8 layers wired: Shipwright → Tekton → Quay → ESO → ArgoCD → Istio → Rollout → Promoter</td></tr>
<tr><td>Platform onboarding</td><td><b>10/10</b></td><td>Complete team setup: namespace, quota, NetworkPolicy, RBAC, pipeline, AppProject, mesh</td></tr>
<tr><td>DORA metrics</td><td><b>10/10</b></td><td>PromQL for all 4 metrics + Grafana dashboard JSON + PrometheusRule alerts</td></tr>
<tr><td>Cross-layer debug</td><td><b>10/10</b></td><td>9-step trace from commit through all platform layers with CLI commands</td></tr>
<tr><td>Platform health check</td><td><b>10/10</b></td><td>All 7 controllers checked, CRDs verified, summary produced</td></tr>
<tr><td>Quay registry setup</td><td><b>10/10</b></td><td>QuayRegistry CR + Clair + robot accounts + scanning policies + Tekton integration</td></tr>
<tr><td>ESO + Vault</td><td><b>10/10</b></td><td>ClusterSecretStore + Vault K8s auth + 3 ExternalSecrets + 1h refresh</td></tr>
<tr><td><b>Overall</b></td><td><b>100/100</b></td><td>Perfect score across all 10 evals — correct YAML, right CRDs, complete coverage</td></tr>
</tbody>
</table>

<sub>Run locally with <code>make test-evals</code> or via GitHub Actions (<code>evals</code> workflow).</sub>

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

<details>
<summary><b>Development</b></summary>

```shell
# Install prerequisites (macOS)
brew bundle

# Run tests
make test

# Run evals
make eval
```

See [AGENTS.md](AGENTS.md) for the repo layout, skill conventions, and eval runner instructions.

</details>

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

[MIT License](LICENSE)
