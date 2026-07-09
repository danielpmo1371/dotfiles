#!/bin/bash

# Test harness for the AZDO pipeline PreToolUse hooks:
#   config/claude/hooks/pipeline-guard.sh
#   config/claude/hooks/pipeline-trigger-guard.sh
#   config/claude/hooks/pipeline-registry-write-guard.sh
# Usage: ./tests/test-pipeline-hooks.sh
#
# Each hook is a black box: hook payload JSON on stdin, exit 0 = allow,
# exit 2 = block. pipeline-guard discovers the registry by walking up from
# CWD and logs under $HOME, so its cases run in throwaway git workspaces
# with an overridden HOME. The other two hooks are pure functions of stdin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$DOTFILES_ROOT/config/claude/hooks"
PIPELINE_GUARD="$HOOKS_DIR/pipeline-guard.sh"
TRIGGER_GUARD="$HOOKS_DIR/pipeline-trigger-guard.sh"
WRITE_GUARD="$HOOKS_DIR/pipeline-registry-write-guard.sh"

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME"

# Workspace with a committed registry (pipeline-guard only trusts the
# committed state — pinned below).
WS="$TMP/ws"
mkdir -p "$WS/.claude"
cat > "$WS/.claude/pipeline-registry.json" << 'EOF'
{
  "organization": "test-org",
  "services": {
    "svc": {
      "project": "Test Project",
      "ci": { "id": 100, "name": "svc-ci" },
      "cd": { "id": 900, "name": "svc-cd" },
      "stages": {
        "all": ["Shared_SIT", "Shared_UAT", "Shared_Zone"],
        "allowed": ["Shared_SIT", "Shared_UAT"],
        "blocked": ["Shared_Zone"]
      }
    },
    "iac": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": { "id": 802, "name": "Test - Terraform" },
      "stages": {
        "all": ["plan_travellerdirectives", "apply_travellerdirectives"],
        "allowed": ["plan_travellerdirectives"],
        "blocked": ["apply_travellerdirectives"]
      }
    }
  }
}
EOF
git -C "$WS" init -q
git -C "$WS" add .claude/pipeline-registry.json
git -C "$WS" -c user.email=test@test -c user.name=test commit -qm "registry" >/dev/null

# Workspace with the same registry, committed then locally modified
WS_DIRTY="$TMP/dirty"
mkdir -p "$WS_DIRTY/.claude"
cp "$WS/.claude/pipeline-registry.json" "$WS_DIRTY/.claude/"
git -C "$WS_DIRTY" init -q
git -C "$WS_DIRTY" add .claude/pipeline-registry.json
git -C "$WS_DIRTY" -c user.email=test@test -c user.name=test commit -qm "registry" >/dev/null
printf '\n' >> "$WS_DIRTY/.claude/pipeline-registry.json"

# Workspace with no registry in its ancestry
WS_BARE="$TMP/bare"
mkdir -p "$WS_BARE"

# run_hook <hook> <workspace-dir> <input-json>
# Sets RC. Never trips set -e.
run_hook() {
    local hook="$1" ws="$2" json="$3"
    set +e
    (cd "$ws" && HOME="$FAKE_HOME" "$hook" <<< "$json" >/dev/null 2>&1)
    RC=$?
    set -e
}

# expect <allow|block> <hook> <workspace> <label> <json>
expect() {
    local want="$1" hook="$2" ws="$3" label="$4" json="$5"
    run_hook "$hook" "$ws" "$json"
    local want_rc=0
    [[ "$want" == "block" ]] && want_rc=2
    if [[ $RC -eq $want_rc ]]; then
        echo -e "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label — expected rc=$want_rc ($want), got rc=$RC"
        FAIL=$((FAIL + 1))
    fi
}

mcp_input() {
    printf '{"tool_name":"mcp__azure-devops__pipelines_run_pipeline","tool_input":%s}' "$1"
}
bash_input() {
    jq -nc --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

echo -e "${BLUE}=== pipeline-guard.sh (MCP trigger chokepoint) ===${NC}"
expect allow "$PIPELINE_GUARD" "$WS" "unrelated tool passes through" \
    '{"tool_name":"mcp__azure-devops__pipelines_get_builds","tool_input":{}}'
expect block "$PIPELINE_GUARD" "$WS" "unregistered pipeline ID blocked" \
    "$(mcp_input '{"pipelineId":555,"project":"P"}')"
expect block "$PIPELINE_GUARD" "$WS" "CD with empty stagesToSkip blocked (all stages would run)" \
    "$(mcp_input '{"pipelineId":900,"project":"P","stagesToSkip":[]}')"
expect block "$PIPELINE_GUARD" "$WS" "CD missing a registry-blocked stage in stagesToSkip" \
    "$(mcp_input '{"pipelineId":900,"project":"P","stagesToSkip":["Shared_UAT"]}')"
expect allow "$PIPELINE_GUARD" "$WS" "CD skipping all blocked stages allowed" \
    "$(mcp_input '{"pipelineId":900,"project":"P","stagesToSkip":["Shared_Zone","Shared_UAT"]}')"
expect block "$PIPELINE_GUARD" "$WS" "parameter referencing blocked environment (env=prd)" \
    "$(mcp_input '{"pipelineId":100,"project":"P","templateParameters":{"environment":"prd"}}')"
expect block "$PIPELINE_GUARD" "$WS" "terraform 802 without apply stage in stagesToSkip" \
    "$(mcp_input '{"pipelineId":802,"project":"P","stagesToSkip":["something_else"],"templateParameters":{"requireManualApproval":"True"}}')"
expect block "$PIPELINE_GUARD" "$WS" "terraform 802 without requireManualApproval=True" \
    "$(mcp_input '{"pipelineId":802,"project":"P","stagesToSkip":["apply_travellerdirectives"]}')"
expect allow "$PIPELINE_GUARD" "$WS" "terraform 802 plan-only with manual approval allowed" \
    "$(mcp_input '{"pipelineId":802,"project":"P","stagesToSkip":["apply_travellerdirectives"],"templateParameters":{"requireManualApproval":"True"}}')"
expect block "$PIPELINE_GUARD" "$WS_DIRTY" "registry with uncommitted changes fails closed" \
    "$(mcp_input '{"pipelineId":900,"project":"P","stagesToSkip":["Shared_Zone"]}')"
# Pins CURRENT behavior: without a registry, checks 0-2 are skipped and only
# the parameter grep + terraform-802 checks stand. Known weakness, documented.
expect allow "$PIPELINE_GUARD" "$WS_BARE" "no registry: registry checks skipped (current behavior)" \
    "$(mcp_input '{"pipelineId":900,"project":"P","stagesToSkip":[]}')"

echo -e "${BLUE}=== pipeline-trigger-guard.sh (Bash trigger chokepoint) ===${NC}"
expect block "$TRIGGER_GUARD" "$WS_BARE" "az pipelines run blocked" \
    "$(bash_input 'az pipelines run --id 5 --org https://dev.azure.com/o')"
expect block "$TRIGGER_GUARD" "$WS_BARE" "az pipelines build queue blocked" \
    "$(bash_input 'az pipelines build queue --definition-id 5')"
expect allow "$TRIGGER_GUARD" "$WS_BARE" "az pipelines runs list (read) allowed" \
    "$(bash_input 'az pipelines runs list --org https://dev.azure.com/o --project P')"
expect block "$TRIGGER_GUARD" "$WS_BARE" "curl POST to build trigger endpoint blocked" \
    "$(bash_input 'curl -X POST https://dev.azure.com/o/P/_apis/build/builds?api-version=7.1 -d "{}"')"
expect allow "$TRIGGER_GUARD" "$WS_BARE" "curl GET to build endpoint (read) allowed" \
    "$(bash_input 'curl https://dev.azure.com/o/P/_apis/build/builds?api-version=7.1')"
expect block "$TRIGGER_GUARD" "$WS_BARE" "az rest POST to pipeline runs endpoint blocked" \
    "$(bash_input 'az rest --method post --uri https://dev.azure.com/o/P/_apis/pipelines/5/runs')"
expect block "$TRIGGER_GUARD" "$WS_BARE" "gh workflow run blocked" \
    "$(bash_input 'gh workflow run deploy.yml')"
expect allow "$TRIGGER_GUARD" "$WS_BARE" "unrelated command allowed" \
    "$(bash_input 'ls -la')"
expect block "$TRIGGER_GUARD" "$WS_BARE" "unparseable payload fails closed" 'not json'

echo -e "${BLUE}=== pipeline-registry-write-guard.sh (registry mutation chokepoint) ===${NC}"
expect block "$WRITE_GUARD" "$WS_BARE" "Edit targeting the registry blocked" \
    '{"tool_name":"Edit","tool_input":{"file_path":"/x/.claude/pipeline-registry.json","old_string":"a","new_string":"b"}}'
expect block "$WRITE_GUARD" "$WS_BARE" "Write targeting the registry blocked" \
    '{"tool_name":"Write","tool_input":{"file_path":"/x/.claude/pipeline-registry.json","content":"{}"}}'
expect allow "$WRITE_GUARD" "$WS_BARE" "Edit of an unrelated file allowed" \
    '{"tool_name":"Edit","tool_input":{"file_path":"/x/notes.md","old_string":"a","new_string":"b"}}'
expect allow "$WRITE_GUARD" "$WS_BARE" "Bash read via jq allowed (incl. 2>/dev/null)" \
    "$(bash_input 'jq . .claude/pipeline-registry.json 2>/dev/null')"
expect allow "$WRITE_GUARD" "$WS_BARE" "Bash read via cat allowed" \
    "$(bash_input 'cat .claude/pipeline-registry.json')"
expect block "$WRITE_GUARD" "$WS_BARE" "Bash redirect into the registry blocked" \
    "$(bash_input 'echo {} > .claude/pipeline-registry.json')"
expect block "$WRITE_GUARD" "$WS_BARE" "Bash tee into the registry blocked" \
    "$(bash_input 'echo {} | tee .claude/pipeline-registry.json')"
expect block "$WRITE_GUARD" "$WS_BARE" "Bash sed -i on the registry blocked" \
    "$(bash_input "sed -i '' 's/a/b/' .claude/pipeline-registry.json")"
expect block "$WRITE_GUARD" "$WS_BARE" "Bash mv over the registry blocked" \
    "$(bash_input 'mv /tmp/new.json .claude/pipeline-registry.json')"
expect allow "$WRITE_GUARD" "$WS_BARE" "unrelated Bash command allowed" \
    "$(bash_input 'git status')"
expect block "$WRITE_GUARD" "$WS_BARE" "payload without tool_name fails closed" \
    '{"tool_input":{}}'
expect block "$WRITE_GUARD" "$WS_BARE" "unparseable payload fails closed" 'not json'

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}"
[[ $FAIL -eq 0 ]]
