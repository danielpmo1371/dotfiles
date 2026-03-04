#!/usr/bin/env bash
#
# Pipeline Guard — PreToolUse Hook
#
# Intercepts mcp__azure-devops__pipelines_run_pipeline calls.
# Reads tool input from stdin JSON, validates against hard rules.
# Exit 0 = allow, exit 2 = block (with reason on stderr).
#
# SAFETY: Second line of defense. Even if the validator script is bypassed,
# this hook catches direct MCP calls.
#
# LOGGING: Comprehensive audit trail for every pipeline trigger attempt.

set -euo pipefail

# ============================================================================
# HARD-CODED SAFETY RULES — MIRRORS pipeline-validator.sh
# ============================================================================
BLOCKED_STAGE_PATTERNS=("pre" "prd" "prod" "production")
TERRAFORM_PIPELINE_ID="802"
TERRAFORM_APPLY_STAGE="apply_travellerdirectives"
# ============================================================================

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pipeline-triggers.jsonl"
DETAIL_LOG="$LOG_DIR/pipeline-guard-detail.log"

INPUT=$(cat)

# Extract tool name and input from hook payload
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}')

# Only process pipeline run calls
if [[ "$TOOL_NAME" != *"pipelines_run_pipeline"* ]]; then
  exit 0
fi

# Parse the MCP tool input
PIPELINE_ID=$(echo "$TOOL_INPUT" | jq -r '.pipelineId // empty' 2>/dev/null)
PROJECT=$(echo "$TOOL_INPUT" | jq -r '.project // empty' 2>/dev/null)
BRANCH=$(echo "$TOOL_INPUT" | jq -r '.resources.repositories.self.refName // "unknown"' 2>/dev/null)
STAGES_TO_SKIP_JSON=$(echo "$TOOL_INPUT" | jq -c '.stagesToSkip // []' 2>/dev/null)
STAGES_TO_SKIP_LIST=$(echo "$TOOL_INPUT" | jq -r '.stagesToSkip // [] | join(", ")' 2>/dev/null)
TEMPLATE_PARAMS_JSON=$(echo "$TOOL_INPUT" | jq -c '.templateParameters // {}' 2>/dev/null)
TEMPLATE_PARAMS=$(echo "$TOOL_INPUT" | jq -r '.templateParameters // {} | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || true)
VARIABLES=$(echo "$TOOL_INPUT" | jq -r '.variables // {} | to_entries[] | "\(.key)=\(.value.value // .value)"' 2>/dev/null || true)
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# ============================================================================
# Detailed logging — always log full context BEFORE any decision
# ============================================================================
log_detail() {
  echo "[$TIMESTAMP] $1" >> "$DETAIL_LOG"
}

log_audit() {
  local action="$1"
  local reason="${2:-}"
  jq -n \
    --arg ts "$TIMESTAMP" \
    --arg pid "$PIPELINE_ID" \
    --arg proj "$PROJECT" \
    --arg branch "$BRANCH" \
    --arg action "$action" \
    --arg reason "$reason" \
    --argjson stagesToSkip "$STAGES_TO_SKIP_JSON" \
    --argjson templateParameters "$TEMPLATE_PARAMS_JSON" \
    '{
      timestamp: $ts,
      pipelineId: $pid,
      project: $proj,
      branch: $branch,
      action: $action,
      reason: $reason,
      stagesToSkip: $stagesToSkip,
      templateParameters: $templateParameters
    }' >> "$LOG_FILE"
}

# Log the full raw tool input for forensics
log_detail "=== PIPELINE TRIGGER ATTEMPT ==="
log_detail "Pipeline ID: $PIPELINE_ID"
log_detail "Project: $PROJECT"
log_detail "Branch: $BRANCH"
log_detail "stagesToSkip: $STAGES_TO_SKIP_LIST"
log_detail "templateParameters: $TEMPLATE_PARAMS_JSON"
log_detail "Full tool_input: $TOOL_INPUT"

# ============================================================================
# Registry lookup — find pipeline-registry.json from CWD
# ============================================================================
find_registry() {
  local dir="${PWD}"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.claude/pipeline-registry.json" ]]; then
      echo "$dir/.claude/pipeline-registry.json"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

REGISTRY_FILE=""
REGISTRY_FILE=$(find_registry) || true

# ============================================================================
# Check 0: Block unregistered pipelines
# ============================================================================
if [[ -n "$REGISTRY_FILE" && -n "$PIPELINE_ID" ]]; then
  # Search all services for a matching ci.id, cd.id, terraform.id, or test.id
  MATCHED_SERVICE=$(jq -r --arg pid "$PIPELINE_ID" '
    .services | to_entries[] |
    select(
      (.value.ci.id // -1 | tostring) == $pid or
      (.value.cd.id // -1 | tostring) == $pid or
      (.value.terraform.id // -1 | tostring) == $pid or
      (.value.test.id // -1 | tostring) == $pid
    ) | .key
  ' "$REGISTRY_FILE" 2>/dev/null || true)

  if [[ -z "$MATCHED_SERVICE" ]]; then
    log_detail "BLOCKED: Pipeline $PIPELINE_ID not found in registry"
    log_audit "blocked" "Pipeline $PIPELINE_ID not found in registry. Unregistered pipelines cannot be triggered."
    echo "BLOCKED by pipeline-guard hook: Pipeline $PIPELINE_ID not found in registry. Unregistered pipelines cannot be triggered." >&2
    exit 2
  fi

  log_detail "Registry match: pipeline $PIPELINE_ID belongs to service '$MATCHED_SERVICE'"

  # Determine if this is a CD pipeline
  IS_CD=$(jq -r --arg pid "$PIPELINE_ID" --arg svc "$MATCHED_SERVICE" '
    (.services[$svc].cd.id // empty | tostring) == $pid
  ' "$REGISTRY_FILE" 2>/dev/null || echo "false")

  # ==========================================================================
  # Check 1: CD pipeline must have stagesToSkip
  # ==========================================================================
  if [[ "$IS_CD" == "true" ]]; then
    STAGES_COUNT=$(echo "$STAGES_TO_SKIP_JSON" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$STAGES_COUNT" == "0" ]]; then
      log_detail "BLOCKED: CD pipeline $PIPELINE_ID has empty stagesToSkip — all stages would run"
      log_audit "blocked" "CD pipeline $PIPELINE_ID requires stagesToSkip. All stages run when empty."
      echo "BLOCKED by pipeline-guard hook: CD pipeline $PIPELINE_ID requires stagesToSkip. All stages run when empty." >&2
      exit 2
    fi

    log_detail "PASS: CD pipeline has $STAGES_COUNT stages to skip"

    # ========================================================================
    # Check 2: Blocked stages must be in stagesToSkip
    # ========================================================================
    BLOCKED_STAGES=$(jq -r --arg svc "$MATCHED_SERVICE" '
      .services[$svc].stages.blocked // [] | .[]
    ' "$REGISTRY_FILE" 2>/dev/null || true)

    for blocked_stage in $BLOCKED_STAGES; do
      HAS_STAGE=$(echo "$STAGES_TO_SKIP_JSON" | jq -r --arg s "$blocked_stage" '[.[] | select(. == $s)] | length' 2>/dev/null || echo "0")
      if [[ "$HAS_STAGE" == "0" ]]; then
        log_detail "BLOCKED: Blocked stage '$blocked_stage' is not in stagesToSkip"
        log_audit "blocked" "Blocked stage '$blocked_stage' is not in stagesToSkip. PRE/PRD stages must always be skipped."
        echo "BLOCKED by pipeline-guard hook: Blocked stage '$blocked_stage' is not in stagesToSkip. PRE/PRD stages must always be skipped." >&2
        exit 2
      fi
    done

    log_detail "PASS: All blocked stages are in stagesToSkip"
  else
    log_detail "Pipeline $PIPELINE_ID is not a CD pipeline — skipping stage checks"
  fi
elif [[ -z "$REGISTRY_FILE" ]]; then
  log_detail "WARNING: No pipeline-registry.json found — registry checks skipped"
fi

# ============================================================================
# Check 3: Blocked environments in parameters
# ============================================================================
ALL_PARAMS="$TEMPLATE_PARAMS $VARIABLES"
ALL_PARAMS_LOWER=$(echo "$ALL_PARAMS" | tr '[:upper:]' '[:lower:]')

for pattern in "${BLOCKED_STAGE_PATTERNS[@]}"; do
  if echo "$ALL_PARAMS_LOWER" | grep -qiE "(environment|env|stage|deploy).*=.*${pattern}"; then
    log_detail "BLOCKED: Parameter references blocked environment '${pattern}'"
    log_audit "blocked" "Parameter references blocked environment '${pattern}'"
    echo "BLOCKED by pipeline-guard hook: Parameter references blocked environment '${pattern}'. PRE/PRD deployments are NEVER allowed via AI." >&2
    exit 2
  fi
done

# ============================================================================
# Check 4: Terraform pipeline MUST skip apply stage
# ============================================================================
if [[ "$PIPELINE_ID" == "$TERRAFORM_PIPELINE_ID" ]]; then
  log_detail "Terraform pipeline detected (ID=$TERRAFORM_PIPELINE_ID) — enforcing apply skip"

  # Check if stagesToSkip contains the apply stage
  HAS_APPLY_SKIP=$(echo "$TOOL_INPUT" | jq -r --arg stage "$TERRAFORM_APPLY_STAGE" \
    '[.stagesToSkip // [] | .[] | select(. == $stage)] | length' 2>/dev/null)

  if [[ "$HAS_APPLY_SKIP" != "1" ]]; then
    log_detail "BLOCKED: Terraform pipeline missing '$TERRAFORM_APPLY_STAGE' in stagesToSkip!"
    log_detail "stagesToSkip was: $STAGES_TO_SKIP_JSON"
    log_audit "blocked" "CRITICAL: Terraform pipeline 802 triggered WITHOUT '$TERRAFORM_APPLY_STAGE' in stagesToSkip. stagesToSkip=$STAGES_TO_SKIP_JSON"
    echo "BLOCKED by pipeline-guard hook: Terraform pipeline 802 MUST include '$TERRAFORM_APPLY_STAGE' in stagesToSkip. The apply stage is NEVER allowed. Got stagesToSkip=$STAGES_TO_SKIP_JSON" >&2
    exit 2
  fi

  log_detail "PASS: apply stage is in stagesToSkip"

  # Also verify requireManualApproval is True
  MANUAL_APPROVAL=$(echo "$TOOL_INPUT" | jq -r '.templateParameters.requireManualApproval // "unset"' 2>/dev/null)
  if [[ "$MANUAL_APPROVAL" != "True" && "$MANUAL_APPROVAL" != "true" ]]; then
    log_detail "BLOCKED: requireManualApproval is '$MANUAL_APPROVAL' (must be True)"
    log_audit "blocked" "Terraform pipeline requireManualApproval='$MANUAL_APPROVAL' (must be True)"
    echo "BLOCKED by pipeline-guard hook: Terraform pipeline 802 MUST have requireManualApproval=True. Got '$MANUAL_APPROVAL'" >&2
    exit 2
  fi

  log_detail "PASS: requireManualApproval=True"
fi

# ============================================================================
# All checks passed — allow and log
# ============================================================================
log_detail "ALLOWED: All safety checks passed"
log_audit "allowed" "All safety checks passed"
exit 0
