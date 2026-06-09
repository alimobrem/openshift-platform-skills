#!/usr/bin/env bash
set -o errexit
set -o pipefail

# -----------------------------------------------------------------------
# validate.sh — Validate YAML syntax and schemas for platform CRDs.
#
# Prerequisites: yq >= 4.50, kubeconform >= 0.7
# -----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_SCHEMAS_DIR="$SKILL_DIR/assets/schemas"
ROOT_DIR=""
EXCLUDE_DIRS=""
ERROR_COUNT=0
WARN_COUNT=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Validate YAML files containing platform CRDs.

Options:
  -d <dir>    Root directory to validate (required)
  -e <dir>    Comma-separated directories to exclude (relative to root)
  -h          Show this help message

Validation passes:
  1. YAML syntax check (yq)
  2. Schema validation against platform CRD schemas (kubeconform)

Prerequisites:
  yq          >= 4.50    https://github.com/mikefarah/yq
  kubeconform >= 0.7     https://github.com/yannh/kubeconform

Example:
  $(basename "$0") -d /path/to/repo
  $(basename "$0") -d . -e vendor,tmp
EOF
  exit 0
}

while getopts ":d:e:h" opt; do
  case $opt in
    d) ROOT_DIR="$OPTARG" ;;
    e) EXCLUDE_DIRS="$OPTARG" ;;
    h) usage ;;
    \?) echo "Error: Unknown option -$OPTARG" >&2; exit 1 ;;
    :) echo "Error: Option -$OPTARG requires an argument" >&2; exit 1 ;;
  esac
done

if [[ -z "$ROOT_DIR" ]]; then
  echo "Error: -d <dir> is required" >&2
  exit 1
fi

if [[ ! -d "$ROOT_DIR" ]]; then
  echo "Error: '$ROOT_DIR' is not a directory" >&2
  exit 1
fi

# Check prerequisites
HAS_YQ=false
HAS_KUBECONFORM=false
command -v yq >/dev/null 2>&1 && HAS_YQ=true
command -v kubeconform >/dev/null 2>&1 && HAS_KUBECONFORM=true

if ! $HAS_YQ && ! $HAS_KUBECONFORM; then
  echo '{"error":"neither yq nor kubeconform found — install at least one","results":[]}'
  exit 1
fi

# Build find command
find_args=("$ROOT_DIR")
find_args+=(-path '*/.git' -prune)
if [[ -n "$EXCLUDE_DIRS" ]]; then
  IFS=',' read -ra DIRS <<< "$EXCLUDE_DIRS"
  for d in "${DIRS[@]}"; do
    find_args+=(-o -path "*/$d" -prune)
  done
fi
find_args+=(-o \( -name '*.yaml' -o -name '*.yml' \) -print)

RESULTS=""
first=true

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  rel_path="${file#"$ROOT_DIR"/}"
  valid=true
  errors=""

  # Pass 1: YAML syntax
  if $HAS_YQ; then
    if ! yq_err=$(yq eval '.' "$file" 2>&1 >/dev/null); then
      valid=false
      errors="YAML syntax error"
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
  fi

  # Pass 2: Schema validation (only if syntax passed and schemas exist)
  if $valid && $HAS_KUBECONFORM && [[ -d "$ASSETS_SCHEMAS_DIR" ]] && ls "$ASSETS_SCHEMAS_DIR"/*.json >/dev/null 2>&1; then
    kc_output=$(kubeconform -schema-location "$ASSETS_SCHEMAS_DIR/{{ .ResourceKind | lower }}-{{ .Group }}-{{ .ResourceAPIVersion }}.json" \
         -schema-location 'default' -strict -output json "$file" 2>/dev/null) || true
    if echo "$kc_output" | grep -q '"status":"statusError"\|"status":"statusInvalid"'; then
      valid=false
      errors="Schema validation failed"
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
  fi

  $first || RESULTS="${RESULTS},"
  RESULTS="${RESULTS}{\"file\":\"$rel_path\",\"valid\":$valid,\"errors\":\"$errors\"}"
  first=false

done < <(find "${find_args[@]}" 2>/dev/null)

echo "{\"error_count\":$ERROR_COUNT,\"warn_count\":$WARN_COUNT,\"results\":[${RESULTS}]}"

[[ $ERROR_COUNT -eq 0 ]] && exit 0 || exit 1
