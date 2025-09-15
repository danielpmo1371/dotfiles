# shellcheck shell=bash

# add_shortcut shell function for bash and zsh.
#
# How to install:
# - Bash: add this line to your ~/.bashrc
#       source /path/to/add-shortcut.function.sh
# - Zsh: add this line to your ~/.zshrc
#       source /path/to/add-shortcut.function.sh
#
# Usage:
#   add-shortcut <name>          # captures the previous command
#   add-shortcut <name> "cmd"    # use explicit command
#
# Works inside tmux because it runs in your current shell process.

add-shortcut() {
  local name="$1" cmd rc shell_name

  if [[ ${1-} == "-h" || ${1-} == "--help" || $# -lt 1 || $# -gt 2 ]]; then
    printf "Usage: add-shortcut <name> [\"<command>\"]\n" >&2
    return $([[ $# -lt 1 ]] && echo 1 || echo 0)
  fi

  # Validate name
  if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf "Error: name must match [A-Za-z0-9_-]\n" >&2
    return 1
  fi

  # Determine shell rc file
  shell_name="${ZSH_VERSION:+zsh}"
  if [[ -z "$shell_name" ]]; then
    shell_name="${BASH_VERSION:+bash}"
  fi
  if [[ -z "$shell_name" ]]; then
    shell_name="${SHELL##*/}"
  fi
  case "$shell_name" in
    zsh) rc="$HOME/.zshrc" ;;
    bash|*) rc="$HOME/.bashrc" ;;
  esac

  # Resolve command
  if [[ $# -eq 2 ]]; then
    cmd="$2"
  else
    # Prefer the command before this invocation.
    # In bash/zsh, fc lists history; -l = list, -n = suppress numbers.
    # Try last entry; if it looks like our own call, fallback to previous.
    cmd=$(fc -ln -1 2>/dev/null)
    if [[ "$cmd" == add-shortcut* || "$cmd" == *" add-shortcut"* || "$cmd" == *" add-shortcut "* ]]; then
      cmd=$(fc -ln -2 2>/dev/null | head -1)
    fi
    # If still empty, try previous unconditionally
    if [[ -z "${cmd// }" ]]; then
      cmd=$(fc -ln -2 2>/dev/null | head -1)
    fi
    if [[ -z "${cmd// }" ]]; then
      printf "Error: Could not read last command. Pass it explicitly: add-shortcut %s \"<command>\"\n" "$name" >&2
      return 1
    fi
    # Normalize multi-line commands to a single line for aliasing
    cmd=$(printf %s "$cmd" | tr '\n' ' ' | sed 's/[[:space:]]\{2,\}/ /g')
  fi

  # Warn if alias exists
  if [[ -f "$rc" ]] && grep -qE "^[[:space:]]*alias[[:space:]]+$name=" "$rc"; then
    printf "Error: alias '%s' already exists in %s\n" "$name" "$rc" >&2
    return 1
  fi

  # Escape single quotes and write alias using single quotes
  local esc
  esc=$(printf %s "$cmd" | sed "s/'/'\\''/g")
  printf "alias %s='%s'\n" "$name" "$esc" >> "$rc"
  printf "Created shortcut: %s -> %s\nAdded to: %s\n" "$name" "$cmd" "$rc"
  printf "To use now: source %s\n" "$rc"
}
