#!/bin/bash

# End-to-end test for util-scripts/tmux-restart.sh against the REAL `claude`
# binary and the REAL tmux-resurrect save.sh, on a throwaway tmux server.
# Usage: E2E_TMUX_RESTART=1 ./tests/e2e-tmux-restart.sh
#
# OPT-IN AND NOT FREE: every scenario starts a real Claude Code session and
# sends it one or two prompts, so it costs API calls and needs a logged-in
# `claude` plus network access. Without E2E_TMUX_RESTART=1 the script prints
# SKIP and exits 0 so nothing here can call the API by accident. The hermetic
# fake-claude suite is tests/test-tmux-restart.sh; keep using that for logic.
#
# Side effects that are NOT undone: each scenario creates a Claude Code
# session transcript under ~/.claude/projects/ for E2E_TMUX_RESTART_CWD (the
# working directory claude runs in; default ~/.cache/tmux-restart-e2e, created
# once and kept so any folder-trust decision is made only once). If claude
# shows its folder-trust prompt for that directory, the script answers
# "Yes, I trust this folder", which adds a trust entry to ~/.claude.json.
#
# Safety invariants (asserted, not assumed):
#   - own server only: `tmux -L e2e-tmux-restart-$$ -f /dev/null`; the default
#     server is never addressed.
#   - the throwaway server is started with every CLAUDE* variable scrubbed
#     from its environment: when this script itself runs under a Claude Code
#     session, the inherited CLAUDE_CODE_CHILD_SESSION marker makes the nested
#     claude switch transcript saving OFF, and it then never prints a resume
#     hint. The script fails loudly if the pane shows that warning.
#   - resurrect writes go to a temp @resurrect-dir; the default resurrect
#     dir's `last` link is recorded before and, if it changed during the run
#     (tmux-continuum autosaves the default server every few minutes), the
#     new save file must not list the throwaway session.
#   - EXIT trap: SIGTERM any claude left in the throwaway panes, kill the
#     throwaway server, remove the temp dir.
#
# Scenarios:
#   1. full restart, idle claude with one completed turn -> hint saved
#   2. full restart while claude is mid-turn -> hint saved (reports whether
#      the /exit retry fired)
#   3. full restart, empty session -> exits, no hint (known behaviour; a hint
#      is reported as INFO, not a failure)
#   4. --pane round-trip: two claudes, exit one, `claude --resume <uuid>` it
#      from the pane's own scrollback (same regex as `cres`), conversation
#      restored, the other claude untouched, nothing saved.
#
# Exit status: 0 all scenarios passed (or SKIP), 1 a check failed,
#              2 prerequisites missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
RESTART="$DOTFILES_ROOT/util-scripts/tmux-restart.sh"

EXIT_FAIL=1
EXIT_PREREQ=2

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<EOF
Environment:
  E2E_TMUX_RESTART=1        Required; without it the script SKIPs (exit 0).
  E2E_TMUX_RESTART_CWD      Directory claude runs in
                            (default \${XDG_CACHE_HOME:-~/.cache}/tmux-restart-e2e)
  E2E_READY_TIMEOUT         Seconds to wait for claude to be ready   (default 90)
  E2E_ANSWER_TIMEOUT        Seconds to wait for a reply             (default 180)
  TMUX_PLUGIN_MANAGER_PATH  Where tmux-resurrect lives (default ~/.tmux/plugins)
EOF
    exit 0
fi

if [ "${E2E_TMUX_RESTART:-0}" != "1" ]; then
    echo "SKIP: set E2E_TMUX_RESTART=1 to run the real-claude end-to-end test (costs API calls)"
    exit 0
fi

SOCKET="e2e-tmux-restart-$$"
SESSION="e2e-tmux-restart-$$"
E2E_CWD="${E2E_TMUX_RESTART_CWD:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux-restart-e2e}"
READY_TIMEOUT="${E2E_READY_TIMEOUT:-90}"
ANSWER_TIMEOUT="${E2E_ANSWER_TIMEOUT:-180}"
POLL=1
KEY_PAUSE=0.5           # between typing a line and pressing Enter
MID_TURN_DELAY=1        # how long the long prompt runs before the restart fires
PANE_WIDTH=160
PANE_HEIGHT=45
PLUGIN_PATH_LITERAL='~/.tmux/plugins/'   # mirrors tmux.conf (tilde on purpose)

READY_RE='auto mode|bypass permissions|for shortcuts'
NO_TRANSCRIPT_RE='Transcript saving is off'
TRUST_RE='Is this a project you created'
HINT_RE='^[[:space:]]*claude --resume [0-9a-f-]{36}'
CLAUDE_ARGS_RE='(^|/)claude( |$)'

PASS=0
FAIL=0
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }
info() { echo -e "  ${YELLOW}INFO${NC} $1"; }
check() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
section() { echo -e "${BLUE}=== $1 ===${NC}"; }

tmx() { tmux -L "$SOCKET" "$@"; }
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }
cap() { tmx capture-pane -p -S - -t "$1" 2>/dev/null | strip_ansi; }
server_alive() { tmx list-sessions >/dev/null 2>&1; }
server_gone() { ! server_alive; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
prereq_fail() { echo "PREREQ: $1" >&2; exit "$EXIT_PREREQ"; }
command -v claude >/dev/null 2>&1 || prereq_fail "claude not on PATH"
command -v tmux >/dev/null 2>&1 || prereq_fail "tmux not on PATH"
PLUGIN_PATH="${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins}"
PLUGIN_PATH="${PLUGIN_PATH/#\~/$HOME}"
SAVE_SH="${PLUGIN_PATH%/}/tmux-resurrect/scripts/save.sh"
[ -x "$SAVE_SH" ] || prereq_fail "tmux-resurrect save.sh not found at $SAVE_SH"
[ -x "$RESTART" ] || prereq_fail "$RESTART missing or not executable"

mkdir -p "$E2E_CWD"
TMP="$(mktemp -d)"
RESDIR="$TMP/resurrect"
mkdir -p "$RESDIR"

# Default resurrect dirs (both locations tmux-resurrect may use). A save
# misdirected at the default server would list our throwaway session there.
DEFAULT_RESURRECT_DIRS=("${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect" "$HOME/.tmux/resurrect")
snapshot_default_resurrect() {
    local d
    for d in "${DEFAULT_RESURRECT_DIRS[@]}"; do
        [ -d "$d" ] || continue
        printf '%s last=%s\n' "$d" "$(readlink "$d/last" 2>/dev/null || echo none)"
    done
}
# default_resurrect_lists_our_session: true if any default `last` save file
# has a pane row for the throwaway session.
default_resurrect_lists_our_session() {
    local d f
    for d in "${DEFAULT_RESURRECT_DIRS[@]}"; do
        f="$d/$(readlink "$d/last" 2>/dev/null || true)"
        [ -f "$f" ] || continue
        awk -F'\t' -v s="$SESSION" '$1=="pane" && $2==s { found=1 } END { exit found ? 0 : 1 }' "$f" && return 0
    done
    return 1
}
RESURRECT_BEFORE="$(snapshot_default_resurrect)"

# ---------------------------------------------------------------------------
# Process helpers (same tree walk as tmux-restart.sh)
# ---------------------------------------------------------------------------
# claude_pids_under <pid>: pids of claude processes in that pane's tree.
claude_pids_under() {
    ps -Ao pid=,ppid=,args= | awk -v root="$1" -v re="$CLAUDE_ARGS_RE" '
        { pid=$1; ppid=$2; $1=""; $2=""; sub(/^[[:space:]]+/, ""); args[pid]=$0; kids[ppid]=kids[ppid] " " pid }
        END {
            n=1; stack[n]=root
            while (n>0) {
                cur=stack[n]; n--
                if (cur in args && args[cur] ~ re) print cur
                split(kids[cur], ch, " ")
                for (i in ch) if (ch[i] != "") { n++; stack[n]=ch[i] }
            }
        }'
}
pane_pid() { tmx display-message -p -t "$1" '#{pane_pid}'; }
pane_has_claude() { [ -n "$(claude_pids_under "$(pane_pid "$1")")" ]; }
pane_has_no_claude() { ! pane_has_claude "$1"; }

cleanup() {
    local rc=$?
    if server_alive; then
        local p pid
        for p in $(tmx list-panes -a -F '#{pane_id}' 2>/dev/null); do
            for pid in $(claude_pids_under "$(pane_pid "$p")"); do
                kill -TERM "$pid" 2>/dev/null || true
            done
        done
        tmx kill-server 2>/dev/null || true
    fi
    rm -rf "$TMP"
    if default_resurrect_lists_our_session; then
        echo -e "${RED}SAFETY: a default tmux-resurrect save lists the throwaway session $SESSION${NC}" >&2
        echo "before: $RESURRECT_BEFORE" >&2
        echo "after:  $(snapshot_default_resurrect)" >&2
        exit "$EXIT_FAIL"
    fi
    exit "$rc"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# tmux / claude helpers
# ---------------------------------------------------------------------------
# Bare bash with a known prompt; inherits PATH/HOME so claude, its login and
# the user's hooks work. No user rc files: `cres` is therefore NOT defined in
# these panes; scenario 4 types the `claude --resume <uuid>` that cres would.
pane_shell() {
    printf "env TERM=xterm-256color PS1='e2e\\$ ' /bin/bash --noprofile --norc"
}

# `env -u` flags for every CLAUDE* variable in our environment (see header).
claude_env_scrub_flags() {
    env | grep -o '^CLAUDE[A-Za-z0-9_]*' | sed 's/^/-u /' | tr '\n' ' '
}
pane_shows_prompt() { cap "$1" | grep -q 'e2e\$'; }

# wait_pane <pane> <ERE> <timeout-s> <label>: until the pane matches.
wait_pane() {
    local pane="$1" re="$2" timeout="$3" label="$4" start=$SECONDS
    while :; do
        if cap "$pane" | grep -Eq "$re"; then return 0; fi
        if [ $((SECONDS - start)) -ge "$timeout" ]; then
            echo "timeout (${timeout}s) waiting for: $label in $pane" >&2
            cap "$pane" | grep -v '^[[:space:]]*$' | tail -15 >&2
            return 1
        fi
        sleep "$POLL"
    done
}

# wait_cond <timeout-s> <label> <command...>
wait_cond() {
    local timeout="$1" label="$2" start=$SECONDS; shift 2
    while :; do
        if "$@"; then return 0; fi
        if [ $((SECONDS - start)) -ge "$timeout" ]; then
            echo "timeout (${timeout}s) waiting for: $label" >&2
            return 1
        fi
        sleep "$POLL"
    done
}

start_server() {
    # shellcheck disable=SC2046  # the -u flags are meant to word-split
    env $(claude_env_scrub_flags) tmux -L "$SOCKET" -f /dev/null \
        new-session -d -s "$SESSION" -x "$PANE_WIDTH" -y "$PANE_HEIGHT" -c "$E2E_CWD" "$(pane_shell)"
    tmx set -g @resurrect-dir "$RESDIR"
    tmx set -g @resurrect-capture-pane-contents on
    tmx set -g history-limit 50000
    tmx set-environment -g TMUX_PLUGIN_MANAGER_PATH "$PLUGIN_PATH_LITERAL"
    PANE_A="$(tmx list-panes -t "$SESSION" -F '#{pane_id}')"
    wait_pane "$PANE_A" 'e2e\$' "$READY_TIMEOUT" "shell prompt"
}

add_pane() {
    tmx split-window -h -t "$SESSION" -c "$E2E_CWD" "$(pane_shell)"
    PANE_B="$(tmx list-panes -t "$SESSION" -F '#{pane_id}' | sed -n 2p)"
    wait_pane "$PANE_B" 'e2e\$' "$READY_TIMEOUT" "shell prompt (pane B)"
}

type_line() { # type_line <pane> <text>
    tmx send-keys -t "$1" -l "$2"
    sleep "$KEY_PAUSE"
    tmx send-keys -t "$1" Enter
}

# start_claude <pane>: launch claude, answer the folder-trust prompt if it
# appears (default option is "No, exit", so Down then Enter), wait for ready.
start_claude() {
    local pane="$1" start=$SECONDS out
    type_line "$pane" "claude"
    while :; do
        out="$(cap "$pane")"
        if grep -Eq "$NO_TRANSCRIPT_RE" <<<"$out"; then
            echo "claude in $pane reports transcript saving OFF (inherited CLAUDE_CODE_CHILD_SESSION); it will never print a resume hint" >&2
            return 1
        fi
        if grep -Eq "$READY_RE" <<<"$out"; then return 0; fi
        if grep -q "$TRUST_RE" <<<"$out"; then
            info "folder-trust prompt shown for $E2E_CWD; answering 'Yes, I trust this folder'"
            tmx send-keys -t "$pane" Down
            sleep "$KEY_PAUSE"
            tmx send-keys -t "$pane" Enter
            sleep "$POLL"
        fi
        if [ $((SECONDS - start)) -ge "$READY_TIMEOUT" ]; then
            echo "timeout (${READY_TIMEOUT}s) waiting for claude ready in $pane" >&2
            grep -v '^[[:space:]]*$' <<<"$out" | tail -15 >&2
            return 1
        fi
        sleep "$POLL"
    done
}

# ask_token <pane> <token>: one cheap turn whose reply is TOKEN; waits for the
# reply line (⏺ ... TOKEN) - never for the echoed prompt.
ask_token() {
    local pane="$1" token="$2"
    type_line "$pane" "Reply with exactly the single word $token and nothing else."
    wait_pane "$pane" "^[[:space:]]*⏺.*$token" "$ANSWER_TIMEOUT" "reply containing $token"
}

new_token() { printf 'E2E%s%s' "$1" "$(date +%s | tail -c 5)$RANDOM"; }

run_restart() { # sets RC, OUT
    set +e
    OUT="$("$RESTART" -L "$SOCKET" "$@" 2>&1)"
    RC=$?
    set -e
}

# archive_hint_lines: resume-hint lines from the temp resurrect archive.
archive_hint_lines() {
    local out="$TMP/archive"
    rm -rf "$out"; mkdir -p "$out"
    [ -f "$RESDIR/pane_contents.tar.gz" ] || return 1
    tar xzf "$RESDIR/pane_contents.tar.gz" -C "$out"
    # save.sh captures with -e (SGR escapes kept); strip before matching, as
    # the restored pane renders them and `cres` sees plain text.
    cat "$out"/pane_contents/* 2>/dev/null | strip_ansi | grep -E "$HINT_RE" || true
}
archive_has_hint() { [ -n "$(archive_hint_lines)" ]; }
archive_has_no_hint() { ! archive_has_hint; }
archive_exists() { [ -f "$RESDIR/pane_contents.tar.gz" ]; }
archive_absent() { ! archive_exists; }
retry_logged() { grep -q "re-sending /exit" <<<"$OUT"; }

reset_resdir() { rm -rf "$RESDIR"; mkdir -p "$RESDIR"; }
elapsed() { echo "  (scenario wall time: $((SECONDS - SCENARIO_START))s)"; }

# ---------------------------------------------------------------------------
section "1. full restart, idle claude with one completed turn"
SCENARIO_START=$SECONDS
start_server
start_claude "$PANE_A"
TOKEN1="$(new_token A)"
ask_token "$PANE_A" "$TOKEN1"
run_restart
check "script exit 0" [ "$RC" -eq 0 ]
check "log: all claude instances exited" grep -q "all claude instances exited" <<<"$OUT"
check "log: layout saved with tmux-resurrect" grep -q "saving layout with tmux-resurrect" <<<"$OUT"
check "throwaway server gone" server_gone
check "resurrect archive written to the temp @resurrect-dir" archive_exists
check "saved pane contents contain 'claude --resume <uuid>' at line start" archive_has_hint
[ "$FAIL" -eq 0 ] && info "hint line: $(archive_hint_lines | tail -1 | sed 's/^[[:space:]]*//')"
elapsed
reset_resdir

# ---------------------------------------------------------------------------
section "2. full restart while claude is mid-turn"
SCENARIO_START=$SECONDS
start_server
start_claude "$PANE_A"
type_line "$PANE_A" "Count slowly from 1 to 40, writing one full sentence for each number before moving on to the next."
sleep "$MID_TURN_DELAY"
run_restart
check "script exit 0" [ "$RC" -eq 0 ]
check "throwaway server gone" server_gone
check "saved pane contents contain the resume hint" archive_has_hint
if retry_logged; then
    info "the /exit retry fired: $(grep -c 're-sending /exit' <<<"$OUT") re-send(s) (first /exit swallowed by the interrupt re-render)"
else
    info "no retry needed: claude exited on the first /exit"
fi
elapsed
reset_resdir

# ---------------------------------------------------------------------------
section "3. full restart, empty session (no turns)"
SCENARIO_START=$SECONDS
start_server
start_claude "$PANE_A"
run_restart
check "script exit 0" [ "$RC" -eq 0 ]
check "throwaway server gone" server_gone
check "resurrect archive written" archive_exists
if archive_has_no_hint; then
    pass "no resume hint for an empty session (known behaviour, nothing to resume)"
else
    info "this claude version prints a resume hint even for an empty session: $(archive_hint_lines | tail -1 | sed 's/^[[:space:]]*//')"
fi
elapsed
reset_resdir

# ---------------------------------------------------------------------------
section "4. --pane round-trip: exit one of two claudes and resume it"
SCENARIO_START=$SECONDS
start_server
add_pane
start_claude "$PANE_A"
start_claude "$PANE_B"
TOKEN_A="$(new_token A)"
TOKEN_B="$(new_token B)"
ask_token "$PANE_A" "$TOKEN_A"
ask_token "$PANE_B" "$TOKEN_B"
run_restart --pane "$PANE_A"
check "--pane $PANE_A: exit 0" [ "$RC" -eq 0 ]
check "--pane: success line points at prefix+R" grep -q "claude exited in $PANE_A; prefix+R (cres) resumes it" <<<"$OUT"
check "--pane: pane A has no claude process left" pane_has_no_claude "$PANE_A"
check "--pane: pane B's claude still running" pane_has_claude "$PANE_B"
check "--pane: server still alive" server_alive
check "--pane: nothing saved (no archive in @resurrect-dir)" archive_absent
check "--pane: pane A scrollback has the resume hint" bash -c "grep -Eq '$HINT_RE' <<<\"\$1\"" _ "$(cap "$PANE_A")"
check "--pane: pane A's shell prompt is back (claude exited cleanly)" pane_shows_prompt "$PANE_A"

# Same extraction `cres` does (config/shell/aliases.sh). cres itself is not
# typed here: these panes have no rc files, and cres resumes via cdang, whose
# flags (--rc, --dangerously-skip-permissions) are not wanted in a test.
RESUME_ID="$( { cap "$PANE_A" \
    | grep -E '^[[:space:]]*claude --resume ' \
    | grep -Eo 'claude --resume ("[^"]+"|[A-Za-z0-9_-]+)' | tail -1 \
    | sed -E 's/^claude --resume "?([^"]+)"?$/\1/'; } || true)"
if [[ "$RESUME_ID" =~ ^[0-9a-f-]{36}$ ]]; then
    pass "--pane: uuid extracted with the cres regex"
else
    fail "--pane: uuid extracted with the cres regex (got '$RESUME_ID')"
fi
info "resuming pane A with: claude --resume $RESUME_ID"
type_line "$PANE_A" "claude --resume $RESUME_ID"
if [ -n "$RESUME_ID" ] && start_claude "$PANE_A"; then
    pass "resumed claude is ready in pane A"
    # The restored transcript is re-rendered, so the earlier reply is visible.
    check "pane A shows its own earlier reply ($TOKEN_A) - conversation restored" \
        bash -c "grep -Eq '^[[:space:]]*⏺.*$TOKEN_A' <<<\"\$1\"" _ "$(cap "$PANE_A")"
    check "pane A does not show pane B's token" bash -c "! grep -q '$TOKEN_B' <<<\"\$1\"" _ "$(cap "$PANE_A")"
else
    fail "resumed claude did not become ready in pane A"
fi
# Tidy both claudes through the script (single-pane mode, no save/kill).
run_restart --pane "$PANE_A" --pane "$PANE_B"
check "cleanup --pane A --pane B: exit 0" [ "$RC" -eq 0 ]
check "cleanup: no claude left in pane B" pane_has_no_claude "$PANE_B"
check "cleanup: server still alive (single-pane mode never kills it)" server_alive
elapsed
tmx kill-server 2>/dev/null || true

# ---------------------------------------------------------------------------
section "safety"
if [ "$(snapshot_default_resurrect)" != "$RESURRECT_BEFORE" ]; then
    info "default tmux-resurrect dir was saved during the run (tmux-continuum autosave of the default server); checking it is unrelated"
fi
if default_resurrect_lists_our_session; then
    fail "default tmux-resurrect save lists the throwaway session $SESSION"
else
    pass "default tmux-resurrect saves do not mention the throwaway session"
fi

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  (total wall time: ${SECONDS}s)"
[ "$FAIL" -eq 0 ]
