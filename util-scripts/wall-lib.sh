# wall-lib.sh
# Shared helpers for wall-next and wall-fav: notify/fail, focused-monitor
# lookup, current-image lookup via awww, and the shared wallpaper/favorites
# dir env-var defaults.
#
# Sourced by both scripts relative to their own resolved dir (Hyprland runs
# them by absolute path, so `source wall-lib.sh` alone would fail):
#   SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
#   source "$SCRIPT_DIR/wall-lib.sh"

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/walls}"
WALL_FAVORITES_DIR="${WALL_FAVORITES_DIR:-$HOME/Pictures/wall-favorites}"

WALL_LIB_TAG="${WALL_LIB_TAG:-wall}"

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "$WALL_LIB_TAG" "$1"
    echo "$WALL_LIB_TAG: $1" >&2
}

fail() {
    notify "$1"
    exit 1
}

# focused_monitor — print the name of the currently focused Hyprland output.
focused_monitor() {
    hyprctl monitors -j | jq -er '.[] | select(.focused) | .name'
}

# current_image <monitor> — print the image path awww reports currently
# displaying on <monitor>.
#
# On success: prints the image path, or empty for a colour/unset background
# (return code non-zero, but that is NOT a failure — callers should treat it
# as "no current image").
# If awww itself can't be reached: prints awww's error text and returns 2, so
# callers can tell "daemon down" apart from "no image set" and fail loudly.
current_image() {
    local monitor="$1" query
    if ! query=$(awww query -j 2>&1); then
        printf '%s' "$query"
        return 2
    fi
    printf '%s' "$query" \
        | jq -er --arg m "$monitor" '.[""][]? | select(.name == $m) | .displaying.image // empty'
}
