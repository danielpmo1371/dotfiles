#!/usr/bin/env bash
#
# Hermetic tests for the tmux theme switcher:
#   util-scripts/tmux-theme.sh   (list / current / apply / apply-saved / --pick)
#   config/tmux/themes/*.conf    (the themes themselves)
#
# Why this exists: themes replace each other by sourcing a file, so every theme
# must set the same options or the previous one leaks through. And every
# status-right must keep continuum_save.sh: continuum's autosave, which the
# Claude crash relaunch depends on, only runs while that string is in it.
#
# Runs against a private tmux server (-L) with -f /dev/null and a temp state
# file (TMUX_THEME_STATE); the script talks to "the server in $TMUX", so $TMUX
# is pointed at the private server. The user's own server is never touched.
# fzf is replaced by a stub for the picker cases (no tty needed).
#
# Usage: ./tests/test-tmux-theme.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
THEME_SCRIPT="$DOTFILES_ROOT/util-scripts/tmux-theme.sh"
THEMES_DIR="$DOTFILES_ROOT/config/tmux/themes"
TMUX_CONF="$DOTFILES_ROOT/config/tmux/tmux.conf"

SOCKET="tmux-theme-test-$$"
DEFAULT_THEME="gruvbox-dark"
# A theme other than the default, and an option whose value differs between them.
OTHER_THEME="nord"
PROBE_OPTION="status-style"
CONTINUUM_MARKER="continuum_save.sh"

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }
check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$label"
    else
        fail "$label"
        echo "       expected: $expected"
        echo "       actual:   $actual"
    fi
}

WORK="$(mktemp -d)"

t() { tmux -L "$SOCKET" "$@"; }

cleanup() {
    # Only this test's private server.
    t kill-server 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

export TMUX_THEME_STATE="$WORK/state/current"

t -f /dev/null new-session -d -s boot -c "$WORK"
TMUX="$(t display-message -p '#{socket_path}'),$(t display-message -p '#{pid}'),0"
export TMUX

theme() { "$THEME_SCRIPT" "$@"; }

# Option names a theme file sets (or unsets), sorted.
theme_keys() {
    awk '$1 == "set" && $2 ~ /^-g/ { print $3 }' "$1" | sort
}

# Current value of every option the default theme manages, one "name value" line each.
snapshot() {
    local opt
    for opt in $(theme_keys "$THEMES_DIR/$DEFAULT_THEME.conf"); do
        printf '%s %s\n' "$opt" "$(t show -gv "$opt" 2>/dev/null || t show -gwv "$opt")"
    done
}

echo -e "${BLUE}Theme files${NC}"

THEME_FILES=("$THEMES_DIR"/*.conf)
[ -f "$THEMES_DIR/$DEFAULT_THEME.conf" ] && pass "default theme $DEFAULT_THEME exists" || fail "default theme $DEFAULT_THEME missing"

REFERENCE_KEYS="$(theme_keys "$THEMES_DIR/$DEFAULT_THEME.conf")"
for f in "${THEME_FILES[@]}"; do
    name="$(basename "$f" .conf)"
    if err="$(t source-file "$f" 2>&1)" && [ -z "$err" ]; then
        pass "$name sources without error"
    else
        fail "$name sources without error: $err"
    fi
    check "$name sets the same options as $DEFAULT_THEME" "$REFERENCE_KEYS" "$(theme_keys "$f")"
    case "$(t show -gv status-right)" in
        *"$CONTINUUM_MARKER"*) pass "$name status-right keeps $CONTINUUM_MARKER" ;;
        *) fail "$name status-right lost $CONTINUUM_MARKER" ;;
    esac
    case "$(t show -gv status-right)" in
        *"range=user|datetime"*"%d/%m %a %H:%M"*) pass "$name status-right shows date and 24h time" ;;
        *) fail "$name status-right lost the date/time segment" ;;
    esac
    case "$(t show -gv status-right)" in
        *"range=user|power"*"tmux-weather.sh"*"tmux-battery.sh"*) pass "$name status-right toggles battery and weather" ;;
        *) fail "$name status-right lost the battery/weather toggle" ;;
    esac
done

echo -e "${BLUE}list / current${NC}"

check "list prints every theme file" \
    "$(for f in "${THEME_FILES[@]}"; do basename "$f" .conf; done)" "$(theme list)"
check "current with no state file is the default" "$DEFAULT_THEME" "$(theme current)"
mkdir -p "$(dirname "$TMUX_THEME_STATE")"
echo "no-such-theme" > "$TMUX_THEME_STATE"
check "current with an unknown saved name is the default" "$DEFAULT_THEME" "$(theme current)"
echo "../$DEFAULT_THEME" > "$TMUX_THEME_STATE"
check "current rejects a saved path" "$DEFAULT_THEME" "$(theme current)"
echo "$OTHER_THEME" > "$TMUX_THEME_STATE"
check "current reads the saved name" "$OTHER_THEME" "$(theme current)"
rm -f "$TMUX_THEME_STATE"

echo -e "${BLUE}apply / apply-saved${NC}"

theme apply "$DEFAULT_THEME"
DEFAULT_SNAPSHOT="$(snapshot)"
DEFAULT_PROBE="$(t show -gv "$PROBE_OPTION")"
theme apply "$OTHER_THEME"
OTHER_PROBE="$(t show -gv "$PROBE_OPTION")"
[ "$OTHER_PROBE" != "$DEFAULT_PROBE" ] && pass "apply $OTHER_THEME changes $PROBE_OPTION" \
    || fail "apply $OTHER_THEME left $PROBE_OPTION at $DEFAULT_PROBE"
[ ! -e "$TMUX_THEME_STATE" ] && pass "apply does not save" || fail "apply wrote the state file"

for f in "${THEME_FILES[@]}"; do
    theme apply "$(basename "$f" .conf)"
done
theme apply "$DEFAULT_THEME"
check "switching through every theme and back leaves no trace" "$DEFAULT_SNAPSHOT" "$(snapshot)"

theme apply no-such-theme 2>/dev/null
check "apply of an unknown theme exits 1" "1" "$?"
check "apply of an unknown theme leaves options alone" "$DEFAULT_PROBE" "$(t show -gv "$PROBE_OPTION")"
theme apply 2>/dev/null
check "apply without a name exits 1" "1" "$?"
theme bogus-subcommand 2>/dev/null
check "unknown subcommand exits 2" "2" "$?"

echo "$OTHER_THEME" > "$TMUX_THEME_STATE"
theme apply-saved
check "apply-saved applies the saved theme" "$OTHER_PROBE" "$(t show -gv "$PROBE_OPTION")"
rm -f "$TMUX_THEME_STATE"
theme apply-saved
check "apply-saved with no state applies the default" "$DEFAULT_PROBE" "$(t show -gv "$PROBE_OPTION")"

echo -e "${BLUE}--pick (stub fzf)${NC}"

# Stub fzf: records its stdin and the --bind it got, then behaves as
# FZF_STUB_MODE says: "pick:<line-number>" prints that input line and exits 0;
# "abort" exits 130 like Esc does.
STUB_BIN="$WORK/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
input="$(cat)"
printf '%s\n' "$input" > "$FZF_STUB_LOG"
case "$FZF_STUB_MODE" in
    pick:*) printf '%s\n' "$input" | sed -n "${FZF_STUB_MODE#pick:}p"; exit 0 ;;
    abort)  exit 130 ;;
esac
EOF
chmod +x "$STUB_BIN/fzf"
export FZF_STUB_LOG="$WORK/fzf-input"

pick() { PATH="$STUB_BIN:$PATH" FZF_STUB_MODE="$1" theme --pick; }

OTHER_LINE="$(theme list | grep -nx "$OTHER_THEME" | cut -d: -f1)"
pick "pick:$OTHER_LINE"
check "Enter applies the picked theme" "$OTHER_PROBE" "$(t show -gv "$PROBE_OPTION")"
check "Enter saves the picked theme" "$OTHER_THEME" "$(theme current)"

# Esc after a live preview: the preview changed the server, abort must undo it.
theme apply "$DEFAULT_THEME"
pick abort
check "picker marks the saved theme" "*" "$(grep "$OTHER_THEME\$" "$FZF_STUB_LOG" | cut -c1)"
check "Esc restores the saved theme after a preview" "$OTHER_PROBE" "$(t show -gv "$PROBE_OPTION")"
check "Esc keeps the saved name" "$OTHER_THEME" "$(theme current)"

echo -e "${BLUE}tmux.conf wiring${NC}"

grep -q 'tmux-gruvbox' "$TMUX_CONF" && fail "tmux.conf still references tmux-gruvbox" \
    || pass "tmux.conf no longer references tmux-gruvbox"
grep -q '^run-shell .*tmux-theme\.sh apply-saved' "$TMUX_CONF" && pass "tmux.conf runs tmux-theme.sh apply-saved" \
    || fail "tmux.conf does not run tmux-theme.sh apply-saved"
tpm_line="$(grep -n "^run '~/.tmux/plugins/tpm/tpm'" "$TMUX_CONF" | cut -d: -f1)"
theme_line="$(grep -n '^run-shell .*tmux-theme\.sh apply-saved' "$TMUX_CONF" | cut -d: -f1)"
[ -n "$tpm_line" ] && [ -n "$theme_line" ] && [ "$theme_line" -gt "$tpm_line" ] \
    && pass "apply-saved runs after TPM" || fail "apply-saved must come after the TPM run line"
grep -q '^set -g status-right' "$TMUX_CONF" && fail "tmux.conf still sets a status-right of its own" \
    || pass "status-right is left to the themes"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
