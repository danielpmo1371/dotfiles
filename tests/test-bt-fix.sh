#!/usr/bin/env bash
#
# Tests for util-scripts/bt-fix (pick a Bluetooth device by name, connect it).
#
# Pins: a working saved pairing just reconnects (nothing removed or re-paired);
# an unpaired device is paired, trusted and connected; a stale pairing is
# removed only after a yes, and a "no" leaves it in place; a device that comes
# back on a new address is paired there and the old entry is kept; a device
# that never shows up fails with exit 1; unnamed devices are hidden unless -a;
# the NAME filter picks the device without fzf; BT_FIX_FZF_OPTS is appended to
# fzf one option per line.
#
# Hermetic: bluetoothctl and fzf are stubs backed by a state dir (one file per
# device), timeout is a pass-through, nothing touches the real adapter.

set -uo pipefail

BT_FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/util-scripts/bt-fix"

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

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-bt-fix.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
STUB="$ROOT/bin"
STATE="$ROOT/state"
mkdir -p "$STUB"

# Fake bluetoothctl. Each device is $STATE/dev/<MAC> with key=value lines:
#   name, paired, trusted, connected (yes/no), rssi (empty = not nearby),
#   bond_ok (1 = the saved pairing still works), pairable (1 = in pairing mode).
# A scan runs $STATE/on-scan once if present (a device entering pairing mode).
cat > "$STUB/bluetoothctl" <<'EOF'
#!/usr/bin/env bash
S="$BT_STATE"
echo "$*" >> "$S/calls"
# Like the real one, drain stdin: a caller that leaks its stdin loses input.
[[ -t 0 ]] || cat >/dev/null
get() { sed -n "s/^$2=//p" "$S/dev/$1" 2>/dev/null; }
put() { sed -i "s/^$2=.*/$2=$3/" "$S/dev/$1"; }
[[ "$1" == "--timeout" ]] && shift 2
case "$1" in
    devices)
        for f in "$S"/dev/*; do [[ -e "$f" ]] && echo "Device $(basename "$f") $(get "$(basename "$f")" name)"; done ;;
    info)
        [[ -f "$S/dev/$2" ]] || { echo "Device $2 not available"; exit 1; }
        echo "Device $2 (public)"
        echo "	Name: $(get "$2" name)"
        echo "	Paired: $(get "$2" paired)"
        echo "	Trusted: $(get "$2" trusted)"
        echo "	Connected: $(get "$2" connected)"
        r=$(get "$2" rssi); [[ -n "$r" ]] && echo "	RSSI: $r"
        exit 0 ;;
    scan)
        if [[ -x "$S/on-scan" ]]; then "$S/on-scan"; mv "$S/on-scan" "$S/on-scan.done"; fi ;;
    connect)
        if [[ "$(get "$2" paired)" == yes && "$(get "$2" bond_ok)" == 1 ]]; then
            put "$2" connected yes; echo "Connection successful"
        else echo "Failed to connect"; exit 1; fi ;;
    pair)
        if [[ "$(get "$2" pairable)" == 1 && "$(get "$2" paired)" != yes ]]; then
            put "$2" paired yes; put "$2" bond_ok 1; echo "Pairing successful"
        else echo "Failed to pair"; exit 1; fi ;;
    trust)  put "$2" trusted yes ;;
    remove)
        # Like bluez: forgotten; it is listed again (unpaired) once it advertises.
        name=$(get "$2" name); pairable=$(get "$2" pairable); rm -f "$S/dev/$2"
        if [[ "$pairable" == 1 ]]; then
            printf 'name=%s\npaired=no\ntrusted=no\nconnected=no\nrssi=-40\nbond_ok=0\npairable=1\n' "$name" > "$S/dev/$2"
        fi ;;
esac
EOF

# Fake fzf: picks the first input line containing $FZF_PICK; records argv.
cat > "$STUB/fzf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$BT_STATE/fzf-argv"
cat > "$BT_STATE/fzf-input"
line=$(grep -F -- "$FZF_PICK" "$BT_STATE/fzf-input" | head -n1)
[[ -n "$line" ]] || exit 130
echo "$line"
EOF

# timeout pass-through: drop the duration.
cat > "$STUB/timeout" <<'EOF'
#!/usr/bin/env bash
shift; exec "$@"
EOF
chmod +x "$STUB"/*

reset_state() {
    rm -rf "$STATE"; mkdir -p "$STATE/dev"; : > "$STATE/calls"
}
# add_device MAC NAME paired connected rssi bond_ok pairable
add_device() {
    printf 'name=%s\npaired=%s\ntrusted=%s\nconnected=%s\nrssi=%s\nbond_ok=%s\npairable=%s\n' \
        "$2" "$3" "$3" "$4" "$5" "$6" "$7" > "$STATE/dev/$1"
}
field() { sed -n "s/^$2=//p" "$STATE/dev/$1" 2>/dev/null; }

# run [env...] -- [args...]; stdin is the confirmation answer.
run() {
    local -a envs=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
    shift
    env -i PATH="$STUB:/usr/bin:/bin" HOME="$ROOT" BT_STATE="$STATE" \
        BT_FIX_SCAN=1 BT_FIX_POLL=1 BT_FIX_WAIT=3 "${envs[@]}" "$BT_FIX" "$@" 2>&1
}

echo "saved pairing still works: just reconnects"
reset_state
add_device AA:AA:AA:AA:AA:01 Midnight yes no -45 1 0
out=$(run FZF_PICK=Midnight -- </dev/null); rc=$?
check    "exit 0"                 "0" "$rc"
check    "connected"              "yes" "$(field AA:AA:AA:AA:AA:01 connected)"
lacks    "no remove"              "remove" "$(cat "$STATE/calls")"
lacks    "no pair"                "pair " "$(cat "$STATE/calls")"
contains "says connected"         "Midnight connected" "$out"

echo "already connected: nothing to do"
reset_state
add_device AA:AA:AA:AA:AA:01 Midnight yes yes -45 1 0
out=$(run FZF_PICK=Midnight -- </dev/null); rc=$?
check    "exit 0"                 "0" "$rc"
contains "says already connected" "already connected" "$out"
lacks    "no connect call"        "connect" "$(cat "$STATE/calls")"

echo "unpaired device in pairing mode: pair, trust, connect"
reset_state
add_device AA:AA:AA:AA:AA:02 Headset no no -40 0 1
out=$(run FZF_PICK=Headset -- </dev/null); rc=$?
check "exit 0"    "0"   "$rc"
check "paired"    "yes" "$(field AA:AA:AA:AA:AA:02 paired)"
check "trusted"   "yes" "$(field AA:AA:AA:AA:AA:02 trusted)"
check "connected" "yes" "$(field AA:AA:AA:AA:AA:02 connected)"
lacks "no remove" "remove" "$(cat "$STATE/calls")"

echo "stale pairing, same address: remove only after yes, then re-pair"
reset_state
add_device AA:AA:AA:AA:AA:03 Speaker yes no -50 0 1
out=$(echo y | run FZF_PICK=Speaker --); rc=$?
check    "exit 0"         "0"   "$rc"
contains "asked first"    "remove the saved pairing for Speaker" "$out"
contains "removed"        "remove AA:AA:AA:AA:AA:03" "$(cat "$STATE/calls")"
check    "re-paired"      "yes" "$(field AA:AA:AA:AA:AA:03 paired)"
check    "connected"      "yes" "$(field AA:AA:AA:AA:AA:03 connected)"

echo "stale pairing, answer no: pairing left in place"
reset_state
add_device AA:AA:AA:AA:AA:03 Speaker yes no -50 0 1
out=$(echo n | run FZF_PICK=Speaker --); rc=$?
check "exit 130"            "130" "$rc"
lacks "not removed"         "remove" "$(cat "$STATE/calls")"
check "still paired"        "yes" "$(field AA:AA:AA:AA:AA:03 paired)"

echo "-y removes without asking"
reset_state
add_device AA:AA:AA:AA:AA:03 Speaker yes no -50 0 1
out=$(run FZF_PICK=Speaker -- -y </dev/null); rc=$?
check "exit 0"    "0" "$rc"
lacks "no prompt" "[y/N]" "$out"

echo "pairing mode on a new address (Logitech): pair the twin, keep the old entry"
reset_state
add_device F1:00:00:00:00:BC "MX Master" yes no "" 0 0
cat > "$STATE/on-scan" <<EOF
#!/usr/bin/env bash
printf 'name=MX Master\npaired=no\ntrusted=no\nconnected=no\nrssi=-38\nbond_ok=0\npairable=1\n' > "$STATE/dev/F1:00:00:00:00:BD"
EOF
chmod +x "$STATE/on-scan"
out=$(run FZF_PICK=F1:00:00:00:00:BC -- </dev/null); rc=$?
check    "exit 0"          "0"   "$rc"
contains "reports new address" "new address (F1:00:00:00:00:BD)" "$out"
check    "twin connected"  "yes" "$(field F1:00:00:00:00:BD connected)"
check    "old entry kept"  "yes" "$(field F1:00:00:00:00:BC paired)"
lacks    "nothing removed" "remove" "$(cat "$STATE/calls")"

echo "device never enters pairing mode: exit 1"
reset_state
add_device AA:AA:AA:AA:AA:04 Ghost yes no "" 0 0
out=$(run FZF_PICK=Ghost -- </dev/null); rc=$?
check    "exit 1"      "1" "$rc"
contains "explains"    "never showed up in pairing mode" "$out"
lacks    "not removed" "remove" "$(cat "$STATE/calls")"

echo "unnamed devices hidden unless -a"
reset_state
add_device AA:AA:AA:AA:AA:05 Named no no -40 0 1
add_device BB:BB:BB:BB:BB:06 BB-BB-BB-BB-BB-06 no no -40 0 1
run FZF_PICK=Named -- </dev/null >/dev/null
lacks    "hidden by default" "BB:BB:BB:BB:BB:06" "$(cat "$STATE/fzf-input")"
reset_state
add_device AA:AA:AA:AA:AA:05 Named no no -40 0 1
add_device BB:BB:BB:BB:BB:06 BB-BB-BB-BB-BB-06 no no -40 0 1
run FZF_PICK=Named -- -a </dev/null >/dev/null
contains "shown with -a"     "(no name)" "$(cat "$STATE/fzf-input")"

echo "every device is listed (bluetoothctl must not eat the loop's input)"
reset_state
add_device AA:AA:AA:AA:AA:01 Midnight yes no -45 1 0
add_device AA:AA:AA:AA:AA:07 Speaker no no -45 0 1
add_device AA:AA:AA:AA:AA:08 Keyboard no no "" 0 0
run FZF_PICK=Midnight -- </dev/null >/dev/null
check    "three lines"     "3" "$(wc -l < "$STATE/fzf-input" | tr -d ' ')"
check    "nearby first"    "Midnight" "$(head -n1 "$STATE/fzf-input" | cut -f1)"
check    "not seen last"   "Keyboard" "$(tail -n1 "$STATE/fzf-input" | cut -f1)"

echo "NAME filter goes to fzf as the query"
reset_state
add_device AA:AA:AA:AA:AA:01 Midnight yes no -45 1 0
run FZF_PICK=Midnight -- midnight </dev/null >/dev/null
contains "query passed"  "--query=midnight" "$(cat "$STATE/fzf-argv")"
contains "select-1 set"  "--select-1" "$(cat "$STATE/fzf-argv")"

echo "BT_FIX_FZF_OPTS: one fzf option per line, appended after bt-fix's own"
reset_state
add_device AA:AA:AA:AA:AA:01 Midnight yes no -45 1 0
run FZF_PICK=Midnight -- </dev/null >/dev/null
default_argv="$(cat "$STATE/fzf-argv")"
reset_state
add_device AA:AA:AA:AA:AA:01 Midnight yes no -45 1 0
extra_opts=$'--header=Two words here\n\n--color=bg:#123456,fg:#abcdef'
run FZF_PICK=Midnight "BT_FIX_FZF_OPTS=$extra_opts" -- </dev/null >/dev/null; rc=$?
check "exit 0"                    "0" "$rc"
check "own options come first"    "$default_argv" "$(head -n "$(wc -l <<<"$default_argv")" "$STATE/fzf-argv")"
check "extras appended verbatim, blank line skipped" \
    $'--header=Two words here\n--color=bg:#123456,fg:#abcdef' \
    "$(tail -n +"$(( $(wc -l <<<"$default_argv") + 1 ))" "$STATE/fzf-argv")"
check "connected"                 "yes" "$(field AA:AA:AA:AA:AA:01 connected)"
lacks "unset adds nothing"        "Two words" "$default_argv"

echo "without fzf: NAME filter picks the single match"
reset_state
add_device AA:AA:AA:AA:AA:01 Midnight yes no -45 1 0
add_device AA:AA:AA:AA:AA:07 Speaker yes no -45 1 0
mv "$STUB/fzf" "$STUB/fzf.off"
out=$(run -- midnight </dev/null); rc=$?
mv "$STUB/fzf.off" "$STUB/fzf"
check "exit 0"          "0"   "$rc"
check "picked Midnight" "yes" "$(field AA:AA:AA:AA:AA:01 connected)"
check "left Speaker"    "no"  "$(field AA:AA:AA:AA:AA:07 connected)"

echo "nothing picked: exit 130"
reset_state
add_device AA:AA:AA:AA:AA:01 Midnight yes no -45 1 0
out=$(run FZF_PICK=nomatch -- </dev/null); rc=$?
check "exit 130" "130" "$rc"

echo "bad usage: exit 2"
out=$(run -- -z </dev/null); rc=$?
check "exit 2" "2" "$rc"

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0))
