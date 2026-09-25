#!/bin/bash

# Hermetic tests for util-scripts/wall-fav.
#
# Fakes hyprctl (focused-monitor lookup) and awww (query, for the current
# image) on PATH, and builds a temp wallpaper tree with two collections that
# reuse a basename, to exercise the name-collision-avoiding relative-path
# naming scheme. Real jq/realpath/basename are used (not under test).
# $WALL_FAVORITES_DIR is never pre-created — wall-fav must mkdir -p it
# itself on first add.
#
# Usage: ./tests/test-wall-fav.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
WALL_FAV="$DOTFILES_ROOT/util-scripts/wall-fav"

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

# --- Fake wallpaper tree: two collections reusing the basename "img.png". ---
WALLS="$WORK/walls"
mkdir -p "$WALLS/collectionA/sub" "$WALLS/collectionB"
touch "$WALLS/collectionA/sub/img.png"
touch "$WALLS/collectionB/img.png"

# An image outside $WALLPAPER_DIR entirely.
mkdir -p "$WORK/outside"
touch "$WORK/outside/pic.jpg"

FAVS="$WORK/favorites"   # never mkdir'd here — wall-fav must create it.

# --- Fake hyprctl: only `monitors -j` is used, single focused monitor. -----
mkdir -p "$WORK/bin"
cat > "$WORK/bin/hyprctl" <<'EOF'
#!/bin/bash
if [ "$1" = "monitors" ] && [ "$2" = "-j" ]; then
    printf '[{"name":"eDP-1","focused":true}]'
    exit 0
fi
echo "fake hyprctl: unsupported args: $*" >&2
exit 1
EOF
chmod +x "$WORK/bin/hyprctl"

# --- Fake awww: only `query -j` is used (wall-fav never calls `img`). ------
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
        f="$STATE_DIR/current-eDP-1"
        if [ -f "$f" ]; then
            printf '{"":[{"name":"eDP-1","displaying":{"image":"%s"}}]}' "$(cat "$f")"
        else
            printf '{"":[{"name":"eDP-1","displaying":{"color":"#000000"}}]}'
        fi
        exit 0
        ;;
    *)
        echo "fake awww: unsupported command: $1" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$WORK/bin/awww"

run_wall_fav() {
    PATH="$WORK/bin:$PATH" \
        WALLPAPER_DIR="$WALLS" \
        WALL_FAVORITES_DIR="$FAVS" \
        FAKE_AWWW_STATE_DIR="$STATE_DIR" \
        "$WALL_FAV"
}

set_current() {  # set_current <path>
    printf '%s' "$1" > "$STATE_DIR/current-eDP-1"
}

clear_current() {
    rm -f "$STATE_DIR/current-eDP-1" "$STATE_DIR/daemon-down"
}

echo -e "${BLUE}wall-fav${NC}"

# 1. Colour background (no image) -> error, non-zero exit, favorites dir
#    is not even created.
clear_current
if run_wall_fav >/dev/null 2>&1; then
    fail "colour background did not error"
else
    pass "colour background -> non-zero exit"
fi
if [ ! -e "$FAVS" ]; then
    pass "colour background -> favorites dir not created"
else
    fail "favorites dir was created despite the error"
fi

# 2. Daemon down -> error, non-zero exit.
clear_current
touch "$STATE_DIR/daemon-down"
if run_wall_fav >/dev/null 2>&1; then
    fail "daemon-down did not error"
else
    pass "daemon-down -> non-zero exit"
fi
rm -f "$STATE_DIR/daemon-down"

# 3. Add a favorite: name is the path relative to $WALLPAPER_DIR, "/" -> "__".
clear_current
set_current "$WALLS/collectionA/sub/img.png"
run_wall_fav >/dev/null 2>&1
LINK_A="$FAVS/collectionA__sub__img.png"
if [ -L "$LINK_A" ] && [ "$(readlink -f "$LINK_A")" = "$WALLS/collectionA/sub/img.png" ]; then
    pass "add: symlink created with the relative-path name, pointing at the real image"
else
    fail "expected symlink $LINK_A -> $WALLS/collectionA/sub/img.png"
fi

# 4. Name collision across collections: same basename, different collection
#    -> a distinct favorite name (no clobbering).
clear_current
set_current "$WALLS/collectionB/img.png"
run_wall_fav >/dev/null 2>&1
LINK_B="$FAVS/collectionB__img.png"
if [ -L "$LINK_B" ] && [ -L "$LINK_A" ] && [ "$(readlink -f "$LINK_B")" = "$WALLS/collectionB/img.png" ]; then
    pass "add: same basename in a different collection gets a distinct, non-clobbering name"
else
    fail "expected both $LINK_A and $LINK_B to exist as distinct symlinks"
fi

# 5. Remove: toggling again on the same current image removes only the link.
clear_current
set_current "$WALLS/collectionB/img.png"
run_wall_fav >/dev/null 2>&1
if [ ! -e "$LINK_B" ] && [ -f "$WALLS/collectionB/img.png" ]; then
    pass "remove: symlink gone, target image untouched"
else
    fail "expected $LINK_B removed and target image still present"
fi

# 6. Current image IS a favorites symlink -> toggling removes it (realpath
#    resolves through the favorites link back to the real image / same name).
clear_current
set_current "$LINK_A"
run_wall_fav >/dev/null 2>&1
if [ ! -e "$LINK_A" ]; then
    pass "current is a favorites symlink -> toggling removes that favorite"
else
    fail "expected $LINK_A to be removed"
fi

# 7. Image outside $WALLPAPER_DIR -> falls back to basename.
clear_current
set_current "$WORK/outside/pic.jpg"
run_wall_fav >/dev/null 2>&1
LINK_OUTSIDE="$FAVS/pic.jpg"
if [ -L "$LINK_OUTSIDE" ] && [ "$(readlink -f "$LINK_OUTSIDE")" = "$WORK/outside/pic.jpg" ]; then
    pass "image outside \$WALLPAPER_DIR -> favorite named by basename"
else
    fail "expected symlink $LINK_OUTSIDE -> $WORK/outside/pic.jpg"
fi
run_wall_fav >/dev/null 2>&1   # toggle back off, tidy up for the next case

# 8. A non-symlink file already at the target name -> refuse to touch it.
clear_current
set_current "$WALLS/collectionA/sub/img.png"
echo "not a symlink" > "$LINK_A"
if run_wall_fav >/dev/null 2>&1; then
    fail "non-symlink collision did not error"
else
    pass "non-symlink file at the target name -> non-zero exit"
fi
if [ -f "$LINK_A" ] && [ ! -L "$LINK_A" ] && [ "$(cat "$LINK_A")" = "not a symlink" ]; then
    pass "non-symlink file at the target name is left untouched"
else
    fail "the pre-existing non-symlink file was modified or removed"
fi
rm -f "$LINK_A"

echo ""
echo -e "${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}"
[ "$FAIL" -eq 0 ]
