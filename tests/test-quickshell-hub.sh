#!/usr/bin/env bash
#
# Tests for the Quickshell control hub (config/quickshell, util-scripts/hub-shell).
#
# Pins: the config layout the vendored panels rely on (omarchy/shell points
# back at the config, every tile and summon plugin resolves to a file);
# hub-shell's qs invocations (single instance, IPC through `call --`, the
# summon default payload); the local helper replacements keep Omarchy's
# contracts (menu-select returns the label or "label<TAB>subtext" and exits 1
# when nothing is picked, the OSD replaces itself, there is no speaker tuning).
#
# Hermetic: qs, wofi and notify-send are stubs that record their argv.
#
# Optional live check: with QS_BIN pointing at a quickshell binary and a
# Wayland session, a copy of the config is started for a few seconds (hidden,
# under its own instance id) and its log must show no load errors.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO/config/quickshell"
HUB_SHELL="$REPO/util-scripts/hub-shell"
HELPERS="$CONFIG/omarchy/bin"

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

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-quickshell-hub.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
STUB="$ROOT/bin"
ARGV_LOG="$ROOT/argv"
mkdir -p "$STUB"

# Stub that records one argv element per line and prints $STUB_OUTPUT.
make_stub() {
    cat > "$STUB/$1" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGV_LOG"
[[ -n "\${STUB_OUTPUT:-}" ]] && printf '%s\n' "\$STUB_OUTPUT"
exit "\${STUB_EXIT:-0}"
EOF
    chmod +x "$STUB/$1"
}
make_stub qs
make_stub notify-send

# wofi reads the menu from stdin: keep it, and answer with $STUB_OUTPUT.
cat > "$STUB/wofi" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGV_LOG"
cat > "$ROOT/wofi-stdin"
[[ -n "\${STUB_OUTPUT:-}" ]] && printf '%s\n' "\$STUB_OUTPUT"
exit "\${STUB_EXIT:-0}"
EOF
chmod +x "$STUB/wofi"

run() {
    rm -f "$ARGV_LOG"
    env -i PATH="$STUB:/usr/bin:/bin" HOME="$ROOT" OMARCHY_PATH="$CONFIG/omarchy" "$@" 2>&1
}

echo "config layout"
check "omarchy/shell points back at the config" ".." "$(readlink "$CONFIG/omarchy/shell")"
[[ -f "$CONFIG/omarchy/shell/shell.qml" ]] && ok "shell.qml reachable through OMARCHY_PATH" \
    || bad "shell.qml reachable through OMARCHY_PATH" "file" "missing"
if tiles=$(jq -r '.[] | select(.entry) | .entry' "$CONFIG/Hub/tiles.json" 2>&1); then
    ok "tiles.json parses"
    missing=""
    for entry in $tiles; do [[ -f "$CONFIG/$entry" ]] || missing+="$entry "; done
    check "every tile entry exists" "" "$missing"
else
    bad "tiles.json parses" "valid JSON" "$tiles"
fi
check "every tile is a panel or an action" "" \
    "$(jq -r '.[] | select((.entry // .summon // .exec) == null) | .id' "$CONFIG/Hub/tiles.json")"
check "tile ids are unique" "" "$(jq -r '.[].id' "$CONFIG/Hub/tiles.json" | sort | uniq -d)"
for dir in plugins/panels/speedtest plugins/panels/disk-speedtest plugins/panels/wifiqr plugins/image-picker; do
    entry=$(jq -r '.entryPoints.panel // .entryPoints.overlay' "$CONFIG/$dir/manifest.json" 2>/dev/null)
    [[ -f "$CONFIG/$dir/$entry" ]] && ok "summon plugin $dir resolves" \
        || bad "summon plugin $dir resolves" "$dir/<entry>" "${entry:-no manifest}"
done
# Every helper a panel calls by name must be on the hub's PATH.
uncalled=""
# (A layer-shell namespace is a quoted omarchy-* name too, not a command.)
for name in $(grep -rhE '"omarchy-[a-z0-9-]+"' "$CONFIG/plugins" | grep -v 'namespace' \
        | grep -oE '"omarchy-[a-z0-9-]+"' | tr -d '"' | sort -u); do
    [[ -x "$HELPERS/$name" ]] || uncalled+="$name "
done
check "every helper the panels exec is shipped" "" "$uncalled"

echo "theme previews"
stale=""
for theme_dir in "$CONFIG"/omarchy/themes/*/; do
    name=$(basename "$theme_dir")
    env -i PATH="$HELPERS:/usr/bin:/bin" OMARCHY_PATH="$CONFIG/omarchy" \
        "$HELPERS/omarchy-theme-preview" "$theme_dir" "$ROOT/preview.svg" >/dev/null 2>&1
    cmp -s "$ROOT/preview.svg" "$theme_dir/preview.svg" || stale+="$name "
done
check "every committed preview matches its colors.toml (omarchy-theme-preview --all)" "" "$stale"
check "no preview has an unresolved colour" "" "$(grep -l '="#\?"' "$CONFIG"/omarchy/themes/*/preview.svg)"

echo "hub-shell"
run "$HUB_SHELL" toggle >/dev/null
check "toggle goes through qs ipc call --" \
    "$(printf '%s\n' ipc -p "$CONFIG/omarchy/shell" call -- hub toggle)" "$(cat "$ARGV_LOG")"
run "$HUB_SHELL" open omarchy.network >/dev/null
check "open names the panel" \
    "$(printf '%s\n' ipc -p "$CONFIG/omarchy/shell" call -- hub open omarchy.network)" "$(cat "$ARGV_LOG")"
run "$HUB_SHELL" summon omarchy.speedtest >/dev/null
check "summon defaults to an empty JSON payload" \
    "$(printf '%s\n' ipc -p "$CONFIG/omarchy/shell" call -- shell summon omarchy.speedtest '{}')" "$(cat "$ARGV_LOG")"
run "$HUB_SHELL" start >/dev/null
check "start runs a single instance" \
    "$(printf '%s\n' --no-duplicate -p "$CONFIG/omarchy/shell")" "$(cat "$ARGV_LOG")"
run "$HUB_SHELL" bogus >/dev/null; check "unknown command exits 2" "2" "$?"
run "$HUB_SHELL" open >/dev/null; check "open without a panel exits 2" "2" "$?"

echo "omarchy-menu-select (wofi)"
out=$(run STUB_OUTPUT="Berlin" "$HELPERS/omarchy-menu-select" "Set timezone" Auckland Berlin -- --width 520); rc=$?
check "plain option returned"            "Berlin" "$out"
check "plain pick exits 0"               "0" "$rc"
contains "prompt and width reach wofi"   $'--prompt\nSet timezone' "$(cat "$ARGV_LOG")"
contains "width passed through"          $'--width\n520' "$(cat "$ARGV_LOG")"
out=$(run STUB_OUTPUT="X  Office  (5 GHz)" "$HELPERS/omarchy-menu-select" Net $'X\tOffice\t5 GHz' $'Y\tHome'); rc=$?
check "subtext option returns label<TAB>subtext" $'Office\t5 GHz' "$out"
check "glyph shown to wofi"              $'X  Office  (5 GHz)\nY  Home' "$(cat "$ROOT/wofi-stdin")"
out=$(run STUB_OUTPUT="Y  Home" "$HELPERS/omarchy-menu-select" Net $'X\tOffice\t5 GHz' $'Y\tHome')
check "glyph option returns its label"   "Home" "$out"
run STUB_EXIT=1 "$HELPERS/omarchy-menu-select" Net a b >/dev/null; check "cancel exits 1" "1" "$?"
out=$(printf 'one\ntwo\n' | run STUB_OUTPUT="two" "$HELPERS/omarchy-menu-select" Pick)
check "options read from stdin"          "two" "$out"

echo "omarchy-osd (notify-send)"
run "$HELPERS/omarchy-osd" -i brightness -p 40 >/dev/null
argv=$(cat "$ARGV_LOG")
contains "progress hint"                 "int:value:40" "$argv"
contains "replaces the previous OSD"     "string:x-dunst-stack-tag:omarchy-osd" "$argv"
contains "summary names the value"       "Brightness 40%" "$argv"
run "$HELPERS/omarchy-osd" --bogus >/dev/null; check "unknown option exits 1" "1" "$?"

echo "omarchy-audio-tuning"
run "$HELPERS/omarchy-audio-tuning" fronted-sink >/dev/null; check "no tuning in place" "1" "$?"

echo "omarchy-theme-set"
# Stubs: hyprctl and pkill log their argv; tmux-theme.sh knows two themes.
TLOG="$ROOT/theme-calls"
for cmd in hyprctl pkill; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n' "$cmd" "$TLOG" > "$STUB/$cmd"
    chmod +x "$STUB/$cmd"
done
cat > "$STUB/tmux-theme.sh" <<EOF
#!/usr/bin/env bash
if [[ \$1 == list ]]; then printf '%s\n' dracula gruvbox-dark; else echo "tmux-theme \$*" >> "$TLOG"; fi
EOF
chmod +x "$STUB/tmux-theme.sh"
THOME="$ROOT/theme-home"
mkdir -p "$THOME"
theme_set() {
    : > "$TLOG"
    rm -f "$ARGV_LOG"
    env -i PATH="$HELPERS:$STUB:/usr/bin:/bin" HOME="$THOME" XDG_RUNTIME_DIR="$ROOT" \
        OMARCHY_PATH="$CONFIG/omarchy" HYPRLAND_INSTANCE_SIGNATURE=test \
        OMARCHY_TMUX_THEME_CMD="$STUB/tmux-theme.sh" "$HELPERS/omarchy-theme-set" "$@" 2>&1
}
CURRENT="$THOME/.local/state/omarchy/current"
out=$(theme_set Dracula); rc=$?
check "known theme exits 0"              "0" "$rc"
check "name normalised and recorded"     "dracula" "$(cat "$CURRENT/theme.name" 2>/dev/null)"
contains "tiled border from the accent"  'active_border_color = "#ff79c6"' "$(cat "$CURRENT/theme/hyprland.lua" 2>/dev/null)"
contains "float border from the theme"   'floatBorderActive = "#bd93f9"' "$(cat "$CURRENT/theme/hyprland-hub.lua" 2>/dev/null)"
contains "ghostty palette rendered"      "background = #282a36" "$(cat "$CURRENT/theme/ghostty.conf" 2>/dev/null)"
[[ -e "$CURRENT/next-theme" ]] && bad "staging dir swapped away" "absent" "present" || ok "staging dir swapped away"
calls=$(cat "$TLOG")
contains "hyprland reloaded"             "hyprctl reload" "$calls"
contains "ghostty told to reload"        "pkill -USR2 -x ghostty" "$calls"
contains "tmux theme of the same name"   "tmux-theme set dracula" "$calls"
contains "hub reached over IPC"          "applyTheme" "$(cat "$ARGV_LOG" 2>/dev/null)"
theme_set gruvbox >/dev/null
contains "tmux alias for gruvbox"        "tmux-theme set gruvbox-dark" "$(cat "$TLOG")"
magenta=$(sed -n 's/^magenta = "\(.*\)"/\1/p' "$CONFIG/omarchy/themes/gruvbox/colors.toml")
contains "float border defaults to magenta" "floatBorderActive = \"$magenta\"" "$(cat "$CURRENT/theme/hyprland-hub.lua")"
theme_set nord >/dev/null
check "no tmux theme without a match"    "0" "$(grep -c "tmux-theme set" "$TLOG")"
out=$(theme_set no-such-theme); rc=$?
check "unknown theme exits 1"            "1" "$rc"
check "unknown theme keeps the current"  "nord" "$(cat "$CURRENT/theme.name")"
theme_set ../etc >/dev/null; check "path in the name refused" "1" "$?"

if [[ -n "${QS_BIN:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
    echo "live load (QS_BIN=$QS_BIN)"
    cp -a "$CONFIG" "$ROOT/config"
    log="$ROOT/qs.log"
    env OMARCHY_PATH="$ROOT/config/omarchy" PATH="$ROOT/config/omarchy/bin:$PATH" \
        timeout 8 "$QS_BIN" -p "$ROOT/config/omarchy/shell" --no-color >"$log" 2>&1
    errors=$(grep -E 'WARN|ERROR' "$log" | grep -vE 'not placed in the graphics scene|host portal|theme\.name' || true)
    contains "configuration loaded" "Configuration Loaded" "$(cat "$log")"
    check "no load warnings" "" "$errors"
else
    echo "live load skipped (set QS_BIN and run inside Wayland)"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
