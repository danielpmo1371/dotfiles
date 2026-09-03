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
# FAIL CLOSED ON ANY INTERNAL ERROR. Claude Code treats ONLY exit 2 as a
# block; any other non-zero exit is reported as a hook error and the tool call
# PROCEEDS. So a jq crash on a malformed payload or registry must never be
# allowed to end this script with jq's own exit code — set -e would exit 5 and
# the pipeline would run. Every unexpected failure is converted to exit 2 here,
# with an audit record. fail_closed is also used directly by the shape checks
# below that run before log_audit and its inputs exist.
# ============================================================================
fail_closed() {
  local reason="$1"
  trap - ERR
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "unknown")
  local log_dir="${LOG_DIR:-$HOME/.claude/logs}"
  mkdir -p "$log_dir" 2>/dev/null || true
  echo "[$ts] BLOCKED: $reason" >> "$log_dir/pipeline-guard-detail.log" 2>/dev/null || true
  jq -nc \
    --arg ts "$ts" \
    --arg pid "${PIPELINE_ID:-}" \
    --arg proj "${PROJECT:-}" \
    --arg branch "${BRANCH:-unknown}" \
    --arg reason "$reason" \
    '{timestamp: $ts, pipelineId: $pid, project: $proj, branch: $branch,
      action: "blocked", reason: $reason, stagesToSkip: null, templateParameters: null}' \
    >> "$log_dir/pipeline-triggers.jsonl" 2>/dev/null || true
  echo "BLOCKED by pipeline-guard hook: $reason" >&2
  exit 2
}
trap 'fail_closed "internal error (exit $? at line $LINENO: $BASH_COMMAND) — failing closed"' ERR

# ============================================================================
# HARD-CODED SAFETY RULES — MIRRORS pipeline-validator.sh
#
# TERRAFORM_PIPELINE_ID / TERRAFORM_APPLY_STAGE identify YOUR org's terraform
# pipeline and its apply stage — they are deliberately NOT read from
# pipeline-registry.json (checks 0-3 are skipped entirely when no registry is
# found for the CWD; this check must still fire in that case — it is the
# only protection active when the AI is not inside a registered project
# directory). Configure via the OS keychain, same mechanism as AZDO_ORG:
#   secret_set PIPELINE_GUARD_TERRAFORM_ID "<pipeline-id>"
#   secret_set PIPELINE_GUARD_TERRAFORM_APPLY_STAGE "<apply-stage-name>"
# config/shell/secrets.sh exports both. UNSET = FAIL CLOSED: every pipeline
# trigger is blocked below, not silently allowed. This is what "the guard
# breaks until configured" looks like on a fresh clone — that is intentional.
# When a registry IS found, Check 4 ALSO treats the matched service's
# terraform.id as a terraform pipeline and derives its apply*/destroy* stages
# from stages.all — so every registered terraform pipeline is covered, not
# only the keychain one.
#
# The apply stage is blocked by default. The ONE exemption is declared per
# project, in pipeline-registry.json, as
#   .services[<svc>].terraform.applyAllowedEnvironments: ["dev"]
# — deliberately in the registry rather than the keychain, because the registry
# is integrity-checked above: widening this policy requires a HUMAN commit and
# takes effect immediately, with no keychain write or shell restart. Absent
# registry, absent key, or an environment not listed = apply stays blocked, so
# the exemption fails closed. It also stays narrow — see Check 4: the run must
# be deployToggle=deploy with requireManualApproval=True (AzDO still holds it
# at the review gate for a human), and PRE/PRD remain blocked by Check 3
# regardless of what the registry lists. BLOCK OVERRIDES ALLOW, no exceptions:
# a stage the registry lists in stages.blocked or terraform.alwaysSkipStages
# must be skipped on every run even when the environment is allowlisted — a
# registry that does both contradicts itself and the run fails closed.
# ============================================================================
BLOCKED_STAGE_PATTERNS=("pre" "prd" "prod" "production")
TERRAFORM_PIPELINE_ID="${PIPELINE_GUARD_TERRAFORM_ID:-}"
TERRAFORM_APPLY_STAGE="${PIPELINE_GUARD_TERRAFORM_APPLY_STAGE:-}"
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

# Payload shape — every rule below indexes these fields; a wrong type would
# either crash jq (see fail_closed) or, worse, make a check vacuously pass
# (e.g. `length` of a string in Check 1). Absent optional keys are fine.
INPUT_SHAPE_ERROR=$(echo "$TOOL_INPUT" | jq -r '
  def str_array: type == "array" and all(.[]; type == "string");
  if type != "object" then "tool_input must be an object" else
    [ (if (.stagesToSkip // []) | str_array then empty else "stagesToSkip must be an array of strings" end),
      (if (.templateParameters // {}) | type == "object" then empty else "templateParameters must be an object" end),
      (if (.variables // {}) | type == "object" then empty else "variables must be an object" end)
    ] | join("; ")
  end')
if [[ -n "$INPUT_SHAPE_ERROR" ]]; then
  fail_closed "malformed tool_input ($INPUT_SHAPE_ERROR) — cannot evaluate policy. Raw tool_input: $TOOL_INPUT"
fi

# Parse the MCP tool input
PIPELINE_ID=$(echo "$TOOL_INPUT" | jq -r '.pipelineId // empty' 2>/dev/null)
PROJECT=$(echo "$TOOL_INPUT" | jq -r '.project // empty' 2>/dev/null)
BRANCH=$(echo "$TOOL_INPUT" | jq -r '.resources.repositories.self.refName // "unknown"' 2>/dev/null)
STAGES_TO_SKIP_JSON=$(echo "$TOOL_INPUT" | jq -c '.stagesToSkip // []' 2>/dev/null)
STAGES_TO_SKIP_LIST=$(echo "$TOOL_INPUT" | jq -r '.stagesToSkip // [] | join(", ")' 2>/dev/null)
TEMPLATE_PARAMS_JSON=$(echo "$TOOL_INPUT" | jq -c '.templateParameters // {}' 2>/dev/null)
TEMPLATE_PARAMS=$(echo "$TOOL_INPUT" | jq -r '.templateParameters // {} | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null)
VARIABLES=$(echo "$TOOL_INPUT" | jq -r '.variables // {} | to_entries[] | "\(.key)=\(.value.value // .value)"' 2>/dev/null)
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
# Fail closed if unconfigured — see the constants block above. Without a
# known terraform pipeline id/stage, this hook cannot tell an infra-destroy
# pipeline from a harmless CI run, so it refuses ALL triggers rather than
# silently skip the one check that has no registry fallback.
# ============================================================================
if [[ -z "$TERRAFORM_PIPELINE_ID" || -z "$TERRAFORM_APPLY_STAGE" ]]; then
  log_detail "BLOCKED: pipeline-guard not configured (PIPELINE_GUARD_TERRAFORM_ID / PIPELINE_GUARD_TERRAFORM_APPLY_STAGE unset)"
  log_audit "blocked" "pipeline-guard not configured — see PIPELINE_GUARD_TERRAFORM_ID / PIPELINE_GUARD_TERRAFORM_APPLY_STAGE in config/claude/hooks/pipeline-guard.sh"
  echo "BLOCKED by pipeline-guard hook: not configured. Set PIPELINE_GUARD_TERRAFORM_ID and PIPELINE_GUARD_TERRAFORM_APPLY_STAGE (secret_set PIPELINE_GUARD_TERRAFORM_ID \"...\"; secret_set PIPELINE_GUARD_TERRAFORM_APPLY_STAGE \"...\") before any pipeline can be triggered. This hook fails closed when unconfigured." >&2
  exit 2
fi

# ============================================================================
# Fail closed without a usable pipeline id — every check below keys off it.
# A missing/null/empty id used to skip the registry lookup AND terraform
# detection entirely, so the run sailed through with zero checks.
# ============================================================================
if [[ ! "$PIPELINE_ID" =~ ^[0-9]+$ ]]; then
  log_detail "BLOCKED: pipelineId '$PIPELINE_ID' missing or not numeric — cannot evaluate policy"
  log_audit "blocked" "pipelineId missing or not numeric ('$PIPELINE_ID') — cannot evaluate policy"
  echo "BLOCKED by pipeline-guard hook: pipelineId missing or not numeric ('$PIPELINE_ID') — cannot evaluate policy. Pass the numeric pipeline id." >&2
  exit 2
fi

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
# Registry integrity — MIRRORS registry_committed_or_die in
# pipeline-validator.sh (deliberately duplicated: each defense layer must
# stand alone). The registry is only trusted at its committed state;
# untracked, locally modified, or outside a git work tree fails CLOSED.
# ============================================================================
if [[ -n "$REGISTRY_FILE" ]]; then
  REG_ROOT=$(dirname "$(dirname "$REGISTRY_FILE")")
  REG_INTEGRITY_REASON=""
  if ! command -v git >/dev/null 2>&1; then
    REG_INTEGRITY_REASON="git not on PATH — cannot verify registry integrity"
  elif ! git -C "$REG_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REG_INTEGRITY_REASON="registry is not inside a git work tree"
  elif ! git -C "$REG_ROOT" ls-files --error-unmatch -- .claude/pipeline-registry.json >/dev/null 2>&1; then
    REG_INTEGRITY_REASON="registry is not tracked by git"
  elif [[ -n "$(git -C "$REG_ROOT" status --porcelain -- .claude/pipeline-registry.json 2>/dev/null)" ]]; then
    REG_INTEGRITY_REASON="registry has uncommitted changes"
  fi
  if [[ -n "$REG_INTEGRITY_REASON" ]]; then
    log_detail "BLOCKED: $REG_INTEGRITY_REASON ($REGISTRY_FILE)"
    log_audit "blocked" "$REG_INTEGRITY_REASON ($REGISTRY_FILE)"
    echo "BLOCKED by pipeline-guard hook: $REG_INTEGRITY_REASON ($REGISTRY_FILE). The registry is only trusted at its committed, human-reviewed state — a HUMAN must review and commit it before pipelines can be triggered." >&2
    exit 2
  fi
fi

# ============================================================================
# Check 0: Block unregistered pipelines
# ============================================================================
if [[ -n "$REGISTRY_FILE" ]]; then
  # Search all services for a matching ci.id, cd.id, terraform.id, or test.id
  MATCHED_SERVICE=$(jq -r --arg pid "$PIPELINE_ID" '
    .services | to_entries[] |
    select(
      (.value.ci.id // -1 | tostring) == $pid or
      (.value.cd.id // -1 | tostring) == $pid or
      (.value.terraform.id // -1 | tostring) == $pid or
      (.value.test.id // -1 | tostring) == $pid
    ) | .key
  ' "$REGISTRY_FILE" 2>/dev/null)

  if [[ -z "$MATCHED_SERVICE" ]]; then
    log_detail "BLOCKED: Pipeline $PIPELINE_ID not found in registry"
    log_audit "blocked" "Pipeline $PIPELINE_ID not found in registry. Unregistered pipelines cannot be triggered."
    echo "BLOCKED by pipeline-guard hook: Pipeline $PIPELINE_ID not found in registry. Unregistered pipelines cannot be triggered." >&2
    exit 2
  fi

  # Two services claiming the same id would make `.services[$svc]` resolve to
  # null below and the pipeline read as "neither CD nor terraform" — every
  # check silently off. A copy-paste error in the registry must fail closed.
  if [[ "$MATCHED_SERVICE" == *$'\n'* ]]; then
    AMBIGUOUS_SERVICES=$(echo "$MATCHED_SERVICE" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
    log_detail "BLOCKED: ambiguous registry — pipeline $PIPELINE_ID claimed by services: $AMBIGUOUS_SERVICES"
    log_audit "blocked" "Ambiguous registry: pipeline $PIPELINE_ID is claimed by services $AMBIGUOUS_SERVICES. A human must fix the registry."
    echo "BLOCKED by pipeline-guard hook: ambiguous registry — pipeline id $PIPELINE_ID is claimed by services $AMBIGUOUS_SERVICES. A HUMAN must fix the registry so exactly one service owns the id." >&2
    exit 2
  fi

  log_detail "Registry match: pipeline $PIPELINE_ID belongs to service '$MATCHED_SERVICE'"

  # Registry entry shape — the registry is trusted only when well-formed. A
  # wrong type must fail closed, never relax a rule (a non-object
  # defaultParameters must not read as "approval not declared", a string
  # stages.all must not read as "no apply stage"). Absent optional keys are fine.
  REGISTRY_SHAPE_ERROR=$(jq -r --arg svc "$MATCHED_SERVICE" '
    def str_array: type == "array" and all(.[]; type == "string");
    .services[$svc] as $s |
    [ (if ($s.stages.all // []) | str_array then empty else "stages.all must be an array of strings" end),
      (if ($s.stages.blocked // []) | str_array then empty else "stages.blocked must be an array of strings" end),
      (if ($s.terraform.alwaysSkipStages // []) | str_array then empty else "terraform.alwaysSkipStages must be an array of strings" end),
      (if ($s.terraform.applyAllowedEnvironments // []) | str_array then empty else "terraform.applyAllowedEnvironments must be an array of strings" end),
      (if ($s.terraform.defaultParameters // {}) | type == "object" then empty else "terraform.defaultParameters must be an object" end)
    ] | join("; ")' "$REGISTRY_FILE")
  if [[ -n "$REGISTRY_SHAPE_ERROR" ]]; then
    log_detail "BLOCKED: malformed registry entry for service '$MATCHED_SERVICE': $REGISTRY_SHAPE_ERROR"
    log_audit "blocked" "Malformed registry entry for service '$MATCHED_SERVICE' ($REGISTRY_SHAPE_ERROR). A human must fix the registry."
    echo "BLOCKED by pipeline-guard hook: malformed registry entry for service '$MATCHED_SERVICE' — $REGISTRY_SHAPE_ERROR. The registry is trusted only when well-formed; a HUMAN must fix and commit it." >&2
    exit 2
  fi

  # Determine if this is a CD pipeline
  IS_CD=$(jq -r --arg pid "$PIPELINE_ID" --arg svc "$MATCHED_SERVICE" '
    (.services[$svc].cd.id // empty | tostring) == $pid
  ' "$REGISTRY_FILE" 2>/dev/null)

  # ==========================================================================
  # Check 1: CD pipeline must have stagesToSkip
  # ==========================================================================
  if [[ "$IS_CD" == "true" ]]; then
    STAGES_COUNT=$(echo "$STAGES_TO_SKIP_JSON" | jq 'length' 2>/dev/null)

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
    ' "$REGISTRY_FILE" 2>/dev/null)

    for blocked_stage in $BLOCKED_STAGES; do
      HAS_STAGE=$(echo "$STAGES_TO_SKIP_JSON" | jq -r --arg s "$blocked_stage" '[.[] | select(. == $s)] | length' 2>/dev/null)
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
else
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
# Check 4: Terraform pipeline apply/destroy-stage policy
#
# Terraform detection: the matched registry service's terraform.id equals this
# pipeline, OR this pipeline is the keychain-configured
# PIPELINE_GUARD_TERRAFORM_ID (the only detection available without a
# registry). Every registered terraform pipeline is covered, not just the one
# in the keychain.
#
# PRECEDENCE: BLOCK OVERRIDES ALLOW — NO EXCEPTIONS. Every blocking condition
# is evaluated and exits before the single allow path is reached; the
# allowlist can only remove ONE reason to block (an apply stage that is in no
# block list not being skipped) and never grants anything else.
#   1. A terraform pipeline with no identifiable apply stage fails closed.
#   2. destroy* stages (registry stages.all) must ALWAYS be in stagesToSkip.
#   3. EVERY stage in the registry's stages.blocked AND terraform.alwaysSkipStages
#      must be in stagesToSkip on every run, whatever applyAllowedEnvironments
#      says. A registry that allowlists an environment while still listing the
#      apply stage as blocked/always-skipped contradicts itself: the run is
#      blocked and a HUMAN must remove the stage from those lists first.
#   4. requireManualApproval=True is mandatory whenever an apply stage would
#      run, and on plan-only runs of the keychain pipeline or of any service
#      whose registry terraform.defaultParameters declares the parameter (a
#      plan-only run keeps it so an apply can never be reached by a later stage
#      rerun without a human approval).
#   5. Every apply* stage (registry stages.all ∪ keychain apply stage) must be
#      in stagesToSkip UNLESS the environment is listed in the service's
#      terraform.applyAllowedEnvironments AND deployToggle=deploy (exact) AND
#      requireManualApproval=True.
# ============================================================================
IS_KEYCHAIN_TERRAFORM=false
[[ "$PIPELINE_ID" == "$TERRAFORM_PIPELINE_ID" ]] && IS_KEYCHAIN_TERRAFORM=true
IS_REGISTRY_TERRAFORM=false
if [[ -n "$REGISTRY_FILE" && -n "${MATCHED_SERVICE:-}" ]]; then
  REGISTRY_TERRAFORM_ID=$(jq -r --arg svc "$MATCHED_SERVICE" \
    '.services[$svc].terraform.id // empty | tostring' "$REGISTRY_FILE" 2>/dev/null)
  [[ -n "$REGISTRY_TERRAFORM_ID" && "$REGISTRY_TERRAFORM_ID" == "$PIPELINE_ID" ]] && IS_REGISTRY_TERRAFORM=true
fi

if [[ "$IS_KEYCHAIN_TERRAFORM" == true || "$IS_REGISTRY_TERRAFORM" == true ]]; then
  log_detail "Terraform pipeline detected (ID=$PIPELINE_ID, keychain=$IS_KEYCHAIN_TERRAFORM, registry=$IS_REGISTRY_TERRAFORM) — enforcing apply/destroy policy"

  ENVIRONMENT=$(echo "$TOOL_INPUT" | jq -r '.templateParameters.environment // "unset"' 2>/dev/null)
  DEPLOY_TOGGLE=$(echo "$TOOL_INPUT" | jq -r '.templateParameters.deployToggle // "unset"' 2>/dev/null)
  MANUAL_APPROVAL=$(echo "$TOOL_INPUT" | jq -r '.templateParameters.requireManualApproval // "unset"' 2>/dev/null)

  # Registry-derived stage sets (all empty when the pipeline is known only
  # through the keychain). Types were validated in Check 0, so a jq failure
  # here is a genuine internal error and trips fail_closed.
  REGISTRY_STAGES_ALL="[]"
  REGISTRY_STAGES_BLOCKED="[]"
  REGISTRY_ALWAYS_SKIP="[]"
  APPLY_ALLOWED_ENVS=""
  REGISTRY_DECLARES_APPROVAL=false
  if [[ "$IS_REGISTRY_TERRAFORM" == true ]]; then
    REGISTRY_STAGES_ALL=$(jq -c --arg svc "$MATCHED_SERVICE" \
      '.services[$svc].stages.all // []' "$REGISTRY_FILE" 2>/dev/null)
    REGISTRY_STAGES_BLOCKED=$(jq -c --arg svc "$MATCHED_SERVICE" \
      '.services[$svc].stages.blocked // []' "$REGISTRY_FILE" 2>/dev/null)
    REGISTRY_ALWAYS_SKIP=$(jq -c --arg svc "$MATCHED_SERVICE" \
      '.services[$svc].terraform.alwaysSkipStages // []' "$REGISTRY_FILE" 2>/dev/null)
    APPLY_ALLOWED_ENVS=$(jq -r --arg svc "$MATCHED_SERVICE" \
      '.services[$svc].terraform.applyAllowedEnvironments // [] | join(",")' \
      "$REGISTRY_FILE" 2>/dev/null)
    REGISTRY_DECLARES_APPROVAL=$(jq -r --arg svc "$MATCHED_SERVICE" \
      '.services[$svc].terraform.defaultParameters // {} | has("requireManualApproval")' \
      "$REGISTRY_FILE" 2>/dev/null)
  fi

  KEYCHAIN_APPLY_STAGE=""
  [[ "$IS_KEYCHAIN_TERRAFORM" == true ]] && KEYCHAIN_APPLY_STAGE="$TERRAFORM_APPLY_STAGE"

  APPLY_STAGES_JSON=$(jq -nc --argjson all "$REGISTRY_STAGES_ALL" --arg keychain "$KEYCHAIN_APPLY_STAGE" \
    '([$all[] | select(ascii_downcase | startswith("apply"))]
      + (if $keychain != "" then [$keychain] else [] end)) | unique')
  DESTROY_STAGES_JSON=$(jq -nc --argjson all "$REGISTRY_STAGES_ALL" \
    '[$all[] | select(ascii_downcase | startswith("destroy"))] | unique')
  BLOCK_LIST_JSON=$(jq -nc --argjson blocked "$REGISTRY_STAGES_BLOCKED" --argjson always "$REGISTRY_ALWAYS_SKIP" \
    '($blocked + $always) | unique')

  # Is the requested environment allowlisted for apply? Computed up front only
  # so block messages can say so — it grants nothing until every block below
  # has passed. Compared element-by-element in jq: an entry like "dev,sit" is
  # ONE (non-matching) name, never two, and non-string entries never match.
  ENVIRONMENT_LOWER=$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')
  APPLY_ENV_ALLOWED=false
  if [[ "$IS_REGISTRY_TERRAFORM" == true && "$ENVIRONMENT_LOWER" != "unset" ]]; then
    APPLY_ENV_ALLOWED=$(jq -r --arg svc "$MATCHED_SERVICE" --arg env "$ENVIRONMENT_LOWER" \
      '.services[$svc].terraform.applyAllowedEnvironments // []
       | any(.[]; type == "string" and ascii_downcase == $env)' "$REGISTRY_FILE" 2>/dev/null)
  fi

  # not_skipped <stages-json>: the given stages that are NOT in stagesToSkip,
  # comma-joined (empty string when all are skipped).
  not_skipped() {
    jq -r --argjson skip "$STAGES_TO_SKIP_JSON" \
      '[.[] | . as $s | select(any($skip[]; . == $s) | not)] | join(", ")' <<< "$1"
  }

  # Rule 1: fail closed when the apply stage cannot be identified.
  if [[ "$(jq 'length' <<< "$APPLY_STAGES_JSON")" == "0" ]]; then
    log_detail "BLOCKED: terraform pipeline $PIPELINE_ID has no identifiable apply stage (registry stages.all=$REGISTRY_STAGES_ALL)"
    log_audit "blocked" "Terraform pipeline $PIPELINE_ID has no identifiable apply stage — cannot enforce the apply policy. Registry stages.all=$REGISTRY_STAGES_ALL"
    echo "BLOCKED by pipeline-guard hook: Terraform pipeline $PIPELINE_ID has no identifiable apply* stage in the registry's stages.all, so the apply policy cannot be enforced. A HUMAN must fix the registry entry." >&2
    exit 2
  fi

  # Rule 2: destroy stages are never allowed to run — allowlist or not.
  MISSING_DESTROY=$(not_skipped "$DESTROY_STAGES_JSON")
  if [[ -n "$MISSING_DESTROY" ]]; then
    log_detail "BLOCKED: destroy stage(s) not in stagesToSkip: $MISSING_DESTROY"
    log_audit "blocked" "CRITICAL: Terraform pipeline $PIPELINE_ID triggered WITHOUT destroy stage(s) '$MISSING_DESTROY' in stagesToSkip. stagesToSkip=$STAGES_TO_SKIP_JSON"
    echo "BLOCKED by pipeline-guard hook: Terraform pipeline $PIPELINE_ID MUST include destroy stage(s) '$MISSING_DESTROY' in stagesToSkip. Destroy stages are NEVER allowed via AI. Got stagesToSkip=$STAGES_TO_SKIP_JSON" >&2
    exit 2
  fi

  # Rule 3: every stages.blocked / alwaysSkipStages entry must be skipped.
  # Block overrides allow: an allowlisted environment does not exempt an
  # apply stage that the registry ALSO lists here — that is a contradictory
  # registry, and only a human commit can resolve it.
  MISSING_BLOCKED=$(not_skipped "$BLOCK_LIST_JSON")
  if [[ -n "$MISSING_BLOCKED" ]]; then
    MISSING_BLOCKED_JSON=$(jq -c --argjson skip "$STAGES_TO_SKIP_JSON" \
      '[.[] | . as $s | select(any($skip[]; . == $s) | not)]' <<< "$BLOCK_LIST_JSON")
    MISSING_BLOCKED_HAS_APPLY=$(jq -r '[.[] | select(ascii_downcase | startswith("apply"))] | length > 0' <<< "$MISSING_BLOCKED_JSON")
    if [[ "$MISSING_BLOCKED_HAS_APPLY" == "true" && "$APPLY_ENV_ALLOWED" == true ]]; then
      log_detail "BLOCKED: registry contradiction — environment '$ENVIRONMENT' is in applyAllowedEnvironments but stage(s) '$MISSING_BLOCKED' are listed in stages.blocked/alwaysSkipStages and not skipped"
      log_audit "blocked" "Registry contradiction for pipeline $PIPELINE_ID: environment '$ENVIRONMENT' is allowlisted for apply but stage(s) '$MISSING_BLOCKED' are in stages.blocked/terraform.alwaysSkipStages. Block overrides allow. stagesToSkip=$STAGES_TO_SKIP_JSON"
      echo "BLOCKED by pipeline-guard hook: registry contradiction for Terraform pipeline $PIPELINE_ID — environment '$ENVIRONMENT' is in applyAllowedEnvironments, but stage(s) '$MISSING_BLOCKED' are ALSO listed in stages.blocked/terraform.alwaysSkipStages. Block overrides allow: a HUMAN must remove the stage from those lists (and commit) before apply can run. Got stagesToSkip=$STAGES_TO_SKIP_JSON" >&2
      exit 2
    fi
    log_detail "BLOCKED: registry-blocked/always-skip stage(s) not in stagesToSkip: $MISSING_BLOCKED"
    log_audit "blocked" "Terraform pipeline $PIPELINE_ID triggered WITHOUT registry-blocked/always-skip stage(s) '$MISSING_BLOCKED' in stagesToSkip. stagesToSkip=$STAGES_TO_SKIP_JSON"
    echo "BLOCKED by pipeline-guard hook: Terraform pipeline $PIPELINE_ID MUST include registry-blocked/always-skip stage(s) '$MISSING_BLOCKED' in stagesToSkip. Got stagesToSkip=$STAGES_TO_SKIP_JSON" >&2
    exit 2
  fi

  APPLY_NOT_SKIPPED=$(not_skipped "$APPLY_STAGES_JSON")

  # Rule 4: requireManualApproval.
  APPROVAL_REQUIRED=false
  APPROVAL_REASON=""
  if [[ -n "$APPLY_NOT_SKIPPED" ]]; then
    APPROVAL_REQUIRED=true
    APPROVAL_REASON="apply stage(s) '$APPLY_NOT_SKIPPED' would run"
  elif [[ "$IS_KEYCHAIN_TERRAFORM" == true ]]; then
    APPROVAL_REQUIRED=true
    APPROVAL_REASON="keychain-configured terraform pipeline requires it on every run"
  elif [[ "$REGISTRY_DECLARES_APPROVAL" == "true" ]]; then
    APPROVAL_REQUIRED=true
    APPROVAL_REASON="registry terraform.defaultParameters declares requireManualApproval"
  fi

  if [[ "$APPROVAL_REQUIRED" == true && "$MANUAL_APPROVAL" != "True" && "$MANUAL_APPROVAL" != "true" ]]; then
    log_detail "BLOCKED: requireManualApproval is '$MANUAL_APPROVAL' (must be True — $APPROVAL_REASON)"
    log_audit "blocked" "Terraform pipeline $PIPELINE_ID requireManualApproval='$MANUAL_APPROVAL' (must be True — $APPROVAL_REASON)"
    echo "BLOCKED by pipeline-guard hook: Terraform pipeline $PIPELINE_ID MUST have requireManualApproval=True ($APPROVAL_REASON). Got '$MANUAL_APPROVAL'" >&2
    exit 2
  fi
  [[ "$APPROVAL_REQUIRED" == true ]] && log_detail "PASS: requireManualApproval=True"

  # Rule 5: apply stages. Reached only after every block above has passed.
  if [[ -n "$APPLY_NOT_SKIPPED" ]]; then
    if [[ "$APPLY_ENV_ALLOWED" != true ]]; then
      log_detail "BLOCKED: Terraform pipeline missing apply stage(s) '$APPLY_NOT_SKIPPED' in stagesToSkip and environment '$ENVIRONMENT' is not in applyAllowedEnvironments ('$APPLY_ALLOWED_ENVS')"
      log_detail "stagesToSkip was: $STAGES_TO_SKIP_JSON"
      log_audit "blocked" "CRITICAL: Terraform pipeline $PIPELINE_ID triggered WITHOUT apply stage(s) '$APPLY_NOT_SKIPPED' in stagesToSkip for non-allowlisted environment '$ENVIRONMENT'. stagesToSkip=$STAGES_TO_SKIP_JSON"
      echo "BLOCKED by pipeline-guard hook: Terraform pipeline $PIPELINE_ID MUST include apply stage(s) '$APPLY_NOT_SKIPPED' in stagesToSkip for environment '$ENVIRONMENT'. The apply stage is allowed only for environments listed in the registry's terraform.applyAllowedEnvironments: '${APPLY_ALLOWED_ENVS:-<none>}'. Got stagesToSkip=$STAGES_TO_SKIP_JSON" >&2
      exit 2
    fi

    # An allowlisted environment still never gets a destroy run.
    if [[ "$DEPLOY_TOGGLE" != "deploy" ]]; then
      log_detail "BLOCKED: apply stage requested for allowlisted environment '$ENVIRONMENT' but deployToggle is '$DEPLOY_TOGGLE' (must be deploy)"
      log_audit "blocked" "CRITICAL: Terraform apply requested with deployToggle='$DEPLOY_TOGGLE' for environment '$ENVIRONMENT'. Only deployToggle=deploy is permitted."
      echo "BLOCKED by pipeline-guard hook: Terraform pipeline $PIPELINE_ID apply is permitted for environment '$ENVIRONMENT' only with deployToggle=deploy. Got '$DEPLOY_TOGGLE'. Destroy runs are NEVER allowed via AI." >&2
      exit 2
    fi

    log_detail "PASS: apply stage(s) '$APPLY_NOT_SKIPPED' permitted — environment '$ENVIRONMENT' is in applyAllowedEnvironments ('$APPLY_ALLOWED_ENVS'), deployToggle=deploy, requireManualApproval=True"
    log_audit "allowed" "Terraform apply stage(s) '$APPLY_NOT_SKIPPED' permitted for allowlisted environment '$ENVIRONMENT' (deployToggle=deploy, requireManualApproval=True)"
  else
    log_detail "PASS: all apply stage(s) are in stagesToSkip ($APPLY_STAGES_JSON)"
  fi
fi

# ============================================================================
# All checks passed — allow and log
# ============================================================================
log_detail "ALLOWED: All safety checks passed"
log_audit "allowed" "All safety checks passed"
exit 0
