#!/bin/bash

# Test harness for the settings.json hook merge in:
#   installers/logging-hooks.sh  (update_settings)
# Usage: ./tests/test-logging-hooks-merge.sh
#
# The SessionStart/SessionEnd merge used to dedupe with `unique_by(.command)`.
# jq's unique_by sorts by the key, so every install silently alphabetised those
# hooks (logging/session-goal-tracker.sh jumped ahead of tmux-pane-registry.sh).
# These tests pin the replacement: append-only, order-preserving, idempotent,
# and leaving everything else in settings.json alone.
#
# Hermetic: the installer is sourced (never executed) and SETTINGS_FILE is
# repointed at a fixture in a temp dir, so the real config/claude/settings.json
# is only ever read. Only update_settings is called — nothing is symlinked and
# no directory is created.

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

# Source the installer for update_settings. The BASH_SOURCE guard at its foot
# keeps main() from running; log output is muted so only test lines show.
source "$DOTFILES_ROOT/installers/logging-hooks.sh" > /dev/null 2>&1
DRY_RUN=false

# run_merge <fixture-file>
# Points the installer at the fixture and merges in place, as it would in a
# real run. Returns the installer's own exit code in RC.
run_merge() {
    local fixture="$1"
    set +e
    SETTINGS_FILE="$fixture" update_settings > /dev/null 2>&1
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

# expect_identical <label> <expected-file> <actual-file>
expect_identical() {
    if diff -q "$2" "$3" > /dev/null; then
        ok "$1"
    else
        nok "$1" "$(diff "$2" "$3" | head -5)"
    fi
}

LOG="\$HOME/.claude/hooks/logging"
PANE='$HOME/.claude/hooks/tmux-pane-registry.sh'
MEM_START='node $HOME/.claude/hooks/memory/session-start.js'
MEM_END='node $HOME/.claude/hooks/memory/session-end.js'

# The real regression: SessionStart/SessionEnd registered with hooks that sort
# AFTER logging/session-goal-tracker.sh ("t" > "l"), and without it yet, so the
# merge has to append it. Unrelated events and top-level keys ride along.
write_order_fixture() {
    cat > "$1" << 'EOF'
{
  "model": "opus[1m]",
  "permissions": { "allow": ["Bash(ls:*)"] },
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/notification.sh", "timeout": 5 }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/pipeline-trigger-guard.sh", "timeout": 5 },
          { "type": "command", "command": "$HOME/.claude/hooks/destructive-ops-guard.sh", "timeout": 5 }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/tmux-pane-registry.sh", "timeout": 5 },
          { "type": "command", "command": "node $HOME/.claude/hooks/memory/session-start.js", "timeout": 30 }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/tmux-pane-registry.sh", "timeout": 5 },
          { "type": "command", "command": "node $HOME/.claude/hooks/memory/session-end.js", "timeout": 15 }
        ]
      }
    ]
  }
}
EOF
}

echo -e "${BLUE}=== Order: existing hooks keep their place, new ones append ===${NC}"
ORDER="$TMP/order.json"
write_order_fixture "$ORDER"
cp "$ORDER" "$TMP/order-before.json"
run_merge "$ORDER"
expect_rc "merge succeeds" 0
# unique_by(.command) would put "$HOME/.claude/hooks/logging/..." ahead of
# "$HOME/.claude/hooks/tmux-pane-registry.sh". Pin the exact order.
expect_order "$ORDER" SessionStart "SessionStart: tmux-pane-registry stays first, goal tracker appended last" \
    "$PANE" "$MEM_START" "$LOG/session-goal-tracker.sh"
expect_order "$ORDER" SessionEnd "SessionEnd: tmux-pane-registry stays first, goal tracker appended last" \
    "$PANE" "$MEM_END" "$LOG/session-goal-tracker.sh"

echo ""
echo -e "${BLUE}=== Already registered: order is left exactly as found ===${NC}"
# Mirrors the live layout: goal tracker already present in the middle of a
# list that is NOT in sorted order. The merge must be a no-op for these.
PRESENT="$TMP/present.json"
cat > "$PRESENT" << 'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/tmux-pane-registry.sh", "timeout": 5 },
          { "type": "command", "command": "$HOME/.claude/hooks/logging/session-goal-tracker.sh", "timeout": 5 },
          { "type": "command", "command": "$HOME/.claude/hooks/early-hook.sh", "timeout": 5 }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/tmux-pane-registry.sh", "timeout": 5 },
          { "type": "command", "command": "$HOME/.claude/hooks/logging/session-goal-tracker.sh", "timeout": 5 },
          { "type": "command", "command": "$HOME/.claude/hooks/early-hook.sh", "timeout": 5 }
        ]
      }
    ]
  }
}
EOF
run_merge "$PRESENT"
expect_rc "merge succeeds when the goal tracker is already registered" 0
expect_order "$PRESENT" SessionStart "SessionStart order unchanged, no duplicate goal tracker" \
    "$PANE" "$LOG/session-goal-tracker.sh" '$HOME/.claude/hooks/early-hook.sh'
expect_order "$PRESENT" SessionEnd "SessionEnd order unchanged, no duplicate goal tracker" \
    "$PANE" "$LOG/session-goal-tracker.sh" '$HOME/.claude/hooks/early-hook.sh'

echo ""
echo -e "${BLUE}=== Unrelated content untouched ===${NC}"
# Everything except SessionStart/SessionEnd must match the pre-merge fixture.
# UserPromptSubmit and Stop were absent, so they are added; drop those too.
strip_touched='del(.hooks.SessionStart, .hooks.SessionEnd, .hooks.UserPromptSubmit, .hooks.Stop)'
if [[ "$(jq -S "$strip_touched" "$TMP/order-before.json")" == "$(jq -S "$strip_touched" "$ORDER")" ]]; then
    ok "top-level keys and other events (Notification, PreToolUse) unchanged"
else
    nok "top-level keys and other events (Notification, PreToolUse) unchanged" "differs after merge"
fi
expect_order "$ORDER" PreToolUse "PreToolUse guard order preserved" \
    '$HOME/.claude/hooks/pipeline-trigger-guard.sh' '$HOME/.claude/hooks/destructive-ops-guard.sh'
expect_order "$ORDER" UserPromptSubmit "absent UserPromptSubmit created with both logging hooks" \
    "$LOG/user-request-logger.sh" "$LOG/session-goal-tracker.sh"
expect_order "$ORDER" Stop "absent Stop created with the summarizer" \
    "$LOG/response-summarizer.sh"

echo ""
echo -e "${BLUE}=== Idempotency: repeat runs change nothing ===${NC}"
cp "$ORDER" "$TMP/after-first.json"
run_merge "$ORDER"
expect_rc "second merge succeeds" 0
expect_identical "second merge is byte-identical to the first" "$TMP/after-first.json" "$ORDER"
run_merge "$ORDER"
run_merge "$ORDER"
expect_identical "four merges are byte-identical to the first" "$TMP/after-first.json" "$ORDER"

echo ""
echo -e "${BLUE}=== Regression guard against the real settings.json (read-only copy) ===${NC}"
# The reorder shipped against the real file, so replay against a copy of it.
LIVE="$TMP/live.json"
cp "$REAL_SETTINGS" "$LIVE"
LIVE_START=$(commands_for "$LIVE" SessionStart)
LIVE_END=$(commands_for "$LIVE" SessionEnd)
run_merge "$LIVE"
expect_rc "merge succeeds against a copy of the live settings.json" 0
# If the live file already has the goal tracker, the order must be unchanged;
# otherwise it must be the old order with the tracker appended.
for event in SessionStart SessionEnd; do
    if [[ $event == SessionStart ]]; then before="$LIVE_START"; else before="$LIVE_END"; fi
    if grep -qxF "$LOG/session-goal-tracker.sh" <<< "$before"; then
        want="$before"
    else
        want=$(printf '%s\n%s' "$before" "$LOG/session-goal-tracker.sh" | sed '/^$/d')
    fi
    if [[ "$(commands_for "$LIVE" "$event")" == "$want" ]]; then
        ok "live $event order preserved"
    else
        nok "live $event order preserved" "got [$(commands_for "$LIVE" "$event" | tr '\n' '|')]"
    fi
done
if jq -e . "$REAL_SETTINGS" > /dev/null; then
    ok "real settings.json still valid JSON (never written by this suite)"
else
    nok "real settings.json still valid JSON (never written by this suite)" "invalid"
fi

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}"
[[ $FAIL -eq 0 ]]
