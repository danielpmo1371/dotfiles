#!/usr/bin/env bash
#
# Tests for util-scripts/tmux-control-panel.sh (prefix + C-c: Wi-Fi, Bluetooth,
# tmux theme, weather and clock toggles, desktop hub, in a palette-style popup).
#
# Pins: --popup opens the borderless palette popup on the given client and
# passes that client to the run mode; the list has the entries in order, with
# the hub only when hub-shell is installed, and the palette look (shared fzf
# options) with FZF_DEFAULT_OPTS cleared; each entry runs its tool in the same
# popup (Wi-Fi and Bluetooth popups' run modes, the theme picker's --pick) or
# flips its status-bar option and redraws that client; Esc runs nothing.
#
# Hermetic: the panel and the palette library are copied next to stub tools;
# tmux, fzf and hub-shell are stubs; the palette theme is the fallback.
#
# Usage: ./tests/test-tmux-control-panel.sh

set -uo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_NAME='/dev/pts/7'
CLIENT_WIDTH=200
CLIENT_HEIGHT=50
EXPECTED_WIDTH=90
EXPECTED_HEIGHT=20

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

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-tmux-control-panel.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
SCRIPTS="$ROOT/util-scripts"
STUB="$ROOT/bin"
HUB_STUB="$ROOT/hub-bin"
REC="$ROOT/rec"
mkdir -p "$SCRIPTS" "$STUB" "$HUB_STUB" "$REC"
cp "$DOTFILES_ROOT/util-scripts/tmux-control-panel.sh" "$DOTFILES_ROOT/util-scripts/tmux-palette-style.sh" "$SCRIPTS/"
PANEL="$SCRIPTS/tmux-control-panel.sh"

# shellcheck source=../util-scripts/tmux-palette-style.sh
TMUX_PALETTE_DIR=/nonexistent source "$SCRIPTS/tmux-palette-style.sh"

# Tools the panel opens: each records its name and arguments.
for tool in tmux-wifi-popup.sh tmux-bt-popup.sh tmux-theme.sh; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/ran"\n' "$tool" "$REC" > "$SCRIPTS/$tool"
done
printf '#!/usr/bin/env bash\necho "hub-shell $*" >> "%s/ran"\n' "$REC" > "$HUB_STUB/hub-shell"

cat > "$STUB/tmux" <<EOF
#!/usr/bin/env bash
{ printf '%s\n' "\$@"; echo --; } >> "$REC/tmux-calls"
case "\$*" in
    *client_width*)  echo $CLIENT_WIDTH ;;
    *client_height*) echo $CLIENT_HEIGHT ;;
esac
EOF
# Fake fzf: records argv, input and FZF_DEFAULT_OPTS; picks the line whose
# action (first field) is \$FZF_PICK, or exits 130 (Esc) when it is empty.
cat > "$STUB/fzf" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$REC/fzf-args"
printf '%s' "\${FZF_DEFAULT_OPTS:-unset}" > "$REC/fzf-default-opts"
cat > "$REC/fzf-input"
[[ -n "\${FZF_PICK:-}" ]] || exit 130
awk -F'\t' -v p="\$FZF_PICK" '\$1 == p { print; found=1; exit } END { exit !found }' "$REC/fzf-input"
EOF
cat > "$STUB/tput" <<'EOF'
#!/usr/bin/env bash
echo 90
EOF
chmod +x "$SCRIPTS"/* "$STUB"/* "$HUB_STUB"/*

# run [env...] -- [args...]
run() {
    local -a envs=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
    shift
    : > "$REC/tmux-calls"; : > "$REC/ran"
    env -i PATH="${STUB_PATH:-$STUB}:/usr/bin:/bin" HOME="$ROOT" TMUX_PALETTE_DIR=/nonexistent \
        FZF_DEFAULT_OPTS='--tmux center,75%' "${envs[@]}" bash "$PANEL" "$@"
}
popup_call() { awk '/^display-popup$/,/^--$/' "$REC/tmux-calls" | sed '$d'; }
tmux_call() { awk -v c="$1" '$0 == c { on=1 } on { print } on && /^--$/ { exit }' "$REC/tmux-calls" | sed '$d'; }

echo "--popup <client>: palette popup on that client, client passed on"
run -- --popup "$CLIENT_NAME"; rc=$?
check "exit 0" "0" "$rc"
check "display-popup argv" \
    "$(printf '%s\n' display-popup -c "$CLIENT_NAME" -B -s "bg=$DEFAULT_THEME_PANEL" -w "$EXPECTED_WIDTH" -h "$EXPECTED_HEIGHT" -E "$PANEL $CLIENT_NAME")" \
    "$(popup_call)"

echo "--popup without a client"
run -- --popup
check "display-popup argv" \
    "$(printf '%s\n' display-popup -B -s "bg=$DEFAULT_THEME_PANEL" -w "$EXPECTED_WIDTH" -h "$EXPECTED_HEIGHT" -E "$PANEL")" \
    "$(popup_call)"

echo "list: entries in order, palette look, Esc runs nothing"
run FZF_PICK= -- "$CLIENT_NAME"; rc=$?
check "Esc: exit 0" "0" "$rc"
check "Esc: nothing ran" "" "$(cat "$REC/ran")"
check "entries without hub-shell" "$(printf '%s\n' wifi bluetooth theme weather clock)" "$(cut -f1 "$REC/fzf-input")"
contains "Wi-Fi row" "Wi-Fi" "$(grep '^wifi' "$REC/fzf-input")"
check "FZF_DEFAULT_OPTS cleared" "unset" "$(cat "$REC/fzf-default-opts")"
args="$(cat "$REC/fzf-args")"
contains "title row" "Control panel" "$(grep '^--input-label=' <<<"$args")"
check "palette colours" "--color=$(load_theme; palette_fzf_colors)" "$(grep '^--color=' <<<"$args")"
check "shows the label, not the action" "--with-nth=2.." "$(grep '^--with-nth' <<<"$args")"

echo "hub entry only when hub-shell is installed"
STUB_PATH="$STUB:$HUB_STUB" run FZF_PICK= -- "$CLIENT_NAME"
check "entries with hub-shell" "$(printf '%s\n' wifi bluetooth theme weather clock hub)" "$(cut -f1 "$REC/fzf-input")"
STUB_PATH="$STUB:$HUB_STUB" run FZF_PICK=hub -- "$CLIENT_NAME"
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$REC/ran" ]] && break; sleep 0.1; done
check "hub toggled" "hub-shell toggle" "$(cat "$REC/ran")"

echo "entries run their tool in the same popup"
run FZF_PICK=wifi -- "$CLIENT_NAME"
check "Wi-Fi popup run mode" "tmux-wifi-popup.sh " "$(cat "$REC/ran")"
run FZF_PICK=bluetooth -- "$CLIENT_NAME"
check "Bluetooth popup run mode" "tmux-bt-popup.sh " "$(cat "$REC/ran")"
run FZF_PICK=theme -- "$CLIENT_NAME"
check "theme picker" "tmux-theme.sh --pick" "$(cat "$REC/ran")"
lacks "no nested popup" "display-popup" "$(cat "$REC/tmux-calls")"

echo "toggles flip the option and redraw the client"
run FZF_PICK=weather -- "$CLIENT_NAME"
check "weather option" "$(printf '%s\n' set -gF @power_weather '#{?@power_weather,0,1}')" "$(tmux_call set)"
check "redraw that client" "$(printf '%s\n' refresh-client -t "$CLIENT_NAME" -S)" "$(tmux_call refresh-client)"
run FZF_PICK=clock --
check "clock option" "$(printf '%s\n' set -gF @datetime_collapsed '#{?@datetime_collapsed,0,1}')" "$(tmux_call set)"
check "no client: redraw the current one" "$(printf '%s\n' refresh-client -S)" "$(tmux_call refresh-client)"

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0))
