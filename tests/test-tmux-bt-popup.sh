#!/usr/bin/env bash
#
# Tests for util-scripts/tmux-bt-popup.sh (bt-fix in a tmux-palette-style popup,
# opened by clicking the Bluetooth glyph in the status bar).
#
# Pins: --popup opens a borderless popup with the palette panel as its body,
# sized like the palette (capped by the client) and on the clicking client when
# one is given; the run mode hands bt-fix the palette look through
# BT_FIX_FZF_OPTS (theme colour roles, accent prompt, title row, no bt-fix
# header) with FZF_DEFAULT_OPTS cleared; bt-fix's progress lines and its
# question reach the popup, indented; after bt-fix the outcome waits for a key,
# while Esc in the list (exit 130) closes straight away.
#
# Hermetic: tmux and bt-fix are stubs; the palette theme is the script's
# built-in fallback (TMUX_PALETTE_DIR points nowhere), so colours are fixed.
#
# Usage: ./tests/test-tmux-bt-popup.sh

set -uo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POPUP_SCRIPT="$DOTFILES_ROOT/util-scripts/tmux-bt-popup.sh"
STYLE_LIB="$DOTFILES_ROOT/util-scripts/tmux-palette-style.sh"

# Stub client size and the popup size the script asks for by default.
CLIENT_WIDTH=200
CLIENT_HEIGHT=50
SMALL_CLIENT_HEIGHT=15
EXPECTED_WIDTH=90
EXPECTED_HEIGHT=20
CLIENT_NAME='/dev/pts/42'
# How long a run may take before it counts as "waiting for a key".
WAIT_PROBE_SECONDS=2

PASS=0
FAIL=0

ok()  { echo "  PASS $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $1"; echo "       expected: $2"; echo "       actual:   $3"; FAIL=$((FAIL + 1)); }
check() {
    local label="$1" expected="$2" actual="$3"
    [[ "$actual" == "$expected" ]] && ok "$label" || bad "$label" "$expected" "$actual"
}
contains() {
    local label="$1" needle="$2" haystack="$3"
    [[ "$haystack" == *"$needle"* ]] && ok "$label" || bad "$label" "*$needle*" "$haystack"
}
lacks() {
    local label="$1" needle="$2" haystack="$3"
    [[ "$haystack" != *"$needle"* ]] && ok "$label" || bad "$label" "no '$needle'" "$haystack"
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-tmux-bt-popup.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
STUB="$ROOT/bin"
REC="$ROOT/rec"
mkdir -p "$STUB" "$REC"

# Fallback theme values, read from the library so the test follows it.
# shellcheck source=../util-scripts/tmux-palette-style.sh
TMUX_PALETTE_DIR=/nonexistent source "$STYLE_LIB"
PANEL="$DEFAULT_THEME_PANEL"
MUTED="$DEFAULT_THEME_MUTED"
SELECTED="$DEFAULT_THEME_SELECTED"
ACCENT_ANSI="$DEFAULT_THEME_ANSI_ACCENT"
MUTED_ANSI="$DEFAULT_THEME_ANSI_MUTED"

# Fake tmux: client size from $STUB_CLIENT_HEIGHT; records every call's argv
# (one argument per line, calls separated by "--").
cat > "$STUB/tmux" <<EOF
#!/usr/bin/env bash
{ printf '%s\n' "\$@"; echo --; } >> "$REC/tmux-calls"
case "\$*" in
    *client_width*)  echo $CLIENT_WIDTH ;;
    *client_height*) echo "\${STUB_CLIENT_HEIGHT:-$CLIENT_HEIGHT}" ;;
esac
EOF

# Fake bt-fix: records its fzf options and FZF_DEFAULT_OPTS, prints progress
# on stderr like the real one, optionally asks a question, exits $STUB_EXIT.
cat > "$STUB/bt-fix" <<EOF
#!/usr/bin/env bash
printf '%s' "\${BT_FIX_FZF_OPTS:-}" > "$REC/fzf-opts"
printf '%s' "\${FZF_DEFAULT_OPTS:-unset}" > "$REC/fzf-default-opts"
printf 'bt-fix: scanning for 8s…\n' >&2
if [[ -n "\${STUB_ASK:-}" ]]; then
    printf 'bt-fix: remove the saved pairing? [y/N] ' >&2
    read -r answer
    printf 'bt-fix: answer was %s\n' "\$answer" >&2
fi
printf 'bt-fix: done\n' >&2
exit "\${STUB_EXIT:-0}"
EOF
cat > "$STUB/tput" <<'EOF'
#!/usr/bin/env bash
echo 90
EOF
chmod +x "$STUB"/*

# The script's environment: stubs first, no palette plugin, and the
# FZF_DEFAULT_OPTS a user shell may carry (which must not reach fzf).
BASE_ENV=(env -i PATH="$STUB:/usr/bin:/bin" HOME="$ROOT" TMUX_PALETTE_DIR=/nonexistent
    TMUX_BT_FIX="$STUB/bt-fix" FZF_DEFAULT_OPTS='--tmux center,75%')

# run [env...] -- [args...]; stdin passes through (the popup's tty).
run() {
    local -a envs=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
    shift
    "${BASE_ENV[@]}" "${envs[@]}" bash "$POPUP_SCRIPT" "$@"
}
# probe_closes [env...]: run with a stdin that stays open but never sends a
# key; prints the exit status, 124 meaning it was still waiting after the probe.
probe_closes() {
    timeout "$WAIT_PROBE_SECONDS" "${BASE_ENV[@]}" "$@" bash "$POPUP_SCRIPT" \
        < <(sleep "$((WAIT_PROBE_SECONDS * 2))") > "$REC/probe-out"
    echo "$?"
}
popup_call() { awk '/^display-popup$/,/^--$/' "$REC/tmux-calls" | sed '$d'; }

echo "--popup: borderless, panel body, palette size"
: > "$REC/tmux-calls"
run -- --popup; rc=$?
check "exit 0" "0" "$rc"
check "display-popup argv" \
    "$(printf '%s\n' display-popup -B -s "bg=$PANEL" -w "$EXPECTED_WIDTH" -h "$EXPECTED_HEIGHT" -E "$POPUP_SCRIPT")" \
    "$(popup_call)"
lacks "no client given: no -c" "-c" "$(cat "$REC/tmux-calls")"

echo "--popup <client>: sized from and opened on that client"
: > "$REC/tmux-calls"
run -- --popup "$CLIENT_NAME"
check "display-popup on the client" \
    "$(printf '%s\n' display-popup -c "$CLIENT_NAME" -B -s "bg=$PANEL" -w "$EXPECTED_WIDTH" -h "$EXPECTED_HEIGHT" -E "$POPUP_SCRIPT")" \
    "$(popup_call)"
check "size read from the client" "2" "$(grep -c '^display-message$' "$REC/tmux-calls")"
check "all three calls target it" "3" "$(grep -cxF -- "$CLIENT_NAME" "$REC/tmux-calls")"

echo "--popup on a short client: height capped"
: > "$REC/tmux-calls"
run STUB_CLIENT_HEIGHT="$SMALL_CLIENT_HEIGHT" -- --popup
contains "height is client minus margin" \
    "$(printf -- '-h\n%s\n' "$((SMALL_CLIENT_HEIGHT - PALETTE_CLIENT_MARGIN_Y))")" "$(popup_call)"

echo "TMUX_BT_POPUP_HEIGHT overrides the height"
: > "$REC/tmux-calls"
run TMUX_BT_POPUP_HEIGHT=30 -- --popup
contains "height 30" "$(printf -- '-h\n30\n')" "$(popup_call)"

echo "run: bt-fix gets the palette look"
out=$(printf 'x' | run --); rc=$?
check "exit 0" "0" "$rc"
opts="$(cat "$REC/fzf-opts")"
color_line="$(grep '^--color=' <<<"$opts")"
contains "panel bg"               "bg:$PANEL,list-bg:$PANEL,input-bg:$PANEL" "$color_line"
contains "muted rows"             ",fg:$MUTED," "$color_line"
contains "bold current row on selected bg" "current-fg:regular:bold:$DEFAULT_THEME_CURRENT_FG,current-bg:$SELECTED" "$color_line"
check    "colours are the shared palette roles" "--color=$(load_theme; palette_fzf_colors)" "$color_line"
check    "accent prompt"          "--prompt=${ACCENT_ANSI}${PALETTE_MARKER_GLYPH} ${ANSI_RESET}" "$(grep '^--prompt=' <<<"$opts")"
check    "palette pointer"        "--pointer=$PALETTE_MARKER_GLYPH" "$(grep '^--pointer=' <<<"$opts")"
contains "title row"              "Bluetooth" "$(grep '^--input-label=' <<<"$opts")"
check    "bt-fix header dropped"  "--header=" "$(grep '^--header' <<<"$opts")"
check    "gutter keeps its space" "--gutter= " "$(grep '^--gutter' <<<"$opts")"
check    "one option per line"    "0" "$(grep -vc '^--' <<<"$opts")"
check    "FZF_DEFAULT_OPTS cleared" "unset" "$(cat "$REC/fzf-default-opts")"
contains "progress shown, indented and muted" "   ${MUTED_ANSI}bt-fix: scanning for 8s…" "$out"
contains "outcome: connected"     "Connected" "$out"
contains "waits for a key"        "press any key to close" "$out"

echo "run: bt-fix's question reaches the popup and its answer reaches bt-fix"
out=$(printf 'y\nx' | run STUB_ASK=1 --); rc=$?
check    "exit 0"              "0" "$rc"
contains "question shown"      "[y/N] " "$out"
contains "answer passed"       "answer was y" "$out"

echo "run: success waits for a key before closing"
check "still open without a key" "124" "$(probe_closes)"

echo "run: failure shows the outcome and waits for a key"
out=$(printf 'x' | run STUB_EXIT=1 --); rc=$?
check    "exit 0"                "0" "$rc"
contains "outcome: not connected" "Not connected" "$out"
contains "waits for a key"        "press any key to close" "$out"

echo "run: Esc in the list (bt-fix 130) closes straight away"
check "closed without a key" "0" "$(probe_closes STUB_EXIT=130)"
lacks "no outcome line"      "press any key" "$(cat "$REC/probe-out")"

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0))
