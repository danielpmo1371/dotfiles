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

INPUT=$(cat)

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

# Validation: type must be ci or cd
if [[ "$TYPE" != "ci" && "$TYPE" != "cd" ]]; then
  jq -n --arg reason "Invalid type: $TYPE. Must be 'ci' or 'cd'" \
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

  jq -n \
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
    }'
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
  for stage in "${STAGES_ARRAY[@]}"; do
    stage_lower=$(echo "$stage" | tr '[:upper:]' '[:lower:]')
    found=false
    for allowed in "${ALLOWED_CD_STAGES[@]}"; do
      if [[ "$stage_lower" == "$allowed" ]]; then
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

  jq -n \
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
    }'
  exit 0
fi
