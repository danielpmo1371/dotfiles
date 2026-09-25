#!/bin/bash

# Hermetic tests for util-scripts/wall-next.
#
# Fakes hyprctl (focused-monitor lookup) and awww (query/img) on PATH, and
# builds a temp wallpaper tree with two real collections plus a hidden
# omarchy-style dir, a `.git` dir to prune, and a file with spaces in its
# name. Real jq/find/sort are used (not under test).
#
# Usage: ./tests/test-wall-next.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
WALL_NEXT="$DOTFILES_ROOT/util-scripts/wall-next"

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Fake wallpaper tree -----------------------------------------------------
# Sorted (LC_ALL=C) order is: aaa/first.png, bbb/second.jpg, ccc space/third
# image.webp, .omarchy-src/theme/bg.PNG (dot-dirs are kept, only .git is
# pruned). "a bad.git file" is a decoy: only a DIRECTORY named .git is pruned.
WALLS="$WORK/walls"
mkdir -p "$WALLS/aaa" "$WALLS/bbb" "$WALLS/ccc space" "$WALLS/.omarchy-src/theme" "$WALLS/dead.git"
touch "$WALLS/aaa/first.png"
touch "$WALLS/bbb/second.jpg"
touch "$WALLS/ccc space/third image.webp"
touch "$WALLS/.omarchy-src/theme/bg.PNG"
mkdir -p "$WALLS/pruned/.git"
touch "$WALLS/pruned/.git/should-not-appear.png"
touch "$WALLS/aaa/notes.txt"

EXPECTED_ORDER=(
    "$WALLS/.omarchy-src/theme/bg.PNG"
    "$WALLS/aaa/first.png"
    "$WALLS/bbb/second.jpg"
    "$WALLS/ccc space/third image.webp"
)

# --- Fake hyprctl: only `monitors -j` is used, reads the focused name from a file
FOCUSED_FILE="$WORK/focused-monitor"
echo -n "eDP-1" > "$FOCUSED_FILE"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/hyprctl" <<EOF
#!/bin/bash
if [ "\$1" = "monitors" ] && [ "\$2" = "-j" ]; then
    focused="\$(cat "$FOCUSED_FILE")"
    a=false; b=false
    [ "\$focused" = "eDP-1" ] && a=true
    [ "\$focused" = "HDMI-A-1" ] && b=true
    printf '[{"name":"eDP-1","focused":%s},{"name":"HDMI-A-1","focused":%s}]' "\$a" "\$b"
    exit 0
fi
echo "fake hyprctl: unsupported args: \$*" >&2
exit 1
EOF
chmod +x "$WORK/bin/hyprctl"

# --- Fake awww: query -j (reads per-monitor state) and img -o ... (writes it,
# and logs the full argv so a test can assert the flags/monitor passed).
STATE_DIR="$WORK/awww-state"
mkdir -p "$STATE_DIR"
cat > "$WORK/bin/awww" <<'EOF'
#!/bin/bash
STATE_DIR="$FAKE_AWWW_STATE_DIR"
if [ -f "$STATE_DIR/daemon-down" ]; then
    echo 'Error: "Socket file not found. Make sure awww-daemon is running"' >&2
    exit 1
fi
case "$1" in
    query)
        display_of() {
            local mon="$1"
            local f="$STATE_DIR/current-$mon"
            if [ -f "$f" ]; then
                printf '{"name":"%s","displaying":{"image":"%s"}}' "$mon" "$(cat "$f")"
            else
                printf '{"name":"%s","displaying":{"color":"#0"}}' "$mon"
            fi
        }
        printf '{"":[%s,%s]}' "$(display_of eDP-1)" "$(display_of HDMI-A-1)"
        exit 0
        ;;
    img)
        shift
        args=("$@")
        mon=""
        for ((i = 0; i < ${#args[@]}; i++)); do
            [ "${args[$i]}" = "-o" ] && mon="${args[$((i + 1))]}"
        done
        printf '%s\n' "${args[*]}" >> "$STATE_DIR/img-calls.log"
        image="${args[-1]}"
        printf '%s' "$image" > "$STATE_DIR/current-$mon"
        exit 0
        ;;
    *)
        echo "fake awww: unsupported command: $1" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$WORK/bin/awww"

run_wall_next() {  # run_wall_next <next|prev>
    PATH="$WORK/bin:$PATH" \
        WALLPAPER_DIR="$WALLS" \
        FAKE_AWWW_STATE_DIR="$STATE_DIR" \
        "$WALL_NEXT" "$1"
}

current_for() {  # current_for <monitor>
    cat "$STATE_DIR/current-$1" 2>/dev/null
}

reset_state() {
    rm -f "$STATE_DIR"/current-* "$STATE_DIR/img-calls.log" "$STATE_DIR/daemon-down"
    echo -n "eDP-1" > "$FOCUSED_FILE"
}

echo -e "${BLUE}wall-next${NC}"

# 1. No current image set -> next picks the first image (sorted order).
reset_state
run_wall_next next >/dev/null 2>&1
if [ "$(current_for eDP-1)" = "${EXPECTED_ORDER[0]}" ]; then
    pass "no current image -> next starts at the first image"
else
    fail "expected ${EXPECTED_ORDER[0]}, got '$(current_for eDP-1)'"
fi

# 2. next again advances to the second image.
run_wall_next next >/dev/null 2>&1
if [ "$(current_for eDP-1)" = "${EXPECTED_ORDER[1]}" ]; then
    pass "next advances to the second image"
else
    fail "expected ${EXPECTED_ORDER[1]}, got '$(current_for eDP-1)'"
fi

# 3. prev goes back to the first image.
run_wall_next prev >/dev/null 2>&1
if [ "$(current_for eDP-1)" = "${EXPECTED_ORDER[0]}" ]; then
    pass "prev steps back to the first image"
else
    fail "expected ${EXPECTED_ORDER[0]}, got '$(current_for eDP-1)'"
fi

# 4. prev from the first image wraps to the last image.
run_wall_next prev >/dev/null 2>&1
last="${EXPECTED_ORDER[${#EXPECTED_ORDER[@]}-1]}"
if [ "$(current_for eDP-1)" = "$last" ]; then
    pass "prev wraps from the first image to the last"
else
    fail "expected $last, got '$(current_for eDP-1)'"
fi

# 5. next from the last image wraps to the first image.
run_wall_next next >/dev/null 2>&1
if [ "$(current_for eDP-1)" = "${EXPECTED_ORDER[0]}" ]; then
    pass "next wraps from the last image to the first"
else
    fail "expected ${EXPECTED_ORDER[0]}, got '$(current_for eDP-1)'"
fi

# 6. current image not in the list -> next starts at the first, prev at the last.
reset_state
printf '%s' "/not/in/the/list.png" > "$STATE_DIR/current-eDP-1"
run_wall_next next >/dev/null 2>&1
if [ "$(current_for eDP-1)" = "${EXPECTED_ORDER[0]}" ]; then
    pass "unknown current image -> next starts at the first image"
else
    fail "expected ${EXPECTED_ORDER[0]}, got '$(current_for eDP-1)'"
fi

reset_state
printf '%s' "/not/in/the/list.png" > "$STATE_DIR/current-eDP-1"
run_wall_next prev >/dev/null 2>&1
if [ "$(current_for eDP-1)" = "$last" ]; then
    pass "unknown current image -> prev starts at the last image"
else
    fail "expected $last, got '$(current_for eDP-1)'"
fi

# 7. filenames with spaces survive the round trip (image at index 2).
reset_state
printf '%s' "${EXPECTED_ORDER[1]}" > "$STATE_DIR/current-eDP-1"
run_wall_next next >/dev/null 2>&1
if [ "$(current_for eDP-1)" = "${EXPECTED_ORDER[2]}" ]; then
    pass "filenames with spaces are matched and selected correctly"
else
    fail "expected '${EXPECTED_ORDER[2]}', got '$(current_for eDP-1)'"
fi

# 8. hidden dir (.omarchy-src) is included; .git dirs are pruned.
reset_state
run_wall_next next >/dev/null 2>&1
found_pruned=0
for img in "${EXPECTED_ORDER[@]}"; do
    [[ "$img" == *"/pruned/.git/"* ]] && found_pruned=1
done
if [ "$(current_for eDP-1)" = "${WALLS}/.omarchy-src/theme/bg.PNG" ] && [ "$found_pruned" -eq 0 ]; then
    pass "hidden .omarchy-src dir included, .git dirs pruned"
else
    fail "hidden-dir/.git-prune check failed (current: '$(current_for eDP-1)')"
fi

# 9. empty wallpaper dir -> error, non-zero exit.
reset_state
EMPTY_DIR="$WORK/empty-walls"
mkdir -p "$EMPTY_DIR"
if PATH="$WORK/bin:$PATH" WALLPAPER_DIR="$EMPTY_DIR" FAKE_AWWW_STATE_DIR="$STATE_DIR" \
    "$WALL_NEXT" next >/dev/null 2>&1; then
    fail "empty wallpaper dir did not error"
else
    pass "empty wallpaper dir -> non-zero exit"
fi

# 10. daemon down -> error, non-zero exit, no image change.
reset_state
touch "$STATE_DIR/daemon-down"
before="$(current_for eDP-1)"
if run_wall_next next >/dev/null 2>&1; then
    fail "daemon-down did not error"
else
    pass "daemon-down -> non-zero exit"
fi
if [ "$(current_for eDP-1)" = "$before" ]; then
    pass "daemon-down leaves the current image untouched"
else
    fail "daemon-down changed the current image"
fi
rm -f "$STATE_DIR/daemon-down"

# 11. the correct focused monitor's -o flag is passed (two fake monitors).
reset_state
echo -n "HDMI-A-1" > "$FOCUSED_FILE"
run_wall_next next >/dev/null 2>&1
if grep -q -- "-o HDMI-A-1" "$STATE_DIR/img-calls.log" && [ -z "$(current_for eDP-1)" ]; then
    pass "awww img -o targets the focused monitor (HDMI-A-1), not eDP-1"
else
    fail "expected -o HDMI-A-1 in img-calls.log, got: $(cat "$STATE_DIR/img-calls.log" 2>/dev/null)"
fi

echo ""
echo -e "${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}"
[ "$FAIL" -eq 0 ]
