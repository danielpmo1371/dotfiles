#!/bin/bash

# Test harness for config/claude/scripts/pipeline-validator.sh
# Usage: ./tests/test-pipeline-validator.sh
#
# The validator is a black box: JSON on stdin, JSON + exit code out,
# registry discovered by walking up from CWD, logs under $HOME. Each case
# runs in a throwaway workspace with a fixture registry (or none) and an
# overridden HOME, so no real state is read or written.
#
# Registry fixtures are committed into throwaway git repos because the
# validator only trusts a registry at its committed state (fails closed
# on untracked/modified/non-repo — pinned below).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
VALIDATOR="$DOTFILES_ROOT/config/claude/scripts/pipeline-validator.sh"

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

# Commit a workspace's registry so the validator's integrity check trusts it.
commit_registry() {
    local ws="$1"
    git -C "$ws" init -q
    git -C "$ws" add .claude/pipeline-registry.json
    git -C "$ws" -c user.email=test@test -c user.name=test commit -qm "registry" >/dev/null
}

# Workspace WITH a fixture registry
WS="$TMP/ws"
mkdir -p "$WS/.claude"
# Workspace WITHOUT any registry in its ancestry (mktemp dirs have none)
WS_BARE="$TMP/bare"
mkdir -p "$WS_BARE"
# Workspace with a malformed (unparseable) registry — committed, so it gets
# past the integrity check and exercises the jq parse failure
WS_BAD="$TMP/bad"
mkdir -p "$WS_BAD/.claude"
echo '{ this is not json' > "$WS_BAD/.claude/pipeline-registry.json"
commit_registry "$WS_BAD"

cat > "$WS/.claude/pipeline-registry.json" << 'EOF'
{
  "organization": "test-org",
  "services": {
    "svc-registry": {
      "project": "Test Project",
      "ci": { "id": 100, "name": "svc-ci" },
      "cd": { "id": 900, "name": "svc-cd" },
      "folder": "svc-registry",
      "stages": {
        "all": ["Shared_SIT", "Shared_UAT", "Shared_Zone", "preae"],
        "allowed": ["Shared_SIT", "Shared_UAT", "preae"],
        "blocked": ["Shared_Zone"]
      }
    },
    "svc-empty-allowed": {
      "project": "Test Project",
      "ci": null,
      "cd": { "id": 901, "name": "svc2-cd" },
      "folder": "svc-empty-allowed",
      "stages": {
        "all": ["apply_foo", "sitae", "dryae"],
        "allowed": [],
        "blocked": ["apply_foo", "sitae"]
      }
    },
    "svc-terraform": {
      "project": "Test Project",
      "ci": null,
      "cd": null,
      "terraform": {
        "id": 950,
        "name": "Test - Terraform",
        "defaultParameters": { "deployToggle": "plan", "TF_LOG": "NONE" },
        "alwaysSkipStages": ["cleanup_stage"],
        "parameters": {
          "environment": { "values": ["dev", "sit"], "allowed": ["dev", "sit"], "blocked": [] },
          "location": { "values": ["ae", "ase"], "default": "ae" }
        }
      },
      "folder": "svc-terraform",
      "stages": {
        "all": ["plan_x", "apply_x"],
        "allowed": ["plan_x"],
        "blocked": ["apply_x"]
      }
    }
  }
}
EOF
commit_registry "$WS"

# Integrity fixtures: same registry content, different git states.
# Committed then locally modified:
WS_DIRTY="$TMP/dirty"
mkdir -p "$WS_DIRTY/.claude"
cp "$WS/.claude/pipeline-registry.json" "$WS_DIRTY/.claude/"
commit_registry "$WS_DIRTY"
printf '\n' >> "$WS_DIRTY/.claude/pipeline-registry.json"
# In a git repo but never committed:
WS_UNTRACKED="$TMP/untracked"
mkdir -p "$WS_UNTRACKED/.claude"
cp "$WS/.claude/pipeline-registry.json" "$WS_UNTRACKED/.claude/"
git -C "$WS_UNTRACKED" init -q
# Outside any git work tree:
WS_NOREPO="$TMP/norepo"
mkdir -p "$WS_NOREPO/.claude"
cp "$WS/.claude/pipeline-registry.json" "$WS_NOREPO/.claude/"

# run <workspace-dir> <input-json>
# Sets OUT and RC. Never trips set -e.
run() {
    local ws="$1" json="$2"
    set +e
    OUT=$(cd "$ws" && HOME="$FAKE_HOME" "$VALIDATOR" <<< "$json" 2>/dev/null)
    RC=$?
    set -e
}

assert_approved() {
    local label="$1" ws="$2" json="$3"
    run "$ws" "$json"
    if [[ $RC -eq 0 && $(jq -r '.approved' <<< "$OUT" 2>/dev/null) == "true" ]]; then
        echo -e "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label — expected approved, got rc=$RC out=$OUT"
        FAIL=$((FAIL + 1))
    fi
}

# assert_blocked <label> <expected-rule> <expected-rc> <workspace> <json>
assert_blocked() {
    local label="$1" rule="$2" want_rc="$3" ws="$4" json="$5"
    run "$ws" "$json"
    local got_rule
    got_rule=$(jq -r '.rule // empty' <<< "$OUT" 2>/dev/null || true)
    if [[ $RC -eq $want_rc && $(jq -r '.approved' <<< "$OUT" 2>/dev/null) == "false" && "$got_rule" == "$rule" ]]; then
        echo -e "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label — expected rc=$want_rc rule=$rule, got rc=$RC out=$OUT"
        FAIL=$((FAIL + 1))
    fi
}

# assert_fail_closed <label> <workspace> <json>
# Only asserts the request is NOT approved (any non-zero rc, any/no output).
assert_fail_closed() {
    local label="$1" ws="$2" json="$3"
    run "$ws" "$json"
    if [[ $RC -ne 0 && $(jq -r '.approved // "false"' <<< "$OUT" 2>/dev/null || echo "false") != "true" ]]; then
        echo -e "  ${GREEN}PASS${NC} $label (rc=$RC)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label — expected fail-closed, got rc=$RC out=$OUT"
        FAIL=$((FAIL + 1))
    fi
}

echo -e "${BLUE}=== Input validation ===${NC}"
assert_blocked "missing branch -> MISSING_FIELD (exit 2)" "MISSING_FIELD" 2 "$WS_BARE" \
    '{"service":"x","type":"cd","stages":["sitae"]}'
assert_blocked "invalid type -> INVALID_TYPE (exit 2)" "INVALID_TYPE" 2 "$WS_BARE" \
    '{"service":"x","type":"release","branch":"develop"}'
assert_blocked "non-numeric pipelineId -> INVALID_PIPELINE_ID (exit 2)" "INVALID_PIPELINE_ID" 2 "$WS_BARE" \
    '{"service":"x","type":"ci","branch":"develop","pipelineId":"12a"}'

echo -e "${BLUE}=== CI ===${NC}"
assert_approved "CI approved on any branch, no stages needed" "$WS_BARE" \
    '{"service":"x","type":"ci","branch":"feature/foo","pipelineId":"100","project":"Test Project"}'
run "$WS_BARE" '{"service":"x","type":"ci","branch":"develop","pipelineId":"100","project":"P"}'
if [[ $(jq -r '.branch' <<< "$OUT") == "refs/heads/develop" ]]; then
    echo -e "  ${GREEN}PASS${NC} CI branch normalized to refs/heads/"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} CI branch normalization — got $OUT"
    FAIL=$((FAIL + 1))
fi

echo -e "${BLUE}=== CD: hardcoded blocklist (layer 1, can never be overridden) ===${NC}"
# 'preae' is in the fixture's registry ALLOWED list — the hardcoded
# substring blocklist must still win. This is the core safety invariant.
assert_blocked "stage 'preae' blocked despite registry allowing it" "ENVIRONMENT_BLOCKLIST" 1 "$WS" \
    '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","stages":["preae"]}'
assert_blocked "stage 'Prodase' blocked by substring match" "ENVIRONMENT_BLOCKLIST" 1 "$WS_BARE" \
    '{"service":"x","type":"cd","branch":"develop","pipelineId":"1","stages":["Prodase"]}'
assert_blocked "CD without stages -> NO_STAGES_SPECIFIED" "NO_STAGES_SPECIFIED" 1 "$WS_BARE" \
    '{"service":"x","type":"cd","branch":"develop","pipelineId":"1"}'

echo -e "${BLUE}=== CD: registry exact-match (layer 2) ===${NC}"
assert_approved "registry-allowed stage approved (prefix rules would reject it)" "$WS" \
    '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","project":"P","stages":["Shared_SIT"]}'
assert_approved "registry match is case-insensitive (shared_uat)" "$WS" \
    '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","project":"P","stages":["shared_uat"]}'
assert_blocked "registry-blocked prod stage without pre/prd substring" "ENVIRONMENT_BLOCKLIST" 1 "$WS" \
    '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","stages":["Shared_Zone"]}'
assert_blocked "registry-blocked stage blocked case-insensitively" "ENVIRONMENT_BLOCKLIST" 1 "$WS" \
    '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","stages":["SHARED_ZONE"]}'
assert_blocked "stage absent from registry lists -> default-deny" "STAGE_NOT_ALLOWED" 1 "$WS" \
    '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","stages":["Shared_Other"]}'
assert_blocked "one bad stage among good ones blocks the whole request" "ENVIRONMENT_BLOCKLIST" 1 "$WS" \
    '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","stages":["Shared_SIT","Shared_Zone"]}'
assert_approved "unknown service name matched via cd.id" "$WS" \
    '{"service":"not-in-registry","type":"cd","branch":"develop","pipelineId":"900","project":"P","stages":["Shared_SIT"]}'
# The pipeline ID is what actually runs — on a name/ID mismatch the ID's
# entry must win (pipeline-guard.sh matches by ID only). pipelineId 901 is
# svc-empty-allowed's CD, whose blocked list contains 'sitae'; under
# svc-registry (the claimed name) 'sitae' would merely be STAGE_NOT_ALLOWED.
assert_blocked "name/ID mismatch validates against the ID's entry" "ENVIRONMENT_BLOCKLIST" 1 "$WS" \
    '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"901","stages":["sitae"]}'
run "$WS" '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","project":"P","stages":["Shared_SIT"],"allStages":["Shared_SIT","Shared_UAT","Shared_Zone"]}'
if [[ $(jq -c '.stagesToSkip | sort' <<< "$OUT") == '["Shared_UAT","Shared_Zone"]' ]]; then
    echo -e "  ${GREEN}PASS${NC} stagesToSkip = allStages minus requested"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} stagesToSkip derivation — got $OUT"
    FAIL=$((FAIL + 1))
fi

echo -e "${BLUE}=== CD: prefix fallback (layer 3) ===${NC}"
assert_approved "no registry: composite stage 'sitae' matches 'sit' prefix" "$WS_BARE" \
    '{"service":"x","type":"cd","branch":"develop","pipelineId":"1","project":"P","stages":["sitae"]}'
assert_blocked "no registry: unknown stage blocked" "STAGE_NOT_ALLOWED" 1 "$WS_BARE" \
    '{"service":"x","type":"cd","branch":"develop","pipelineId":"1","stages":["randomstage"]}'
# The registry blocked list is honored even when stages.allowed is empty —
# only the ALLOW decision falls back to prefix matching, never the block.
assert_blocked "empty allowed-list: registry-blocked apply_foo still blocked" "ENVIRONMENT_BLOCKLIST" 1 "$WS" \
    '{"service":"svc-empty-allowed","type":"cd","branch":"develop","pipelineId":"901","stages":["apply_foo"]}'
assert_blocked "empty allowed-list: registry-blocked sitae blocked despite matching 'sit' prefix" "ENVIRONMENT_BLOCKLIST" 1 "$WS" \
    '{"service":"svc-empty-allowed","type":"cd","branch":"develop","pipelineId":"901","stages":["sitae"]}'
assert_approved "empty allowed-list: allow decision falls back (dryae approved by prefix)" "$WS" \
    '{"service":"svc-empty-allowed","type":"cd","branch":"develop","pipelineId":"901","project":"P","stages":["dryae"]}'

echo -e "${BLUE}=== CD: malformed registry fails closed ===${NC}"
assert_fail_closed "unparseable registry never approves" "$WS_BAD" \
    '{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","project":"P","stages":["Shared_SIT"]}'

echo -e "${BLUE}=== Registry integrity: only the committed state is trusted ===${NC}"
CD_OK_REQUEST='{"service":"svc-registry","type":"cd","branch":"develop","pipelineId":"900","project":"P","stages":["Shared_SIT"]}'
assert_blocked "registry with uncommitted changes -> fail closed" "REGISTRY_NOT_COMMITTED" 1 "$WS_DIRTY" "$CD_OK_REQUEST"
assert_blocked "untracked registry -> fail closed" "REGISTRY_NOT_COMMITTED" 1 "$WS_UNTRACKED" "$CD_OK_REQUEST"
assert_blocked "registry outside a git work tree -> fail closed" "REGISTRY_NOT_COMMITTED" 1 "$WS_NOREPO" "$CD_OK_REQUEST"
assert_blocked "terraform also refuses an unverifiable registry" "REGISTRY_NOT_COMMITTED" 1 "$WS_DIRTY" \
    '{"service":"svc-terraform","type":"terraform","branch":"develop","pipelineId":"950","project":"P","environment":"sit"}'

echo -e "${BLUE}=== Terraform ===${NC}"
run "$WS" '{"service":"svc-terraform","type":"terraform","branch":"develop","pipelineId":"950","project":"P","environment":"sit","location":"ae"}'
if [[ $RC -eq 0 && $(jq -r '.approved' <<< "$OUT") == "true" ]] \
   && jq -e '.stagesToSkip | index("apply_x")' <<< "$OUT" > /dev/null \
   && jq -e '.stagesToSkip | index("cleanup_stage")' <<< "$OUT" > /dev/null \
   && [[ $(jq -r '.templateParameters.deployToggle' <<< "$OUT") == "plan" ]] \
   && [[ $(jq -r '.templateParameters.environment' <<< "$OUT") == "sit" ]]; then
    echo -e "  ${GREEN}PASS${NC} terraform approved plan-only: apply + alwaysSkipStages skipped, registry params merged"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} terraform registry-driven output — got rc=$RC out=$OUT"
    FAIL=$((FAIL + 1))
fi
assert_blocked "terraform env 'pre' blocked" "ENVIRONMENT_BLOCKLIST" 1 "$WS" \
    '{"service":"svc-terraform","type":"terraform","branch":"develop","pipelineId":"950","environment":"pre"}'
assert_blocked "terraform env not in allowed list" "ENVIRONMENT_NOT_ALLOWED" 1 "$WS" \
    '{"service":"svc-terraform","type":"terraform","branch":"develop","pipelineId":"950","environment":"staging"}'
assert_blocked "terraform missing environment" "MISSING_ENVIRONMENT" 1 "$WS" \
    '{"service":"svc-terraform","type":"terraform","branch":"develop","pipelineId":"950"}'
assert_blocked "terraform invalid location" "LOCATION_NOT_ALLOWED" 1 "$WS" \
    '{"service":"svc-terraform","type":"terraform","branch":"develop","pipelineId":"950","environment":"sit","location":"eu"}'
run "$WS_BARE" '{"service":"x","type":"terraform","branch":"develop","pipelineId":"999","project":"P","environment":"sit"}'
if [[ $RC -eq 0 && $(jq -r '.templateParameters.deployToggle' <<< "$OUT") == "plan" ]] \
   && jq -e '.stagesToSkip | length > 0' <<< "$OUT" > /dev/null; then
    echo -e "  ${GREEN}PASS${NC} terraform without registry: conservative plan-only defaults"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} terraform no-registry fallback — got rc=$RC out=$OUT"
    FAIL=$((FAIL + 1))
fi

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}"
[[ $FAIL -eq 0 ]]
