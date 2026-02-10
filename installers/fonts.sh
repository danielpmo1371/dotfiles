#!/bin/bash

# Nerd Font installer
# Downloads MesloLGS NF fonts required by Powerlevel10k

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

FONT_BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
FONT_FILES=(
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
)

get_font_dir() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "$HOME/Library/Fonts"
    else
        echo "$HOME/.local/share/fonts"
    fi
}

install_fonts() {
    log_header "Nerd Fonts (MesloLGS NF)"

    if ! command -v curl &>/dev/null; then
        log_error "curl is required but not installed"
        return 1
    fi

    local font_dir
    font_dir="$(get_font_dir)"
    ensure_dir "$font_dir"

    local installed=0
    local skipped=0

    for font in "${FONT_FILES[@]}"; do
        local target="$font_dir/$font"

        if [[ -f "$target" ]]; then
            log_success "Already installed: $font"
            skipped=$((skipped + 1))
            continue
        fi

        local encoded_name="${font// /%20}"
        local url="$FONT_BASE_URL/$encoded_name"
        local tmp_file="$target.part"

        log_info "Downloading: $font"
        if curl -fsSL -o "$tmp_file" "$url"; then
            mv "$tmp_file" "$target"
            log_success "Installed: $font"
            installed=$((installed + 1))
        else
            rm -f "$tmp_file"
            log_error "Failed to download: $font"
            return 1
        fi
    done

    # Refresh font cache on Linux when new fonts were installed
    if [[ "$OSTYPE" != "darwin"* ]] && [[ $installed -gt 0 ]]; then
        if command -v fc-cache &>/dev/null; then
            log_info "Refreshing font cache..."
            fc-cache -f "$font_dir"
        fi
    fi

    echo ""
    log_success "Font installation complete ($installed installed, $skipped already present)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_fonts
fi
