#!/bin/bash

# LLM CLI installer (Simon Willison's `llm`) + Groq plugin
# Provides the fast quick-query `q` shell function (see config/shell/aliases.sh).
#
# Groq runs Llama on LPU hardware -> very low time-to-first-token.
# The API key is read from the keychain (secret GROQ_API_KEY) and exported as
# LLM_GROQ_KEY by config/shell/secrets.sh, so no plaintext key file is created.
#
# Dependencies: python3 (pipx preferred, falls back to pip --user)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

install_llm() {
    log_header "LLM CLI (llm + llm-groq)"

    # Resolve an installer: prefer pipx (isolated), fall back to pip --user
    local installed=false
    if command -v llm &> /dev/null; then
        log_info "llm already installed: $(command -v llm)"
        installed=true
    elif command -v pipx &> /dev/null; then
        log_info "Installing llm via pipx..."
        pipx install llm && installed=true
    elif command -v python3 &> /dev/null; then
        log_warn "pipx not found; installing llm via 'pip install --user'"
        python3 -m pip install --user llm && installed=true
    else
        log_error "Neither pipx nor python3 found. Install Python first (./install.sh --tools)."
        return 1
    fi

    if [[ "$installed" != true ]] || ! command -v llm &> /dev/null; then
        log_error "llm installation failed or 'llm' not on PATH"
        return 1
    fi

    # Install the Groq plugin (idempotent: llm reports if already present)
    log_info "Installing llm-groq plugin..."
    llm install llm-groq || { log_error "Failed to install llm-groq"; return 1; }

    # Populate the Groq model list if a key is available
    local groq_key="${LLM_GROQ_KEY:-}"
    if [[ -z "$groq_key" ]] && command -v secret &> /dev/null; then
        groq_key="$(secret GROQ_API_KEY 2>/dev/null)"
    fi

    if [[ -n "$groq_key" ]]; then
        log_info "Refreshing Groq model list..."
        LLM_GROQ_KEY="$groq_key" llm groq refresh || \
            log_warn "Could not refresh model list (will refresh lazily on first use)"
        log_success "LLM CLI ready. Try: q \"hello\""
    else
        log_warn "No Groq API key found."
        echo "  Get a free key at https://console.groq.com/keys then store it:"
        echo "    secret_set GROQ_API_KEY <your-key>"
        echo "  Reload your shell, then run: ./install.sh --llm   (to fetch the model list)"
    fi

    echo ""
    log_info "Default quick-query model: groq/llama-3.1-8b-instant (AI_PROVIDER=groq)"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_llm
fi
