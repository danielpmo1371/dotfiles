#!/bin/bash

# Test harness for util-scripts/tmux-restart.sh (and the once-per-boot
# fastfetch gate in config/zsh/zshrc).
# Usage: ./tests/test-tmux-restart.sh
#
# Hermetic: runs against a throwaway tmux socket (-L), a fake `claude` on
# PATH that prints the resume hint on `/exit`, a stub tmux-resurrect save.sh
# that records what would have been saved, and a temp claude settings file
# (TMUX_RESTART_SETTINGS) so the user's real settings are never read.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
RESTART="$DOTFILES_ROOT/util-scripts/tmux-restart.sh"
ZSHRC="$DOTFILES_ROOT/config/zsh/zshrc"

SOCKET="tmux-restart-test-$$"
FAKE_SESSION_ID="fake-session-abc123"
RESUME_HINT="claude --resume $FAKE_SESSION_ID"
# Generous but bounded: how long the harness waits for panes to start/stop.
WAIT_STEPS=40
WAIT_INTERVAL=0.25
# Short timeout for the stuck-claude cases so the suite stays quick.
STUCK_TIMEOUT=2

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TMP="$(mktemp -d)"
cleanup() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }
check() { # check <label> <command...>
    local label="$1"; shift
    if "$@"; then pass "$label"; else fail "$label"; fi
}

tmx() { tmux -L "$SOCKET" "$@"; }

server_alive() { tmx list-sessions >/dev/null 2>&1; }
server_gone() { ! server_alive; }

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
BIN_OK="$TMP/bin-ok"
BIN_STUCK="$TMP/bin-stuck"
BIN_SECOND="$TMP/bin-second-exit"
PLUGINS="$TMP/plugins"
SAVE_STUB="$PLUGINS/tmux-resurrect/scripts/save.sh"
SAVE_OUT="$TMP/saved-panes.txt"
SAVE_RAN="$TMP/save-ran"
SETTINGS="$TMP/settings.json"
mkdir -p "$BIN_OK" "$BIN_STUCK" "$BIN_SECOND" "$(dirname "$SAVE_STUB")"
echo '{}' > "$SETTINGS"

# Fake claude: ignores SIGINT like the real TUI, exits with the resume hint
# on `/exit`. Accepts a vim-mode prefix (Escape, i) before the command since
# the real TUI swallows those as mode switches.
cat > "$BIN_OK/claude" <<EOF
#!/bin/bash
trap '' INT
while IFS= read -r line; do
    if [ "\$line" = "/exit" ] || [ "\$line" = "\$(printf '\033i/exit')" ]; then
        echo "$RESUME_HINT"
        exit 0
    fi
done
EOF
# Stuck claude: ignores SIGINT and `/exit`.
cat > "$BIN_STUCK/claude" <<'EOF'
#!/bin/bash
trap '' INT
while IFS= read -r line; do :; done
EOF
# Swallows the first `/exit` (like a real claude re-rendering after an
# interrupt) and exits with the hint on the second.
cat > "$BIN_SECOND/claude" <<EOF
#!/bin/bash
trap '' INT
exits=0
while IFS= read -r line; do
    if [ "\$line" = "/exit" ]; then
        exits=\$((exits + 1))
        if [ "\$exits" -ge 2 ]; then
            echo "$RESUME_HINT"
            exit 0
        fi
    fi
done
EOF
chmod +x "$BIN_OK/claude" "$BIN_STUCK/claude" "$BIN_SECOND/claude"

# Stub tmux-resurrect save.sh: resolves the server exactly like the real one
# (socket path from $TMUX) and captures every pane's scrollback.
cat > "$SAVE_STUB" <<EOF
#!/bin/bash
set -eu
touch "$SAVE_RAN"
socket="\${TMUX%%,*}"
: > "$SAVE_OUT"
for pane in \$(tmux -S "\$socket" list-panes -a -F '#{pane_id}'); do
    tmux -S "\$socket" capture-pane -p -S - -t "\$pane" >> "$SAVE_OUT"
done
EOF
chmod +x "$SAVE_STUB"

# wait_for <label> <command...>: polls until the command succeeds or WAIT_STEPS
# elapse; a fixture that never comes up aborts the suite.
wait_for() {
    local label="$1"; shift
    local i
    for ((i = 0; i < WAIT_STEPS; i++)); do
        if "$@"; then return 0; fi
        sleep "$WAIT_INTERVAL"
    done
    echo "fixture error: $label" >&2
    return 1
}

# Bare bash with a known prompt so the harness can tell when the shell is
# ready (readline flushes typed-ahead input when it initialises, so keys sent
# before the first prompt would be lost).
FIXTURE_PS1='fixture\$ '
pane_shell() { # pane_shell <path>
    printf "env -i PATH='%s' HOME='%s' TERM=dumb PS1='%s' /bin/bash --noprofile --norc" "$1" "$TMP" "$FIXTURE_PS1"
}
pane_shows_prompt() { tmx capture-pane -p -t "$1" | grep -q 'fixture\$'; }
fake_claude_process_up() { ps -Ao args= | grep -Eq "^/bin/bash $1/claude$"; }

# start_server <claude-bin-dir>: session "t" with pane 1 = shell running the
# fake claude, pane 2 = plain shell. Waits until the fake claude is running.
start_server() {
    local bin_dir="$1"
    # Hermetic server: -f /dev/null keeps the user's tmux.conf (TPM, resurrect,
    # its `set-environment -g TMUX_PLUGIN_MANAGER_PATH`, hooks) out, and the
    # client env is scrubbed of the same variable since the server's global
    # environment is a copy of it at start-up.
    env -u TMUX_PLUGIN_MANAGER_PATH tmux -L "$SOCKET" -f /dev/null new-session -d -s t -x 120 -y 40 "$(pane_shell "$bin_dir:/usr/bin:/bin")"
    if tmx show-environment -g TMUX_PLUGIN_MANAGER_PATH >/dev/null 2>&1; then
        echo "fixture error: test server inherited TMUX_PLUGIN_MANAGER_PATH" >&2
        return 1
    fi
    tmx split-window -t t "$(pane_shell "/usr/bin:/bin")"
    CLAUDE_PANE="$(tmx list-panes -t t -F '#{pane_id}' | head -1)"
    wait_for "shell prompt in claude pane" pane_shows_prompt "$CLAUDE_PANE"
    tmx send-keys -t "$CLAUDE_PANE" -l 'claude'
    tmx send-keys -t "$CLAUDE_PANE" Enter
    wait_for "fake claude did not start" fake_claude_process_up "$bin_dir"
}

# run_restart <args...>; sets RC, OUT. Knobs (set per call):
#   RESTART_TIMEOUT       TMUX_RESTART_TIMEOUT passed to the script (default 15)
#   RESTART_RETRY         TMUX_RESTART_RETRY passed to the script (default 5)
#   RESTART_PLUGINS       TMUX_PLUGIN_MANAGER_PATH passed to the script
#                         (default $PLUGINS; "unset" removes it from the env)
#   RESTART_HOME          HOME for the script (default: this shell's HOME)
run_restart() {
    local plugins="${RESTART_PLUGINS-$PLUGINS}" env_args=""
    if [ "$plugins" = "unset" ]; then
        env_args="-u TMUX_PLUGIN_MANAGER_PATH"
    else
        env_args="TMUX_PLUGIN_MANAGER_PATH=$plugins"
    fi
    set +e
    # shellcheck disable=SC2086  # env_args is a deliberate word-split
    OUT="$(env $env_args HOME="${RESTART_HOME:-$HOME}" TMUX_RESTART_SETTINGS="$SETTINGS" \
        TMUX_RESTART_SETTLE=0.5 TMUX_RESTART_KEY_PAUSE=0.3 \
        TMUX_RESTART_TIMEOUT="${RESTART_TIMEOUT:-15}" TMUX_RESTART_RETRY="${RESTART_RETRY:-5}" \
        "$RESTART" -L "$SOCKET" "$@" 2>&1)"
    RC=$?
    set -e
}

reset_fixture() {
    tmx kill-server 2>/dev/null || true
    rm -f "$SAVE_OUT" "$SAVE_RAN"
}

# ---------------------------------------------------------------------------
echo -e "${BLUE}=== tmux-restart: refuses without a server ===${NC}"
run_restart
check "exit 1 when no server on the socket" [ "$RC" -eq 1 ]
check "error message names the socket" grep -q "no tmux server reachable" <<<"$OUT"

# ---------------------------------------------------------------------------
echo -e "${BLUE}=== tmux-restart: --dry-run ===${NC}"
start_server "$BIN_OK"
run_restart --dry-run
check "dry-run exits 0" [ "$RC" -eq 0 ]
check "dry-run lists the claude pane id" grep -q "$CLAUDE_PANE" <<<"$OUT"
check "dry-run reports exactly one target pane" grep -q "1 pane(s)" <<<"$OUT"
check "dry-run leaves the server alive" server_alive
check "dry-run does not run the save stub" [ ! -e "$SAVE_RAN" ]
check "dry-run leaves fake claude running" fake_claude_process_up "$BIN_OK"
reset_fixture

# ---------------------------------------------------------------------------
echo -e "${BLUE}=== tmux-restart: happy path ===${NC}"
start_server "$BIN_OK"
run_restart
check "exit 0" [ "$RC" -eq 0 ]
check "reports all claude instances exited" grep -q "all claude instances exited" <<<"$OUT"
check "save stub ran" [ -e "$SAVE_RAN" ]
check "saved pane contents contain the resume hint at line start" \
    grep -Eq "^[[:space:]]*$RESUME_HINT" "$SAVE_OUT"
check "server is gone" server_gone
reset_fixture

# ---------------------------------------------------------------------------
echo -e "${BLUE}=== tmux-restart: /exit swallowed once, retry ===${NC}"
start_server "$BIN_SECOND"
RESTART_RETRY=2 run_restart
check "retry: exit 0" [ "$RC" -eq 0 ]
check "retry: log shows exactly one retry (attempt 2)" \
    [ "$(grep -c 're-sending /exit' <<<"$OUT")" -eq 1 ]
check "retry: retry log line is attempt 2" grep -q "attempt 2: re-sending /exit to 1 pane(s)" <<<"$OUT"
check "retry: resume hint saved" grep -Eq "^[[:space:]]*$RESUME_HINT" "$SAVE_OUT"
check "retry: server gone" server_gone
reset_fixture

# ---------------------------------------------------------------------------
echo -e "${BLUE}=== tmux-restart: stuck claude, timeout ===${NC}"
start_server "$BIN_STUCK"
RESTART_TIMEOUT=$STUCK_TIMEOUT run_restart
check "exit 1 on timeout" [ "$RC" -eq 1 ]
no_retry_logged() { ! grep -q "re-sending /exit" <<<"$OUT"; }
check "no retry within a timeout shorter than the retry interval" no_retry_logged
check "timeout message lists the stuck pane" grep -q "$CLAUDE_PANE" <<<"$OUT"
check "server still alive after timeout" server_alive
check "save stub NOT run after timeout" [ ! -e "$SAVE_RAN" ]

echo -e "${BLUE}=== tmux-restart: stuck claude, --force ===${NC}"
RESTART_TIMEOUT=$STUCK_TIMEOUT run_restart --force
check "--force exits 0" [ "$RC" -eq 0 ]
check "--force warns about the stuck pane" grep -q "force given" <<<"$OUT"
check "--force ran the save stub" [ -e "$SAVE_RAN" ]
check "--force killed the server" server_gone
reset_fixture

# ---------------------------------------------------------------------------
echo -e "${BLUE}=== tmux-restart: vim mode detection ===${NC}"
echo '{"vimMode": true}' > "$SETTINGS"
start_server "$BIN_OK"
run_restart
check "vim mode: exit 0" [ "$RC" -eq 0 ]
check "vim mode: announces Escape+i" grep -q "vim mode on" <<<"$OUT"
check "vim mode: resume hint saved (fake claude accepted Escape,i prefix)" \
    grep -Eq "^[[:space:]]*$RESUME_HINT" "$SAVE_OUT"
echo '{}' > "$SETTINGS"
reset_fixture

# ---------------------------------------------------------------------------
echo -e "${BLUE}=== tmux-restart: plugin path resolution ===${NC}"
# Same stub under a tilde-relative dir; HOME is pointed at $TMP so `~` expands
# to it without touching the real home directory.
TILDE_REL="plugins-tilde"
mkdir -p "$TMP/$TILDE_REL/tmux-resurrect/scripts"
cp "$SAVE_STUB" "$TMP/$TILDE_REL/tmux-resurrect/scripts/save.sh"

start_server "$BIN_OK"
RESTART_HOME="$TMP" RESTART_PLUGINS="~/$TILDE_REL/" run_restart
check "tilde + trailing slash in TMUX_PLUGIN_MANAGER_PATH: exit 0" [ "$RC" -eq 0 ]
check "tilde + trailing slash: save stub ran" [ -e "$SAVE_RAN" ]
check "tilde + trailing slash: resume hint saved" grep -Eq "^[[:space:]]*$RESUME_HINT" "$SAVE_OUT"
check "tilde + trailing slash: server gone" server_gone
reset_fixture

start_server "$BIN_OK"
tmx set-environment -g TMUX_PLUGIN_MANAGER_PATH "~/$TILDE_REL/"
RESTART_HOME="$TMP" RESTART_PLUGINS=unset run_restart
check "path from server set-environment (process env unset): exit 0" [ "$RC" -eq 0 ]
check "path from server set-environment: save stub ran" [ -e "$SAVE_RAN" ]
check "path from server set-environment: server gone" server_gone
reset_fixture

start_server "$BIN_OK"
tmx set-environment -g TMUX_PLUGIN_MANAGER_PATH "~/$TILDE_REL/"
RESTART_HOME="$TMP" RESTART_PLUGINS="$TMP/does-not-exist" run_restart --dry-run
check "server env wins over process env (dry-run names the server path)" \
    grep -q "would then run $TMP/$TILDE_REL/tmux-resurrect/scripts/save.sh" <<<"$OUT"
reset_fixture

echo -e "${BLUE}=== tmux-restart: missing save.sh ===${NC}"
start_server "$BIN_OK"
RESTART_PLUGINS="$TMP/does-not-exist" run_restart
check "missing save.sh: exit 1" [ "$RC" -eq 1 ]
check "missing save.sh: error names the path" grep -q "save.sh not found at $TMP/does-not-exist" <<<"$OUT"
check "missing save.sh: server left alive" server_alive
check "missing save.sh: save stub not run" [ ! -e "$SAVE_RAN" ]

RESTART_PLUGINS="$TMP/does-not-exist" run_restart --force
check "missing save.sh + --force: exit 0" [ "$RC" -eq 0 ]
check "missing save.sh + --force: warns about killing without saving" grep -q "killing without saving" <<<"$OUT"
check "missing save.sh + --force: server gone" server_gone
reset_fixture

# ---------------------------------------------------------------------------
echo -e "${BLUE}=== fastfetch gate: once per boot ===${NC}"
if command -v zsh >/dev/null 2>&1; then
    GATE="$TMP/fetch-gate.zsh"
    sed -n '/^# fetch-banner:begin/,/^# fetch-banner:end/p' "$ZSHRC" > "$GATE"
    FAKE_FF="$TMP/bin-ff"
    mkdir -p "$FAKE_FF"
    printf '#!/bin/bash\necho FAKE-BANNER\n' > "$FAKE_FF/fastfetch"
    chmod +x "$FAKE_FF/fastfetch"
    CACHE="$TMP/xdg-cache"
    run_gate() {
        XDG_CACHE_HOME="$CACHE" DOTFILES_FETCH_BANNER=1 PATH="$FAKE_FF:/usr/sbin:/usr/bin:/bin" \
            zsh -f "$GATE" 2>&1
    }
    check "gate block extracted from zshrc" [ -s "$GATE" ]
    FIRST="$(run_gate)"
    SECOND="$(run_gate)"
    check "first shell after boot prints the banner" grep -q "FAKE-BANNER" <<<"$FIRST"
    check "boot-id marker written" [ -s "$CACHE/fastfetch-boot-id" ]
    check "second shell in the same boot is silent" [ -z "$SECOND" ]
    echo "previous-boot" > "$CACHE/fastfetch-boot-id"
    THIRD="$(run_gate)"
    check "banner prints again when the boot id changes" grep -q "FAKE-BANNER" <<<"$THIRD"
else
    echo "  SKIP zsh not installed"
fi

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}"
[[ $FAIL -eq 0 ]]
