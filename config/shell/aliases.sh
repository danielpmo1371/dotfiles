# Shared shell aliases - works in both bash and zsh
# Source this from .bashrc and .zshrc

# ─────────────────────────────────────────────────────────────────────────────
#   Terminal awarenes
# ─────────────────────────────────────────────────────────────────────────────
alias h='hostname'

# ─────────────────────────────────────────────────────────────────────────────
#   Navigation
# ─────────────────────────────────────────────────────────────────────────────
# Auto-ls after cd. Gated on stdout being a tty: inside a "$(cd ... && pwd)"
# command substitution the listing would be captured as data and corrupt it.
cd() {
    builtin cd "$@" || return
    [ -t 1 ] && lsd
    return 0
}

alias root='cd ~/repos/'
alias ..='cd ..'
alias ...='cd ../..'

# ─────────────────────────────────────────────────────────────────────────────
#   Custom terminal commands behaviour
# ─────────────────────────────────────────────────────────────────────────────
# Case-insensitive grep for interactive use (aliases don't leak into scripts).
# rg gets the same via RIPGREP_CONFIG_PATH (env.sh) -> config/ripgrep/config.
alias grep='grep -i'

# Image cat: timg speaks the kitty/iTerm2 graphics protocols (Ghostty-compatible)
alias icat='timg'

# Override rm: move to the trash instead of deleting.
# Why: a safety net. Anything removed at an interactive prompt stays
# recoverable from the trash instead of being gone for good.
# Dispatch, first match wins:
#   1. trash-put  (trash-cli, freedesktop Trash spec; Arch/Debian)
#   2. trash      (macOS 14+ ships /usr/bin/trash; it does not accept "--")
#   3. mv into ~/.Trash (macOS) or $XDG_DATA_HOME/Trash/files (Linux),
#      suffixing the name when an entry with that name is already there.
# rm-style flags (-r -f -i -v ...) are accepted and ignored: trash handles
# directories. The real binary is still reachable via `command rm` or `\rm`.
# Known gap: the Linux fallback (3) writes only Trash/files, never the
# Trash/info/*.trashinfo sidecars, so trash-list/trash-restore and desktop
# trash UIs will not show those entries. They are recoverable by hand from
# that directory.
rm() {
    local -a files=()
    local arg dropped=no after_dashdash=no
    for arg in "$@"; do
        if [[ "$after_dashdash" == yes ]]; then
            files+=("$arg")
        elif [[ "$arg" == -- ]]; then
            after_dashdash=yes
        elif [[ "$arg" == -?* ]]; then
            dropped=yes
        else
            files+=("$arg")
        fi
    done
    if [[ ${#files[@]} -eq 0 ]]; then
        if [[ "$dropped" == yes ]]; then
            echo "rm: missing operand (names starting with '-' need '--' before them)" >&2
        else
            echo "rm: missing operand" >&2
        fi
        return 1
    fi

    if command -v trash-put >/dev/null 2>&1; then
        trash-put -- "${files[@]}"
        return
    fi

    if command -v trash >/dev/null 2>&1; then
        local -a safe=()
        local f
        for f in "${files[@]}"; do
            case "$f" in
                -*) safe+=("./$f") ;;
                *)  safe+=("$f") ;;
            esac
        done
        trash "${safe[@]}"
        return
    fi

    local dest
    if [[ "$OSTYPE" == darwin* ]]; then
        dest="$HOME/.Trash"
    else
        dest="${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files"
    fi
    mkdir -p "$dest" || return 1

    local f name target stamp n rc=0
    for f in "${files[@]}"; do
        name="${f%/}"
        name="${name##*/}"
        if [[ -z "$name" ]]; then
            echo "rm: refusing to trash '$f'" >&2
            rc=1
            continue
        fi
        target="$dest/$name"
        if [[ -e "$target" || -L "$target" ]]; then
            stamp="$(date +%s)"
            target="$dest/$name.$stamp"
            n=1
            while [[ -e "$target" || -L "$target" ]]; do
                target="$dest/$name.$stamp.$n"
                n=$((n + 1))
            done
        fi
        if ! command mv -- "$f" "$target"; then
            echo "rm: cannot move '$f' to '$dest'" >&2
            rc=1
        fi
    done
    return $rc
}

# ─────────────────────────────────────────────────────────────────────────────
#   Editor & Config
# ─────────────────────────────────────────────────────────────────────────────
alias n='nvim'
alias fvim='nvim "$(fzf)"'
alias nz='nvim $(fzf)'
alias setup-vim='nvim ~/.config/nvim/init.lua'
alias setup-ssh='nvim ~/.ssh/config'
alias setup-dns='nvim /etc/resolv.conf'
alias setup-alias="nvim $DOTFILES_DIR/config/shell/aliases.sh"
alias setup-hyprland="nvim ~/.config/hypr/hyprland.lua"
alias setup-tmux='nvim ~/.tmux.conf'
alias setup-ghostty='nvim ~/.config/ghostty/config'
alias setup-claude='nvim ~/.claude/settings.json'
alias setup-claude-prompt='nvim ~/.claude/CLAUDE.md'
alias re-tmux='tmux source-file ~/.tmux.conf'
alias dot='z dot'
alias ff='fastfetch'
alias inst='sudo pacman -S'

# ─────────────────────────────────────────────────────────────────────────────
#   Git
# ─────────────────────────────────────────────────────────────────────────────
alias lz='lazygit'
alias gs='git status'
alias cm='git cm'
alias psh='git push'
alias lg='git log --pretty'
alias flg="git log --oneline | fzf --ansi --preview 'git show --color=always {1}' | awk '{print \$1}' | xargs git show"

# Git show with syntax highlighting (uses delta > bat > git native)
gshow() {
    local ref="${1:-HEAD}"
    if command -v delta &>/dev/null; then
        git show --color=always "$ref" | delta
    elif command -v bat &>/dev/null; then
        git show --color=always "$ref" | bat --style=plain --paging=never
    else
        git show --color=always "$ref"
    fi
}
alias gsh='gshow'

# ─────────────────────────────────────────────────────────────────────────────
#   AI Tools
# ─────────────────────────────────────────────────────────────────────────────
alias cc='claude -p --model haiku'
alias gg='gemini -p'
alias g='gemini --model gemini-2.5-flash --prompt'
alias update-claude='sudo npm i -g @anthropic-ai/claude-code'
# --rc (--remote-control) takes an optional [name], so it must not be the last
# flag — anything appended after it (e.g. a starter prompt) would be eaten as
# the session name instead of reaching claude as the prompt.
alias cdang='claude --rc --dangerously-skip-permissions'
# Newest recorded session for the current directory, independent of scrollback.
#
# Claude stores each session at ~/.claude/projects/<cwd with / turned into ->/
# <session-id>.jsonl, so the filename IS the session id and the newest file is
# the most recent session for this directory. Directory-scoped, not pane-scoped:
# if two panes ran claude in the same cwd this returns the newer of the two.
_cres_session_from_transcripts() {
    local dir="$HOME/.claude/projects/${PWD//\//-}"
    [ -d "$dir" ] || return 1

    # List names (not a glob): zsh errors on an unmatched glob under nomatch,
    # and an empty project dir is an ordinary case, not an error.
    local newest
    newest=$(ls -1t "$dir" 2>/dev/null | grep -E '\.jsonl$' | head -1)
    [ -n "$newest" ] || return 1

    echo "${newest%.jsonl}"
}

# Re-run the exact `claude --resume <session>` hint claude prints on quit, with
# cdang's flags. Scrapes THIS pane's scrollback for the last such line, so it
# resumes this pane's session even if newer sessions were started in other tabs
# (which would win with --continue). Handles both hint formats: quoted names
# (older CLIs) and bare UUIDs (current).
#
# Falls back to the transcript directory when the scrollback has no hint, which
# is the normal case after a reboot rather than an edge case. Measured: claude
# prints the hint on /exit, SIGTERM and SIGHUP alike, but at shutdown systemd
# stops each pane's tmux-spawn-*.scope with KillMode=control-group, which
# signals the pane's SHELL too -- the shell exits, tmux stops rendering, and
# claude's hint (written ~1s later) never reaches the pane. A running claude is
# also in alt-screen, which has no scrollback, so tmux-continuum's periodic save
# never captures a hint either. Only tmux-restart.sh's exit-then-save ordering
# puts one in a resurrect save; nothing enforces that on an unplanned reboot.
#
# The session stays resumable in every one of those cases -- what is lost is the
# ability to find its id from the pane, which is what this fallback restores.
cres() {
    local session=""

    # Anchor to line start so prose/error messages that merely mention
    # `claude --resume ...` mid-line don't shadow the real quit hint.
    if [ -n "$TMUX" ]; then
        session=$(tmux capture-pane -p -S - -t "$TMUX_PANE" \
            | grep -E '^[[:space:]]*claude --resume ' \
            | grep -Eo 'claude --resume ("[^"]+"|[A-Za-z0-9_-]+)' | tail -1 \
            | sed -E 's/^claude --resume "?([^"]+)"?$/\1/')
    fi

    if [ -z "$session" ]; then
        session=$(_cres_session_from_transcripts) || {
            echo "cres: no resume hint in this pane and no recorded session for $PWD" >&2
            return 1
        }
        # Say so: this one is the newest session for the directory, which is not
        # necessarily the one that ran in this pane.
        echo "cres: no hint in scrollback — resuming newest session for $PWD" >&2
    fi

    cdang --resume "$session"
}

# Fast one-shot query via `llm`. Provider chosen by $AI_PROVIDER (see env.sh);
# defaults to Groq for the lowest time-to-first-token.
#
# The output stage is chosen by $Q_RENDER (see env.sh):
#   pretty - the finished answer is rendered as markdown by glow, so bold,
#            bullets, tables and code blocks display as formatting instead of
#            leaving their literal `*`/backtick markers on screen. Rendering
#            needs the whole document, so nothing appears until the model is
#            done.
#   raw    - the answer streams line by line through bat, which only syntax
#            highlights markdown (the `*` markers stay visible). Keeps the
#            lowest time-to-first-token.
# Renderers are optional: glow -> bat -> cat, so a machine without them still
# works. Piped output (no tty) is always raw markdown so it stays parseable.
#
# The raw answer is copied to the clipboard (pbcopy, when available) and the
# Q&A appended to $Q_LOG_FILE (default ~/.q_history.md) as markdown - display
# formatting never reaches either, they stay free of ANSI escapes.
#   q "explain this regex"            # uses $AI_PROVIDER / $Q_RENDER
#   Q_RENDER=raw q "..."              # stream this one answer instead
#   AI_PROVIDER=gemini q "..."        # switch provider for one call
#   AI_MODEL=groq/llama-3.3-70b-versatile q "..."   # pin a specific model

# Width for the markdown renderer. glow only auto-detects the terminal width
# when its own stdout is a tty; here it feeds the pager, where it would
# otherwise fall back to its built-in 80 columns.
_q_render_width() {
    local cols="$COLUMNS"
    if [ -z "$cols" ] && command -v tput > /dev/null 2>&1; then
        cols="$(tput cols 2>/dev/null)"
    fi
    echo "${cols:-$Q_FALLBACK_WIDTH}"
}

# Display a completed answer: render markdown if we can, degrade if we cannot.
_q_show_pretty() {
    local answer="$1"
    if command -v glow > /dev/null 2>&1; then
        # Fed on stdin: glow only renders a *file* as markdown when its name
        # ends in .md, and mktemp names don't (BSD mktemp has no --suffix).
        # glow execs $PAGER itself and shows nothing if it is missing, so page
        # only when the pager's command exists.
        if command -v "${Q_PAGER%% *}" > /dev/null 2>&1; then
            PAGER="$Q_PAGER" glow --width "$(_q_render_width)" --pager - < "$answer"
        else
            glow --width "$(_q_render_width)" - < "$answer"
        fi
    elif command -v bat > /dev/null 2>&1; then
        bat --style=plain --language=md --paging=always --pager="$Q_PAGER" "$answer"
    else
        cat "$answer"
    fi
}

# Filter that highlights the answer as it streams in (stdin -> stdout).
_q_show_raw() {
    if command -v bat > /dev/null 2>&1; then
        bat --style=plain --language=md --paging=always --pager="$Q_PAGER"
    else
        cat
    fi
}

q() {
    local model="$AI_MODEL"
    if [ -z "$model" ]; then
        case "${AI_PROVIDER:-groq}" in
            groq)   model="groq/openai/gpt-oss-20b" ;;
            gemini) model="gemini-2.5-flash" ;;
            openai) model="gpt-4o-mini" ;;
            claude) model="claude-haiku-4-5-20251001" ;;
            *)      echo "q: unknown AI_PROVIDER '$AI_PROVIDER' (groq|gemini|openai|claude)" >&2; return 2 ;;
        esac
    fi
    local render="${Q_RENDER:-pretty}"
    case "$render" in
        pretty|raw) ;;
        *) echo "q: unknown Q_RENDER '$render' (pretty|raw)" >&2; return 2 ;;
    esac
    if ! command -v llm >/dev/null 2>&1; then
        echo "q: 'llm' not installed -> run: ./install.sh --llm" >&2
        return 127
    fi
    local tmp
    tmp="$(mktemp)" || return 1
    if [ ! -t 1 ]; then
        llm -m "$model" "$@" | tee "$tmp"
    elif [ "$render" = "pretty" ]; then
        llm -m "$model" "$@" > "$tmp"
        [ -s "$tmp" ] && _q_show_pretty "$tmp"
    else
        llm -m "$model" "$@" | tee "$tmp" | _q_show_raw
    fi
    if [ -s "$tmp" ]; then
        if command -v pbcopy >/dev/null 2>&1; then
            pbcopy < "$tmp"
        fi
        {
            printf '\n---\n### %s | %s\n\n**Q:** %s\n\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" "$model" "$*"
            cat "$tmp"
            printf '\n'
        } >> "${Q_LOG_FILE:-$HOME/.q_history.md}"
    fi
    rm -f "$tmp"
}

# ─────────────────────────────────────────────────────────────────────────────
#   Terraform / DevOps
# ─────────────────────────────────────────────────────────────────────────────
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"'

# ─────────────────────────────────────────────────────────────────────────────
#   Terraform / DevOps
# ─────────────────────────────────────────────────────────────────────────────
alias tf='terraform'

# ─────────────────────────────────────────────────────────────────────────────
#   Azure CLI
# ─────────────────────────────────────────────────────────────────────────────
alias az-show='az account show'
alias azl='az account list | grep name'
alias az-list='az account list | grep name'

# ─────────────────────────────────────────────────────────────────────────────
#   File listing (uses lsd if available, falls back to ls)
# ─────────────────────────────────────────────────────────────────────────────
if command -v lsd &> /dev/null; then
    alias ls='lsd'
    alias la='lsd -la'
    alias ll='lsd -l'
else
    alias ls='ls -G'
    alias la='ls -la'
    alias ll='ls -l'
fi

# ─────────────────────────────────────────────────────────────────────────────
#   Utilities
# ─────────────────────────────────────────────────────────────────────────────
alias cls='clear'
alias myip='curl -s ifconfig.me'
alias todo='nvim ~/todo.md'
alias start='tmux new-session -A -n dan'
alias awake='caffeinate -d'  # Keep Mac awake (display on, system won't sleep)
#alias node="/home/linuxbrew/.linuxbrew/Cellar/node/25.2.1/bin/node"
#alias nvim="/home/linuxbrew/.linuxbrew/Cellar/neovim/0.11.5_1/bin/nvim"


# ─────────────────────────────────────────────────────────────────────────────
#   FZF + Ripgrep integration
# ─────────────────────────────────────────────────────────────────────────────
# FZF Search with RG instead of find
alias nzz='rg --line-number --color=always "$1" | fzf --ansi --delimiter : --preview "bat --color=always {1} --highlight-line {2}" | awk -F: '"'"'{ print "+"$2" "$1 }'"'"' | xargs nvim'

# ─────────────────────────────────────────────────────────────────────────────
#   Python
# ─────────────────────────────────────────────────────────────────────────────
alias python=python3
alias pip=pip3

# ─────────────────────────────────────────────────────────────────────────────
#   System Info & Image Display
# ─────────────────────────────────────────────────────────────────────────────
# System info - use native fastfetch (clean ASCII art)
alias fetch='fastfetch'
# Neofetch still available if installed
# Custom image versions available in util-scripts/ if needed

# Manual image display - auto-display disabled in tmux due to compatibility issues
# if command -v chafa &>/dev/null; then
#     # Show image with automatic format detection and size limit (max 1/4 terminal width)
#     show-img() {
#         local max_width=$(($(tput cols) / 4))
#
#         if [[ -n "$TMUX" ]]; then
#             # In tmux: use symbols for stability (or try passthrough at your own risk)
#             chafa -f symbols --size="${max_width}x" "$@"
#         else
#             # Outside tmux: use high-quality graphics
#             chafa --size="${max_width}x" "$@"
#         fi
#     }
#
#     # Show startup image
#     show-start() {
#         if [[ -f "$DOTFILES_DIR/images/start.png" ]]; then
#             show-img "$DOTFILES_DIR/images/start.png"
#         else
#             echo "Startup image not found: $DOTFILES_DIR/images/start.png"
#         fi
#     }
# fi

# ─────────────────────────────────────────────────────────────────────────────
#   macOS power management (lid / caffeinate)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$OSTYPE" == darwin* ]]; then
    # lid off|on|status — control whether closing the lid sleeps the Mac.
    # disablesleep persists across reboots: a closed MacBook in a bag stays
    # awake, runs hot and drains — hence the warning and the status command.
    lid() {
        case "$1" in
            off)
                sudo pmset -a disablesleep 1 && \
                    echo "⚠️  Lid close no longer sleeps this Mac (persists across reboots)." && \
                    echo "   Battery drains and heat builds if closed in a bag. Restore: lid on"
                ;;
            on)
                sudo pmset -a disablesleep 0 && echo "Normal lid-close sleep restored."
                ;;
            status|"")
                pmset -g | grep -E 'disablesleep|^ sleep|SleepDisabled' || \
                    echo "disablesleep not set (normal lid behavior)"
                ;;
            *)
                echo "usage: lid off|on|status" >&2
                return 1
                ;;
        esac
    }
    alias insomnia='lid off'
    alias rest='lid on'

    # caff [cmd...] — keep the Mac awake (lid OPEN only; caffeinate cannot
    # override a closed lid — that's what `lid off` is for).
    # No args: awake until Ctrl+C. With args: awake only while <cmd> runs.
    caff() {
        if [[ $# -eq 0 ]]; then
            echo "Staying awake until Ctrl+C (lid must stay open)..."
            caffeinate -is
        else
            caffeinate -is "$@"
        fi
    }
fi

# ─────────────────────────────────────────────────────────────────────────────
#   Shell functions
# ─────────────────────────────────────────────────────────────────────────────
# Load the add-shortcut function form so `add-shortcut <name>` can capture the
# last command. A function takes precedence over the PATH executable in
# util-scripts/, which runs in a child process and cannot read shell history.
[[ -f "$DOTFILES_DIR/util-scripts/add-shortcut.function.sh" ]] && \
    source "$DOTFILES_DIR/util-scripts/add-shortcut.function.sh"
