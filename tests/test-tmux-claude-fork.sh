#!/bin/bash

# Hermetic tests for the session lookup in util-scripts/tmux-claude-fork.sh.
#
# find_claude_session_pid walks the descendants of a pane's shell and returns
# the first LIVE pid that has a Claude Code sessions json. These tests build a
# real process tree out of `sleep` processes and point CLAUDE_SESSIONS_DIR at a
# temp dir, so neither tmux nor claude is involved.
#
# Usage: ./tests/test-tmux-claude-fork.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
FORK_SCRIPT="$DOTFILES_ROOT/util-scripts/tmux-claude-fork.sh"

# Long enough to outlive the test run; every sleep is killed in cleanup.
SLEEP_SECONDS=300
# Upper bound (in 0.1s polls) while waiting for a spawned tree to materialise.
SPAWN_POLLS=50

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
# Every pid this test spawns, recorded explicitly: once a parent dies its
# children are reparented, so walking the tree at cleanup time would miss them.
SPAWNED=()

cleanup() {
    local pid
    for pid in "${SPAWNED[@]}"; do
        kill "$pid" 2>/dev/null
    done
    rm -rf "$WORK"
}
trap cleanup EXIT

export CLAUDE_SESSIONS_DIR="$WORK/sessions"
mkdir -p "$CLAUDE_SESSIONS_DIR"

# shellcheck source=../util-scripts/tmux-claude-fork.sh
source "$FORK_SCRIPT"

# Wait until $1 has a child and print that child's pid.
wait_for_child() {
    local parent="$1" child i
    for ((i = 0; i < SPAWN_POLLS; i++)); do
        child=$(pgrep -P "$parent" | head -n1)
        if [ -n "$child" ]; then
            echo "$child"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

write_session_json() {
    printf '{"pid":%s,"sessionId":"test-%s","cwd":"%s"}\n' "$1" "$1" "$WORK" \
        > "$CLAUDE_SESSIONS_DIR/$1.json"
}

echo -e "${BLUE}find_claude_session_pid${NC}"

# 1. shell -> claude-like child with a sessions json.
bash -c "sleep $SLEEP_SECONDS & wait" &
root=$!; SPAWNED+=("$root")
child=$(wait_for_child "$root"); SPAWNED+=("$child")
write_session_json "$child"
found=$(find_claude_session_pid "$root")
if [ "$found" = "$child" ]; then
    pass "live child with sessions json is found"
else
    fail "live child: expected $child, got '${found:-<none>}'"
fi

# 2. stale json for a dead pid, next to a live claude-like child.
bash -c "sleep $SLEEP_SECONDS & wait" &
root=$!; SPAWNED+=("$root")
live=$(wait_for_child "$root"); SPAWNED+=("$live")
sleep "$SLEEP_SECONDS" &
dead=$!
kill "$dead"; wait "$dead" 2>/dev/null
write_session_json "$dead"
write_session_json "$live"
found=$(find_claude_session_pid "$root")
if [ "$found" = "$live" ]; then
    pass "stale json for a dead pid is ignored"
else
    fail "stale json: expected $live, got '${found:-<none>}'"
fi
# A stale json whose pid is dead is never returned, even via liveness alone.
if ! kill -0 "$dead" 2>/dev/null && [ "$found" != "$dead" ]; then
    pass "dead pid is not reported as a session"
else
    fail "dead pid $dead was reported or is still alive"
fi

# 3. process tree without any sessions json.
bash -c "sleep $SLEEP_SECONDS & wait" &
root=$!; SPAWNED+=("$root")
SPAWNED+=("$(wait_for_child "$root")")
if found=$(find_claude_session_pid "$root"); then
    fail "tree without json: expected not found, got '$found'"
else
    pass "process tree without sessions json -> not found"
fi

# 4. nested: shell -> wrapper -> claude-like process.
bash -c "bash -c 'sleep $SLEEP_SECONDS & wait' & wait" &
root=$!; SPAWNED+=("$root")
wrapper=$(wait_for_child "$root"); SPAWNED+=("$wrapper")
nested=$(wait_for_child "$wrapper"); SPAWNED+=("$nested")
write_session_json "$nested"
found=$(find_claude_session_pid "$root")
if [ "$found" = "$nested" ]; then
    pass "nested descendant (shell -> wrapper -> claude) is found"
else
    fail "nested: expected $nested, got '${found:-<none>}'"
fi

echo -e "${BLUE}command quoting${NC}"

# 5. quote_for_shell output round-trips through the pane shells. zsh runs with
# EXTENDED_GLOB (as interactive setups commonly do), where bash's printf %q
# style leaves `#` bare and the command fails with "no matches found".
name=$'it\'s a "fork" $HOME #S;x \\b ~y ^z *'
quoted=$(quote_for_shell "$name")
for sh in "bash --norc --noprofile" "zsh -f -o extendedglob"; do
    if ! command -v "${sh%% *}" >/dev/null 2>&1; then
        continue
    fi
    # shellcheck disable=SC2086 # $sh carries the shell's flags on purpose
    out=$($sh -c "printf '%s' $quoted")
    if [ "$out" = "$name" ]; then
        pass "quoted name with quotes, \$, #, ;, \\ survives ${sh%% *}"
    else
        fail "${sh%% *} parsed quoted name as '$out'"
    fi
done

# 6. the full command line keeps the session id and name as single words.
FORK_COMMAND="printf '[%s]'"
out=$(bash --norc --noprofile -c "$(build_fork_command abc-123 "$name")")
expected="[--resume][abc-123][--fork-session][-n][$name]"
if [ "$out" = "$expected" ]; then
    pass "build_fork_command yields --resume <id> --fork-session -n <name>"
else
    fail "build_fork_command parsed as '$out'"
fi

echo ""
echo -e "${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}"
[ "$FAIL" -eq 0 ]
