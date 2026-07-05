#!/usr/bin/env bash
# ~/.claude/hooks/destructive-ops-guard.sh
# PreToolUse(Bash) hook: blocks destructive cloud/infra operations and
# blocks file deletion outside a git work tree.
#
# Rule: Only the user may delete persistent state. Agents may not.
# The single allowed exception is file-level deletion INSIDE a git
# work tree (recoverable via reflog/checkout).
#
# Pairs with pipeline-trigger-guard.sh — both register on the same
# PreToolUse(Bash) matcher and run independently.

set -uo pipefail

priority_block_message() {
  local reason="$1"
  local detail="${2:-}"
  cat >&2 <<EOF
[destructive-ops-guard] BLOCKED — ${reason}

==============================================================================
AGENT PRIORITY DIRECTIVE — STOP ALL OTHER WORK
==============================================================================
You MUST report this blockage to the user IMMEDIATELY, as the very next
message, before any other tool call or analysis. Do NOT retry. Do NOT work
around. Do NOT minimise. Do NOT continue with the original task.

State clearly:
  - that destructive-ops-guard blocked a Bash command
  - the reason: ${reason}
  - the command that was attempted (truncated if long)
  - the operative rule: only the user may delete persistent state;
    agents may not. The only exception is file-level deletion INSIDE
    a git work tree.

Then await user direction.
==============================================================================

${detail}
EOF
}

if ! command -v jq >/dev/null 2>&1; then
  priority_block_message "jq not on PATH" \
    "The guard cannot parse hook input without jq and is failing closed for safety. Install jq and retry."
  exit 2
fi

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
jq_exit=$?
if [[ $jq_exit -ne 0 ]]; then
  priority_block_message "could not parse hook input as JSON" \
    "jq exited $jq_exit. Failing closed."
  exit 2
fi

[[ -z "$cmd" ]] && exit 0

# Normalise: collapse whitespace, lowercase for case-insensitive matching.
norm=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ')
lc=$(printf '%s' "$norm" | tr '[:upper:]' '[:lower:]')

block=0
reason=""

# 1) az CLI destructive: any `az ... delete|purge` (covers az group delete,
#    az network ... delete, az storage ... delete, az keyvault delete, etc.)
if [[ "$lc" =~ (^|[[:space:]\;\&\|])az[[:space:]]+[^\;\&\|]*[[:space:]](delete|purge)([[:space:]]|$) ]]; then
  block=1
  reason="az CLI destructive (delete/purge)"
fi

# 2) terraform destructive: destroy, apply -destroy, state rm, workspace delete,
#    workspace select with -force-copy that overwrites, taint, untaint,
#    refresh -destroy.
if [[ $block -eq 0 ]]; then
  if [[ "$lc" =~ (^|[[:space:]\;\&\|])terraform[[:space:]]+destroy([[:space:]]|$) ]] \
     || [[ "$lc" =~ (^|[[:space:]\;\&\|])terraform[[:space:]]+apply[^\;\&\|]*-destroy ]] \
     || [[ "$lc" =~ (^|[[:space:]\;\&\|])terraform[[:space:]]+state[[:space:]]+rm([[:space:]]|$) ]] \
     || [[ "$lc" =~ (^|[[:space:]\;\&\|])terraform[[:space:]]+workspace[[:space:]]+delete([[:space:]]|$) ]] \
     || [[ "$lc" =~ (^|[[:space:]\;\&\|])terraform[[:space:]]+taint([[:space:]]|$) ]]; then
    block=1
    reason="terraform destructive (destroy/state-rm/workspace-delete/taint)"
  fi
fi

# 3) gcloud destructive: any `gcloud ... delete`.
if [[ $block -eq 0 ]]; then
  if [[ "$lc" =~ (^|[[:space:]\;\&\|])gcloud[[:space:]]+[^\;\&\|]*[[:space:]]delete([[:space:]]|$) ]]; then
    block=1
    reason="gcloud destructive (delete)"
  fi
fi

# 4) aws destructive: delete-* subcommands, s3 rm, s3api delete-*.
if [[ $block -eq 0 ]]; then
  if [[ "$lc" =~ (^|[[:space:]\;\&\|])aws[[:space:]]+[^\;\&\|]*[[:space:]]delete-[a-z-]+ ]] \
     || [[ "$lc" =~ (^|[[:space:]\;\&\|])aws[[:space:]]+s3[[:space:]]+rm([[:space:]]|$) ]] \
     || [[ "$lc" =~ (^|[[:space:]\;\&\|])aws[[:space:]]+s3api[[:space:]]+delete-[a-z-]+ ]]; then
    block=1
    reason="aws destructive (delete-*/s3 rm)"
  fi
fi

# 5) kubectl destructive.
if [[ $block -eq 0 ]]; then
  if [[ "$lc" =~ (^|[[:space:]\;\&\|])kubectl[[:space:]]+delete([[:space:]]|$) ]]; then
    block=1
    reason="kubectl delete"
  fi
fi

# 6) docker destructive removals/prunes.
if [[ $block -eq 0 ]]; then
  if [[ "$lc" =~ (^|[[:space:]\;\&\|])docker[[:space:]]+(rm|rmi)([[:space:]]|$) ]] \
     || [[ "$lc" =~ (^|[[:space:]\;\&\|])docker[[:space:]]+(image|container|volume|network|system|builder)[[:space:]]+(rm|prune)([[:space:]]|$) ]]; then
    block=1
    reason="docker destructive (rm/rmi/prune)"
  fi
fi

# 7) gh destructive subcommands.
if [[ $block -eq 0 ]]; then
  if [[ "$lc" =~ (^|[[:space:]\;\&\|])gh[[:space:]]+(repo|release|issue|pr|workflow|run|gist|secret|cache|extension|label|variable|ssh-key|gpg-key)[[:space:]]+delete([[:space:]]|$) ]]; then
    block=1
    reason="gh destructive (delete subcommand)"
  fi
  # gh api with -X DELETE
  if [[ $block -eq 0 ]] && [[ "$lc" =~ (^|[[:space:]\;\&\|])gh[[:space:]]+api ]] \
     && [[ "$lc" =~ (-x[[:space:]]+delete|--method[[:space:]]+delete) ]]; then
    block=1
    reason="gh api -X DELETE"
  fi
fi

# 8) helm destructive.
if [[ $block -eq 0 ]]; then
  if [[ "$lc" =~ (^|[[:space:]\;\&\|])helm[[:space:]]+(uninstall|delete)([[:space:]]|$) ]]; then
    block=1
    reason="helm uninstall/delete"
  fi
fi

# 9) curl/wget destructive HTTP methods (X DELETE) against remote APIs.
if [[ $block -eq 0 ]]; then
  if [[ "$lc" =~ (^|[[:space:]\;\&\|])curl[[:space:]] ]] \
     && [[ "$lc" =~ (-x[[:space:]]+delete|--request[[:space:]]+delete) ]]; then
    block=1
    reason="curl -X DELETE"
  fi
fi

# 10) File-deletion outside a git work tree.
#     `rm`, `rmdir`, `find ... -delete`. Allowed only if the agent's CWD is
#     inside a git work tree (recoverable via reflog/checkout). Heuristic, not
#     perfect — `rm /tmp/foo` from inside a repo passes this gate, but the
#     primary protection is cloud-infra blocking above.
if [[ $block -eq 0 ]]; then
  is_rm=0
  if [[ "$lc" =~ (^|[[:space:]\;\&\|])(rm|rmdir|unlink)([[:space:]]|$) ]]; then
    is_rm=1
  elif [[ "$lc" =~ (^|[[:space:]\;\&\|])find[[:space:]] ]] && [[ "$lc" =~ -delete([[:space:]]|$) ]]; then
    is_rm=1
  fi

  if [[ $is_rm -eq 1 ]]; then
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      block=1
      reason="file deletion outside a git work tree"
    fi
  fi
fi

if [[ $block -eq 1 ]]; then
  priority_block_message "$reason" \
    "Operative rule: only the user may delete persistent state. Agents may not.
The single exception is file-level deletion INSIDE a git work tree.

If you genuinely need this action, surface it to the user with:
  - what you want to delete and why
  - what would be lost (irrecoverable vs recoverable)
  - what alternative you tried first (importing into terraform with
    \`lifecycle { ignore_changes = all }\`, archiving, ignoring, etc.)

Then let the user execute the deletion themselves.

Command attempted (truncated):
$(printf '%.300s' "$cmd")"
  exit 2
fi

exit 0
