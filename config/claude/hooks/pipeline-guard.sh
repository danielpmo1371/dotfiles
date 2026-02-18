#!/usr/bin/env bash
#
# Pipeline Guard — PreToolUse Hook
#
# Intercepts mcp__azure-devops__pipelines_run_pipeline calls.
# Reads tool input from stdin JSON, validates against hard rules.
# Exit 0 = allow, exit 1 = block (with reason on stdout).
#
# SAFETY: Second line of defense. Even if the validator script is bypassed,
# this hook catches direct MCP calls.

set -euo pipefail

# ============================================================================
# HARD-CODED SAFETY RULES — MIRRORS pipeline-validator.sh
# ============================================================================
BLOCKED_STAGE_PATTERNS=("pre" "prd" "prod" "production")
# ============================================================================

INPUT=$(cat)

# Extract tool name and input from hook payload
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')

# Only process pipeline run calls
if [[ "$TOOL_NAME" != *"pipelines_run_pipeline"* ]]; then
  exit 0
fi

# Parse the MCP tool input
PIPELINE_ID=$(echo "$TOOL_INPUT" | jq -r '.pipelineId // empty' 2>/dev/null)
PROJECT=$(echo "$TOOL_INPUT" | jq -r '.project // empty' 2>/dev/null)
STAGES_TO_SKIP=$(echo "$TOOL_INPUT" | jq -r '.stagesToSkip // [] | .[]' 2>/dev/null)
TEMPLATE_PARAMS=$(echo "$TOOL_INPUT" | jq -r '.templateParameters // {} | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null)
VARIABLES=$(echo "$TOOL_INPUT" | jq -r '.variables // {} | to_entries[] | "\(.key)=\(.value.value // .value)"' 2>/dev/null)

# Check: do any variables or template params reference blocked environments?
ALL_PARAMS="$TEMPLATE_PARAMS $VARIABLES"
ALL_PARAMS_LOWER=$(echo "$ALL_PARAMS" | tr '[:upper:]' '[:lower:]')

# Audit log helper
log_audit() {
  local action="$1"
  local reason="${2:-}"
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local log_dir="$HOME/.claude/logs"
  mkdir -p "$log_dir"
  jq -n --arg ts "$timestamp" --arg pid "$PIPELINE_ID" --arg proj "$PROJECT" \
    --arg action "$action" --arg reason "$reason" \
    '{timestamp:$ts, pipelineId:$pid, project:$proj, action:$action, reason:$reason}' \
    >> "$log_dir/pipeline-triggers.jsonl"
}

for pattern in "${BLOCKED_STAGE_PATTERNS[@]}"; do
  # Check if any parameter values contain blocked env names in deployment context
  if echo "$ALL_PARAMS_LOWER" | grep -qiE "(environment|env|stage|deploy).*=.*${pattern}"; then
    log_audit "blocked" "Parameter references blocked environment '${pattern}'"
    echo "BLOCKED by pipeline-guard hook: Parameter references blocked environment '${pattern}'. PRE/PRD deployments are NEVER allowed via AI."
    exit 1
  fi
done

# Log allowed call and pass through
log_audit "allowed"
exit 0
