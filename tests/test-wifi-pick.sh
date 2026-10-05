#!/usr/bin/env bash
#
# Tests for util-scripts/wifi-pick (pick a Wi-Fi network by name, connect it).
#
# Pins: the list puts the connected network first, then saved ones, then by
# signal, one row per SSID, hidden networks left out; a saved network connects
# with its profile and no password; a saved profile whose password stopped
# working asks for the new one and retries; a new WPA2 network gets a wpa-psk
# profile, WPA3-only gets sae; an open network connects without a profile;
# 802.1X is refused; the password never appears in nmcli's argv; picking the
# connected network disconnects only after a yes; the radio is turned on only
# after a yes; Esc in the list exits 130; the NAME filter picks without fzf;
# WIFI_PICK_FZF_OPTS is appended to fzf one option per line.
#
# Hermetic: nmcli and fzf are stubs backed by a state dir; nothing touches the
# real NetworkManager.

set -uo pipefail

WIFI_PICK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/util-scripts/wifi-pick"

GOOD_PASSWORD='correct horse:battery'
NEW_PASSWORD='n3w-passw0rd'
WRONG_PASSWORD='wrong-password'

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

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-wifi-pick.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
STUB="$ROOT/bin"
STATE="$ROOT/state"
mkdir -p "$STUB"

# Fake nmcli. State:
#   radio                 enabled | disabled
#   aps                   one access point per line: SSID|SIGNAL|BARS|SECURITY|PASSWORD
#                         (PASSWORD is what the network accepts; empty = open)
#   conns/<uuid>          key=value: ssid, psk, ts, active (1/0), keymgmt
#   calls                 every call's argv, one per line
cat > "$STUB/nmcli" <<'EOF'
#!/usr/bin/env bash
S="$NM_STATE"
echo "$*" >> "$S/calls"
get() { sed -n "s/^$2=//p" "$S/conns/$1" 2>/dev/null; }
put() { if grep -q "^$2=" "$S/conns/$1"; then sed -i "s|^$2=.*|$2=$3|" "$S/conns/$1"; else echo "$2=$3" >> "$S/conns/$1"; fi; }
esc() { local v="${1//\\/\\\\}"; printf '%s' "${v//:/\\:}"; }
ap_password() { awk -F'|' -v s="$1" '$1 == s { print $5; exit }' "$S/aps"; }
active_ssid() { for c in "$S"/conns/*; do [[ -e "$c" && "$(get "$(basename "$c")" active)" == 1 ]] && get "$(basename "$c")" ssid; done; }
activate() {
    for c in "$S"/conns/*; do [[ -e "$c" ]] && put "$(basename "$c")" active 0; done
    put "$1" active 1
}
wait=""; [[ "$1" == "--wait" ]] && { wait="$2"; shift 2; }
case "$*" in
    "radio wifi")    cat "$S/radio" ;;
    "radio wifi on") echo enabled > "$S/radio" ;;
    "-t -f IN-USE,SIGNAL,BARS,SECURITY,SSID device wifi list --rescan "*)
        [[ "$(cat "$S/radio")" == enabled ]] || exit 0
        current="$(active_ssid)"
        while IFS='|' read -r ssid signal bars security _; do
            inuse=" "; [[ -n "$ssid" && "$ssid" == "$current" ]] && inuse="*"
            printf '%s:%s:%s:%s:%s\n' "$inuse" "$signal" "$bars" "$security" "$(esc "$ssid")"
        done < "$S/aps" ;;
    "-t -f UUID,TYPE,TIMESTAMP connection show")
        echo "eth-uuid:802-3-ethernet:9999999999"
        for c in "$S"/conns/*; do [[ -e "$c" ]] && echo "$(basename "$c"):802-11-wireless:$(get "$(basename "$c")" ts)"; done ;;
    "-t -f UUID,TYPE connection show --active")
        echo "eth-uuid:802-3-ethernet"
        for c in "$S"/conns/*; do
            u="$(basename "$c")"; [[ -e "$c" && "$(get "$u" active)" == 1 ]] && echo "$u:802-11-wireless"
        done ;;
    "-g 802-11-wireless.ssid connection show uuid "*) esc "$(get "$6" ssid)"; echo ;;
    "connection up uuid "*)
        u="$4"; [[ -f "$S/conns/$u" ]] || exit 10
        if [[ "${5:-}" == passwd-file ]]; then
            put "$u" psk "$(sed -n 's/^802-11-wireless-security\.psk://p' "$6")"
        fi
        [[ "$(get "$u" psk)" == "$(ap_password "$(get "$u" ssid)")" ]] || { echo "Error: secrets were required" >&2; exit 4; }
        activate "$u" ;;
    "connection down uuid "*) put "$4" active 0 ;;
    "connection add type wifi con-name "*)
        u="$(printf '%08d-0000-4000-8000-000000000000' "$(ls "$S/conns" | wc -l)")"
        # argv: connection add type wifi con-name NAME ssid SSID wifi-sec.key-mgmt KEYMGMT
        printf 'ssid=%s\npsk=\nts=0\nactive=0\nkeymgmt=%s\n' "$8" "${10}" > "$S/conns/$u"
        echo "Connection '$6' ($u) successfully added." ;;
    "device wifi connect "*)
        ssid="$4"; [[ -z "$(ap_password "$ssid")" ]] || exit 4
        u="open-$(printf '%s' "$ssid" | tr -c 'a-zA-Z0-9' '-')"
        printf 'ssid=%s\npsk=\nts=0\nactive=0\n' "$ssid" > "$S/conns/$u"
        activate "$u" ;;
    *) echo "nmcli stub: unhandled: $*" >&2; exit 99 ;;
esac
EOF

# Fake fzf: records argv and input; picks the first line whose SSID column
# equals $FZF_PICK, or exits 130 (Esc) when FZF_PICK is empty.
cat > "$STUB/fzf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$NM_STATE/fzf-args"
cat > "$NM_STATE/fzf-input"
[[ -n "${FZF_PICK:-}" ]] || exit 130
awk -F'\t' -v p="$FZF_PICK" '$1 == p { print; found=1; exit } END { exit !found }' "$NM_STATE/fzf-input"
EOF
cat > "$STUB/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB"/*

# fresh: reset the state to the scenario below.
#   Home      saved, connected, WPA2 (password GOOD)
#   Cafe      open, strong
#   Office    saved, WPA2, but its password changed to NEW
#   Neighbour WPA2, not saved; a second, weaker AP with the same SSID
#   Modern    WPA3 only, not saved
#   Corp      802.1X
#   (hidden)  no SSID
fresh() {
    rm -rf "$STATE"; mkdir -p "$STATE/conns"
    echo enabled > "$STATE/radio"
    cat > "$STATE/aps" <<APS
Home|60|▂▄▆_|WPA2|$GOOD_PASSWORD
Cafe|90|▂▄▆█|--|
Office|50|▂▄__|WPA2|$NEW_PASSWORD
Neighbour|40|▂▄__|WPA1 WPA2|$GOOD_PASSWORD
Neighbour|20|▂___|WPA1 WPA2|$GOOD_PASSWORD
Modern|30|▂▄__|WPA3|$GOOD_PASSWORD
Corp|70|▂▄▆_|WPA2 802.1X|
|80|▂▄▆_|WPA2|
APS
    printf 'ssid=Home\npsk=%s\nts=200\nactive=1\n' "$GOOD_PASSWORD" > "$STATE/conns/uuid-home"
    printf 'ssid=Office\npsk=%s\nts=100\nactive=0\n' "$GOOD_PASSWORD" > "$STATE/conns/uuid-office"
    : > "$STATE/calls"
}

# run [env...] -- [args...]; stdin is the answers to wifi-pick's questions.
run() {
    local -a envs=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
    shift
    env -i PATH="$STUB:/usr/bin:/bin" HOME="$ROOT" NM_STATE="$STATE" "${envs[@]}" bash "$WIFI_PICK" "$@" 2>&1
}
conn_with_ssid() { grep -l "^ssid=$1\$" "$STATE"/conns/* 2>/dev/null | head -n1; }
field_of() { sed -n "s/^$2=//p" "$(conn_with_ssid "$1")"; }

echo "list: connected, saved, then signal; one row per SSID; no hidden"
fresh
run FZF_PICK= -- >/dev/null; rc=$?
check "Esc exits 130" "130" "$rc"
check "row order" "$(printf '%s\n' Home Office Cafe Corp Neighbour Modern)" "$(cut -f1 "$STATE/fzf-input")"
contains "connected row labelled" "connected" "$(grep '^Home' "$STATE/fzf-input")"
contains "saved row labelled" "saved" "$(grep '^Office' "$STATE/fzf-input")"
contains "open row labelled" "open" "$(grep '^Cafe' "$STATE/fzf-input" | cut -f4)"
contains "strongest AP's signal shown" "40%" "$(grep '^Neighbour' "$STATE/fzf-input")"
check "fzf shows only the label column" "--with-nth=4" "$(grep -- '--with-nth' "$STATE/fzf-args")"

echo "saved network: connects with its profile, no password asked"
# Office's saved password is stale in the scenario; make it current for this case.
fresh; sed -i "s/^psk=.*/psk=$NEW_PASSWORD/" "$STATE/conns/uuid-office"
out=$(run FZF_PICK=Office -- </dev/null); rc=$?
check "exit 0" "0" "$rc"
check "Office active" "1" "$(field_of Office active)"
check "Home no longer active" "0" "$(field_of Home active)"
lacks "no password asked" "password for" "$out"
lacks "no passwd-file used" "passwd-file" "$(cat "$STATE/calls")"

echo "saved network with a changed password: asks and retries"
fresh
out=$(printf '%s\n' "$NEW_PASSWORD" | run FZF_PICK=Office --); rc=$?
check "exit 0" "0" "$rc"
contains "says the saved one failed" "saved password did not work" "$out"
contains "asks for the password" "password for Office> " "$out"
check "new password stored in the profile" "$NEW_PASSWORD" "$(field_of Office psk)"
check "Office active" "1" "$(field_of Office active)"
lacks "password not in nmcli argv" "$NEW_PASSWORD" "$(cat "$STATE/calls")"
lacks "password not echoed" "$NEW_PASSWORD" "$out"

echo "saved network, wrong new password: fails"
fresh
out=$(printf '%s\n' "$WRONG_PASSWORD" | run FZF_PICK=Office --); rc=$?
check "exit 1" "1" "$rc"
contains "says check the password" "check the password" "$out"

echo "new WPA2 network: wpa-psk profile, password via passwd-file"
fresh
out=$(printf '%s\n' "$GOOD_PASSWORD" | run FZF_PICK=Neighbour --); rc=$?
check "exit 0" "0" "$rc"
check "profile key-mgmt" "wpa-psk" "$(field_of Neighbour keymgmt)"
check "Neighbour active" "1" "$(field_of Neighbour active)"
contains "password via passwd-file" "passwd-file" "$(grep 'connection up' "$STATE/calls")"
lacks "password not in nmcli argv" "$GOOD_PASSWORD" "$(cat "$STATE/calls")"

echo "new WPA3-only network: sae profile"
fresh
printf '%s\n' "$GOOD_PASSWORD" | run FZF_PICK=Modern -- >/dev/null; rc=$?
check "exit 0" "0" "$rc"
check "profile key-mgmt" "sae" "$(field_of Modern keymgmt)"

echo "new network, empty password: fails without a profile"
fresh
out=$(printf '\n' | run FZF_PICK=Neighbour --); rc=$?
check "exit 1" "1" "$rc"
check "no profile created" "" "$(conn_with_ssid Neighbour)"

echo "open network: connects directly"
fresh
out=$(run FZF_PICK=Cafe -- </dev/null); rc=$?
check "exit 0" "0" "$rc"
contains "device wifi connect used" "device wifi connect Cafe" "$(cat "$STATE/calls")"
lacks "no password asked" "password for" "$out"

echo "802.1X network: refused"
fresh
out=$(run FZF_PICK=Corp -- </dev/null); rc=$?
check "exit 1" "1" "$rc"
contains "points to nmtui" "nmtui" "$out"
lacks "no profile added" "connection add" "$(cat "$STATE/calls")"

echo "connected network: disconnect only after a yes"
fresh
out=$(printf 'n\n' | run FZF_PICK=Home --); rc=$?
check "no: exit 0" "0" "$rc"
check "no: still active" "1" "$(field_of Home active)"
contains "asks first" "disconnect from Home? [y/N] " "$out"
out=$(printf 'y\n' | run FZF_PICK=Home --); rc=$?
check "yes: exit 0" "0" "$rc"
check "yes: disconnected" "0" "$(field_of Home active)"

echo "radio off: turned on only after a yes"
fresh; echo disabled > "$STATE/radio"
out=$(printf 'n\n' | run FZF_PICK=Cafe --); rc=$?
check "no: exit 130" "130" "$rc"
check "no: radio stays off" "disabled" "$(cat "$STATE/radio")"
out=$(printf 'y\n' | run FZF_PICK=Cafe --); rc=$?
check "yes: exit 0" "0" "$rc"
check "yes: radio on" "enabled" "$(cat "$STATE/radio")"
check "yes: Cafe connected" "1" "$(field_of Cafe active)"

echo "NAME filter without fzf picks the single match"
fresh; mv "$STUB/fzf" "$STUB/fzf.off"
out=$(printf '%s\n' "$GOOD_PASSWORD" | run -- Modern); rc=$?
mv "$STUB/fzf.off" "$STUB/fzf"
check "exit 0" "0" "$rc"
check "Modern active" "1" "$(field_of Modern active)"

echo "WIFI_PICK_FZF_OPTS is appended one option per line"
fresh
run FZF_PICK= WIFI_PICK_FZF_OPTS=$'--prompt=custom > \n--border-label=two words' -- >/dev/null
args="$(cat "$STATE/fzf-args")"
check "custom prompt is the last --prompt" "--prompt=custom > " "$(grep -- '^--prompt' <<<"$args" | tail -n1)"
contains "spaces kept inside an option" "--border-label=two words" "$args"

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0))
