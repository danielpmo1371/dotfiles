# Shared tmux integration - works in both bash and zsh
# Source this from .bashrc and .zshrc

# ─────────────────────────────────────────────────────────────────────────────
#   Auto-attach: "always inside tmux" is an ENFORCED invariant
# ─────────────────────────────────────────────────────────────────────────────
# tmux is the single brain for all meta (Alt/Option/Cmd) keybindings — the
# shells carry NO meta bindings. That is only safe while tmux sits between
# the terminal and every interactive vi-mode shell: an unbound ESC+char in a
# bare vi-mode shell executes as a vi command (measured destructive: ESC+d d
# wipes the line, ESC+k Enter re-runs stale history). So every interactive,
# local, non-tmux shell execs straight into the same session `start` uses.
# Escape hatches: NO_TMUX=1 for a deliberate bare shell; SSH sessions and
# IDE-embedded terminals (VS Code) are left alone.
if [[ $- == *i* && -z "${TMUX:-}" && -z "${NO_TMUX:-}" && -z "${SSH_TTY:-}" ]] \
   && [[ "${TERM:-}" != "dumb" && "${TERM_PROGRAM:-}" != "vscode" ]] \
   && [ -t 0 ] && command -v tmux >/dev/null 2>&1; then
    exec tmux new-session -A -s main
fi

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
#   Tmux aliases
# ─────────────────────────────────────────────────────────────────────────────
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tn='tmux new-session -s'
alias tk='tmux kill-session -t'
alias start='tmux new-session -A -s main'
