#!/usr/bin/env bash
# ~/.claude/hooks/pipeline-registry-write-guard.sh
# PreToolUse(Edit|Write|NotebookEdit|Bash) hook: blocks AI mutations of
# .claude/pipeline-registry.json.
#
# The registry is the allow/block authority for pipeline stage safety —
# an agent that can rewrite it can grant itself prod stages. Only a human
# may change it, via a normal reviewed commit (see the pipeline-ops skill's
# REGISTRY.md). Pairs with the committed-registry integrity check in
# pipeline-validator.sh / pipeline-guard.sh, which refuses to trust an
# uncommitted registry even if a write slips past this hook.

set -uo pipefail  # no -e: emit our own error messages, never crash silently

REGISTRY_BASENAME="pipeline-registry.json"

block() {
  cat >&2 <<EOF
[pipeline-registry-write-guard] BLOCKED — $1

$REGISTRY_BASENAME is the allow/block authority for pipeline stage safety.
AI agents must never modify it. Report this to the user and let a HUMAN
edit and commit the file (authoring guide: skills/pipeline-ops/REGISTRY.md).

If you were only READING it, do so without redirects or in-place tools:
  jq '.' .claude/pipeline-registry.json
EOF
  exit 2
}

# Fail closed if we cannot parse hook input at all.
command -v jq >/dev/null 2>&1 \
  && input=$(cat) \
  && tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) \
  || block "cannot inspect tool input (jq missing or unparseable payload)"
[[ -z "$tool" ]] && block "hook payload carries no tool_name"

case "$tool" in
  Edit|Write|NotebookEdit)
    file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
    if [[ "$(basename "${file_path:-/}")" == "$REGISTRY_BASENAME" ]]; then
      block "$tool targeting $file_path"
    fi
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if [[ "$cmd" == *"$REGISTRY_BASENAME"* ]]; then
      # Conservative write detection: any common write/rename/delete
      # indicator alongside a mention of the registry blocks. Harmless
      # redirects to /dev/null and stderr merges are exempted so plain
      # reads (jq/cat with 2>/dev/null) still work; other false positives
      # (e.g. redirecting a read into a temp file) are acceptable — read
      # without redirects instead.
      norm=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ' \
        | sed -E 's/[0-9]*>+[[:space:]]*\/dev\/null//g; s/2>&1//g')
      if [[ "$norm" == *">"* ]] \
         || [[ "$norm" =~ (^|[;&| ])(tee|mv|cp|rm|truncate|dd|install|sponge)[[:space:]] ]] \
         || [[ "$norm" =~ (^|[;&| ])(sed|perl)[[:space:]]+-[a-zA-Z]*i ]]; then
        block "Bash command with write indicators touching $REGISTRY_BASENAME"
      fi
    fi
    ;;
esac

exit 0
