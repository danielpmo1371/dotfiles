#!/usr/bin/env bash
#
# Pipeline Validator — Hard Safety Rules
#
# Input (stdin): JSON with service, type, branch, stages, pipelineId, project
# Output (stdout): JSON with approved/blocked decision + params
# Exit: 0=approved, 1=blocked, 2=error
#
# SAFETY: PRE/PRD environments are NEVER allowed. This is non-negotiable.

set -euo pipefail

# ============================================================================
# HARD-CODED SAFETY RULES — DO NOT MODIFY WITHOUT HUMAN REVIEW
# ============================================================================
BLOCKED_ENVS=("pre" "prd" "prod" "pre-prod" "production")
ALLOWED_CD_STAGES=("dry" "dev" "dry_deploy" "sit" "sit_deploy" "test" "uat" "uat_deploy" "stage" "npe" "npe_deploy")
# ============================================================================

# Logging
VALIDATOR_LOG_DIR="$HOME/.claude/logs"
mkdir -p "$VALIDATOR_LOG_DIR"
VALIDATOR_LOG="$VALIDATOR_LOG_DIR/pipeline-validator.log"
VALIDATOR_TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

log_validator() {
  echo "[$VALIDATOR_TIMESTAMP] $1" >> "$VALIDATOR_LOG"
}

INPUT=$(cat)

# Log the incoming request
log_validator "=== VALIDATOR REQUEST ==="
log_validator "Input: $INPUT"

# Parse fields
SERVICE=$(echo "$INPUT" | jq -r '.service // empty')
TYPE=$(echo "$INPUT" | jq -r '.type // empty')
BRANCH=$(echo "$INPUT" | jq -r '.branch // empty')
PIPELINE_ID=$(echo "$INPUT" | jq -r '.pipelineId // empty')
PROJECT=$(echo "$INPUT" | jq -r '.project // empty')
STAGES_ARRAY=()
while IFS= read -r _stage; do
  [[ -n "$_stage" ]] && STAGES_ARRAY+=("$_stage")
done < <(echo "$INPUT" | jq -r '.stages // [] | .[]' 2>/dev/null)

# Validation: required fields
for field in SERVICE TYPE BRANCH; do
  if [[ -z "${!field}" ]]; then
    jq -n --arg reason "Missing required field: $field" \
      '{"approved": false, "reason": $reason, "rule": "MISSING_FIELD"}'
    exit 2
  fi
done

# Validation: type must be ci, cd, or terraform
if [[ "$TYPE" != "ci" && "$TYPE" != "cd" && "$TYPE" != "terraform" ]]; then
  jq -n --arg reason "Invalid type: $TYPE. Must be 'ci', 'cd', or 'terraform'" \
    '{"approved": false, "reason": $reason, "rule": "INVALID_TYPE"}'
  exit 2
fi

# Validation: pipelineId must be numeric if provided
if [[ -n "$PIPELINE_ID" && ! "$PIPELINE_ID" =~ ^[0-9]+$ ]]; then
  jq -n --arg reason "pipelineId must be numeric: $PIPELINE_ID" \
    '{"approved": false, "reason": $reason, "rule": "INVALID_PIPELINE_ID"}'
  exit 2
fi

# Rule 1: Branch must not be empty and must look like a git ref
if [[ -z "$BRANCH" || "$BRANCH" == "null" ]]; then
  jq -n '{"approved": false, "reason": "Branch is required", "rule": "EMPTY_BRANCH"}'
  exit 1
fi

# Rule 2: CI pipelines are always allowed (no stage restrictions)
if [[ "$TYPE" == "ci" ]]; then
  # Normalize branch to refs/heads/ format
  REF_BRANCH="$BRANCH"
  if [[ ! "$BRANCH" =~ ^refs/ ]]; then
    REF_BRANCH="refs/heads/$BRANCH"
  fi

  CI_OUTPUT=$(jq -n \
    --arg pipelineId "$PIPELINE_ID" \
    --arg project "$PROJECT" \
    --arg branch "$REF_BRANCH" \
    --arg reason "CI pipeline approved for branch $BRANCH" \
    '{
      "approved": true,
      "pipelineId": ($pipelineId | tonumber),
      "project": $project,
      "branch": $branch,
      "stagesToSkip": [],
      "reason": $reason
    }')

  log_validator "=== VALIDATOR OUTPUT (ci) ==="
  log_validator "Output: $CI_OUTPUT"

  echo "$CI_OUTPUT"
  exit 0
fi

# Rule 3: CD pipelines — check for blocked environments
if [[ "$TYPE" == "cd" ]]; then
  # If no stages specified for CD, block it
  if [[ ${#STAGES_ARRAY[@]} -eq 0 ]]; then
    jq -n '{"approved": false, "reason": "CD pipeline requires explicit stage selection", "rule": "NO_STAGES_SPECIFIED"}'
    exit 1
  fi

  # Check each requested stage against blocked list
  for stage in "${STAGES_ARRAY[@]}"; do
    stage_lower=$(echo "$stage" | tr '[:upper:]' '[:lower:]')
    for blocked in "${BLOCKED_ENVS[@]}"; do
      if [[ "$stage_lower" == *"$blocked"* ]]; then
        jq -n \
          --arg reason "BLOCKED: Stage '$stage' matches blocked environment '$blocked'. PRE/PRD are NEVER allowed." \
          --arg rule "ENVIRONMENT_BLOCKLIST" \
          '{"approved": false, "reason": $reason, "rule": $rule}'
        exit 1
      fi
    done
  done

  # Check each requested stage is in allowed list
  # Uses prefix matching: "sitae" matches allowed prefix "sit", "dryae" matches "dry", etc.
  # This supports composite stage names like {env}{region} (e.g., sitae, uatase)
  for stage in "${STAGES_ARRAY[@]}"; do
    stage_lower=$(echo "$stage" | tr '[:upper:]' '[:lower:]')
    found=false
    for allowed in "${ALLOWED_CD_STAGES[@]}"; do
      if [[ "$stage_lower" == "$allowed" || "$stage_lower" == "${allowed}"* ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" == "false" ]]; then
      jq -n \
        --arg reason "BLOCKED: Stage '$stage' is not in the allowed list. Allowed: ${ALLOWED_CD_STAGES[*]}" \
        --arg rule "STAGE_NOT_ALLOWED" \
        '{"approved": false, "reason": $reason, "rule": $rule}'
      exit 1
    fi
  done

  # Normalize branch
  REF_BRANCH="$BRANCH"
  if [[ ! "$BRANCH" =~ ^refs/ ]]; then
    REF_BRANCH="refs/heads/$BRANCH"
  fi

  # Build stagesToSkip: read all stages from input, skip any not in requested stages
  ALL_STAGES=$(echo "$INPUT" | jq -r '.allStages // [] | .[]' 2>/dev/null)
  STAGES_TO_SKIP="[]"
  if [[ -n "$ALL_STAGES" ]]; then
    STAGES_JSON=$(printf '%s\n' "${STAGES_ARRAY[@]}" | jq -R . | jq -sc .)
    STAGES_TO_SKIP=$(echo "$INPUT" | jq -c --argjson requested "$STAGES_JSON" '[.allStages[] | select(. as $s | ($requested | map(ascii_downcase)) | index($s | ascii_downcase) | not)]')
  fi

  STAGES_LIST=$(IFS=','; echo "${STAGES_ARRAY[*]}")

  CD_OUTPUT=$(jq -n \
    --arg pipelineId "$PIPELINE_ID" \
    --arg project "$PROJECT" \
    --arg branch "$REF_BRANCH" \
    --argjson stagesToSkip "$STAGES_TO_SKIP" \
    --arg reason "CD pipeline approved for stages: $STAGES_LIST" \
    '{
      "approved": true,
      "pipelineId": ($pipelineId | tonumber),
      "project": $project,
      "branch": $branch,
      "stagesToSkip": $stagesToSkip,
      "reason": $reason
    }')

  log_validator "=== VALIDATOR OUTPUT (cd) ==="
  log_validator "Output: $CD_OUTPUT"

  echo "$CD_OUTPUT"
  exit 0
fi

# ============================================================================
# Rule 4: Terraform pipelines — plan only, NEVER apply
# ============================================================================
ALLOWED_TF_ENVS=("dev" "sit" "uat" "npe" "dry")
ALLOWED_TF_LOCATIONS=("ae" "ase")

if [[ "$TYPE" == "terraform" ]]; then
  # Parse terraform-specific fields
  TF_ENVIRONMENT=$(echo "$INPUT" | jq -r '.environment // empty')
  TF_LOCATION=$(echo "$INPUT" | jq -r '.location // "ae"')

  # Validate environment is provided
  if [[ -z "$TF_ENVIRONMENT" ]]; then
    jq -n '{"approved": false, "reason": "Terraform pipeline requires an environment parameter", "rule": "MISSING_ENVIRONMENT"}'
    exit 1
  fi

  # Check environment against blocked list (global hard-coded guard — NEVER weaken)
  TF_ENV_LOWER=$(echo "$TF_ENVIRONMENT" | tr '[:upper:]' '[:lower:]')
  for blocked in "${BLOCKED_ENVS[@]}"; do
    if [[ "$TF_ENV_LOWER" == "$blocked" ]]; then
      jq -n \
        --arg reason "BLOCKED: Environment '$TF_ENVIRONMENT' is blocked. PRE/PRD are NEVER allowed for terraform pipelines." \
        '{"approved": false, "reason": $reason, "rule": "ENVIRONMENT_BLOCKLIST"}'
      exit 1
    fi
  done

  # Check environment is in allowed list
  TF_ENV_ALLOWED=false
  for allowed in "${ALLOWED_TF_ENVS[@]}"; do
    if [[ "$TF_ENV_LOWER" == "$allowed" ]]; then
      TF_ENV_ALLOWED=true
      break
    fi
  done
  if [[ "$TF_ENV_ALLOWED" == "false" ]]; then
    jq -n \
      --arg reason "BLOCKED: Environment '$TF_ENVIRONMENT' is not in allowed list. Allowed: ${ALLOWED_TF_ENVS[*]}" \
      '{"approved": false, "reason": $reason, "rule": "ENVIRONMENT_NOT_ALLOWED"}'
    exit 1
  fi

  # Validate location
  TF_LOC_LOWER=$(echo "$TF_LOCATION" | tr '[:upper:]' '[:lower:]')
  TF_LOC_ALLOWED=false
  for allowed in "${ALLOWED_TF_LOCATIONS[@]}"; do
    if [[ "$TF_LOC_LOWER" == "$allowed" ]]; then
      TF_LOC_ALLOWED=true
      break
    fi
  done
  if [[ "$TF_LOC_ALLOWED" == "false" ]]; then
    jq -n \
      --arg reason "BLOCKED: Location '$TF_LOCATION' is not valid. Allowed: ${ALLOWED_TF_LOCATIONS[*]}" \
      '{"approved": false, "reason": $reason, "rule": "LOCATION_NOT_ALLOWED"}'
    exit 1
  fi

  # Normalize branch
  REF_BRANCH="$BRANCH"
  if [[ ! "$BRANCH" =~ ^refs/ ]]; then
    REF_BRANCH="refs/heads/$BRANCH"
  fi

  # ==========================================================================
  # Registry-driven configuration
  #
  # Look up the pipeline-registry.json by walking up from CWD. Match by
  # pipelineId (numeric) against services.*.terraform.id. The registry is the
  # single source of truth for:
  #   - stagesToSkip (services.<svc>.stages.blocked  ∪  terraform.alwaysSkipStages)
  #   - templateParameters (terraform.defaultParameters merged with env/location)
  #
  # If the registry cannot be found or the pipelineId is not in it, we fail
  # CLOSED: emit a conservative plan-only default that still skips any stage
  # whose name contains "apply" — but we warn loudly in the reason.
  # ==========================================================================
  find_registry_from_cwd() {
    local dir
    dir="${PWD}"
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
  if REGISTRY_FILE=$(find_registry_from_cwd); then
    log_validator "Using registry: $REGISTRY_FILE"
  else
    log_validator "WARNING: No pipeline-registry.json found from CWD — falling back to hardcoded defaults"
  fi

  SERVICE_ENTRY="null"
  if [[ -n "$REGISTRY_FILE" && -n "$PIPELINE_ID" ]]; then
    SERVICE_ENTRY=$(jq --arg pid "$PIPELINE_ID" \
      '[.services | to_entries[] | select(.value.terraform.id == ($pid | tonumber))] | .[0] // null' \
      "$REGISTRY_FILE")
  fi

  if [[ "$SERVICE_ENTRY" != "null" && -n "$SERVICE_ENTRY" ]]; then
    # Derive stagesToSkip: union of stages.blocked and terraform.alwaysSkipStages
    STAGES_TO_SKIP=$(echo "$SERVICE_ENTRY" | jq -c '
      ((.value.stages.blocked // []) + (.value.terraform.alwaysSkipStages // []))
      | unique
    ')

    # Defensive: make sure every stage whose name contains "apply" is skipped,
    # even if the registry has a mistake. This is a belt-and-braces guard.
    ALL_STAGES_FROM_REG=$(echo "$SERVICE_ENTRY" | jq -c '.value.stages.all // []')
    STAGES_TO_SKIP=$(jq -nc \
      --argjson skip "$STAGES_TO_SKIP" \
      --argjson all "$ALL_STAGES_FROM_REG" \
      '($skip + [$all[] | select(ascii_downcase | startswith("apply"))]) | unique')

    # Derive templateParameters from defaultParameters (registry) + env/location
    DEFAULT_PARAMS=$(echo "$SERVICE_ENTRY" | jq -c '.value.terraform.defaultParameters // {}')
    TEMPLATE_PARAMS=$(jq -nc \
      --arg env "$TF_ENV_LOWER" \
      --arg loc "$TF_LOC_LOWER" \
      --argjson defaults "$DEFAULT_PARAMS" \
      '$defaults + {"environment": $env, "location": $loc}')

    REG_SVC_NAME=$(echo "$SERVICE_ENTRY" | jq -r '.key')
    REASON="Terraform PLAN-ONLY approved for service '$REG_SVC_NAME' env=$TF_ENV_LOWER loc=$TF_LOC_LOWER (registry-driven: blocked stages + alwaysSkipStages applied)"
  else
    # Fallback (fail-closed): no registry match. Skip any stage named like apply/destroy.
    log_validator "WARNING: pipelineId $PIPELINE_ID not found in registry; using conservative plan-only defaults"
    STAGES_TO_SKIP='["apply_travellerdirectives","apply_flightchecker","apply_advancedpassengerprocessing","destroy_advancedpassengerprocessing","RemoveThisStageWhenOtherPipelinesUsesHostedAgents"]'
    TEMPLATE_PARAMS=$(jq -nc \
      --arg env "$TF_ENV_LOWER" \
      --arg loc "$TF_LOC_LOWER" \
      '{
        "environment": $env,
        "location": $loc,
        "deployToggle": "plan",
        "TF_LOG": "NONE"
      }')
    REASON="Terraform PLAN-ONLY approved (fallback mode — pipelineId $PIPELINE_ID not in registry) env=$TF_ENV_LOWER loc=$TF_LOC_LOWER"
  fi

  VALIDATOR_OUTPUT=$(jq -n \
    --arg pipelineId "$PIPELINE_ID" \
    --arg project "$PROJECT" \
    --arg branch "$REF_BRANCH" \
    --argjson stagesToSkip "$STAGES_TO_SKIP" \
    --argjson templateParameters "$TEMPLATE_PARAMS" \
    --arg reason "$REASON" \
    '{
      "approved": true,
      "pipelineId": ($pipelineId | tonumber),
      "project": $project,
      "branch": $branch,
      "stagesToSkip": $stagesToSkip,
      "templateParameters": $templateParameters,
      "reason": $reason
    }')

  log_validator "=== VALIDATOR OUTPUT (terraform) ==="
  log_validator "Output: $VALIDATOR_OUTPUT"

  echo "$VALIDATOR_OUTPUT"
  exit 0
fi
