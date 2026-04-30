#!/usr/bin/env bash
# ~/.claude/hooks/pipeline-trigger-guard.sh
# PreToolUse(Bash) hook: blocks attempts to trigger AZDO pipelines outside
# the documented MCP path (mcp__azure-devops__pipelines_run_pipeline).
# Layer 1 — deterministic, fast, free.
# Pairs with ~/.claude/hooks/pipeline-guard.sh which guards the MCP path itself.

set -uo pipefail  # no -e: emit our own error messages, never crash silently

priority_block_message() {
  local reason="$1"
  local detail="${2:-}"
  cat >&2 <<EOF
[pipeline-trigger-guard] BLOCKED — ${reason}

==============================================================================
AGENT PRIORITY DIRECTIVE — STOP ALL OTHER WORK
==============================================================================
You MUST report this blockage to the user IMMEDIATELY, as the very next
message, before any other tool call or analysis. Do not retry. Do not work
around. Do not minimise. Do not continue with the original task.

State clearly:
  - that a pipeline-trigger-guard hook blocked a Bash command
  - the reason: ${reason}
  - the command that was attempted (truncated if long)
  - that the documented path is the MCP tool:
      mcp__azure-devops__pipelines_run_pipeline

Then await user direction.
==============================================================================

${detail}
EOF
}

# Guard prerequisite: jq must be present so we can parse hook input.
# Fail closed if absent — we cannot enforce without it.
if ! command -v jq >/dev/null 2>&1; then
  priority_block_message "jq not on PATH" \
    "The guard cannot parse hook input without jq and is failing closed for safety. Install jq (\`brew install jq\` on macOS) and retry."
  exit 2
fi

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
jq_exit=$?
if [[ $jq_exit -ne 0 ]]; then
  priority_block_message "could not parse hook input as JSON" \
    "jq exited $jq_exit. The guard is failing closed for safety. Investigate the harness input shape."
  exit 2
fi

# Empty command: nothing to evaluate. Allow.
[[ -z "$cmd" ]] && exit 0

# Normalise: collapse whitespace, lowercase for case-insensitive matching.
norm=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ')
lc=$(printf '%s' "$norm" | tr '[:upper:]' '[:lower:]')

block=0
reason=""

# 1) curl POST against AZDO build/run endpoints.
#    Triggered by explicit POST verb OR by -d/--data flags (curl defaults to POST with body).
if [[ "$lc" =~ curl ]] \
   && [[ "$lc" =~ dev\.azure\.com ]] \
   && [[ "$lc" =~ (_apis/build/builds|_apis/pipelines/[^[:space:]]*/runs) ]]; then
  if [[ "$lc" =~ (-x[[:space:]]+post|--request[[:space:]]+post) ]] \
     || [[ "$lc" =~ ([[:space:]]-d[[:space:]]|--data[[:space:]]|--data-(raw|binary|urlencode)[[:space:]]) ]]; then
    block=1
    reason="curl POST against AZDO pipeline trigger endpoint"
  fi
fi

# 2) az CLI pipeline trigger commands.
#    Match `az pipelines run` (trigger) and `az pipelines build queue` (legacy trigger).
#    Require word boundary after `run` so `az pipelines runs list/show/tag` (READ subgroup)
#    is NOT matched.
if [[ "$lc" =~ az[[:space:]]+pipelines[[:space:]]+run([[:space:]]|$) ]] \
   || [[ "$lc" =~ az[[:space:]]+pipelines[[:space:]]+build[[:space:]]+queue([[:space:]]|$) ]]; then
  block=1
  reason="az pipelines run/build queue"
fi

# 3) az rest POST against the same endpoints.
if [[ "$lc" =~ az[[:space:]]+rest ]] \
   && [[ "$lc" =~ --method[[:space:]]+post ]] \
   && [[ "$lc" =~ dev\.azure\.com ]] \
   && [[ "$lc" =~ (_apis/build/builds|_apis/pipelines/[^[:space:]]*/runs) ]]; then
  block=1
  reason="az rest POST against AZDO pipeline trigger endpoint"
fi

# 4) gh workflow run (forward-compat for any GH Actions wiring).
if [[ "$lc" =~ gh[[:space:]]+workflow[[:space:]]+run ]]; then
  block=1
  reason="gh workflow run"
fi

if [[ "$block" -eq 1 ]]; then
  priority_block_message "$reason" \
    "Use the MCP tool instead:
    mcp__azure-devops__pipelines_run_pipeline

That path goes through pipeline-validator.sh (registry-driven stagesToSkip)
and the audit-logging guard hook. Direct REST / az CLI triggers bypass both.

If this is a read-only op that tripped a false positive, switch to GET or use
the MCP read tools (pipelines_get_run / pipelines_list_runs / *_get_build_log).

Command attempted (truncated):
$(printf '%.200s' "$cmd")"
  exit 2
fi

exit 0
