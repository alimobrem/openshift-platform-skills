# DORA Metrics Reference — Measuring Delivery Performance

Definitions, thresholds, data sources, PromQL queries, Grafana dashboard, and
PrometheusRule alerts for the four DORA metrics on an OpenShift delivery platform.

---

## The Four DORA Metrics

| Metric | Definition | Elite | High | Medium | Low |
|--------|-----------|-------|------|--------|-----|
| **Deployment Frequency** | How often code is deployed to production | On-demand (multiple/day) | Between once/day and once/week | Between once/week and once/month | Fewer than once/month |
| **Lead Time for Changes** | Time from commit to running in production | Less than 1 hour | Between 1 day and 1 week | Between 1 week and 1 month | More than 6 months |
| **Change Failure Rate** | Percentage of deployments causing a failure | 0–5% | 5–10% | 10–15% | 46–60% |
| **Mean Time to Recovery** | Time to restore service after an incident | Less than 1 hour | Less than 1 day | Between 1 day and 1 week | More than 6 months |

Source: DORA State of DevOps Report 2023.

---

## Data Sources Per Metric

### Deployment Frequency

- **Primary:** Argo CD Application sync events (`argocd_app_sync_total` with `phase="Succeeded"`)
- **Secondary:** Tekton PipelineRun completions (`tekton_pipelines_controller_pipelinerun_duration_seconds_count`)
- **Note:** Count syncs to the production environment only. Filter by Application name or label to isolate prod.

### Lead Time for Changes

- **Start:** Git commit timestamp (captured as a PipelineRun annotation or parameter)
- **End:** Argo CD sync completion timestamp for the production Application
- **Calculation:** `sync_completion_time - git_commit_time`
- **Proxy (when commit timestamp is unavailable):** PipelineRun creation → Argo CD sync completion. Less accurate but requires no custom instrumentation.

### Change Failure Rate

- **Numerator:** Failed Argo CD syncs (`argocd_app_sync_total{phase="Error"}`) + Rollout aborts (`argocd_app_health_status{health_status="Degraded"}` transitions)
- **Denominator:** Total syncs (`argocd_app_sync_total`) or total Rollout promotions
- **Alternative:** Istio error rate spike after a deployment (`istio_requests_total{response_code=~"5.."}`)

### Mean Time to Recovery (MTTR)

- **Start:** Application health transitions to `Degraded` or `Missing` (`argocd_app_health_status`)
- **End:** Application health returns to `Healthy`
- **Calculation:** Duration between the two state transitions
- **Secondary signal:** Argo Rollout abort timestamp → next successful promotion timestamp

---

## PromQL Queries

### Deployment Frequency (deploys per week)

```promql
# Successful syncs per application over the last 7 days
sum by (name) (
  increase(argocd_app_sync_total{phase="Succeeded", dest_namespace=~".*prod.*"}[7d])
)
```

**Required exporter:** Argo CD exposes these metrics natively on `:8082/metrics`.
Ensure the `argocd-metrics` Service is scraped by your Prometheus (ServiceMonitor or PodMonitor).

### Lead Time for Changes (p50, seconds)

```promql
# Using Tekton PipelineRun duration as a proxy for lead time
# (commit → pipeline start → build → test → gitops-update → sync)
histogram_quantile(0.50,
  sum by (le, pipeline) (
    rate(tekton_pipelines_controller_pipelinerun_duration_seconds_bucket[1h])
  )
)
```

**Note:** This measures pipeline duration only (commit-to-sync-trigger), not the full
commit-to-production lead time. For the full metric, instrument a custom histogram
that records `sync_completion_time - commit_time`. Push this from a Tekton finally
task or a post-sync hook.

**Required exporter:** Tekton Pipelines controller exposes metrics on port `9090`.
Install the OpenShift Pipelines operator — metrics are enabled by default.

### Change Failure Rate (ratio, 0–1)

```promql
# Failed syncs as a fraction of total syncs over the last 30 days
sum(increase(argocd_app_sync_total{phase="Error"}[30d]))
/
sum(increase(argocd_app_sync_total[30d]))
```

To include Rollout failures:

```promql
# Combined: failed syncs + degraded health transitions vs total syncs
(
  sum(increase(argocd_app_sync_total{phase="Error"}[30d]))
  +
  sum(increase(argocd_app_health_status{health_status="Degraded"}[30d]))
)
/
sum(increase(argocd_app_sync_total[30d]))
```

**Required exporter:** Argo CD metrics (same as Deployment Frequency).

### Mean Time to Recovery (seconds)

MTTR requires tracking state transitions, which basic counters cannot express.
Use a recording rule to capture the duration between `Degraded` and `Healthy` states.

```promql
# Approximate: average time spent in Degraded state over the last 30 days
# Uses the proportion-of-time the app was Degraded, converted to seconds
avg by (name) (
  avg_over_time(
    (argocd_app_health_status{health_status="Degraded"})[30d:1m]
  )
) * 30 * 24 * 3600
/ 
sum by (name) (
  increase(argocd_app_health_status{health_status="Degraded"}[30d])
)
```

**Recommended approach:** Use Argo CD notifications to push webhooks on health
state changes, record timestamps in a dedicated Prometheus metric via pushgateway
or a small exporter, then compute `avg(recovery_time - degraded_time)`.

---

## Grafana Dashboard JSON

A complete importable dashboard with 4 stat panels (current values) and 4 time-series
panels (trends). Import via Grafana UI → Dashboards → Import → paste JSON.

```json
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "panels": [
    {
      "title": "Deployment Frequency (per week)",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
      "targets": [
        {
          "expr": "sum(increase(argocd_app_sync_total{phase=\"Succeeded\", dest_namespace=~\".*prod.*\"}[7d]))",
          "legendFormat": "Deploys / week",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "red", "value": null },
              { "color": "orange", "value": 1 },
              { "color": "yellow", "value": 4 },
              { "color": "green", "value": 7 }
            ]
          },
          "unit": "short"
        }
      }
    },
    {
      "title": "Lead Time p50 (seconds)",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 6, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
      "targets": [
        {
          "expr": "histogram_quantile(0.50, sum by (le) (rate(tekton_pipelines_controller_pipelinerun_duration_seconds_bucket[1h])))",
          "legendFormat": "p50 Lead Time",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 3600 },
              { "color": "orange", "value": 86400 },
              { "color": "red", "value": 604800 }
            ]
          },
          "unit": "s"
        }
      }
    },
    {
      "title": "Change Failure Rate",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 12, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
      "targets": [
        {
          "expr": "sum(increase(argocd_app_sync_total{phase=\"Error\"}[30d])) / sum(increase(argocd_app_sync_total[30d]))",
          "legendFormat": "CFR",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 0.05 },
              { "color": "orange", "value": 0.10 },
              { "color": "red", "value": 0.15 }
            ]
          },
          "unit": "percentunit"
        }
      }
    },
    {
      "title": "MTTR (hours)",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 18, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
      "targets": [
        {
          "expr": "avg by (name) (avg_over_time((argocd_app_health_status{health_status=\"Degraded\"})[30d:1m])) * 30 * 24 * 3600 / sum by (name) (increase(argocd_app_health_status{health_status=\"Degraded\"}[30d])) / 3600",
          "legendFormat": "{{ name }}",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 1 },
              { "color": "orange", "value": 24 },
              { "color": "red", "value": 168 }
            ]
          },
          "unit": "h"
        }
      }
    },
    {
      "title": "Deployment Frequency Trend",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
      "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
      "targets": [
        {
          "expr": "sum by (name) (increase(argocd_app_sync_total{phase=\"Succeeded\", dest_namespace=~\".*prod.*\"}[1d]))",
          "legendFormat": "{{ name }}",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": { "custom": { "drawStyle": "bars", "fillOpacity": 30 }, "unit": "short" }
      }
    },
    {
      "title": "Lead Time Trend (p50 / p95)",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
      "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
      "targets": [
        {
          "expr": "histogram_quantile(0.50, sum by (le) (rate(tekton_pipelines_controller_pipelinerun_duration_seconds_bucket[1h])))",
          "legendFormat": "p50",
          "refId": "A"
        },
        {
          "expr": "histogram_quantile(0.95, sum by (le) (rate(tekton_pipelines_controller_pipelinerun_duration_seconds_bucket[1h])))",
          "legendFormat": "p95",
          "refId": "B"
        }
      ],
      "fieldConfig": {
        "defaults": { "unit": "s" }
      }
    },
    {
      "title": "Change Failure Rate Trend",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 12 },
      "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
      "targets": [
        {
          "expr": "sum(increase(argocd_app_sync_total{phase=\"Error\"}[7d])) / sum(increase(argocd_app_sync_total[7d]))",
          "legendFormat": "CFR (7d rolling)",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": { "unit": "percentunit", "max": 1, "min": 0 }
      }
    },
    {
      "title": "MTTR Trend",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 12 },
      "datasource": { "type": "prometheus", "uid": "${DS_PROMETHEUS}" },
      "targets": [
        {
          "expr": "avg by (name) (avg_over_time((argocd_app_health_status{health_status=\"Degraded\"})[7d:1m])) * 7 * 24 * 3600 / sum by (name) (increase(argocd_app_health_status{health_status=\"Degraded\"}[7d])) / 3600",
          "legendFormat": "{{ name }}",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": { "unit": "h" }
      }
    }
  ],
  "schemaVersion": 39,
  "tags": ["dora", "platform-engineering", "openshift"],
  "templating": {
    "list": [
      {
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "query": "prometheus",
        "current": { "text": "Prometheus", "value": "Prometheus" }
      }
    ]
  },
  "time": { "from": "now-30d", "to": "now" },
  "title": "DORA Metrics — OpenShift Platform",
  "uid": "dora-platform-engineering",
  "version": 1
}
```

---

## PrometheusRule Alerts

Alert when DORA metrics drop below configurable thresholds. Adjust the threshold
values in the `params` annotations to match your team's targets.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dora-metrics-alerts
  namespace: openshift-monitoring
  labels:
    prometheus: k8s
    role: alert-rules
spec:
  groups:
    - name: dora.deployment-frequency
      interval: 1h
      rules:
        - alert: DeploymentFrequencyLow
          expr: |
            sum(increase(argocd_app_sync_total{phase="Succeeded", dest_namespace=~".*prod.*"}[7d])) < 1
          for: 1d
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Deployment frequency below 1/week"
            description: >
              No successful production syncs in the last 7 days.
              Expected at least 1 deploy per week for Medium DORA performance.

    - name: dora.change-failure-rate
      interval: 1h
      rules:
        - alert: ChangeFailureRateHigh
          expr: |
            (
              sum(increase(argocd_app_sync_total{phase="Error"}[30d]))
              /
              sum(increase(argocd_app_sync_total[30d]))
            ) > 0.15
          for: 6h
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Change failure rate exceeds 15%"
            description: >
              Over 15% of syncs in the last 30 days failed.
              This is below the Medium DORA threshold (10-15%).

        - alert: ChangeFailureRateCritical
          expr: |
            (
              sum(increase(argocd_app_sync_total{phase="Error"}[30d]))
              /
              sum(increase(argocd_app_sync_total[30d]))
            ) > 0.45
          for: 6h
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "Change failure rate exceeds 45%"
            description: >
              Over 45% of syncs in the last 30 days failed.
              This is in the Low DORA performance band.

    - name: dora.lead-time
      interval: 1h
      rules:
        - alert: LeadTimeHigh
          expr: |
            histogram_quantile(0.50,
              sum by (le) (
                rate(tekton_pipelines_controller_pipelinerun_duration_seconds_bucket[1h])
              )
            ) > 604800
          for: 1d
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Lead time p50 exceeds 1 week"
            description: >
              The median pipeline duration (proxy for lead time) exceeds 604800 seconds (1 week).
              This is below the Medium DORA threshold.

    - name: dora.mttr
      interval: 1h
      rules:
        - alert: MTTRHigh
          expr: |
            (
              avg(avg_over_time((argocd_app_health_status{health_status="Degraded"})[7d:1m]))
              * 7 * 24 * 3600
              / sum(increase(argocd_app_health_status{health_status="Degraded"}[7d]))
            ) > 86400
          for: 6h
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Mean time to recovery exceeds 1 day"
            description: >
              Average recovery time from Degraded state exceeds 24 hours.
              Target: less than 1 day for High DORA performance.
```

---

## Integrating Tekton Metrics

Tekton Pipelines controller exposes metrics that complement the Argo CD data sources.

### Key Tekton Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `tekton_pipelines_controller_pipelinerun_duration_seconds` | Histogram | End-to-end PipelineRun duration |
| `tekton_pipelines_controller_pipelinerun_count` | Counter | Total PipelineRuns by status |
| `tekton_pipelines_controller_taskrun_duration_seconds` | Histogram | Per-task duration |
| `tekton_pipelines_controller_running_pipelineruns_count` | Gauge | Currently executing PipelineRuns |

### ServiceMonitor for Tekton

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: tekton-pipelines
  namespace: openshift-pipelines
  labels:
    app: tekton-pipelines-controller
spec:
  selector:
    matchLabels:
      app: tekton-pipelines-controller
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

### ServiceMonitor for Argo CD

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: openshift-gitops
  labels:
    app.kubernetes.io/part-of: argocd
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

### Combined Dashboard Queries

Add these panels to the Grafana dashboard above to see Tekton data alongside Argo CD:

```promql
# Pipeline success rate (last 7 days)
sum(tekton_pipelines_controller_pipelinerun_count{status="success"})
/
sum(tekton_pipelines_controller_pipelinerun_count)

# Pipeline duration p95 by pipeline name
histogram_quantile(0.95,
  sum by (le, pipeline) (
    rate(tekton_pipelines_controller_pipelinerun_duration_seconds_bucket[1h])
  )
)

# Pipeline throughput (runs per hour)
sum by (pipeline) (
  rate(tekton_pipelines_controller_pipelinerun_count[1h])
)
```

---

## Prerequisites Checklist

- [ ] Argo CD metrics endpoint scraped by Prometheus (ServiceMonitor or PodMonitor)
- [ ] Tekton Pipelines metrics endpoint scraped (ServiceMonitor above)
- [ ] Grafana deployed with Prometheus data source configured
- [ ] PrometheusRule applied and visible in Prometheus UI under Alerts
- [ ] Production Application names or labels identified for filtering
- [ ] (Optional) Custom lead-time exporter deployed for accurate commit-to-production tracking
