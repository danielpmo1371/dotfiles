#!/usr/bin/env bash
#
# Tests for util-scripts/rc-start.sh (and the matching rc-stop.sh path).
#
# Why this exists: after a tmux server restart, tmux-resurrect restored every
# rc-* session as a plain shell. rc-start.sh used to skip any session whose name
# existed, so the Remote Control bridges never came back. It now treats a
# session as running only when its pane runs the bridge, respawns the bridge
# into a lone idle shell, and leaves a pane running anything else alone.
#
# Hermetic: a private tmux server (tmux -L, started with -f /dev/null so the
# user's tmux.conf and its resurrect/continuum plugins never load), HOME,
# XDG_CONFIG_HOME, ZDOTDIR and the folder list all under a temp dir, and a stub
# in place of claude. The default tmux server and ~/.config/claude-rc are never
# touched.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RC_START="$REPO/util-scripts/rc-start.sh"
RC_STOP="$REPO/util-scripts/rc-stop.sh"

# Seconds to wait for a bridge stub to report in or a session to change.
WAIT_SECONDS=10
POLL_INTERVAL=0.2
STOP_TIMEOUT=5
# @claude-rc-idle-timeout for these tests: long enough for a short child to
# finish, short enough that "stays busy" cases don't drag.
IDLE_TIMEOUT=4
# How long the "becomes idle" pane keeps a child running (under IDLE_TIMEOUT).
SHORT_CHILD_SECONDS=2

PASS=0
FAIL=0

ok()   { echo "  PASS $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL $1"; echo "       expected: $2"; echo "       actual:   $3"; FAIL=$((FAIL + 1)); }
check() {
    local label="$1" expected="$2" actual="$3"
    [[ "$actual" == "$expected" ]] && ok "$label" || bad "$label" "$expected" "$actual"
}

for cmd in tmux zsh; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "SKIP: $cmd not installed"; exit 0; }
done

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-rc-start.XXXXXX")
SOCK="test-rc-start-$$"
SOCK_PATH=""
HOOK_SOCK_PATH=""
cleanup() {
    tmux -L "$SOCK" kill-server 2>/dev/null
    [ -n "$HOOK_SOCK_PATH" ] && { tmux -S "$HOOK_SOCK_PATH" kill-server 2>/dev/null; rm -f "$HOOK_SOCK_PATH"; }
    # Some tmux versions leave the socket file behind after kill-server.
    [ -n "$SOCK_PATH" ] && rm -f "$SOCK_PATH"
    rm -rf "$ROOT"
}
trap cleanup EXIT

# Isolate everything rc-start.sh, zsh -lic and tmux could read or write.
unset TMUX TMUX_PANE
export HOME="$ROOT/home" XDG_CONFIG_HOME="$ROOT/home/.config" ZDOTDIR="$ROOT/zdotdir"
export CLAUDE_RC_TMUX_SOCKET="$SOCK"
export CLAUDE_RC_FOLDERS_FILE="$ROOT/folders"
export CLAUDE_RC_STOP_TIMEOUT="$STOP_TIMEOUT"
export CLAUDE_BIN="$ROOT/bin/claude"
CALLS="$ROOT/calls.log"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$ZDOTDIR" "$ROOT/bin" "$ROOT/work"
# An empty startup file, or zsh -lic stops at the zsh-newuser-install wizard.
: >"$ZDOTDIR/.zshrc"

# Stub bridge: records "<cwd> <args>" and stays alive until SIGTERM.
cat >"$CLAUDE_BIN" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "\$PWD" "\$*" >>"$CALLS"
trap 'exit 0' TERM
while :; do sleep 1; done
EOF
chmod +x "$CLAUDE_BIN"
: >"$CALLS"

tm() { tmux -L "$SOCK" "$@"; }

# The server exists before rc-start.sh runs, so no config is ever loaded, and
# the keepalive session stops it exiting when the last rc-* session goes.
tm -f /dev/null new-session -d -s keepalive -- sleep 3600
SOCK_PATH="$(tm display-message -p '#{socket_path}')"
tm set-option -g @claude-rc-idle-timeout "$IDLE_TIMEOUT"

mkdir_work() { mkdir -p "$ROOT/work/$1" && (cd "$ROOT/work/$1" && pwd -P); }
pane_pid()  { tm list-panes -t "=$1" -F '#{pane_pid}' 2>/dev/null | head -n1; }
bridge_calls() { grep -c "^$1 remote-control" "$CALLS"; }

wait_for_calls() {
    local dir="$1" want="$2" deadline
    deadline=$(( $(date +%s) + WAIT_SECONDS ))
    while [ "$(bridge_calls "$dir")" -lt "$want" ] && [ "$(date +%s)" -lt "$deadline" ]; do
        sleep "$POLL_INTERVAL"
    done
}

# Poll until session $1's pane shows command $2 (a new pane briefly shows "tmux").
wait_for_cmd() {
    local deadline
    deadline=$(( $(date +%s) + WAIT_SECONDS ))
    while [ "$(tm list-panes -t "=$1" -F '#{pane_current_command}')" != "$2" ] && [ "$(date +%s)" -lt "$deadline" ]; do
        sleep "$POLL_INTERVAL"
    done
    tm list-panes -t "=$1" -F '#{pane_current_command}'
}

run_start() { "$RC_START" "$@" 2>&1; }

HOST="$(uname -n | cut -d. -f1)"

echo "== fresh start"
fresh="$(mkdir_work fresh)"
out="$(run_start "$fresh")"; rc=$?
check "exit 0" 0 "$rc"
check "reports started" "rc-start: started rc-fresh ($fresh)" "$out"
wait_for_calls "$fresh" 1
check "bridge launched once in the folder" 1 "$(bridge_calls "$fresh")"
check "bridge args" "$fresh remote-control --permission-mode bypassPermissions --spawn same-dir --name $HOST-fresh" \
    "$(grep "^$fresh " "$CALLS")"
check "folder remembered" "$fresh" "$(cat "$CLAUDE_RC_FOLDERS_FILE")"

echo "== existing session with the bridge running is skipped"
before="$(pane_pid rc-fresh)"
out="$(run_start "$fresh")"; rc=$?
check "exit 0" 0 "$rc"
check "reports skipped" "rc-start: rc-fresh already running, skipped" "$out"
sleep 1
check "no second bridge" 1 "$(bridge_calls "$fresh")"
check "pane untouched" "$before" "$(pane_pid rc-fresh)"

echo "== restored idle shell gets the bridge (respawned in the same session)"
idle="$(mkdir_work idle)"
tm new-session -d -s rc-idle -c "$idle" -- zsh -f
out="$(run_start "$idle")"; rc=$?
check "exit 0" 0 "$rc"
check "reports restart" "rc-start: restarted bridge in rc-idle ($idle, pane was idle zsh)" "$out"
wait_for_calls "$idle" 1
check "bridge launched in the folder" 1 "$(bridge_calls "$idle")"
check "still one window" 1 "$(tm list-windows -t "=rc-idle" | wc -l | tr -d ' ')"
out="$(run_start "$idle")"
check "then counts as running" "rc-start: rc-idle already running, skipped" "$out"

echo "== dead pane (remain-on-exit) gets the bridge"
dead="$(mkdir_work dead)"
tm new-session -d -s rc-dead -c "$dead" -- sleep 3600
tm set-option -w -t "=rc-dead:" remain-on-exit on
kill "$(pane_pid rc-dead)"
sleep 0.5
check "pane is dead" 1 "$(tm list-panes -t "=rc-dead" -F '#{pane_dead}')"
out="$(run_start "$dead")"; rc=$?
check "exit 0" 0 "$rc"
wait_for_calls "$dead" 1
check "bridge launched" 1 "$(bridge_calls "$dead")"

echo "== session running something else is left alone"
busy="$(mkdir_work busy)"
tm new-session -d -s rc-busy -c "$busy" -- sleep 3600
before="$(pane_pid rc-busy)"
start=$(date +%s)
out="$(run_start "$busy")"; rc=$?
elapsed=$(( $(date +%s) - start ))
[ "$elapsed" -ge "$IDLE_TIMEOUT" ] && ok "waited the idle timeout first (${elapsed}s)" \
    || bad "waited the idle timeout first" ">= ${IDLE_TIMEOUT}s" "${elapsed}s"
check "exit 1" 1 "$rc"
check "reports left alone" "rc-start: rc-busy exists without the bridge but runs something else (sleep, not idle within ${IDLE_TIMEOUT}s), left alone" "$out"
check "pane untouched" "$before" "$(pane_pid rc-busy)"
check "no bridge" 0 "$(bridge_calls "$busy")"

echo "== shell with a child process is left alone"
shbusy="$(mkdir_work shbusy)"
tm new-session -d -s rc-shbusy -c "$shbusy" -- bash -c 'sleep 3600 & wait'
before="$(pane_pid rc-shbusy)"
out="$(run_start "$shbusy")"; rc=$?
check "exit 1" 1 "$rc"
check "pane untouched" "$before" "$(pane_pid rc-shbusy)"
check "no bridge" 0 "$(bridge_calls "$shbusy")"

echo "== shell whose child finishes within the timeout gets the bridge"
settling="$(mkdir_work settling)"
tm new-session -d -s rc-settling -c "$settling" -- bash -c "sleep $SHORT_CHILD_SECONDS & wait; exec zsh -f"
check "starts busy (shell with a child)" "bash" "$(wait_for_cmd rc-settling bash)"
out="$(run_start "$settling")"; rc=$?
check "exit 0" 0 "$rc"
check "reports restart" "rc-start: restarted bridge in rc-settling ($settling, pane was idle zsh)" "$out"
wait_for_calls "$settling" 1
check "bridge launched" 1 "$(bridge_calls "$settling")"

echo "== invalid @claude-rc-idle-timeout falls back to the default"
badopt="$(mkdir_work badopt)"
tm new-session -d -s rc-badopt -c "$badopt" -- zsh -f
tm set-option -g @claude-rc-idle-timeout soon
out="$(run_start "$badopt")"; rc=$?
tm set-option -g @claude-rc-idle-timeout "$IDLE_TIMEOUT"
check "exit 0" 0 "$rc"
check "warns" 1 "$(printf '%s\n' "$out" | grep -c "invalid @claude-rc-idle-timeout 'soon', using 30")"
wait_for_calls "$badopt" 1
check "bridge launched" 1 "$(bridge_calls "$badopt")"

echo "== --if-listed is a no-op without a list"
out="$(CLAUDE_RC_FOLDERS_FILE="$ROOT/missing" CLAUDE_BIN="$ROOT/no-claude" "$RC_START" --if-listed 2>&1)"; rc=$?
check "missing list: exit 0" 0 "$rc"
check "missing list: silent" "" "$out"
printf '# nothing yet\n\n' >"$ROOT/comments-only"
out="$(CLAUDE_RC_FOLDERS_FILE="$ROOT/comments-only" "$RC_START" --if-listed 2>&1)"; rc=$?
check "comments-only list: exit 0" 0 "$rc"
check "comments-only list: silent" "" "$out"
out="$(CLAUDE_RC_FOLDERS_FILE="$ROOT/missing" "$RC_START" 2>&1)"; rc=$?
check "without --if-listed a missing list is still an error" 1 "$rc"

echo "== no-arg run over the folder list keeps going past a busy one"
out="$(run_start)"; rc=$?
check "exit 1 (busy folders)" 1 "$rc"
check "running ones skipped" 5 "$(printf '%s\n' "$out" | grep -c 'already running, skipped')"
check "busy ones reported" 2 "$(printf '%s\n' "$out" | grep -c 'left alone')"

echo "== rc-stop: idle shell stops at once, bridge gets SIGTERM"
lone="$(mkdir_work lone)"
tm new-session -d -s rc-lone -c "$lone" -- zsh -f
start=$(date +%s)
out="$("$RC_STOP" "$lone" 2>&1)"
elapsed=$(( $(date +%s) - start ))
check "reports no bridge" "rc-stop: stopped rc-lone (no bridge was running)" "$out"
check "gone" 1 "$(tm has-session -t "=rc-lone" 2>/dev/null; echo $?)"
[ "$elapsed" -lt "$STOP_TIMEOUT" ] && ok "did not wait out the timeout (${elapsed}s)" \
    || bad "did not wait out the timeout" "< ${STOP_TIMEOUT}s" "${elapsed}s"
out="$("$RC_STOP" "$fresh" 2>&1)"
check "bridge stopped by SIGTERM" "rc-stop: stopped rc-fresh" "$out"
check "folder forgotten" "" "$(grep -xF "$fresh" "$CLAUDE_RC_FOLDERS_FILE")"

echo "== post-restore hook from tmux.conf"
# Run the hook exactly as tmux-resurrect does (bash eval), against a server on
# a private TMUX_TMPDIR, so its bare "tmux" calls never reach the real server.
HOOK="$(sed -n "s/^set -g @resurrect-hook-post-restore-all '\(.*\)'\$/\1/p" "$REPO/config/tmux/tmux.conf")"
check "hook found" 1 "$([ -n "$HOOK" ] && echo 1)"
run_hook() {
    env -u CLAUDE_RC_TMUX_SOCKET HOME="$1" TMUX_TMPDIR="$ROOT/tmuxtmp" XDG_STATE_HOME="$ROOT/state-$2" \
        CLAUDE_RC_FOLDERS_FILE="$3" bash -c "$HOOK" >/dev/null 2>&1
}
mkdir -p "$ROOT/tmuxtmp" "$ROOT/nohome" "$ROOT/hookhome/repos"
ln -s "$REPO" "$ROOT/hookhome/repos/dotfiles"
hooked="$(mkdir_work hooked)"
printf '%s\n' "$hooked" >"$ROOT/hook-folders"
TMUX_TMPDIR="$ROOT/tmuxtmp" tmux -f /dev/null new-session -d -s rc-hooked -c "$hooked" -- zsh -f
HOOK_SOCK_PATH="$(TMUX_TMPDIR="$ROOT/tmuxtmp" tmux display-message -p '#{socket_path}')"

run_hook "$ROOT/nohome" nohome "$ROOT/hook-folders"; rc=$?
sleep 1
check "no rc-start.sh: exit 0" 0 "$rc"
check "no rc-start.sh: no log written" 0 "$([ -e "$ROOT/state-nohome/claude-rc" ] && echo 1 || echo 0)"

run_hook "$ROOT/hookhome" empty "$ROOT/missing"; rc=$?
sleep 1
check "no folder list: exit 0" 0 "$rc"
check "no folder list: log has only the run header" "post-restore" \
    "$(awk '{ print $3 }' "$ROOT/state-empty/claude-rc/restore.log" 2>/dev/null)"

run_hook "$ROOT/hookhome" listed "$ROOT/hook-folders"; rc=$?
check "listed: exit 0" 0 "$rc"
wait_for_calls "$hooked" 1
check "listed: bridge restarted in the restored shell" 1 "$(bridge_calls "$hooked")"
check "listed: outcome logged" 1 \
    "$(grep -c "rc-start: restarted bridge in rc-hooked" "$ROOT/state-listed/claude-rc/restore.log" 2>/dev/null)"

echo "== default tmux server never used"
check "only the private socket was targeted" "$SOCK" "$CLAUDE_RC_TMUX_SOCKET"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
