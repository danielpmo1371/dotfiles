# Shared tmux integration - works in both bash and zsh
# Source this from .bashrc and .zshrc

# ─────────────────────────────────────────────────────────────────────────────
#   Tmux prompt marker (for scraping/automation)
# ─────────────────────────────────────────────────────────────────────────────
# Prints a unique marker line each time a prompt is shown
# Useful for tools that need to parse terminal output

DISPLAY_PROMPT_MARKER="true"
if [[ -n "${TMUX:-}" && ( "${DISPLAY_PROMPT_MARKER:-}" == "true" || "${DISPLAY_PROMPT_MARKER:-}" == "1" ) ]]; then
    PROMPT_MARKER='😎💻🧑‍💻🤖'

    # Zsh uses precmd hook
    if [[ -n "$ZSH_VERSION" ]]; then
        __tmux_prompt_marker() {
            printf "\n%s%s\n" "${PROMPT_MARKER}" "$(date '+%b %d %H:%M:%S')"
        }
        # Add to precmd_functions array if not already there
        if [[ ! " ${precmd_functions[*]} " =~ " __tmux_prompt_marker " ]]; then
            precmd_functions+=(__tmux_prompt_marker)
        fi
    fi

    # Bash uses PROMPT_COMMAND
    if [[ -n "$BASH_VERSION" ]]; then
        __tmux_prompt_marker() {
            printf "\n%s%s\n" "${PROMPT_MARKER}" "$(date '+%b %d %H:%M:%S')"
        }
        case ";${PROMPT_COMMAND:-};" in
            *";__tmux_prompt_marker;"*) ;;
            *) PROMPT_COMMAND="__tmux_prompt_marker;${PROMPT_COMMAND:-}" ;;
        esac
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
#   Never leave the pane title empty (tmux-resurrect safety)
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code clears the pane title when it exits. tmux-resurrect parses its
# tab-separated pane lines with `IFS=$'\t' read`, which collapses the empty
# title field, shifting every later field left: the saved cwd becomes "0"/"1"
# and restored panes open in $HOME. Restore the tmux default title (short
# hostname) at each prompt, only when empty, so `prefix T` titles are kept.
if [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]]; then
    __tmux_fill_empty_title() {
        tmux if-shell -F -t "$TMUX_PANE" '#{pane_title}' '' \
            "select-pane -t '$TMUX_PANE' -T '${__tmux_default_title}'" 2>/dev/null
    }

    if [[ -n "$ZSH_VERSION" ]]; then
        __tmux_default_title="${HOST%%.*}"
        if [[ ! " ${precmd_functions[*]} " =~ " __tmux_fill_empty_title " ]]; then
            precmd_functions+=(__tmux_fill_empty_title)
        fi
    fi

    if [[ -n "$BASH_VERSION" ]]; then
        __tmux_default_title="${HOSTNAME%%.*}"
        case ";${PROMPT_COMMAND:-};" in
            *";__tmux_fill_empty_title;"*) ;;
            *) PROMPT_COMMAND="__tmux_fill_empty_title;${PROMPT_COMMAND:-}" ;;
        esac
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
#   Tmux aliases
# ─────────────────────────────────────────────────────────────────────────────
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tn='tmux new-session -s'
alias tk='tmux kill-session -t'
alias start='tmux new-session -A -s main'
# Exit all claude panes cleanly, resurrect-save, kill server (prefix + C-q equivalent)
alias trs='~/repos/dotfiles/util-scripts/tmux-restart.sh'
