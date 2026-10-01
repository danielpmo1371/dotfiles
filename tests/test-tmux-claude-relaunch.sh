#!/bin/bash

# Hermetic tests for the crash-relaunch pair:
#   config/claude/hooks/tmux-pane-registry.sh  (SessionStart/SessionEnd hook)
#   util-scripts/tmux-claude-relaunch.sh       (post-restore-all relauncher)
#
# Runs against a private tmux server (-L), a temp state dir
# (CLAUDE_TMUX_STATE_DIR) and a temp resurrect snapshot (RESURRECT_DIR). Both
# scripts talk to "the server in $TMUX", so $TMUX is pointed at the private
# server; the user's own server is never touched. The relaunch command is
# replaced with a harmless `echo` via @claude-relaunch-cmd.
#
# Usage: ./tests/test-tmux-claude-relaunch.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
HOOK="$DOTFILES_ROOT/config/claude/hooks/tmux-pane-registry.sh"
RELAUNCH="$DOTFILES_ROOT/util-scripts/tmux-claude-relaunch.sh"

SOCKET="tmux-claude-relaunch-test-$$"
PANE_SHELL="bash --norc --noprofile"
RELAUNCH_MARKER="RELAUNCH"
# Short so the busy-pane case stays quick; must exceed the stable-shell polls.
TEST_TIMEOUT=2
# Upper bound while waiting for pane output / shells to appear.
WAIT_STEPS=40
WAIT_INTERVAL=0.1

SESSION_ID="0b5e6f1c-1111-4222-8333-944455556666"
OTHER_ID="0b5e6f1c-aaaa-4bbb-8ccc-dddddddddddd"

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"

t() { tmux -L "$SOCKET" "$@"; }

cleanup() {
    # Only this test's private server.
    t kill-server 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

export CLAUDE_TMUX_STATE_DIR="$WORK/state"
export RESURRECT_DIR="$WORK/resurrect"
PANES_DIR="$CLAUDE_TMUX_STATE_DIR/panes"
SNAPSHOT="$RESURRECT_DIR/last"
PROJ="$WORK/proj"
OTHER_DIR="$WORK/other"
mkdir -p "$PANES_DIR" "$RESURRECT_DIR" "$PROJ" "$OTHER_DIR"

t -f /dev/null new-session -d -s boot -c "$WORK" "$PANE_SHELL"
t set -g @claude-relaunch-cmd "echo $RELAUNCH_MARKER"
t set -g @claude-relaunch-timeout "$TEST_TIMEOUT"
TMUX="$(t display-message -p '#{socket_path}'),$(t display-message -p '#{pid}'),0"
export TMUX

# Record file path for pane key $1 (same encoding as the scripts).
record_path() {
    local key="${1//%/%25}"
    printf '%s/%s' "$PANES_DIR" "${key//\//%2F}"
}

# Write a record for key $1: session id $2, cwd $3 and, when given, transcript
# path $4. Without $4 the record has no transcript_path, like records written
# before the field existed.
write_record() {
    if [ -n "${4:-}" ]; then
        jq -n --arg id "$2" --arg cwd "$3" --arg t "$4" \
            '{session_id: $id, cwd: $cwd, transcript_path: $t, epoch: 0}'
    else
        jq -n --arg id "$2" --arg cwd "$3" '{session_id: $id, cwd: $cwd, epoch: 0}'
    fi > "$(record_path "$1")"
}

# Append a resurrect pane line saying pane key $1 (session:window.pane) ran $2.
snapshot_pane() {
    local key="$1" command="$2" window
    window="${key##*:}"
    printf 'pane\t%s\t%s\t1\t:*\t%s\ttitle\t:%s\t1\t%s\t:%s\n' \
        "${key%:*}" "${window%.*}" "${key##*.}" "$PROJ" "$command" "$command" >> "$SNAPSHOT"
}

# Create a window in a (new) session $1 at dir $2 running $3; print its key.
new_pane() {
    local session="$1" dir="$2" command="$3"
    if t has-session -t "=$session" 2>/dev/null; then
        t new-window -d -P -F '#{session_name}:#{window_index}.#{pane_index}' \
            -t "=$session:" -c "$dir" "$command"
    else
        t new-session -d -P -F '#{session_name}:#{window_index}.#{pane_index}' \
            -s "$session" -c "$dir" "$command"
    fi
}

wait_for_shell() {
    local i
    for ((i = 0; i < WAIT_STEPS; i++)); do
        [ "$(t display-message -p -t "=$1" '#{pane_current_command}')" = bash ] && return 0
        sleep "$WAIT_INTERVAL"
    done
    return 1
}

# True when pane $1 printed "<marker> --resume <id $2>" within the wait budget.
pane_relaunched() {
    local i
    for ((i = 0; i < WAIT_STEPS; i++)); do
        t capture-pane -p -t "=$1" | grep -qx "$RELAUNCH_MARKER --resume $2" && return 0
        sleep "$WAIT_INTERVAL"
    done
    return 1
}

pane_has_marker() {
    t capture-pane -p -t "=$1" | grep -q "$RELAUNCH_MARKER"
}

# True when the record for key $1 exists and carries a numeric relaunched_at.
record_marked() {
    jq -e '.relaunched_at | numbers' "$(record_path "$1")" > /dev/null 2>&1
}

# Mark the record for key $1 as relaunched (never confirmed) $2 times.
mark_record() {
    jq --argjson n "$2" '. + {relaunched_at: 1, relaunch_attempts: $n}' \
        "$(record_path "$1")" > "$WORK/marked" && mv "$WORK/marked" "$(record_path "$1")"
}

record_attempts() {
    jq -r '.relaunch_attempts' "$(record_path "$1")" 2>/dev/null
}

reset_state() {
    rm -f "$PANES_DIR"/* "$SNAPSHOT"
    : > "$SNAPSHOT"
}

run_relaunch() {
    "$RELAUNCH" > "$WORK/relaunch.out" 2>&1
}

echo -e "${BLUE}tmux-claude-relaunch.sh${NC}"

# 1. eligible pane (session name with `/` and a space) -> relaunched, record kept and marked.
reset_state
key=$(new_pane "proj/x y" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
snapshot_pane "$key" claude
run_relaunch
if pane_relaunched "$key" "$SESSION_ID"; then
    pass "eligible pane (record without transcript_path) gets '<cmd> --resume <id>'"
else
    fail "eligible pane: no relaunch output; log: $(tail -n3 "$CLAUDE_TMUX_STATE_DIR/relaunch.log")"
fi
if record_marked "$key" && [ "$(record_attempts "$key")" = 1 ] \
    && [ "$(jq -r '.session_id' "$(record_path "$key")")" = "$SESSION_ID" ]; then
    pass "relaunched pane's record is kept, marked relaunched_at, relaunch_attempts 1"
else
    fail "relaunched pane's record: '$(cat "$(record_path "$key")" 2>/dev/null)'"
fi
ELIGIBLE_KEY="$key"

# 2. no record -> nothing typed.
reset_state
key=$(new_pane "norec" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
snapshot_pane "$key" claude
run_relaunch
sleep 0.5
if ! pane_has_marker "$key"; then
    pass "pane without a record is left alone"
else
    fail "pane without a record was relaunched"
fi

# 3. snapshot says zsh -> skipped, record removed.
reset_state
key=$(new_pane "notclaude" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
snapshot_pane "$key" zsh
run_relaunch
sleep 0.5
if ! pane_has_marker "$key" && [ ! -e "$(record_path "$key")" ]; then
    pass "snapshot not claude -> skipped, record removed"
else
    fail "snapshot not claude: relaunched or record kept"
fi

# 4. cwd mismatch -> skipped.
reset_state
key=$(new_pane "cwdmis" "$OTHER_DIR" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
snapshot_pane "$key" claude
run_relaunch
sleep 0.5
if ! pane_has_marker "$key" && [ ! -e "$(record_path "$key")" ]; then
    pass "cwd mismatch -> skipped, record removed"
else
    fail "cwd mismatch: relaunched or record kept"
fi

# 5. busy pane (sleep) until the timeout -> skipped, record kept.
reset_state
key=$(new_pane "busy" "$PROJ" "sleep 60")
write_record "$key" "$SESSION_ID" "$PROJ"
snapshot_pane "$key" claude
start=$SECONDS
run_relaunch
elapsed=$((SECONDS - start))
if ! pane_has_marker "$key" && [ -e "$(record_path "$key")" ]; then
    pass "busy pane -> skipped after ${elapsed}s, record kept"
else
    fail "busy pane: relaunched or record removed"
fi
if grep -q "no idle shell within ${TEST_TIMEOUT}s" "$CLAUDE_TMUX_STATE_DIR/relaunch.log"; then
    pass "timeout is logged"
else
    fail "timeout not logged"
fi

# 6. @claude-relaunch off -> nothing, record kept.
reset_state
key=$(new_pane "disabled" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
snapshot_pane "$key" claude
t set -g @claude-relaunch off
run_relaunch
t set -gu @claude-relaunch
sleep 0.5
if ! pane_has_marker "$key" && [ -e "$(record_path "$key")" ]; then
    pass "@claude-relaunch off -> nothing done, record kept"
else
    fail "@claude-relaunch off: relaunched or record removed"
fi

# 7. malicious session_id -> rejected, nothing typed, no side effect.
reset_state
key=$(new_pane "evil" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "x; touch $WORK/pwned" "$PROJ"
snapshot_pane "$key" claude
run_relaunch
sleep 0.5
if [ ! -e "$WORK/pwned" ] && ! pane_has_marker "$key"; then
    pass "malicious session_id rejected, nothing typed"
else
    fail "malicious session_id reached the pane"
fi
if grep -q "evil.*invalid session_id" "$CLAUDE_TMUX_STATE_DIR/relaunch.log"; then
    pass "malicious session_id is logged"
else
    fail "malicious session_id not logged"
fi

# 8. record for a pane that does not exist -> removed, logged.
reset_state
write_record "ghost:9.9" "$SESSION_ID" "$PROJ"
snapshot_pane "ghost:9.9" claude
run_relaunch
if [ ! -e "$(record_path "ghost:9.9")" ] \
    && grep -q "ghost:9.9.*pane does not exist (session $SESSION_ID, cwd $PROJ)" "$CLAUDE_TMUX_STATE_DIR/relaunch.log"; then
    pass "missing pane -> record removed, logged"
else
    fail "missing pane: record kept or not logged"
fi

# 8b. recorded transcript missing (no turns yet) -> skipped, record removed, logged.
reset_state
key=$(new_pane "noturns" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ" "$WORK/transcripts/absent.jsonl"
snapshot_pane "$key" claude
run_relaunch
sleep 0.5
if ! pane_has_marker "$key" && [ ! -e "$(record_path "$key")" ] \
    && grep -q "noturns.*no transcript at $WORK/transcripts/absent.jsonl — session had no turns (session $SESSION_ID, cwd $PROJ)" \
        "$CLAUDE_TMUX_STATE_DIR/relaunch.log"; then
    pass "missing transcript -> skipped, record removed, logged"
else
    fail "missing transcript: relaunched, record kept or not logged"
fi

# 8c. recorded transcript present -> relaunched.
reset_state
key=$(new_pane "withturns" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
mkdir -p "$WORK/transcripts"
: > "$WORK/transcripts/$SESSION_ID.jsonl"
write_record "$key" "$SESSION_ID" "$PROJ" "$WORK/transcripts/$SESSION_ID.jsonl"
snapshot_pane "$key" claude
run_relaunch
if pane_relaunched "$key" "$SESSION_ID" && record_marked "$key"; then
    pass "existing transcript -> relaunched, record kept and marked"
else
    fail "existing transcript: not relaunched or record not marked"
fi

# 8d. regression (2026-09-30): the pane shell is still stuck in its rc file
# (there: secret-tool waiting on a locked keyring) yet already reports itself
# as the pane's command, so the typed command never runs. The record must
# survive for the next restore instead of being removed on typing.
reset_state
cat > "$WORK/stuck-rc" <<'RC'
stuck=$(sleep 30)
RC
key=$(new_pane "stuckrc" "$PROJ" "bash --noprofile --rcfile $WORK/stuck-rc -i")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
snapshot_pane "$key" claude
run_relaunch
sleep 0.5
if record_marked "$key" && ! t capture-pane -p -t "=$key" | grep -qx "$RELAUNCH_MARKER --resume $SESSION_ID"; then
    pass "relaunch typed into a shell stuck in its rc -> record kept and marked"
else
    fail "stuck rc: record '$(cat "$(record_path "$key")" 2>/dev/null)'"
fi

# 8e. next restore: the snapshot saved meanwhile shows the shell the relaunch
# never got past, but the record is still marked -> retried.
reset_state
key=$(new_pane "retry" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
jq '. + {relaunched_at: 1}' "$(record_path "$key")" > "$WORK/marked" && mv "$WORK/marked" "$(record_path "$key")"
snapshot_pane "$key" bash
run_relaunch
if pane_relaunched "$key" "$SESSION_ID" \
    && grep -q "retry.*relaunch at 1 was never confirmed; retrying" "$CLAUDE_TMUX_STATE_DIR/relaunch.log"; then
    pass "unconfirmed relaunch is retried although the snapshot shows a shell"
else
    fail "unconfirmed relaunch not retried; log: $(tail -n3 "$CLAUDE_TMUX_STATE_DIR/relaunch.log")"
fi

# 8f. marked record below the default limit -> retried, counter incremented.
reset_state
key=$(new_pane "below" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
mark_record "$key" 2
snapshot_pane "$key" bash
run_relaunch
if pane_relaunched "$key" "$SESSION_ID" && [ "$(record_attempts "$key")" = 3 ]; then
    pass "marked record below the limit is retried, relaunch_attempts 2 -> 3"
else
    fail "below the limit: record '$(cat "$(record_path "$key")" 2>/dev/null)'"
fi

# 8g. marked record at the default limit -> nothing typed, removed, manual
# resume command and attempt count logged.
reset_state
key=$(new_pane "atlimit" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
mark_record "$key" 3
snapshot_pane "$key" claude
run_relaunch
sleep 0.5
if ! pane_has_marker "$key" && [ ! -e "$(record_path "$key")" ] \
    && grep -q "atlimit.*record removed — 3 relaunch attempts never confirmed (limit 3); resume manually: echo $RELAUNCH_MARKER --resume $SESSION_ID (session $SESSION_ID, cwd $PROJ)" \
        "$CLAUDE_TMUX_STATE_DIR/relaunch.log"; then
    pass "marked record at the limit -> nothing typed, record removed, manual resume logged"
else
    fail "at the limit: typed, record kept or not logged; log: $(tail -n3 "$CLAUDE_TMUX_STATE_DIR/relaunch.log")"
fi

# 8h. custom @claude-relaunch-max-attempts is honoured: 2 attempts reach a limit of 2.
reset_state
key=$(new_pane "customlimit" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
mark_record "$key" 2
snapshot_pane "$key" claude
t set -g @claude-relaunch-max-attempts 2
run_relaunch
t set -gu @claude-relaunch-max-attempts
sleep 0.5
if ! pane_has_marker "$key" && [ ! -e "$(record_path "$key")" ] \
    && grep -q "customlimit.*2 relaunch attempts never confirmed (limit 2)" "$CLAUDE_TMUX_STATE_DIR/relaunch.log"; then
    pass "@claude-relaunch-max-attempts 2 -> record with 2 attempts removed"
else
    fail "custom limit not honoured; log: $(tail -n3 "$CLAUDE_TMUX_STATE_DIR/relaunch.log")"
fi

# 8i. invalid @claude-relaunch-max-attempts (0) -> logged, default 3 applies.
reset_state
key=$(new_pane "badlimit" "$PROJ" "$PANE_SHELL")
wait_for_shell "$key"
write_record "$key" "$SESSION_ID" "$PROJ"
mark_record "$key" 2
snapshot_pane "$key" claude
t set -g @claude-relaunch-max-attempts 0
run_relaunch
t set -gu @claude-relaunch-max-attempts
if pane_relaunched "$key" "$SESSION_ID" && [ "$(record_attempts "$key")" = 3 ] \
    && grep -q "invalid @claude-relaunch-max-attempts '0', using 3" "$CLAUDE_TMUX_STATE_DIR/relaunch.log"; then
    pass "invalid @claude-relaunch-max-attempts -> logged, default limit applies"
else
    fail "invalid limit: record '$(cat "$(record_path "$key")" 2>/dev/null)'; log: $(tail -n3 "$CLAUDE_TMUX_STATE_DIR/relaunch.log")"
fi

# 9. no state dir -> exit 0, nothing created.
if CLAUDE_TMUX_STATE_DIR="$WORK/absent" "$RELAUNCH" && [ ! -e "$WORK/absent" ]; then
    pass "absent state dir -> exit 0, nothing created"
else
    fail "absent state dir: non-zero exit or dir created"
fi

echo -e "${BLUE}tmux-pane-registry.sh${NC}"

# The hook records a SessionStart only when exactly one process named claude
# sits between it and the pane's shell, so it is run the way Claude Code runs
# it: from a (fake) claude process inside the pane. The fake is a script named
# `claude`, so its comm is claude. With FAKE_CLAUDE_NEST=N it first starts N
# more fakes, like a headless `claude -p` launched from a claude session.
FAKE_BIN="$WORK/bin"
PAYLOAD="$WORK/payload.json"
HOOK_OUT="$WORK/hook.out"
HOOK_DONE="$WORK/hook.done"
# The hook's SessionEnd budget in Claude Code.
HOOK_BUDGET_MS=1500
TIMING_RUNS=5
# The fake claude's hook run is slower than a pane echo; give it more polls.
HOOK_WAIT_STEPS=100
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/claude" <<'FAKE'
#!/bin/bash
if [ "${FAKE_CLAUDE_NEST:-0}" -gt 0 ]; then
    FAKE_CLAUDE_NEST=$((FAKE_CLAUDE_NEST - 1)) claude
    exit $?
fi
start=$(date +%s%N)
"$HOOK" < "$PAYLOAD" > "$HOOK_OUT"
status=$?
end=$(date +%s%N)
echo "$status $(((end - start) / 1000000))" > "$HOOK_DONE"
FAKE
chmod +x "$FAKE_BIN/claude"
cat > "$WORK/fake-env" <<ENV
export PATH="$FAKE_BIN:\$PATH" HOOK="$HOOK" PAYLOAD="$PAYLOAD" HOOK_OUT="$HOOK_OUT"
export HOOK_DONE="$HOOK_DONE" CLAUDE_TMUX_STATE_DIR="$CLAUDE_TMUX_STATE_DIR"
ENV

reset_state
HOOK_KEY=$(new_pane "hooks" "$PROJ" "$PANE_SHELL")
wait_for_shell "$HOOK_KEY"
HOOK_PANE=$(t display-message -p -t "=$HOOK_KEY" '#{pane_id}')
HOOK_RECORD="$(record_path "$HOOK_KEY")"
t send-keys -t "$HOOK_PANE" -l ". $WORK/fake-env"
t send-keys -t "$HOOK_PANE" Enter

# Write the payload for event $1, session id $2, extra JSON field $3 (k:v).
write_payload() {
    printf '{"hook_event_name":"%s","session_id":"%s","cwd":"%s","transcript_path":"%s",%s}' \
        "$1" "$2" "$PROJ" "$WORK/transcripts/$2.jsonl" "$3" > "$PAYLOAD"
}

# Run the hook from a fake claude in the hook pane, nested $1 levels deeper.
# Sets HOOK_STATUS and HOOK_MS; returns 1 if the fake never finished.
run_in_pane() {
    local nest="${1:-0}" i
    rm -f "$HOOK_DONE"
    t send-keys -t "$HOOK_PANE" -l "FAKE_CLAUDE_NEST=$nest claude"
    t send-keys -t "$HOOK_PANE" Enter
    for ((i = 0; i < HOOK_WAIT_STEPS; i++)); do
        if [ -s "$HOOK_DONE" ]; then
            read -r HOOK_STATUS HOOK_MS < "$HOOK_DONE"
            return 0
        fi
        sleep "$WAIT_INTERVAL"
    done
    HOOK_STATUS="<none>"; HOOK_MS="<none>"
    return 1
}

# Run the hook in the pane for event $1, id $2, extra field $3, nesting $4.
run_hook() {
    write_payload "$1" "$2" "$3"
    run_in_pane "${4:-0}"
}

recorded_id() {
    jq -r '.session_id' "$HOOK_RECORD" 2>/dev/null
}

# 10. SessionStart from the pane's claude writes the record, replacing one the
# relaunch marked (that is how a resumed session confirms the relaunch).
jq -n --arg id "$SESSION_ID" --arg cwd "$PROJ" \
    '{session_id: $id, cwd: $cwd, epoch: 0, relaunched_at: 1, relaunch_attempts: 2}' > "$HOOK_RECORD"
run_hook SessionStart "$SESSION_ID" '"source":"resume"'
if [ "$HOOK_STATUS" = 0 ] && [ "$(recorded_id)" = "$SESSION_ID" ] \
    && [ "$(jq 'has("relaunched_at") or has("relaunch_attempts")' "$HOOK_RECORD")" = false ] \
    && [ "$(jq -r '.cwd' "$HOOK_RECORD")" = "$PROJ" ] \
    && [ "$(jq -r '.transcript_path' "$HOOK_RECORD")" = "$WORK/transcripts/$SESSION_ID.jsonl" ]; then
    pass "SessionStart writes {session_id, cwd, transcript_path} for the pane's key, clearing relaunched_at and relaunch_attempts"
else
    fail "SessionStart: status $HOOK_STATUS, record '$(cat "$HOOK_RECORD" 2>/dev/null)'"
fi
if [ -e "$HOOK_OUT" ] && [ ! -s "$HOOK_OUT" ]; then
    pass "hook prints nothing on stdout"
else
    fail "hook stdout: '$(cat "$HOOK_OUT" 2>/dev/null)'"
fi

# 10b. SessionStart removes another pane's record holding the same session id
# (a session resumed by hand in a new pane), keeps records of other sessions.
STALE_KEY="old/ses sion:1.0"
KEEP_KEY="keep:2.0"
jq -n --arg id "$SESSION_ID" --arg cwd "$PROJ" \
    '{session_id: $id, cwd: $cwd, epoch: 0, relaunched_at: 1}' > "$(record_path "$STALE_KEY")"
write_record "$KEEP_KEY" "$OTHER_ID" "$PROJ"
run_hook SessionStart "$SESSION_ID" '"source":"resume"'
if [ "$HOOK_STATUS" = 0 ] && [ ! -e "$(record_path "$STALE_KEY")" ] \
    && [ -f "$(record_path "$KEEP_KEY")" ] && [ "$(recorded_id)" = "$SESSION_ID" ]; then
    pass "SessionStart removes other panes' records of the same session, keeps the rest"
else
    fail "dedupe: status $HOOK_STATUS, records: $(ls "$PANES_DIR" | tr '\n' ' ')"
fi
rm -f "$(record_path "$KEEP_KEY")"

# 11. second SessionStart with a new id overwrites.
run_hook SessionStart "$OTHER_ID" '"source":"clear"'
if [ "$(recorded_id)" = "$OTHER_ID" ]; then
    pass "SessionStart with a new id overwrites the record"
else
    fail "second SessionStart: record holds '$(recorded_id)'"
fi

# 11b. nested claude (claude -> claude -p) does not overwrite the pane's record.
run_hook SessionStart "$SESSION_ID" '"source":"startup"' 1
if [ "$HOOK_STATUS" = 0 ] && [ "$(recorded_id)" = "$OTHER_ID" ]; then
    pass "nested claude's SessionStart leaves the pane's record alone"
else
    fail "nested claude: status $HOOK_STATUS, record holds '$(recorded_id)'"
fi

# 11c. hook not running under the pane's shell at all -> no change.
write_payload SessionStart "$SESSION_ID" '"source":"startup"'
TMUX_PANE="$HOOK_PANE" "$HOOK" < "$PAYLOAD" > /dev/null
if [ "$(recorded_id)" = "$OTHER_ID" ]; then
    pass "SessionStart from outside the pane's process tree is ignored"
else
    fail "outside the pane: record holds '$(recorded_id)'"
fi

# 12. SessionEnd prompt_input_exit with a non-matching id keeps the record.
run_hook SessionEnd "$SESSION_ID" '"reason":"prompt_input_exit"'
if [ "$(recorded_id)" = "$OTHER_ID" ]; then
    pass "SessionEnd for an older session keeps the newer record"
else
    fail "SessionEnd non-matching id removed the record"
fi

# 13. SessionEnd with another reason keeps the record.
run_hook SessionEnd "$OTHER_ID" '"reason":"other"'
if [ "$(recorded_id)" = "$OTHER_ID" ]; then
    pass "SessionEnd reason other keeps the record"
else
    fail "SessionEnd reason other removed the record"
fi

# 14. SessionEnd prompt_input_exit with the matching id removes the record.
run_hook SessionEnd "$OTHER_ID" '"reason":"prompt_input_exit"'
if [ ! -e "$HOOK_RECORD" ]; then
    pass "SessionEnd prompt_input_exit removes the record"
else
    fail "SessionEnd prompt_input_exit kept the record"
fi

# 15. no TMUX_PANE -> exit 0, no record, no stdout.
reset_state
out=$(printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s"}' \
    "$SESSION_ID" "$PROJ" | env -u TMUX_PANE "$HOOK")
status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$(ls -A "$PANES_DIR")" ]; then
    pass "no TMUX_PANE -> exit 0, no record, no stdout"
else
    fail "no TMUX_PANE: status $status, out '$out', files $(ls -A "$PANES_DIR")"
fi

# 16. malformed input from the pane's claude -> exit 0, no record.
printf 'not json' > "$PAYLOAD"
run_in_pane 0
if [ "$HOOK_STATUS" = 0 ] && [ ! -s "$HOOK_OUT" ] && [ -z "$(ls -A "$PANES_DIR")" ]; then
    pass "malformed input -> exit 0, no record, no stdout"
else
    fail "malformed input: status $HOOK_STATUS, out '$(cat "$HOOK_OUT" 2>/dev/null)'"
fi

# 17. TMUX_PANE naming a pane that does not exist -> exit 0, no record.
out=$(printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s"}' \
    "$SESSION_ID" "$PROJ" | TMUX_PANE="%99999" "$HOOK")
status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$(ls -A "$PANES_DIR")" ]; then
    pass "stale TMUX_PANE -> exit 0, no record written for another pane"
else
    fail "stale TMUX_PANE: status $status, files $(ls -A "$PANES_DIR")"
fi

# 18. timing: SessionStart is the heavier path (ancestry walk + write).
max_ms=0
for ((run = 0; run < TIMING_RUNS; run++)); do
    run_hook SessionStart "$SESSION_ID" '"source":"startup"' || { max_ms="<none>"; break; }
    [ "$HOOK_MS" -gt "$max_ms" ] && max_ms="$HOOK_MS"
done
if [ "$max_ms" != "<none>" ] && [ "$max_ms" -lt "$HOOK_BUDGET_MS" ]; then
    pass "hook max wall time ${max_ms}ms over $TIMING_RUNS runs (< ${HOOK_BUDGET_MS}ms)"
else
    fail "hook max wall time ${max_ms}ms over $TIMING_RUNS runs"
fi

echo ""
echo -e "${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}"
[ "$FAIL" -eq 0 ]
