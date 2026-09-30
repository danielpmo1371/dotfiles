# Shared clipboard-history integration - works in both bash and zsh
# Source this from .bashrc and .zshrc (after `bindkey -v` / `set -o vi`, which
# reset the keymaps).
#
# Ctrl-X Ctrl-V picks an entry from the cliphist history with fzf and inserts
# it at the cursor, via util-scripts/clip-pick --print. The chord follows the
# ^X^X edit-command-line convention (^X^V avoids the tmux prefix C-e and is
# unbound in zsh's vi keymaps; in bash it replaces display-shell-version).

CLIP_PICK="${CLIP_PICK:-$DOTFILES_DIR/util-scripts/clip-pick}"

# clip — pick a history entry and copy it to the clipboard (fzf, no insert).
clip() {
    "$CLIP_PICK" --picker fzf "$@"
}

if [[ -n "$ZSH_VERSION" && -o interactive ]]; then
    __clip_pick_widget() {
        local entry
        entry="$("$CLIP_PICK" --picker fzf --print)"
        LBUFFER+="$entry"
        zle reset-prompt
    }
    zle -N __clip_pick_widget
    bindkey -M viins '^X^V' __clip_pick_widget
    bindkey -M vicmd '^X^V' __clip_pick_widget
    bindkey -M emacs '^X^V' __clip_pick_widget
fi

if [[ -n "$BASH_VERSION" && $- == *i* ]]; then
    __clip_pick_readline() {
        local entry
        entry="$("$CLIP_PICK" --picker fzf --print)"
        READLINE_LINE="${READLINE_LINE:0:READLINE_POINT}${entry}${READLINE_LINE:READLINE_POINT}"
        READLINE_POINT=$((READLINE_POINT + ${#entry}))
    }
    bind -m vi-insert  -x '"\C-x\C-v": __clip_pick_readline'
    bind -m vi-command -x '"\C-x\C-v": __clip_pick_readline'
    bind -m emacs      -x '"\C-x\C-v": __clip_pick_readline'
fi
