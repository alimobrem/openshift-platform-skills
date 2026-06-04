# Istio / OpenShift Service Mesh (OSSM) Reference

## CRD Reference

| Kind | apiVersion | Purpose |
|------|-----------|---------|
| ServiceMeshControlPlane | maistra.io/v2 | Deploys and configures the Istio control plane (OSSM only) |
| ServiceMeshMemberRoll | maistra.io/v1 | Lists namespaces participating in the mesh (OSSM only) |
| VirtualService | networking.istio.io/v1 | Traffic routing rules (weight, header, cookie matching) |
| DestinationRule | networking.istio.io/v1 | Subsets, circuit breaking, load balancing, connection pool |
| Gateway | networking.istio.io/v1 | Ingress gateway for external traffic into the mesh |
| PeerAuthentication | security.istio.io/v1 | mTLS mode between mesh services |
| AuthorizationPolicy | security.istio.io/v1 | Allow/deny rules for service-to-service access |
| RequestAuthentication | security.istio.io/v1 | JWT token validation at the mesh edge |

## OSSM vs Upstream Istio

| Aspect | OSSM (OpenShift) | Upstream Istio |
|--------|-------------------|---------------|
| Install method | 3 operators via OLM (Elasticsearch, Jaeger, OSSM) | `istioctl install` or Helm |
| Control plane | `ServiceMeshControlPlane` CR | `IstioOperator` CR or CLI flags |
| Namespace enrollment | `ServiceMeshMemberRoll` CR (explicit opt-in) | Label `istio-injection=enabled` (opt-out) |
| Multi-tenancy | Built-in -- each SMCP is scoped to enrolled namespaces | Requires Istio revision labels |
| Sidecar injection | Automatic for SMMR members | Label-based on namespace or pod |
| Observability | Bundled Kiali, Jaeger, Prometheus via SMCP | Separate addons install |

**Key difference:** OSSM uses explicit namespace enrollment via SMMR. A namespace NOT in the
SMMR will never get sidecars injected, regardless of labels.

## Operator Installation (OSSM)

```bash
# 1. Elasticsearch Operator -- required by Jaeger
#    OperatorHub: "OpenShift Elasticsearch Operator" -> openshift-operators-redhat
# 2. Jaeger Operator -- required by OSSM for tracing
#    OperatorHub: "Red Hat OpenShift distributed tracing platform" -> openshift-distributed-tracing
# 3. Service Mesh Operator
#    OperatorHub: "Red Hat OpenShift Service Mesh" -> openshift-operators

# Verify
oc get csv -n openshift-operators | grep -E 'servicemesh|jaeger|elasticsearch'
```

## ServiceMeshControlPlane -- Production Config

```yaml
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: production
  namespace: istio-system
spec:
  version: v2.5                          # Check operator compatibility matrix
  security:
    dataPlane: { mtls: true, automtls: true }
    controlPlane: { mtls: true }
  proxy:
    runtime:
      container:
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits: { cpu: 500m, memory: 256Mi }
    accessLogging:
      file: { name: /dev/stdout, encoding: JSON }
  gateways:
    ingress:
      enabled: true
      runtime:
        deployment: { replicas: 2 }      # HA for ingress gateway
      service: { type: ClusterIP }       # OpenShift Routes handle external traffic
    egress: { enabled: true }
  tracing:
    type: Jaeger
    sampling: 10000                      # 100% = 10000; prod: use 100-1000 (1-10%)
  addons:
    kiali: { enabled: true }
    jaeger:
      install:
        storage:
          type: Elasticsearch            # Production: use Elasticsearch, not Memory
          elasticsearch:
            nodeCount: 3
            storage: { size: 50Gi }
            redundancyPolicy: SingleRedundancy
    prometheus: { enabled: true }
    grafana: { enabled: true }
  techPreview:
    meshConfig:
      defaultConfig:
        holdApplicationUntilProxyStarts: true  # Prevent app start before sidecar ready
```

## ServiceMeshMemberRoll -- Adding Namespaces

```yaml
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default                          # Must be named "default"
  namespace: istio-system                # Same namespace as SMCP
spec:
  members:
    - my-app-dev
    - my-app-staging
    - my-app-prod
```

After adding a namespace, restart pods to get sidecar injection:

```bash
oc rollout restart deployment -n my-app-dev
# Verify: each pod should show istio-proxy container
oc get pods -n my-app-dev -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'
```

## Gateway -- External Traffic Ingress

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: app-gateway
  namespace: my-app-prod
spec:
  selector:
    istio: ingressgateway
  servers:
    - port: { number: 443, name: https, protocol: HTTPS }
      tls:
        mode: SIMPLE
        credentialName: app-tls-cert     # TLS Secret must be in istio-system
      hosts: ["app.example.com"]
    - port: { number: 80, name: http, protocol: HTTP }
      tls: { httpsRedirect: true }
      hosts: ["app.example.com"]
# OpenShift: create a passthrough Route to the ingress gateway
# oc create route passthrough app-gateway --service=istio-ingressgateway \
#   --hostname=app.example.com --port=https -n istio-system
```

## VirtualService -- Traffic Management

### Weight-Based Routing (Canary)

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: my-app
  namespace: my-app-prod
spec:
  hosts:
    - my-app                             # Must match the Kubernetes Service name
  gateways: [app-gateway, mesh]          # External + internal traffic
  http:
    - route:
        - destination:
            host: my-app
            subset: stable
            port: { number: 8080 }
          weight: 90
        - destination:
            host: my-app
            subset: canary
            port: { number: 8080 }
          weight: 10
```

### Header-Based Routing

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: my-app
  namespace: my-app-prod
spec:
  hosts: [my-app]
  http:
    - match:
        - headers:
            x-canary:
              exact: "true"              # Route canary header to canary subset
      route:
        - destination: { host: my-app, subset: canary }
    - route:                             # Default: stable
        - destination: { host: my-app, subset: stable }
```

### Cookie-Based Routing

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: my-app
  namespace: my-app-prod
spec:
  hosts: [my-app]
  http:
    - match:
        - headers:
            cookie:
              regex: ".*canary=true.*"   # Cookie matching uses header regex
      route:
        - destination: { host: my-app, subset: canary }
    - route:
        - destination: { host: my-app, subset: stable }
```

## DestinationRule -- Subsets, Circuit Breaking, Resilience

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: my-app
  namespace: my-app-prod
spec:
  host: my-app                           # Must match VirtualService destination host
  trafficPolicy:
    connectionPool:
      tcp: { maxConnections: 100, connectTimeout: 5s }
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 100
        maxRequestsPerConnection: 10
        maxRetries: 3
    outlierDetection:
      consecutive5xxErrors: 5            # Eject after 5 consecutive 5xx
      interval: 30s
      baseEjectionTime: 30s             # Doubles each eviction
      maxEjectionPercent: 50
    loadBalancer:
      simple: ROUND_ROBIN               # ROUND_ROBIN | LEAST_REQUEST | RANDOM
  subsets:
    - name: stable
      labels: { version: stable }        # Must match pod labels
    - name: canary
      labels: { version: canary }
```

Retries and timeouts are set on VirtualService `http[]` entries:

```yaml
timeout: 10s                             # Overall request timeout
retries:
  attempts: 3
  perTryTimeout: 3s
  retryOn: "5xx,reset,connect-failure,retriable-4xx"
```

## Security -- mTLS

### PeerAuthentication -- Strict mTLS

```yaml
# Mesh-wide strict mTLS
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system                # Mesh-wide when in control plane namespace
spec:
  mtls:
    mode: STRICT                         # STRICT | PERMISSIVE | DISABLE
---
# Per-workload port exception (e.g., health check)
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: health-check-exception
  namespace: my-app-prod
spec:
  selector:
    matchLabels: { app: my-app }
  mtls:
    mode: STRICT
  portLevelMtls:
    8081:
      mode: PERMISSIVE                   # Allow plain HTTP on health check port
```

### AuthorizationPolicy -- Allow/Deny Rules

```yaml
# Deny-all baseline
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: my-app-prod
spec: {}                                 # Empty spec = deny all traffic
---
# Allow from ingress gateway + same namespace
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-from-api-gateway
  namespace: my-app-prod
spec:
  selector:
    matchLabels: { app: my-app }
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account"]
        - source:
            namespaces: [my-app-prod]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/*"]
            ports: ["8080"]
```

### RequestAuthentication -- JWT Validation

```yaml
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: jwt-auth
  namespace: my-app-prod
spec:
  selector:
    matchLabels: { app: my-app }
  jwtRules:
    - issuer: "https://auth.example.com"
      jwksUri: "https://auth.example.com/.well-known/jwks.json"
      audiences: ["my-app"]
      forwardOriginalToken: true
---
# Require valid JWT (combine with RequestAuthentication above)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: require-jwt
  namespace: my-app-prod
spec:
  selector:
    matchLabels: { app: my-app }
  action: ALLOW
  rules:
    - from:
        - source:
            requestPrincipals: ["*"]     # Any valid JWT
      when:
        - key: request.auth.claims[iss]
          values: ["https://auth.example.com"]
```

## Observability

### Kiali and Jaeger Access

```bash
# Kiali dashboard (enabled via SMCP addons.kiali.enabled)
oc get route kiali -n istio-system -o jsonpath='{.spec.host}'

# Jaeger tracing UI
oc get route jaeger -n istio-system -o jsonpath='{.spec.host}'

# Vanilla K8s: kubectl port-forward svc/kiali -n istio-system 20001:20001
```

### Prometheus Mesh Metrics

```promql
# Request rate by service
sum(rate(istio_requests_total{reporter="destination",
  destination_service_namespace="my-app-prod"}[5m])) by (destination_service_name, response_code)

# 5xx error rate
sum(rate(istio_requests_total{reporter="destination",
  destination_service_namespace="my-app-prod", response_code=~"5.."}[5m]))
/ sum(rate(istio_requests_total{reporter="destination",
  destination_service_namespace="my-app-prod"}[5m]))

# P99 latency
histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{
  reporter="destination", destination_service_namespace="my-app-prod"}[5m]))
  by (destination_service_name, le))

# Canary vs stable split (useful during rollouts)
sum(rate(istio_requests_total{reporter="destination",
  destination_service_namespace="my-app-prod"}[5m])) by (destination_workload, response_code)
```

## Argo Rollouts + Istio Integration

Requires 4 resources: Rollout, VirtualService, DestinationRule, and two Services (stable + canary).

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
  namespace: my-app-prod
spec:
  replicas: 5
  selector:
    matchLabels: { app: my-app }
  template:
    metadata:
      labels: { app: my-app }
      annotations: { sidecar.istio.io/inject: "true" }
    spec:
      containers:
        - name: my-app
          image: quay.io/myorg/my-app:v2.0.0
          ports: [{ containerPort: 8080 }]
  strategy:
    canary:
      canaryService: my-app-canary       # Service selecting canary pods
      stableService: my-app-stable       # Service selecting stable pods
      trafficRouting:
        istio:
          virtualServices:
            - name: my-app
              routes: [primary]          # Must match VirtualService http[].name
          destinationRule:
            name: my-app
            canarySubsetName: canary
            stableSubsetName: stable
      steps:
        - setWeight: 5
        - pause: { duration: 2m }
        - setWeight: 20
        - pause: { duration: 5m }
        - setWeight: 50
        - pause: { duration: 5m }
        - setWeight: 80
        - pause: { duration: 2m }
      analysis:
        templates: [{ templateName: istio-success-rate }]
        startingStep: 2                  # Start analysis at 20%
        args:
          - name: service-name
            value: my-app-canary.my-app-prod.svc.cluster.local
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: my-app
  namespace: my-app-prod
spec:
  hosts: [my-app]
  gateways: [mesh]
  http:
    - name: primary                      # Referenced by Rollout
      route:
        - destination: { host: my-app-stable, subset: stable }
          weight: 100                    # Managed by Rollouts controller
        - destination: { host: my-app-canary, subset: canary }
          weight: 0
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: my-app
  namespace: my-app-prod
spec:
  host: my-app
  subsets:
    - name: stable
      labels: { app: my-app }
    - name: canary
      labels: { app: my-app }
---
apiVersion: v1
kind: Service
metadata: { name: my-app-stable, namespace: my-app-prod }
spec:
  selector: { app: my-app }
  ports: [{ port: 8080, targetPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: my-app-canary, namespace: my-app-prod }
spec:
  selector: { app: my-app }
  ports: [{ port: 8080, targetPort: 8080 }]
---
# AnalysisTemplate: abort rollout if canary success rate < 95%
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: istio-success-rate
  namespace: my-app-prod
spec:
  args: [{ name: service-name }]
  metrics:
    - name: success-rate
      interval: 60s
      failureLimit: 3
      successCondition: "result[0] > 0.95"
      provider:
        prometheus:
          address: http://prometheus.istio-system:9090
          query: |
            sum(rate(istio_requests_total{reporter="destination",
              destination_service=~"{{args.service-name}}",
              response_code!~"5.*"}[5m]))
            / sum(rate(istio_requests_total{reporter="destination",
              destination_service=~"{{args.service-name}}"}[5m]))
```

**Flow:** Rollouts creates canary ReplicaSet -> patches VirtualService weights per step ->
AnalysisTemplate queries Prometheus -> abort + rollback if success rate < 95%.

## Common Mistakes

| # | Mistake | Symptom | Fix |
|---|---------|---------|-----|
| 1 | Namespace not in SMMR | No sidecar, Kiali shows no graph | Add to SMMR members, `oc rollout restart deployment -n <ns>` |
| 2 | mTLS mode mismatch | `connection reset by peer` | Ensure both sides have sidecars + matching PeerAuthentication mode |
| 3 | VirtualService host mismatch | 404, traffic goes nowhere | `hosts` must match Kubernetes Service name exactly |
| 4 | DestinationRule subset label mismatch | 503, NR in Kiali | Subset labels must match actual pod labels |
| 5 | Gateway TLS secret missing | TLS handshake error on 443 | `credentialName` secret must exist in `istio-system` namespace |
| 6 | Rollout route name mismatch | `VirtualService does not contain route` | Rollout `routes: [primary]` must match VS `http[].name: primary` |
| 7 | Pods deployed before SMMR update | No sidecar on existing pods | `oc rollout restart deployment -n <ns>` after SMMR change |

## Debug Commands

```bash
# Control plane health
oc get smcp -n istio-system && oc get pods -n istio-system

# Sidecar status
oc get pods -n <ns> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}'

# Proxy config (routes, clusters, listeners, endpoints)
istioctl proxy-config routes <pod>.<ns>
istioctl proxy-config clusters <pod>.<ns>

# Analyze mesh config for errors
istioctl analyze -n <ns>

# Proxy logs
kubectl logs <pod> -n <ns> -c istio-proxy --tail=100

# Validate VirtualService/DestinationRule
oc get vs,dr -n <ns> -o yaml | istioctl validate -f -
```
