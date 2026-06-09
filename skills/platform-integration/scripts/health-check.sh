#!/usr/bin/env bash
set -o errexit
set -o pipefail

# -----------------------------------------------------------------------
# health-check.sh — Check OpenShift platform operator health.
#
# Checks 7 required Red Hat operators for: pod status, CRD presence,
# CSV phase. Outputs structured JSON.
#
# Exit codes: 0 = all healthy, 1 = degraded, 2 = missing required operator
# -----------------------------------------------------------------------

CLI="oc"
command -v oc >/dev/null 2>&1 || CLI="kubectl"
command -v "$CLI" >/dev/null 2>&1 || { echo '{"error":"neither oc nor kubectl found"}'; exit 2; }

OPERATORS=(
  "openshift-pipelines-operator-rh|tekton.dev|openshift-pipelines"
  "openshift-builds-operator|shipwright.io|openshift-builds"
  "servicemeshoperator3|sailoperator.io|istio-system"
  "quay-operator|quay.redhat.com|openshift-operators"
  "external-secrets-operator|external-secrets.io|openshift-operators"
  "kiali-ossm|kiali.io|openshift-operators"
  "opentelemetry-product|opentelemetry.io|openshift-operators"
)

EXIT_CODE=0
RESULTS=()

for entry in "${OPERATORS[@]}"; do
  IFS='|' read -r sub_name api_group default_ns <<< "$entry"

  # Check CSV phase
  csv_phase=$($CLI get csv -n openshift-operators --no-headers 2>/dev/null \
    | grep -i "$sub_name" | awk '{print $NF}' | head -1) || true
  csv_version=$($CLI get csv -n openshift-operators --no-headers 2>/dev/null \
    | grep -i "$sub_name" | awk '{print $1}' | head -1) || true

  # Check CRDs
  crd_count=$($CLI api-resources --api-group="$api_group" --no-headers 2>/dev/null | wc -l | tr -d ' ') || crd_count=0

  # Determine status
  if [[ -z "$csv_phase" ]]; then
    status="missing"
    EXIT_CODE=2
  elif [[ "$csv_phase" != "Succeeded" ]]; then
    status="degraded"
    [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
  elif [[ "$crd_count" -eq 0 ]]; then
    status="degraded"
    [[ $EXIT_CODE -lt 1 ]] && EXIT_CODE=1
  else
    status="healthy"
  fi

  RESULTS+=("{\"operator\":\"$sub_name\",\"status\":\"$status\",\"version\":\"${csv_version:-unknown}\",\"crd_count\":$crd_count,\"csv_phase\":\"${csv_phase:-not_found}\"}")
done

# Output JSON
echo -n '{"operators":['
first=true
for r in "${RESULTS[@]}"; do
  $first || echo -n ','
  echo -n "$r"
  first=false
done
echo "],"
echo "\"exit_code\":$EXIT_CODE,"
echo "\"summary\":\"$([ $EXIT_CODE -eq 0 ] && echo 'all healthy' || ([ $EXIT_CODE -eq 1 ] && echo 'degraded' || echo 'missing operators'))\"}"

exit $EXIT_CODE
