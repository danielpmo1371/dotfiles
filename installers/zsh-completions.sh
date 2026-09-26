#!/bin/bash

# Zsh completions installer
# Links custom completion functions (config/zsh/completions/_*) into the
# directory that config/zsh/zshrc prepends to fpath.
#
# The target directory is shared with generated completions (e.g. a `_bat`
# emitted by `bat --completion zsh`), so files are linked one by one; the
# directory itself is never symlinked.
#
# Dependencies: none (zsh only needed to use the completions)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

ZSH_COMPLETIONS_SOURCE_DIR="$DOTFILES_ROOT/config/zsh/completions"
# Must match the directory config/zsh/zshrc adds to fpath
# (~/.local/share/zsh/completions); the XDG default resolves to the same path.
ZSH_COMPLETIONS_TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/completions"
ZSH_COMPDUMP="$HOME/.zcompdump"

install_zsh_completions() {
    log_header "Zsh Completions"

    ensure_dir "$ZSH_COMPLETIONS_TARGET_DIR"

    local linked=0
    local src
    for src in "$ZSH_COMPLETIONS_SOURCE_DIR"/_*; do
        # With nullglob off an unmatched pattern is returned literally
        [ -e "$src" ] || continue
        if create_symlink_with_backup "$src" "$ZSH_COMPLETIONS_TARGET_DIR/$(basename "$src")"; then
            linked=$((linked + 1))
        fi
    done

    if [ "$linked" -eq 0 ]; then
        log_warn "No completion files found in $ZSH_COMPLETIONS_SOURCE_DIR"
        return 0
    fi
    log_success "Linked $linked completion file(s) into $ZSH_COMPLETIONS_TARGET_DIR"

    # zshrc runs `compinit -C` (trust the cached dump) unless ~/.zcompdump is
    # older than 24h, so a newly linked completion stays invisible until the
    # next full compinit. Backdating the dump's mtime forces that full run on
    # the next shell start. The file is deliberately not deleted.
    if [ -f "$ZSH_COMPDUMP" ]; then
        touch -t 197001010000 "$ZSH_COMPDUMP"
        log_info "Reset mtime of $ZSH_COMPDUMP so the next zsh start rebuilds the completion cache"
    fi

    echo ""
    echo "Next steps:"
    echo "  1. Run 'exec zsh' to load the new completions"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_zsh_completions
fi
