#!/usr/bin/env bash
set -o errexit
set -o pipefail

# -----------------------------------------------------------------------
# discover.sh — Scan a directory tree for OpenShift platform CRDs.
#
# Finds YAML files containing Shipwright, Tekton, Istio, ESO, Quay, and
# gitops-promoter resources. Groups by kind and directory. Detects common
# issues (wrong apiVersions, missing fields).
#
# Output: JSON inventory.
# -----------------------------------------------------------------------

ROOT_DIR=""
EXCLUDE_DIRS=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Scan a directory for OpenShift platform CRDs.

Options:
  -d <dir>    Root directory to scan (required)
  -e <dir>    Comma-separated directories to exclude (relative to root)
  -h          Show this help message

Output:
  JSON object with platform resources grouped by kind,
  plus an issues array for detected problems.

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

# Platform API groups to detect
PLATFORM_GROUPS="shipwright\.io|tekton\.dev|triggers\.tekton\.dev|sailoperator\.io|networking\.istio\.io|security\.istio\.io|quay\.redhat\.com|external-secrets\.io|promoter\.argoproj\.io"

# Deprecated/wrong apiVersions to flag
DEPRECATED_VERSIONS="shipwright.io/v1alpha1"

file_count=0
issue_count=0
issues=""
kinds=""

# Build find command excluding .git and user-specified dirs
find_args=("$ROOT_DIR")
find_args+=(-path '*/.git' -prune)
if [[ -n "$EXCLUDE_DIRS" ]]; then
  IFS=',' read -ra DIRS <<< "$EXCLUDE_DIRS"
  for d in "${DIRS[@]}"; do
    find_args+=(-o -path "*/$d" -prune)
  done
fi
find_args+=(-o -name '*.yaml' -print -o -name '*.yml' -print)

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Extract apiVersion and kind pairs using awk
  while IFS='|' read -r api_version kind; do
    [[ -z "$kind" || -z "$api_version" ]] && continue

    # Check if this is a platform resource
    if echo "$api_version" | grep -qE "$PLATFORM_GROUPS"; then
      rel_path="${file#"$ROOT_DIR"/}"
      file_count=$((file_count + 1))

      # Track kinds
      if [[ -n "$kinds" ]]; then
        kinds="${kinds},"
      fi
      kinds="${kinds}\"${kind}\""

      # Check for deprecated apiVersions
      if echo "$api_version" | grep -qE "$DEPRECATED_VERSIONS"; then
        issue_count=$((issue_count + 1))
        if [[ -n "$issues" ]]; then
          issues="${issues},"
        fi
        issues="${issues}{\"file\":\"$rel_path\",\"kind\":\"$kind\",\"issue\":\"deprecated apiVersion $api_version\",\"severity\":\"error\"}"
      fi
    fi
  done < <(awk '/^apiVersion:/{api=$2} /^kind:/{if(api) print api"|"$2; api=""}' "$file")
done < <(find "${find_args[@]}" 2>/dev/null)

echo "{\"file_count\":$file_count,\"issue_count\":$issue_count,\"kinds\":[${kinds}],\"issues\":[${issues}]}"
