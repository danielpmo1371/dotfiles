#!/bin/bash

# Test harness for the settings.json hook merge in:
#   installers/memory-hooks.sh  (update_settings_json)
# Usage: ./tests/test-memory-hooks-merge.sh
#
# The merge used to be `.hooks = (.hooks // {}) * $new_hooks`. jq's `*`
# recurses into objects but replaces arrays wholesale, so registering the
# memory hooks silently deleted every other hook on those events — all four
# PreToolUse guards and both logging UserPromptSubmit hooks. These tests pin
# the replacement: append-only, per event and per matcher, order-preserving,
# and idempotent.
#
# Hermetic: the installer is sourced (never executed) and SETTINGS_FILE is
# repointed at a fixture in a temp dir, so the real config/claude/settings.json
# is only ever read. Only update_settings_json is called — nothing is
# downloaded and nothing is symlinked.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
REAL_SETTINGS="$DOTFILES_ROOT/config/claude/settings.json"

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Source the installer for update_settings_json. The BASH_SOURCE guard at its
# foot keeps main() from running; log output is muted so only test lines show.
source "$DOTFILES_ROOT/installers/memory-hooks.sh" > /dev/null 2>&1
DRY_RUN=false

# run_merge <fixture-file>
# Points the installer at the fixture and merges in place, as it would in a
# real run. Returns the installer's own exit code in RC.
run_merge() {
    local fixture="$1"
    set +e
    SETTINGS_FILE="$fixture" update_settings_json > /dev/null 2>&1
    RC=$?
    set -e
}

# commands_for <file> <event>
# Flat, in-order list of every hook command registered against an event.
commands_for() {
    jq -r --arg e "$2" '(.hooks[$e] // [])[].hooks[].command' "$1"
}

# ok / nok <label> — record a result
ok() {
    echo -e "  ${GREEN}PASS${NC} $1"
    PASS=$((PASS + 1))
}
nok() {
    echo -e "  ${RED}FAIL${NC} $1 — $2"
    FAIL=$((FAIL + 1))
}

# expect_contains <file> <event> <label> <command...>
# Every named command must still be registered against the event.
expect_contains() {
    local file="$1" event="$2" label="$3"
    shift 3
    local actual missing=""
    actual=$(commands_for "$file" "$event")
    local want
    for want in "$@"; do
        grep -qxF "$want" <<< "$actual" || missing+=" $want"
    done
    if [[ -z "$missing" ]]; then
        ok "$label"
    else
        nok "$label" "missing from $event:$missing"
    fi
}

# expect_order <file> <event> <label> <command...>
# The event's commands must be exactly these, in exactly this order.
expect_order() {
    local file="$1" event="$2" label="$3"
    shift 3
    local actual want
    actual=$(commands_for "$file" "$event")
    want=$(printf '%s\n' "$@")
    if [[ "$actual" == "$want" ]]; then
        ok "$label"
    else
        nok "$label" "expected [$(tr '\n' '|' <<< "$want")] got [$(tr '\n' '|' <<< "$actual")]"
    fi
}

# expect_rc <label> <expected-rc>
expect_rc() {
    if [[ $RC -eq $2 ]]; then
        ok "$1"
    else
        nok "$1" "expected rc=$2, got rc=$RC"
    fi
}

# A settings.json carrying everything the old merge destroyed: all four
# PreToolUse guards (in their real order) and the logging hooks.
write_full_fixture() {
    cat > "$1" << 'EOF'
{
  "model": "opus[1m]",
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/notification.sh", "timeout": 5 }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/logging/session-goal-tracker.sh", "timeout": 5 }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/logging/session-goal-tracker.sh", "timeout": 5 }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "mcp__azure-devops__pipelines_run_pipeline",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/pipeline-guard.sh", "timeout": 10 }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/pipeline-trigger-guard.sh", "timeout": 5 },
          { "type": "command", "command": "$HOME/.claude/hooks/destructive-ops-guard.sh", "timeout": 5 }
        ]
      },
      {
        "matcher": "Edit|Write|NotebookEdit|Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/pipeline-registry-write-guard.sh", "timeout": 5 }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/logging/user-request-logger.sh", "timeout": 5 },
          { "type": "command", "command": "$HOME/.claude/hooks/logging/session-goal-tracker.sh", "timeout": 5 }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/logging/response-summarizer.sh", "timeout": 30 }
        ]
      }
    ]
  }
}
EOF
}

MEM="\$HOME/.claude/hooks/memory"

echo -e "${BLUE}=== Preservation: existing guards survive the merge ===${NC}"
FULL="$TMP/full.json"
write_full_fixture "$FULL"
run_merge "$FULL"
expect_rc "merge succeeds against a fully-populated settings.json" 0

expect_contains "$FULL" PreToolUse "all four PreToolUse guards preserved" \
    '$HOME/.claude/hooks/pipeline-guard.sh' \
    '$HOME/.claude/hooks/pipeline-trigger-guard.sh' \
    '$HOME/.claude/hooks/destructive-ops-guard.sh' \
    '$HOME/.claude/hooks/pipeline-registry-write-guard.sh'
expect_contains "$FULL" UserPromptSubmit "both logging UserPromptSubmit hooks preserved" \
    '$HOME/.claude/hooks/logging/user-request-logger.sh' \
    '$HOME/.claude/hooks/logging/session-goal-tracker.sh'
expect_contains "$FULL" SessionStart "logging SessionStart hook preserved" \
    '$HOME/.claude/hooks/logging/session-goal-tracker.sh'
expect_contains "$FULL" SessionEnd "logging SessionEnd hook preserved" \
    '$HOME/.claude/hooks/logging/session-goal-tracker.sh'
expect_contains "$FULL" Notification "unrelated event (Notification) untouched" \
    '$HOME/.claude/hooks/notification.sh'
expect_contains "$FULL" Stop "unrelated event (Stop) untouched" \
    '$HOME/.claude/hooks/logging/response-summarizer.sh'

echo ""
echo -e "${BLUE}=== Addition: the memory hooks are actually registered ===${NC}"
expect_contains "$FULL" PreToolUse "memory permission-request added" \
    "node $MEM/permission-request.js"
expect_contains "$FULL" PostToolUse "memory auto-capture added" \
    "node $MEM/auto-capture-hook.js"
expect_contains "$FULL" SessionStart "memory session-start added" \
    "node $MEM/session-start.js"
expect_contains "$FULL" SessionEnd "memory session-end added" \
    "node $MEM/session-end.js"
expect_contains "$FULL" UserPromptSubmit "memory mid-conversation added" \
    "node $MEM/mid-conversation.js"

echo ""
echo -e "${BLUE}=== Order: appended, never alphabetised ===${NC}"
# unique_by(.command) would sort these; "$HOME/..." sorts before "node ...",
# so the guards would survive but silently swap places. Pin the exact order.
expect_order "$FULL" UserPromptSubmit "existing UserPromptSubmit order kept, memory hook appended" \
    '$HOME/.claude/hooks/logging/user-request-logger.sh' \
    '$HOME/.claude/hooks/logging/session-goal-tracker.sh' \
    "node $MEM/mid-conversation.js"
expect_order "$FULL" SessionStart "existing SessionStart order kept, memory hook appended" \
    '$HOME/.claude/hooks/logging/session-goal-tracker.sh' \
    "node $MEM/session-start.js"
# The Bash matcher's two guards must stay in their registered order, and the
# new mcp__memory__.* entry must land as a separate entry after them.
expect_order "$FULL" PreToolUse "PreToolUse entry and hook order preserved, memory entry appended" \
    '$HOME/.claude/hooks/pipeline-guard.sh' \
    '$HOME/.claude/hooks/pipeline-trigger-guard.sh' \
    '$HOME/.claude/hooks/destructive-ops-guard.sh' \
    '$HOME/.claude/hooks/pipeline-registry-write-guard.sh' \
    "node $MEM/permission-request.js"

echo ""
echo -e "${BLUE}=== Idempotency: repeat runs change nothing ===${NC}"
cp "$FULL" "$TMP/after-first.json"
run_merge "$FULL"
expect_rc "second merge succeeds" 0
if diff -q "$TMP/after-first.json" "$FULL" > /dev/null; then
    ok "second merge is byte-identical to the first"
else
    nok "second merge is byte-identical to the first" "$(diff "$TMP/after-first.json" "$FULL" | head -5)"
fi
run_merge "$FULL"
run_merge "$FULL"
if diff -q "$TMP/after-first.json" "$FULL" > /dev/null; then
    ok "four merges are byte-identical to the first"
else
    nok "four merges are byte-identical to the first" "$(diff "$TMP/after-first.json" "$FULL" | head -5)"
fi

echo ""
echo -e "${BLUE}=== Matcher handling ===${NC}"
# A PreToolUse entry whose matcher already equals the memory one: the new hook
# must join that entry rather than create a duplicate matcher.
SAME="$TMP/same-matcher.json"
cat > "$SAME" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__memory__.*",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/pre-existing.sh", "timeout": 5 }
        ]
      }
    ]
  }
}
EOF
run_merge "$SAME"
expect_rc "merge succeeds against a colliding matcher" 0
expect_order "$SAME" PreToolUse "matching matcher merged in place, existing hook first" \
    '$HOME/.claude/hooks/pre-existing.sh' \
    "node $MEM/permission-request.js"
if [[ "$(jq '.hooks.PreToolUse | length' "$SAME")" == "1" ]]; then
    ok "no duplicate matcher entry created"
else
    nok "no duplicate matcher entry created" "PreToolUse has $(jq '.hooks.PreToolUse | length' "$SAME") entries, expected 1"
fi

echo ""
echo -e "${BLUE}=== Bare settings.json (no .hooks key) ===${NC}"
BARE="$TMP/bare.json"
echo '{"model":"opus[1m]"}' > "$BARE"
run_merge "$BARE"
expect_rc "merge succeeds against settings.json with no .hooks key" 0
expect_contains "$BARE" PreToolUse "PreToolUse created from nothing" \
    "node $MEM/permission-request.js"
expect_contains "$BARE" SessionStart "SessionStart created from nothing" \
    "node $MEM/session-start.js"
if [[ "$(jq -r '.model' "$BARE")" == "opus[1m]" ]]; then
    ok "unrelated top-level keys preserved"
else
    nok "unrelated top-level keys preserved" "model is $(jq -r '.model' "$BARE")"
fi
cp "$BARE" "$TMP/bare-first.json"
run_merge "$BARE"
if diff -q "$TMP/bare-first.json" "$BARE" > /dev/null; then
    ok "bare settings.json merge is idempotent"
else
    nok "bare settings.json merge is idempotent" "$(diff "$TMP/bare-first.json" "$BARE" | head -5)"
fi

echo ""
echo -e "${BLUE}=== Regression guard against the real settings.json (read-only copy) ===${NC}"
# The bug shipped against the real file, so replay it against a copy of the
# real file too — a fixture that drifts from reality would stop catching it.
LIVE="$TMP/live.json"
cp "$REAL_SETTINGS" "$LIVE"
BEFORE=$(jq -r '[.hooks // {} | to_entries[] | .value[].hooks[].command] | sort | .[]' "$LIVE")
run_merge "$LIVE"
expect_rc "merge succeeds against a copy of the live settings.json" 0
AFTER=$(jq -r '[.hooks // {} | to_entries[] | .value[].hooks[].command] | sort | .[]' "$LIVE")
LOST=$(comm -23 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER"))
if [[ -z "$LOST" ]]; then
    ok "no hook command from the live settings.json was dropped"
else
    nok "no hook command from the live settings.json was dropped" "lost:$(tr '\n' ' ' <<< "$LOST")"
fi
if [[ "$(jq -e . "$REAL_SETTINGS" > /dev/null && echo ok)" == "ok" ]]; then
    ok "real settings.json still valid JSON (never written by this suite)"
else
    nok "real settings.json still valid JSON (never written by this suite)" "invalid"
fi

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}"
[[ $FAIL -eq 0 ]]
