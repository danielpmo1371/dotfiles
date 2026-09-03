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

# Locate the project pipeline-registry.json by walking up from CWD.
# The registry is the source of truth for service-specific stage names
# (e.g. svc-apim's PROD_SHARED_STAGE_* stages) that the generic prefix
# lists above cannot express.
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

# The registry is safety-load-bearing: its stage lists decide what the AI
# may trigger. Refuse to trust a copy git cannot vouch for — untracked,
# locally modified, or outside a git work tree all fail CLOSED. Tampering
# must be a hard stop, NOT a fallback to prefix matching (which could
# approve a stage the committed registry blocks). Mirrored in
# pipeline-guard.sh; AI writes to the file are blocked separately by
# pipeline-registry-write-guard.sh.
registry_committed_or_die() {
  local reg="$1" root reason=""
  root=$(dirname "$(dirname "$reg")")
  if ! command -v git >/dev/null 2>&1; then
    reason="git not on PATH — cannot verify registry integrity"
  elif ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    reason="registry is not inside a git work tree"
  elif ! git -C "$root" ls-files --error-unmatch -- .claude/pipeline-registry.json >/dev/null 2>&1; then
    reason="registry is not tracked by git"
  elif [[ -n "$(git -C "$root" status --porcelain -- .claude/pipeline-registry.json 2>/dev/null)" ]]; then
    reason="registry has uncommitted changes"
  fi
  if [[ -n "$reason" ]]; then
    log_validator "BLOCKED: $reason ($reg)"
    jq -n --arg reason "BLOCKED: $reason ($reg). The registry drives stage safety decisions and is only trusted at its committed, human-reviewed state." \
      '{"approved": false, "reason": $reason, "rule": "REGISTRY_NOT_COMMITTED"}'
    exit 1
  fi
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

  # Registry lookup: service-specific stage lists take precedence over the
  # generic prefix lists, because stage names like PROD_SHARED_STAGE_SIT
  # (svc-apim) are invisible to prefix matching — including its PROD stage
  # PROD_SHARED_STAGE, which the substring blocklist above does NOT catch.
  # Match by cd.id FIRST — the pipeline ID is what actually gets triggered,
  # and pipeline-guard.sh matches by ID only, so a name/ID mismatch must
  # validate against the ID's entry. Service name is the fallback for
  # requests that carry no pipelineId.
  CD_REG_ENTRY="null"
  if REGISTRY_FILE=$(find_registry_from_cwd); then
    registry_committed_or_die "$REGISTRY_FILE"
    CD_REG_ENTRY=$(jq --arg svc "$SERVICE" --arg pid "${PIPELINE_ID:-0}" '
      ([.services | to_entries[] | select(.value.cd.id? == ($pid | tonumber))] | .[0].value // null) as $byId
      | if $byId != null then $byId
        else (.services[$svc] // null)
        end' "$REGISTRY_FILE")
  fi

  # The registry blocked list is honored UNCONDITIONALLY whenever an entry
  # matches — even when 'allowed' is empty and the allow decision falls
  # through to the generic prefix fallback below. This is the only layer
  # that can block prod stages whose names carry no pre/prd/prod substring.
  if [[ "$CD_REG_ENTRY" != "null" && -n "$CD_REG_ENTRY" ]]; then
    for stage in "${STAGES_ARRAY[@]}"; do
      stage_lower=$(echo "$stage" | tr '[:upper:]' '[:lower:]')
      if [[ $(echo "$CD_REG_ENTRY" | jq -r --arg s "$stage_lower" '[.stages.blocked // [] | .[] | ascii_downcase] | index($s) != null') == "true" ]]; then
        jq -n \
          --arg reason "BLOCKED: Stage '$stage' is in the registry blocked list for service '$SERVICE'. PRE/PRD are NEVER allowed." \
          --arg rule "ENVIRONMENT_BLOCKLIST" \
          '{"approved": false, "reason": $reason, "rule": $rule}'
        exit 1
      fi
    done
  fi

  if [[ "$CD_REG_ENTRY" != "null" && -n "$CD_REG_ENTRY" ]] && [[ $(echo "$CD_REG_ENTRY" | jq -r '.stages.allowed // [] | length') -gt 0 ]]; then
    # Registry-driven allow decision: exact case-insensitive match;
    # anything not explicitly allowed is blocked (default-deny).
    for stage in "${STAGES_ARRAY[@]}"; do
      stage_lower=$(echo "$stage" | tr '[:upper:]' '[:lower:]')
      if [[ $(echo "$CD_REG_ENTRY" | jq -r --arg s "$stage_lower" '[.stages.allowed // [] | .[] | ascii_downcase] | index($s) != null') != "true" ]]; then
        REG_ALLOWED=$(echo "$CD_REG_ENTRY" | jq -r '.stages.allowed | join(" ")')
        jq -n \
          --arg reason "BLOCKED: Stage '$stage' is not in the registry allowed list for service '$SERVICE'. Allowed: $REG_ALLOWED" \
          --arg rule "STAGE_NOT_ALLOWED" \
          '{"approved": false, "reason": $reason, "rule": $rule}'
        exit 1
      fi
    done
    log_validator "CD stages validated against registry entry for service '$SERVICE'"
  else
    # Fallback: generic prefix matching — "sitae" matches allowed prefix "sit",
    # "dryae" matches "dry", etc. Supports composite {env}{region} stage names.
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
  fi

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
# Rule 4: Terraform pipelines — plan only by default. The apply stage runs
# only for an env in the registry's terraform.applyAllowedEnvironments, and
# a BLOCK always overrides an ALLOW: stages.blocked, alwaysSkipStages and
# destroy* stages are skipped on every run, whatever the allowlist says.
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
  #   - per-service environment policy (terraform.parameters.environment.{blocked,allowed})
  #   - stagesToSkip (stages.blocked ∪ terraform.alwaysSkipStages ∪ destroy* stages,
  #     plus apply* stages unless the env is in terraform.applyAllowedEnvironments)
  #   - templateParameters (terraform.defaultParameters merged with env/location)
  #
  # If the registry cannot be found or the pipelineId is not in it, we fail
  # CLOSED (TERRAFORM_NOT_REGISTERED below) — stage names are never guessed.
  # ==========================================================================
  # (find_registry_from_cwd is defined at the top of this script)
  REGISTRY_FILE=""
  if REGISTRY_FILE=$(find_registry_from_cwd); then
    registry_committed_or_die "$REGISTRY_FILE"
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
    REG_SVC_NAME=$(echo "$SERVICE_ENTRY" | jq -r '.key')

    # Registry per-service environment policy. Runs AFTER the hardcoded checks
    # above and can only narrow them, never widen them: blocked list first,
    # then the allowed list (default-deny when the list is present and non-empty).
    REG_ENV_BLOCKED=$(echo "$SERVICE_ENTRY" | jq -r --arg env "$TF_ENV_LOWER" '
      [.value.terraform.parameters.environment.blocked // [] | .[] | ascii_downcase] | index($env) != null')
    if [[ "$REG_ENV_BLOCKED" == "true" ]]; then
      log_validator "BLOCKED: env '$TF_ENV_LOWER' is in terraform.parameters.environment.blocked for '$REG_SVC_NAME'"
      jq -n \
        --arg reason "BLOCKED: Environment '$TF_ENVIRONMENT' is blocked by the registry for service '$REG_SVC_NAME' (terraform.parameters.environment.blocked)." \
        '{"approved": false, "reason": $reason, "rule": "ENVIRONMENT_BLOCKLIST"}'
      exit 1
    fi
    REG_ENV_ALLOWED=$(echo "$SERVICE_ENTRY" | jq -r --arg env "$TF_ENV_LOWER" '
      (.value.terraform.parameters.environment.allowed // []) as $a
      | ($a | length) == 0 or ([$a[] | ascii_downcase] | index($env) != null)')
    if [[ "$REG_ENV_ALLOWED" != "true" ]]; then
      log_validator "BLOCKED: env '$TF_ENV_LOWER' is not in terraform.parameters.environment.allowed for '$REG_SVC_NAME'"
      jq -n \
        --arg reason "BLOCKED: Environment '$TF_ENVIRONMENT' is not in the registry's allowed list for service '$REG_SVC_NAME' (terraform.parameters.environment.allowed)." \
        '{"approved": false, "reason": $reason, "rule": "ENVIRONMENT_NOT_ALLOWED"}'
      exit 1
    fi

    ALL_STAGES_FROM_REG=$(echo "$SERVICE_ENTRY" | jq -c '.value.stages.all // []')

    # Hard skip set — skipped on EVERY run; nothing below can remove an entry
    # (block overrides allow):
    #   stages.blocked ∪ terraform.alwaysSkipStages ∪ destroy* stages
    # The registry lists are the authority. The "starts with destroy" match is
    # belt-and-braces only: a destroy stage named differently must be listed.
    HARD_SKIP=$(echo "$SERVICE_ENTRY" | jq -c '
      ((.value.stages.blocked // [])
       + (.value.terraform.alwaysSkipStages // [])
       + [(.value.stages.all // [])[] | select(ascii_downcase | startswith("destroy"))])
      | unique')

    # Apply stages = every stages.all entry whose name starts with "apply".
    # Same caveat: prefix match is belt-and-braces, the blocked list is the
    # authority for anything named differently.
    APPLY_STAGES=$(jq -nc --argjson all "$ALL_STAGES_FROM_REG" \
      '[$all[] | select(ascii_downcase | startswith("apply"))]')

    # Apply-stage policy. Plan-only is the default. An environment listed in the
    # registry's terraform.applyAllowedEnvironments may run the apply stage —
    # same allowlist the pipeline-guard hook enforces, so both layers agree.
    APPLY_ALLOWED_ENVS=$(echo "$SERVICE_ENTRY" | jq -r '
      .value.terraform.applyAllowedEnvironments // [] | map(ascii_downcase) | join(",")')
    APPLY_PERMITTED=false
    if [[ -n "$APPLY_ALLOWED_ENVS" ]]; then
      IFS=',' read -ra ALLOWED_APPLY_ENVS <<< "$APPLY_ALLOWED_ENVS"
      for allowed_apply_env in "${ALLOWED_APPLY_ENVS[@]}"; do
        if [[ "$allowed_apply_env" == "$TF_ENV_LOWER" ]]; then
          APPLY_PERMITTED=true
          break
        fi
      done
    fi

    DEFAULT_PARAMS=$(echo "$SERVICE_ENTRY" | jq -c '.value.terraform.defaultParameters // {}')

    if [[ "$APPLY_PERMITTED" == "true" ]]; then
      # Block overrides allow: the allowlist may un-skip an apply stage only if
      # the registry does NOT also list it in stages.blocked/alwaysSkipStages.
      # If it does, the registry contradicts itself — fail closed. A silent
      # downgrade to plan-only would hide the mistake, so we refuse instead.
      CONTRADICTED=$(jq -nc --argjson hard "$HARD_SKIP" --argjson apply "$APPLY_STAGES" \
        '[$apply[] | select(. as $s | $hard | index($s) != null)]')
      if [[ "$(echo "$CONTRADICTED" | jq 'length')" != "0" ]]; then
        log_validator "BLOCKED: registry contradiction for '$REG_SVC_NAME': apply stage(s) $CONTRADICTED in stages.blocked/alwaysSkipStages while env '$TF_ENV_LOWER' is in applyAllowedEnvironments"
        jq -n \
          --arg reason "BLOCKED: Registry contradiction for service '$REG_SVC_NAME': apply stage(s) $CONTRADICTED are listed in stages.blocked/alwaysSkipStages AND environment '$TF_ENV_LOWER' is in applyAllowedEnvironments. Blocked lists always win. A human must remove the stage from stages.blocked/alwaysSkipStages and commit before apply can run." \
          '{"approved": false, "reason": $reason, "rule": "REGISTRY_CONTRADICTION"}'
        exit 1
      fi

      STAGES_TO_SKIP="$HARD_SKIP"

      # The apply is only ever reachable behind a human approval, and only as a
      # deploy — never a destroy — whatever the registry defaults happen to say.
      TEMPLATE_PARAMS=$(jq -nc \
        --arg env "$TF_ENV_LOWER" \
        --arg loc "$TF_LOC_LOWER" \
        --argjson defaults "$DEFAULT_PARAMS" \
        '$defaults + {"environment": $env, "location": $loc,
                      "deployToggle": "deploy", "requireManualApproval": "True"}')

      REASON="Terraform PLAN+APPLY approved for service '$REG_SVC_NAME' env=$TF_ENV_LOWER loc=$TF_LOC_LOWER (env is in registry applyAllowedEnvironments; apply held at the manual approval gate, blocked/alwaysSkip/destroy stages still skipped)"
    else
      # Plan-only: hard skip set plus every apply stage.
      STAGES_TO_SKIP=$(jq -nc \
        --argjson hard "$HARD_SKIP" \
        --argjson apply "$APPLY_STAGES" \
        '($hard + $apply) | unique')

      # Plan-only means plan: pin deployToggle regardless of what the registry's
      # defaultParameters say, so a registry typo can never turn into a destroy.
      TEMPLATE_PARAMS=$(jq -nc \
        --arg env "$TF_ENV_LOWER" \
        --arg loc "$TF_LOC_LOWER" \
        --argjson defaults "$DEFAULT_PARAMS" \
        '$defaults + {"environment": $env, "location": $loc, "deployToggle": "plan"}')

      REASON="Terraform PLAN-ONLY approved for service '$REG_SVC_NAME' env=$TF_ENV_LOWER loc=$TF_LOC_LOWER (registry-driven: blocked stages + alwaysSkipStages + destroy/apply stages skipped)"
    fi
  else
    # Fail closed: no registry entry for this pipelineId means we have no
    # verified list of its stages, so we cannot safely compute stagesToSkip.
    # A prior version of this rule shipped a hardcoded guess-list of stage
    # names specific to one org's terraform layout — reused elsewhere, a
    # differently-named apply/destroy stage would have silently slipped
    # through unskipped. Refusing to guess is strictly safer: register the
    # pipeline (.claude/pipeline-registry.json in the target project repo)
    # instead of relying on this fallback.
    log_validator "BLOCKED: pipelineId $PIPELINE_ID not found in registry — refusing to guess stagesToSkip"
    jq -n --arg reason "BLOCKED: pipelineId $PIPELINE_ID not found in pipeline-registry.json. Terraform pipelines require a registry entry (services.<svc>.terraform.id) so stagesToSkip can be derived from real data, not guessed." \
      '{"approved": false, "reason": $reason, "rule": "TERRAFORM_NOT_REGISTERED"}'
    exit 1
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
