# Shared tmux integration - works in both bash and zsh
# Source this from .bashrc and .zshrc

# ─────────────────────────────────────────────────────────────────────────────
#   Tmux prompt marker (for scraping/automation)
# ─────────────────────────────────────────────────────────────────────────────
# Prints a unique marker line each time a prompt is shown
# Useful for tools that need to parse terminal output

if [[ -n "${TMUX:-}" ]]; then
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
#   Tmux aliases
# ─────────────────────────────────────────────────────────────────────────────
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tn='tmux new-session -s'
alias tk='tmux kill-session -t'
alias start='tmux new-session -A -s main'
