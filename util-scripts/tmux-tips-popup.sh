#!/bin/bash
# tmux-tips-popup.sh - Display a random tip about tmux, terminal tools, and configs
# Called without args: launches the tmux popup
# Called with --display: renders the tip content (runs inside the popup)

TIPS=(
  # ── Tmux Navigation ──
  "Ctrl+h/j/k/l navigates panes without prefix — no need to hit Cmd+e first."
  "Alt+h/j/k/l also cycles panes — two sets of prefix-free pane nav!"
  "Shift+Left / Shift+Right switches between windows without prefix."
  "Shift+Up / Shift+Down switches between tmux sessions."
  "Ctrl+Shift+Left / Ctrl+Shift+Right moves the current window left or right."
  "Prefix + p shows pane numbers — press the number to jump to that pane."
  "Prefix + m shows pane numbers for 5s — press a number to swap with that pane."
  "Prefix + z toggles zoom on the current pane (fullscreen and back)."

  # ── Tmux Splits & Windows ──
  "Prefix + | splits the pane horizontally (side by side) in current directory."
  "Prefix + - splits the pane vertically (top/bottom) in current directory."
  "Prefix + N prompts for a name, then creates and switches to a new session."
  "Prefix + c creates a new window. Prefix + , renames it."
  "Prefix + e toggles synchronized panes — type in all panes at once!"
  "Prefix + T lets you set a custom title for the current pane."

  # ── Tmux Popups ──
  "Ctrl+q toggles the Claude Code scratchpad popup — session persists on close."
  "Ctrl+a opens a floating Neovim editor (80% size) in current directory."
  "Ctrl+w opens a floating Lazygit window (80% size) in current directory."
  "Prefix + ? shows the full keybindings cheat sheet popup."
  "Prefix + S opens the Ghostty shader picker — try different visual effects!"
  "Prefix + Ctrl+i toggles the Claude corner pane for background AI tasks."

  # ── Tmux Modes ──
  "Prefix + Z enters Zen mode — distraction-free, no status bar, pure focus."
  "Prefix + V enters Cinema mode — transparent overlay for watching content."
  "Prefix + [ enters copy mode with vi bindings — search with / and yank with y."
  "Prefix + Ctrl+e also enters copy mode — same as prefix + [."

  # ── Tmux Config ──
  "Prefix + r reloads tmux.conf — see changes instantly without restarting."
  "Windows and panes start at index 1, not 0 — matches keyboard layout."
  "tmux-resurrect auto-saves sessions. tmux-continuum restores them on restart."
  "Your tmux history limit is 50,000 lines — scroll far back with copy mode."

  # ── Shell Aliases ──
  "Type 'lz' to launch lazygit — full git GUI in the terminal."
  "Type 'gs' for git status, 'cm' for git commit, 'psh' for git push."
  "Type 'n' to open neovim. 'nz' opens neovim with fzf file picker."
  "Type 'dot' to jump to dotfiles directory. 'root' goes to ~/repos/."
  "Type 'la' for detailed file listing with lsd. 'll' for compact listing."
  "Type 'gsh' or 'gshow' to view commits with syntax highlighting (delta/bat)."
  "Type 'flg' for fuzzy git log — search commits with fzf preview."
  "Type 'start' to create or reattach to your main tmux session."
  "Type 'myip' to quickly check your public IP address."
  "Type 'awake' to keep your Mac from sleeping (caffeinate)."

  # ── Setup Aliases ──
  "Type 'setup-vim' to edit neovim config, 'setup-tmux' for tmux.conf."
  "Type 'setup-alias' to edit your shell aliases, 'setup-ghostty' for terminal."
  "Type 'setup-claude' to edit your global Claude CLAUDE.md instructions."
  "Type 're-tmux' to quickly reload your tmux configuration."

  # ── Terminal Tools ──
  "ripgrep (rg) is faster than grep — use 'nzz' to search code and open in nvim."
  "fzf is bound to ** for completion — type 'cd **<TAB>' to fuzzy-find dirs."
  "bat provides syntax-highlighted file viewing — used by fzf previews."
  "delta renders beautiful git diffs — used by 'gshow' and lazygit."
  "lsd replaces ls with icons and colors — aliased as default 'ls'."

  # ── AI Tools ──
  "Type 'cc' for quick Claude haiku queries: cc \"explain this error\"."
  "Type 'g' for Gemini Flash queries: g \"summarize this concept\"."
  "Type 'gg' for full Gemini queries with default model."

  # ── Neovim ──
  "LazyVim is your neovim base — plugins defined in config/nvim/lua/plugins/."
  "Your neovim uses LazyVim defaults plus custom keymaps in config/keymaps.lua."

  # ── Claude Skills ──
  "Type /braindump to start a brainstorming session — captures ideas and organizes notes."
  "Type /memory to search and recall persistent memories across Claude sessions."
  "Type /skill-forge to create, review, and optimize Claude Code skills."
  "Type /claude-agent-forge to build agents using the Anthropic Agent SDK."
  "Type /test-dotfiles to run Docker e2e tests for dotfiles across Linux distros."
  "Type /pipeline-ops to trigger, monitor, and manage Azure DevOps pipelines."
  "Type /fetch-azdo-logs to interactively debug Azure DevOps pipeline failures."
  "Type /learn-from-mistake after errors — guides post-mortem analysis and safeguards."
  "Type /conversation-history to search past Claude Code sessions for context."
  "Type /tit-for-tat for rapid, succinct back-and-forth communication style."

  # ── Claude Commands ──
  "Type /review-before-commit to get a pre-commit code review from Claude."
  "Type /review-branch to review all work done on the current branch."
  "Type /plan-next-strategy to plan the next phase of your project strategically."
  "Type /pipe-deploy to trigger CI/CD pipelines with safety checks and monitoring."
  "Type /session-presentation to generate an HTML presentation of your session."

  # ── Claude Agent Teams ──
  "Type /setup-machine to spawn 4 agents installing dotfiles in parallel."
  "Type /test-all-distros to spawn 3 agents testing Docker e2e on Ubuntu, Debian, Fedora."
  "Type /review-changes to spawn 3 agents for pre-commit review (compat, security, symlinks)."
  "Agent teams use tmux split panes — enable with CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1."
  "The pipeline-runner agent autonomously triggers, monitors, and recovers CI/CD pipelines."
  "The fetch-azdo-logs agent fetches pipeline logs and summarizes failures automatically."

  # ── Tmux Sessions ──
  "Type 'ta <name>' to attach to a session, 'tn <name>' to create one."
  "Type 'tl' to list sessions, 'tk <name>' to kill one."
  "Prefix + s shows an interactive session tree — navigate and switch fast."
)

if [[ "${1:-}" == "--display" ]]; then
  # Running inside the popup — render the tip
  TIP="${TIPS[$((RANDOM % ${#TIPS[@]}))]}"

  # Wrap long tips at ~56 chars for clean display
  WRAPPED=$(echo "$TIP" | fold -s -w 56)

  printf '\n'
  printf '  \033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
  printf '  \033[1;33m  💡 Tip of the Moment\033[0m\n'
  printf '  \033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
  printf '\n'
  while IFS= read -r line; do
    printf '    %s\n' "$line"
  done <<< "$WRAPPED"
  printf '\n'
  printf '  \033[2m  any key to dismiss · auto-closes in 9s\033[0m\n'
  printf '\n'

  read -t 9 -n 1 -s 2>/dev/null
  exit 0
fi

# Launch the popup
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
tmux display-popup -E -w 66% -h 50% -b rounded -S "fg=colour208" \
  "$SCRIPT_DIR/tmux-tips-popup.sh --display"
