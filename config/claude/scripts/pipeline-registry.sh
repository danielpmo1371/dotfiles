#!/usr/bin/env bash
#
# Pipeline Registry Helper
#
# Detects service from CWD and resolves pipeline info from project-level registry.
#
# Usage: pipeline-registry.sh [service-name]
#   If service-name not provided, auto-detects from CWD.
#
# Output: JSON with service info (pipeline IDs, project, stages)
# Exit: 0=found, 1=not found, 2=error

set -euo pipefail

SERVICE_OVERRIDE="${1:-}"
CWD="${PWD}"

# Find the pipeline registry — walk up from CWD to find .claude/pipeline-registry.json
find_registry() {
  local dir="$CWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.claude/pipeline-registry.json" ]]; then
      echo "$dir/.claude/pipeline-registry.json"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# Detect service from CWD folder name
detect_service() {
  local dir="$CWD"
  local basename
  basename=$(basename "$dir")

  # Check if current folder matches a service
  local registry="$1"
  if jq -e --arg svc "$basename" '.services[$svc]' "$registry" > /dev/null 2>&1; then
    echo "$basename"
    return 0
  fi

  # Check if we're inside a service subfolder (e.g., td-api/src/)
  while [[ "$dir" != "/" ]]; do
    basename=$(basename "$dir")
    if jq -e --arg svc "$basename" '.services[$svc]' "$registry" > /dev/null 2>&1; then
      echo "$basename"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  return 1
}

# Find registry
REGISTRY=$(find_registry) || {
  jq -n '{"error": "No pipeline-registry.json found in parent directories", "cwd": $ENV.PWD}'
  exit 2
}

# Resolve service
if [[ -n "$SERVICE_OVERRIDE" ]]; then
  SERVICE="$SERVICE_OVERRIDE"
else
  SERVICE=$(detect_service "$REGISTRY") || {
    jq -n --arg cwd "$CWD" \
      '{"error": "Could not detect service from current directory", "cwd": $cwd, "hint": "Run from a service folder (e.g., td-api/) or pass service name as argument"}'
    exit 1
  }
fi

# Extract service info
SERVICE_INFO=$(jq --arg svc "$SERVICE" '.services[$svc] // empty' "$REGISTRY")
if [[ -z "$SERVICE_INFO" || "$SERVICE_INFO" == "null" ]]; then
  AVAILABLE=$(jq -r '.services | keys | join(", ")' "$REGISTRY")
  jq -n --arg svc "$SERVICE" --arg available "$AVAILABLE" \
    '{"error": "Unknown service", "service": $svc, "available": $available}'
  exit 1
fi

# Add organization and detected service name to output
ORG=$(jq -r '.organization' "$REGISTRY")
echo "$SERVICE_INFO" | jq --arg svc "$SERVICE" --arg org "$ORG" '. + {"service": $svc, "organization": $org}'
exit 0
