#!/usr/bin/env bash
#
# tmux-theme.sh - switch the tmux colour theme at runtime
#
# Themes are plain tmux config files in config/tmux/themes/<name>.conf. Every one
# sets the same options, so sourcing a theme fully replaces the previous one. The
# chosen name is saved, and tmux.conf re-applies it on every start/reload.
#
# Usage:
#   tmux-theme.sh list            # theme names, one per line
#   tmux-theme.sh current         # saved theme (default when unset or unknown)
#   tmux-theme.sh apply <name>    # apply a theme now (not saved)
#   tmux-theme.sh apply-saved     # apply the saved theme (run by tmux.conf)
#   tmux-theme.sh --pick          # fzf picker: live preview on focus, Enter saves,
#                                 #   Esc restores the saved theme (needs a tty)
#   tmux-theme.sh --popup         # open the picker in a tmux popup (prefix + C-t)
#
# Talks to the tmux server in $TMUX (tests point it at a private -L server).
# Overrides: TMUX_THEME_DIR (themes dir), TMUX_THEME_STATE (state file).

set -euo pipefail

DEFAULT_THEME='gruvbox-dark'
THEME_EXT='.conf'
ACTIVE_MARKER='*'
POPUP_WIDTH='40%'
POPUP_HEIGHT='60%'
POPUP_TITLE=' tmux Theme Picker '
TAB=$'\t'

# Resolve the script's real location (it may be reached through a symlink) so the
# themes dir is found relative to the repo. Plain readlink loop: macOS has no -f.
resolve_script_path() {
    local path="${BASH_SOURCE[0]}" dir
    while [ -L "$path" ]; do
        dir="$(cd "$(dirname "$path")" && pwd)"
        path="$(readlink "$path")"
        case "$path" in /*) ;; *) path="$dir/$path" ;; esac
    done
    printf '%s/%s\n' "$(cd "$(dirname "$path")" && pwd)" "$(basename "$path")"
}

SCRIPT_PATH="$(resolve_script_path)"
THEME_DIR="${TMUX_THEME_DIR:-$(dirname "$(dirname "$SCRIPT_PATH")")/config/tmux/themes}"
STATE_FILE="${TMUX_THEME_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-theme/current}"

die() { echo "tmux-theme: $*" >&2; exit 1; }

usage() {
    cat >&2 <<'EOF'
Usage: tmux-theme.sh list | current | apply <name> | apply-saved | --pick | --popup
EOF
}

list_themes() {
    local f
    for f in "$THEME_DIR"/*"$THEME_EXT"; do
        [ -f "$f" ] || continue
        f="$(basename "$f")"
        printf '%s\n' "${f%"$THEME_EXT"}"
    done
}

theme_exists() {
    case "$1" in ''|*/*) return 1 ;; esac
    [ -f "$THEME_DIR/$1$THEME_EXT" ]
}

current_theme() {
    local name=""
    [ -f "$STATE_FILE" ] && IFS= read -r name < "$STATE_FILE" || true
    if theme_exists "$name"; then
        printf '%s\n' "$name"
    else
        printf '%s\n' "$DEFAULT_THEME"
    fi
}

apply_theme() {
    theme_exists "$1" || die "unknown theme '$1' (see: tmux-theme.sh list)"
    tmux source-file "$THEME_DIR/$1$THEME_EXT"
}

save_theme() {
    theme_exists "$1" || die "unknown theme '$1' (see: tmux-theme.sh list)"
    mkdir -p "$(dirname "$STATE_FILE")"
    printf '%s\n' "$1" > "$STATE_FILE"
}

# What the picker does when it closes without a choice: undo the live preview.
restore_saved() {
    apply_theme "$(current_theme)"
}

# Picker line -> theme name: the name follows the marker column's tab.
strip_marker() {
    printf '%s\n' "${1#*"$TAB"}"
}

pick_theme() {
    command -v fzf >/dev/null 2>&1 || die "fzf not found"
    local saved saved_pos choices name selected self
    saved="$(current_theme)"
    choices="$(list_themes | while IFS= read -r name; do
        if [ "$name" = "$saved" ]; then
            printf '%s%s%s\n' "$ACTIVE_MARKER" "$TAB" "$name"
        else
            printf ' %s%s\n' "$TAB" "$name"
        fi
    done)"
    [ -n "$choices" ] || die "no themes in $THEME_DIR"
    self="$(printf %q "$SCRIPT_PATH")"
    # Start on the saved theme, so opening the picker previews nothing new.
    saved_pos="$(list_themes | grep -nxF "$saved" | cut -d: -f1)"

    # Lines are "<marker><TAB><name>": field 2 is the name, which is what the
    # search matches and what the live preview applies. Any exit but a pick
    # (Esc, ctrl-c, no match) restores the saved theme. --no-multi/--no-preview
    # override FZF_DEFAULT_OPTS: one pick only, and no file preview pane.
    if selected="$(printf '%s\n' "$choices" | fzf \
        --delimiter="$TAB" \
        --nth=2 \
        --tabstop=2 \
        --header="  Select tmux theme ($ACTIVE_MARKER = saved)" \
        --prompt='theme> ' \
        --height=100% \
        --reverse \
        --no-info \
        --no-multi \
        --no-preview \
        --bind "load:pos(${saved_pos:-1})" \
        --bind "focus:execute-silent($self apply {2})")"; then
        name="$(strip_marker "$selected")"
        apply_theme "$name"
        save_theme "$name"
    else
        restore_saved
    fi
}

case "${1:-}" in
    list)        list_themes ;;
    current)     current_theme ;;
    apply)       [ -n "${2:-}" ] || die "usage: tmux-theme.sh apply <name>"; apply_theme "$2" ;;
    apply-saved) restore_saved ;;
    --pick)      pick_theme ;;
    --popup)     tmux display-popup -E -w "$POPUP_WIDTH" -h "$POPUP_HEIGHT" -T "$POPUP_TITLE" \
                     "$(printf %q "$SCRIPT_PATH") --pick" ;;
    *)           usage; exit 2 ;;
esac
