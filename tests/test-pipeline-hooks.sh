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
        "all": ["plan_infra", "apply_infra"],
        "allowed": ["plan_infra"],
        "blocked": ["apply_infra"]
      }
    },
    "iac-allow": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": {
        "id": 803,
        "name": "Test - Terraform (dev apply allowlisted)",
        "applyAllowedEnvironments": ["dev"]
      },
      "stages": {
        "all": ["plan_allow", "apply_allow", "destroy_allow"],
        "allowed": ["plan_allow"],
        "blocked": ["destroy_allow"]
      }
    },
    "iac-other": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": {
        "id": 810,
        "name": "Test - Terraform (registry-only, no allowlist)",
        "defaultParameters": { "deployToggle": "plan" }
      },
      "stages": {
        "all": ["plan_other", "apply_other", "destroy_other"],
        "allowed": ["plan_other"],
        "blocked": ["apply_other", "destroy_other"]
      }
    },
    "iac-other-allow": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": {
        "id": 811,
        "name": "Test - Terraform (registry-only, dev apply allowlisted)",
        "applyAllowedEnvironments": ["dev"],
        "defaultParameters": { "deployToggle": "plan", "requireManualApproval": "True" }
      },
      "stages": {
        "all": ["plan_oa", "apply_oa", "destroy_oa", "cleanup_oa"],
        "allowed": ["plan_oa"],
        "blocked": ["destroy_oa", "cleanup_oa"]
      }
    },
    "iac-contradict": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": {
        "id": 813,
        "name": "Test - Terraform (allowlists dev but still blocks/always-skips apply)",
        "applyAllowedEnvironments": ["dev"],
        "alwaysSkipStages": ["apply_ct", "cleanup_ct"]
      },
      "stages": {
        "all": ["plan_ct", "apply_ct", "destroy_ct", "cleanup_ct"],
        "allowed": ["plan_ct"],
        "blocked": ["apply_ct", "destroy_ct"]
      }
    },
    "iac-noapply": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": { "id": 812, "name": "Test - Terraform (no apply stage registered)" },
      "stages": {
        "all": ["plan_na", "review_na"],
        "allowed": ["plan_na"],
        "blocked": []
      }
    },
    "iac-dup-a": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": { "id": 814, "name": "Test - Terraform (duplicate id, copy A)" },
      "stages": { "all": ["plan_da", "apply_da"], "allowed": ["plan_da"], "blocked": ["apply_da"] }
    },
    "iac-dup-b": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": { "id": 814, "name": "Test - Terraform (duplicate id, copy B)" },
      "stages": { "all": ["plan_db", "apply_db"], "allowed": ["plan_db"], "blocked": ["apply_db"] }
    },
    "iac-bad-all": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": { "id": 815, "name": "Test - Terraform (malformed: stages.all is a string)" },
      "stages": { "all": "plan_ba,apply_ba", "allowed": ["plan_ba"], "blocked": ["apply_ba"] }
    },
    "iac-bad-defaults": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": {
        "id": 816,
        "name": "Test - Terraform (malformed: defaultParameters is an array)",
        "defaultParameters": ["deployToggle", "plan"]
      },
      "stages": { "all": ["plan_bd", "apply_bd"], "allowed": ["plan_bd"], "blocked": [] }
    },
    "iac-csv-allow": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": {
        "id": 817,
        "name": "Test - Terraform (allowlist entry is one CSV string, not two envs)",
        "applyAllowedEnvironments": ["dev,sit"]
      },
      "stages": { "all": ["plan_csv", "apply_csv"], "allowed": ["plan_csv"], "blocked": [] }
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
#
# pipeline-guard.sh fails closed unless PIPELINE_GUARD_TERRAFORM_ID/
# PIPELINE_GUARD_TERRAFORM_APPLY_STAGE are set (see that file's header) — this
# harness supplies test-fixture values matching the "iac" service above so
# the rest of the suite exercises the intended logic, not the unconfigured
# fail-closed path. That path gets its own dedicated test below.
#
# TF_ID / TF_APPLY_STAGE may be set on a call (e.g. `TF_ID=803 expect ...`)
# to point pipeline-guard's Check 4 at a different registered terraform
# pipeline — used by the apply-allowlist cases against "iac-allow" below.
run_hook() {
    local hook="$1" ws="$2" json="$3"
    set +e
    (cd "$ws" && HOME="$FAKE_HOME" \
        PIPELINE_GUARD_TERRAFORM_ID="${TF_ID:-802}" \
        PIPELINE_GUARD_TERRAFORM_APPLY_STAGE="${TF_APPLY_STAGE:-apply_infra}" \
        "$hook" <<< "$json" >/dev/null 2>&1)
    RC=$?
    set -e
}

# Same as run_hook but with the terraform env vars explicitly unset —
# exercises pipeline-guard's fail-closed-when-unconfigured path.
run_hook_unconfigured() {
    local hook="$1" ws="$2" json="$3"
    set +e
    (cd "$ws" && HOME="$FAKE_HOME" env -u PIPELINE_GUARD_TERRAFORM_ID -u PIPELINE_GUARD_TERRAFORM_APPLY_STAGE \
        "$hook" <<< "$json" >/dev/null 2>&1)
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

# Same as expect, but via run_hook_unconfigured (terraform env vars unset)
expect_unconfigured() {
    local want="$1" hook="$2" ws="$3" label="$4" json="$5"
    run_hook_unconfigured "$hook" "$ws" "$json"
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

# expect_block_stderr <hook> <workspace> <label> <json> <stderr-regex>
# Like `expect block`, but ALSO requires the hook's own "BLOCKED by
# pipeline-guard hook" line on stderr, matching the regex. An rc=2 produced by
# a bash error would otherwise be indistinguishable from a deliberate block,
# and these cases exist precisely to prove the hook fails CLOSED (rc=2, never
# jq's rc=5) on malformed payloads and registries.
expect_block_stderr() {
    local hook="$1" ws="$2" label="$3" json="$4" pattern="$5"
    local err
    set +e
    err=$(cd "$ws" && HOME="$FAKE_HOME" \
        PIPELINE_GUARD_TERRAFORM_ID="${TF_ID:-802}" \
        PIPELINE_GUARD_TERRAFORM_APPLY_STAGE="${TF_APPLY_STAGE:-apply_infra}" \
        "$hook" <<< "$json" 2>&1 >/dev/null)
    RC=$?
    set -e
    if [[ $RC -eq 2 && "$err" == *"BLOCKED by pipeline-guard hook"* && "$err" =~ $pattern ]]; then
        echo -e "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label — expected rc=2 with stderr matching /$pattern/, got rc=$RC stderr: ${err:0:200}"
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
    "$(mcp_input '{"pipelineId":802,"project":"P","stagesToSkip":["apply_infra"]}')"
expect allow "$PIPELINE_GUARD" "$WS" "terraform 802 plan-only with manual approval allowed" \
    "$(mcp_input '{"pipelineId":802,"project":"P","stagesToSkip":["apply_infra"],"templateParameters":{"requireManualApproval":"True"}}')"
# Registry without terraform.applyAllowedEnvironments: apply is never
# reachable, whatever the environment — the key's absence fails closed.
expect block "$PIPELINE_GUARD" "$WS" "terraform 802 (no applyAllowedEnvironments key) apply for env=dev blocked" \
    "$(mcp_input '{"pipelineId":802,"project":"P","stagesToSkip":[],"templateParameters":{"environment":"dev","deployToggle":"deploy","requireManualApproval":"True"}}')"

echo -e "${BLUE}=== pipeline-guard.sh (terraform apply allowlist, registry terraform.applyAllowedEnvironments) ===${NC}"
# Pipeline 803 / service "iac-allow" lists ["dev"]. Apply is reachable ONLY
# for that environment AND only with deployToggle=deploy (exact) AND
# requireManualApproval=True. Everything else stays plan-only or blocked.
TF_ID=803 TF_APPLY_STAGE=apply_allow expect allow "$PIPELINE_GUARD" "$WS" "allowlisted env=dev: apply stage not skipped, deploy + manual approval -> allowed" \
    "$(mcp_input '{"pipelineId":803,"project":"P","stagesToSkip":["destroy_allow"],"templateParameters":{"environment":"dev","deployToggle":"deploy","requireManualApproval":"True"}}')"
TF_ID=803 TF_APPLY_STAGE=apply_allow expect allow "$PIPELINE_GUARD" "$WS" "allowlisted env matched case-insensitively (env=DEV)" \
    "$(mcp_input '{"pipelineId":803,"project":"P","stagesToSkip":["destroy_allow"],"templateParameters":{"environment":"DEV","deployToggle":"deploy","requireManualApproval":"True"}}')"
TF_ID=803 TF_APPLY_STAGE=apply_allow expect allow "$PIPELINE_GUARD" "$WS" "allowlisted env=dev with apply IN stagesToSkip (plan-only) still allowed" \
    "$(mcp_input '{"pipelineId":803,"project":"P","stagesToSkip":["apply_allow","destroy_allow"],"templateParameters":{"environment":"dev","deployToggle":"deploy","requireManualApproval":"True"}}')"
TF_ID=803 TF_APPLY_STAGE=apply_allow expect block "$PIPELINE_GUARD" "$WS" "non-allowlisted env=sit: apply stage not skipped -> blocked" \
    "$(mcp_input '{"pipelineId":803,"project":"P","stagesToSkip":["destroy_allow"],"templateParameters":{"environment":"sit","deployToggle":"deploy","requireManualApproval":"True"}}')"
TF_ID=803 TF_APPLY_STAGE=apply_allow expect block "$PIPELINE_GUARD" "$WS" "allowlisted env=dev but deployToggle=destroy -> blocked" \
    "$(mcp_input '{"pipelineId":803,"project":"P","stagesToSkip":["destroy_allow"],"templateParameters":{"environment":"dev","deployToggle":"destroy","requireManualApproval":"True"}}')"
TF_ID=803 TF_APPLY_STAGE=apply_allow expect block "$PIPELINE_GUARD" "$WS" "allowlisted env=dev but deployToggle=Deploy (exact match required) -> blocked" \
    "$(mcp_input '{"pipelineId":803,"project":"P","stagesToSkip":["destroy_allow"],"templateParameters":{"environment":"dev","deployToggle":"Deploy","requireManualApproval":"True"}}')"
TF_ID=803 TF_APPLY_STAGE=apply_allow expect block "$PIPELINE_GUARD" "$WS" "allowlisted env=dev but requireManualApproval=false -> blocked" \
    "$(mcp_input '{"pipelineId":803,"project":"P","stagesToSkip":["destroy_allow"],"templateParameters":{"environment":"dev","deployToggle":"deploy","requireManualApproval":"false"}}')"
TF_ID=803 TF_APPLY_STAGE=apply_allow expect block "$PIPELINE_GUARD" "$WS" "allowlisted pipeline but no templateParameters.environment -> blocked" \
    "$(mcp_input '{"pipelineId":803,"project":"P","stagesToSkip":["destroy_allow"],"templateParameters":{"deployToggle":"deploy","requireManualApproval":"True"}}')"
TF_ID=803 TF_APPLY_STAGE=apply_allow expect block "$PIPELINE_GUARD" "$WS" "allowlisted pipeline, env=prd apply -> still blocked by the hardcoded env blocklist" \
    "$(mcp_input '{"pipelineId":803,"project":"P","stagesToSkip":["destroy_allow"],"templateParameters":{"environment":"prd","deployToggle":"deploy","requireManualApproval":"True"}}')"
echo -e "${BLUE}=== pipeline-guard.sh (terraform detected via registry terraform.id, not the keychain id) ===${NC}"
# Pipelines 810/811/812 are registered as terraform but are NOT
# PIPELINE_GUARD_TERRAFORM_ID (802 here). Check 4 must still cover them.
# Block always overrides allow: destroy* and non-apply blocked stages must be
# skipped even for an allowlisted environment.
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 810: empty stagesToSkip + deployToggle=deploy -> blocked (apply would run)" \
    "$(mcp_input '{"pipelineId":810,"project":"P","stagesToSkip":[],"templateParameters":{"environment":"dev","deployToggle":"deploy"}}')"
expect allow "$PIPELINE_GUARD" "$WS" "registry terraform 810: apply + destroy skipped, no requireManualApproval (param not declared) -> allowed plan-only" \
    "$(mcp_input '{"pipelineId":810,"project":"P","stagesToSkip":["apply_other","destroy_other"],"templateParameters":{"environment":"dev","deployToggle":"plan"}}')"
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 810: apply skipped but destroy NOT skipped -> blocked" \
    "$(mcp_input '{"pipelineId":810,"project":"P","stagesToSkip":["apply_other"],"templateParameters":{"environment":"dev","deployToggle":"plan"}}')"
expect allow "$PIPELINE_GUARD" "$WS" "registry terraform 811 allowlisted env=dev: apply runs, destroy + blocked skipped, deploy + approval -> allowed" \
    "$(mcp_input '{"pipelineId":811,"project":"P","stagesToSkip":["destroy_oa","cleanup_oa"],"templateParameters":{"environment":"dev","deployToggle":"deploy","requireManualApproval":"True"}}')"
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 811 allowlisted env=dev but destroy NOT skipped -> blocked (block overrides allow)" \
    "$(mcp_input '{"pipelineId":811,"project":"P","stagesToSkip":["cleanup_oa"],"templateParameters":{"environment":"dev","deployToggle":"deploy","requireManualApproval":"True"}}')"
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 811 allowlisted env=dev but non-apply blocked stage NOT skipped -> blocked (block overrides allow)" \
    "$(mcp_input '{"pipelineId":811,"project":"P","stagesToSkip":["destroy_oa"],"templateParameters":{"environment":"dev","deployToggle":"deploy","requireManualApproval":"True"}}')"
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 811 plan-only without requireManualApproval -> blocked (registry declares the param)" \
    "$(mcp_input '{"pipelineId":811,"project":"P","stagesToSkip":["apply_oa","destroy_oa","cleanup_oa"],"templateParameters":{"environment":"dev","deployToggle":"plan"}}')"
expect allow "$PIPELINE_GUARD" "$WS" "registry terraform 811 plan-only with requireManualApproval -> allowed" \
    "$(mcp_input '{"pipelineId":811,"project":"P","stagesToSkip":["apply_oa","destroy_oa","cleanup_oa"],"templateParameters":{"environment":"dev","deployToggle":"plan","requireManualApproval":"True"}}')"
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 811 non-allowlisted env=sit: apply not skipped -> blocked" \
    "$(mcp_input '{"pipelineId":811,"project":"P","stagesToSkip":["destroy_oa","cleanup_oa"],"templateParameters":{"environment":"sit","deployToggle":"deploy","requireManualApproval":"True"}}')"
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 811 allowlisted env=dev, apply runs but deployToggle=destroy -> blocked" \
    "$(mcp_input '{"pipelineId":811,"project":"P","stagesToSkip":["destroy_oa","cleanup_oa"],"templateParameters":{"environment":"dev","deployToggle":"destroy","requireManualApproval":"True"}}')"
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 812 with no apply* stage in stages.all -> fails closed" \
    "$(mcp_input '{"pipelineId":812,"project":"P","stagesToSkip":["plan_na","review_na"],"templateParameters":{"environment":"dev","deployToggle":"plan","requireManualApproval":"True"}}')"
# Block overrides allow, NO exceptions: 813 allowlists dev but ALSO lists the
# apply stage in stages.blocked and terraform.alwaysSkipStages. That registry
# contradicts itself -> fail closed until a human removes the stage from those
# lists. Non-apply entries in either list are enforced the same way.
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 813 allowlisted env=dev but apply stage in stages.blocked/alwaysSkipStages -> blocked (registry contradiction)" \
    "$(mcp_input '{"pipelineId":813,"project":"P","stagesToSkip":["destroy_ct","cleanup_ct"],"templateParameters":{"environment":"dev","deployToggle":"deploy","requireManualApproval":"True"}}')"
expect block "$PIPELINE_GUARD" "$WS" "registry terraform 813 allowlisted env=dev, apply skipped but alwaysSkipStages non-apply stage NOT skipped -> blocked" \
    "$(mcp_input '{"pipelineId":813,"project":"P","stagesToSkip":["apply_ct","destroy_ct"],"templateParameters":{"environment":"dev","deployToggle":"deploy","requireManualApproval":"True"}}')"
expect allow "$PIPELINE_GUARD" "$WS" "registry terraform 813 plan-only with every blocked/always-skip stage skipped -> allowed" \
    "$(mcp_input '{"pipelineId":813,"project":"P","stagesToSkip":["apply_ct","destroy_ct","cleanup_ct"],"templateParameters":{"environment":"dev","deployToggle":"plan","requireManualApproval":"True"}}')"

echo -e "${BLUE}=== pipeline-guard.sh (fails CLOSED on malformed payloads and registries) ===${NC}"
# Claude Code blocks ONLY on exit 2 — any other non-zero exit lets the tool
# call proceed. So a jq crash (rc=5) on a wrong-typed field used to be a
# fail-OPEN. Every case here must be rc=2 WITH the hook's own BLOCKED line.
expect_block_stderr "$PIPELINE_GUARD" "$WS" "templateParameters as a string -> rc=2 (not jq's rc=5)" \
    "$(mcp_input '{"pipelineId":802,"project":"P","stagesToSkip":["apply_infra"],"templateParameters":"x"}')" \
    "templateParameters must be an object"
expect_block_stderr "$PIPELINE_GUARD" "$WS" "stagesToSkip as a string -> rc=2" \
    "$(mcp_input '{"pipelineId":900,"project":"P","stagesToSkip":"Shared_Zone"}')" \
    "stagesToSkip must be an array"
expect_block_stderr "$PIPELINE_GUARD" "$WS" "tool_input as a string -> rc=2" \
    "$(mcp_input '"just a string"')" \
    "tool_input must be an object"
expect_block_stderr "$PIPELINE_GUARD" "$WS" "unparseable payload -> rc=2 via the ERR trap" \
    'not json' \
    "internal error"
expect_block_stderr "$PIPELINE_GUARD" "$WS" "pipelineId missing -> rc=2 (used to skip every check)" \
    "$(mcp_input '{"project":"P","stagesToSkip":[]}')" \
    "pipelineId missing or not numeric"
expect_block_stderr "$PIPELINE_GUARD" "$WS" "pipelineId null -> rc=2" \
    "$(mcp_input '{"pipelineId":null,"project":"P","stagesToSkip":[]}')" \
    "pipelineId missing or not numeric"
expect_block_stderr "$PIPELINE_GUARD" "$WS" "duplicate terraform.id across two registry services -> rc=2 ambiguous" \
    "$(mcp_input '{"pipelineId":814,"project":"P","stagesToSkip":["apply_da","apply_db"],"templateParameters":{"environment":"dev","deployToggle":"plan"}}')" \
    "ambiguous registry.*iac-dup-a, iac-dup-b"
expect_block_stderr "$PIPELINE_GUARD" "$WS" "applyAllowedEnvironments [\"dev,sit\"] does NOT allowlist sit -> apply blocked" \
    "$(mcp_input '{"pipelineId":817,"project":"P","stagesToSkip":[],"templateParameters":{"environment":"sit","deployToggle":"deploy","requireManualApproval":"True"}}')" \
    "MUST include apply stage.*apply_csv.*for environment 'sit'"
expect_block_stderr "$PIPELINE_GUARD" "$WS" "registry stages.all as a string -> rc=2 malformed registry" \
    "$(mcp_input '{"pipelineId":815,"project":"P","stagesToSkip":["apply_ba"],"templateParameters":{"environment":"dev","deployToggle":"plan"}}')" \
    "stages.all must be an array of strings"
expect_block_stderr "$PIPELINE_GUARD" "$WS" "registry terraform.defaultParameters as an array -> rc=2 malformed registry" \
    "$(mcp_input '{"pipelineId":816,"project":"P","stagesToSkip":["apply_bd"],"templateParameters":{"environment":"dev","deployToggle":"plan"}}')" \
    "defaultParameters must be an object"
expect block "$PIPELINE_GUARD" "$WS_DIRTY" "registry with uncommitted changes fails closed" \
    "$(mcp_input '{"pipelineId":900,"project":"P","stagesToSkip":["Shared_Zone"]}')"
# Pins CURRENT behavior: without a registry, checks 0-2 are skipped and only
# the parameter grep + terraform checks stand. Known weakness, documented.
expect allow "$PIPELINE_GUARD" "$WS_BARE" "no registry: registry checks skipped (current behavior)" \
    "$(mcp_input '{"pipelineId":900,"project":"P","stagesToSkip":[]}')"
expect_unconfigured block "$PIPELINE_GUARD" "$WS" "unconfigured (no PIPELINE_GUARD_TERRAFORM_ID/STAGE): fails closed, blocks even a harmless CI id" \
    "$(mcp_input '{"pipelineId":100,"project":"P"}')"

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
