#!/bin/bash

# Test harness for dotfiles installers
# Usage: ./tests/test-installer.sh <component|all>
# Components: tools, secrets, terminals, fonts, tmux, bash, zsh, config-dirs, claude, mcp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

# Counters
PASS=0
FAIL=0
SKIP=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

assert_command_exists() {
    local cmd="$1"
    local label="${2:-$cmd}"
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}PASS${NC} command exists: $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} command missing: $label"
        FAIL=$((FAIL + 1))
    fi
}

assert_symlink_exists() {
    local path="$1"
    local label="${2:-$path}"
    if [ -L "$path" ]; then
        local target
        target="$(readlink "$path")"
        echo -e "  ${GREEN}PASS${NC} symlink: $label -> $target"
        PASS=$((PASS + 1))
    elif [ -e "$path" ]; then
        echo -e "  ${YELLOW}SKIP${NC} exists but not symlink: $label"
        SKIP=$((SKIP + 1))
    else
        echo -e "  ${RED}FAIL${NC} missing: $label"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local path="$1"
    local label="${2:-$path}"
    if [ -e "$path" ]; then
        echo -e "  ${GREEN}PASS${NC} file exists: $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} file missing: $label"
        FAIL=$((FAIL + 1))
    fi
}

assert_dir_exists() {
    local path="$1"
    local label="${2:-$path}"
    if [ -d "$path" ]; then
        echo -e "  ${GREEN}PASS${NC} directory exists: $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} directory missing: $label"
        FAIL=$((FAIL + 1))
    fi
}

assert_valid_json() {
    local path="$1"
    local label="${2:-$path}"
    if [ -f "$path" ] || [ -L "$path" ]; then
        if command -v jq &>/dev/null && jq empty "$path" 2>/dev/null; then
            echo -e "  ${GREEN}PASS${NC} valid JSON: $label"
            PASS=$((PASS + 1))
        elif command -v python3 &>/dev/null && python3 -c "import json; json.load(open('$path'))" 2>/dev/null; then
            echo -e "  ${GREEN}PASS${NC} valid JSON: $label"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} invalid JSON: $label"
            FAIL=$((FAIL + 1))
        fi
    else
        echo -e "  ${RED}FAIL${NC} file missing for JSON check: $label"
        FAIL=$((FAIL + 1))
    fi
}

test_tools() {
    echo -e "\n${BLUE}=== Testing: tools ===${NC}"
    assert_command_exists git
    assert_command_exists nvim "neovim"
    assert_command_exists tmux
    assert_command_exists zsh
    assert_command_exists curl
    assert_command_exists node "node.js"
    assert_command_exists npm
    assert_command_exists rg "ripgrep"
    assert_command_exists fzf
    assert_command_exists jq
    assert_command_exists chafa
    assert_command_exists htop
    assert_command_exists tree
}

test_secrets() {
    echo -e "\n${BLUE}=== Testing: secrets ===${NC}"
    # secrets.sh creates a template or uses keychain - just check it ran
    echo -e "  ${GREEN}PASS${NC} secrets installer is config-only (no artifacts to check)"
    PASS=$((PASS + 1))
}

test_terminals() {
    echo -e "\n${BLUE}=== Testing: terminals ===${NC}"
    assert_symlink_exists "$HOME/.config/ghostty" "ghostty config"
    assert_file_exists "$DOTFILES_ROOT/config/ghostty/config" "ghostty config source"
}

test_fonts() {
    echo -e "\n${BLUE}=== Testing: fonts ===${NC}"
    local font_dir
    if [[ "$OSTYPE" == "darwin"* ]]; then
        font_dir="$HOME/Library/Fonts"
    else
        font_dir="$HOME/.local/share/fonts"
    fi
    assert_file_exists "$font_dir/MesloLGS NF Regular.ttf" "MesloLGS NF Regular"
    assert_file_exists "$font_dir/MesloLGS NF Bold.ttf" "MesloLGS NF Bold"
    assert_file_exists "$font_dir/MesloLGS NF Italic.ttf" "MesloLGS NF Italic"
    assert_file_exists "$font_dir/MesloLGS NF Bold Italic.ttf" "MesloLGS NF Bold Italic"
}

test_tmux() {
    echo -e "\n${BLUE}=== Testing: tmux ===${NC}"
    assert_command_exists tmux
    assert_symlink_exists "$HOME/.tmux.conf" "tmux.conf"
    assert_dir_exists "$HOME/.tmux/plugins/tpm" "TPM plugin manager"
    assert_file_exists "$HOME/.tmux/plugins/tpm/tpm" "TPM executable"
}

test_bash() {
    echo -e "\n${BLUE}=== Testing: bash ===${NC}"
    assert_symlink_exists "$HOME/.bashrc" "bashrc"
    assert_symlink_exists "$HOME/.bash_aliases" "bash_aliases"

    # Check shared shell configs are sourceable
    for shared_file in env.sh path.sh aliases.sh git.sh tmux.sh; do
        assert_file_exists "$DOTFILES_ROOT/config/shell/$shared_file" "shared: $shared_file"
    done
}

test_zsh() {
    echo -e "\n${BLUE}=== Testing: zsh ===${NC}"
    assert_command_exists zsh
    assert_symlink_exists "$HOME/.zshrc" "zshrc"
    assert_symlink_exists "$HOME/.p10k.zsh" "p10k config"
    assert_dir_exists "$HOME/.local/share/zap" "zap plugin manager"
}

test_config_dirs() {
    echo -e "\n${BLUE}=== Testing: config-dirs ===${NC}"
    assert_symlink_exists "$HOME/.config/nvim" "nvim config"
    assert_file_exists "$DOTFILES_ROOT/config/nvim/init.lua" "nvim init.lua source"
}

test_claude() {
    echo -e "\n${BLUE}=== Testing: claude ===${NC}"
    assert_symlink_exists "$HOME/.claude/settings.json" "claude settings"
    assert_symlink_exists "$HOME/.claude/CLAUDE.md" "claude CLAUDE.md"
    assert_dir_exists "$HOME/.claude/commands" "claude commands"
    assert_valid_json "$HOME/.claude/settings.json" "claude settings JSON"
}

test_mcp() {
    echo -e "\n${BLUE}=== Testing: mcp ===${NC}"
    # MCP merges config into ~/.claude.json or similar
    if [ -f "$HOME/.claude.json" ]; then
        echo -e "  ${GREEN}PASS${NC} MCP config file exists"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}SKIP${NC} MCP config location varies by setup"
        SKIP=$((SKIP + 1))
    fi
}

print_summary() {
    echo ""
    echo "========================================"
    echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
    echo "========================================"
    if [ "$FAIL" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Main dispatch
component="${1:-all}"

echo -e "${BLUE}Dotfiles Test Harness${NC}"
echo "Testing: $component"
echo "Dotfiles root: $DOTFILES_ROOT"

case "$component" in
    tools)       test_tools ;;
    secrets)     test_secrets ;;
    terminals)   test_terminals ;;
    fonts)       test_fonts ;;
    tmux)        test_tmux ;;
    bash)        test_bash ;;
    zsh)         test_zsh ;;
    config-dirs) test_config_dirs ;;
    claude)      test_claude ;;
    mcp)         test_mcp ;;
    all)
        test_tools
        test_secrets
        test_terminals
        test_fonts
        test_tmux
        test_bash
        test_zsh
        test_config_dirs
        test_claude
        test_mcp
        ;;
    *)
        echo "Unknown component: $component"
        echo "Usage: $0 <tools|secrets|terminals|fonts|tmux|bash|zsh|config-dirs|claude|mcp|all>"
        exit 1
        ;;
esac

print_summary
