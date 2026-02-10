#!/bin/bash

# Validate all expected dotfiles symlinks
# Usage: ./tests/validate-symlinks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

check_symlink() {
    local target="$1"
    local expected_source="$2"
    local label="${3:-$target}"

    if [ ! -L "$target" ]; then
        if [ -e "$target" ]; then
            echo -e "  ${YELLOW}SKIP${NC} exists but not a symlink: $label"
            SKIP=$((SKIP + 1))
        else
            echo -e "  ${RED}FAIL${NC} missing: $label"
            FAIL=$((FAIL + 1))
        fi
        return
    fi

    local actual_source
    actual_source="$(readlink "$target")"

    if [ "$actual_source" = "$expected_source" ]; then
        echo -e "  ${GREEN}PASS${NC} $label -> $actual_source"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label -> $actual_source (expected: $expected_source)"
        FAIL=$((FAIL + 1))
    fi
}

check_source_exists() {
    local source="$1"
    local label="${2:-$source}"

    if [ -e "$source" ]; then
        echo -e "  ${GREEN}PASS${NC} source exists: $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} source missing: $label"
        FAIL=$((FAIL + 1))
    fi
}

echo -e "${BLUE}Dotfiles Symlink Validator${NC}"
echo "Dotfiles root: $DOTFILES_ROOT"

# Shell configs
echo -e "\n${BLUE}=== Shell Configs ===${NC}"
check_symlink "$HOME/.bashrc" "$DOTFILES_ROOT/config/bash/bashrc" "bashrc"
check_symlink "$HOME/.bash_aliases" "$DOTFILES_ROOT/config/bash/bash_aliases" "bash_aliases"
check_symlink "$HOME/.zshrc" "$DOTFILES_ROOT/config/zsh/zshrc" "zshrc"
check_symlink "$HOME/.p10k.zsh" "$DOTFILES_ROOT/config/zsh/p10k.zsh" "p10k.zsh"

# Tmux
echo -e "\n${BLUE}=== Tmux ===${NC}"
check_symlink "$HOME/.tmux.conf" "$DOTFILES_ROOT/config/tmux/tmux.conf" "tmux.conf"

# Config directories
echo -e "\n${BLUE}=== Config Directories (~/.config/) ===${NC}"
check_symlink "$HOME/.config/nvim" "$DOTFILES_ROOT/config/nvim" "nvim"
check_symlink "$HOME/.config/ghostty" "$DOTFILES_ROOT/config/ghostty" "ghostty"

# Claude
echo -e "\n${BLUE}=== Claude Code (~/.claude/) ===${NC}"
check_symlink "$HOME/.claude/settings.json" "$DOTFILES_ROOT/config/claude/settings.json" "settings.json"
check_symlink "$HOME/.claude/CLAUDE.md" "$DOTFILES_ROOT/config/claude/CLAUDE.md" "CLAUDE.md"

if [ -L "$HOME/.claude/commands" ]; then
    check_symlink "$HOME/.claude/commands" "$DOTFILES_ROOT/config/claude/commands" "commands/"
else
    echo -e "  ${YELLOW}SKIP${NC} commands/ (may be a directory with individual symlinks)"
    SKIP=$((SKIP + 1))
fi

# Verify all source files exist in the repo
echo -e "\n${BLUE}=== Source File Verification ===${NC}"
check_source_exists "$DOTFILES_ROOT/config/bash/bashrc" "bash/bashrc"
check_source_exists "$DOTFILES_ROOT/config/bash/bash_aliases" "bash/bash_aliases"
check_source_exists "$DOTFILES_ROOT/config/zsh/zshrc" "zsh/zshrc"
check_source_exists "$DOTFILES_ROOT/config/zsh/p10k.zsh" "zsh/p10k.zsh"
check_source_exists "$DOTFILES_ROOT/config/tmux/tmux.conf" "tmux/tmux.conf"
check_source_exists "$DOTFILES_ROOT/config/nvim/init.lua" "nvim/init.lua"
check_source_exists "$DOTFILES_ROOT/config/claude/settings.json" "claude/settings.json"
check_source_exists "$DOTFILES_ROOT/config/claude/CLAUDE.md" "claude/CLAUDE.md"

# Check for broken symlinks
echo -e "\n${BLUE}=== Broken Symlink Scan ===${NC}"
broken_count=0
while IFS= read -r -d '' link; do
    if [ ! -e "$link" ]; then
        local_target="$(readlink "$link")"
        echo -e "  ${RED}BROKEN${NC} $link -> $local_target"
        broken_count=$((broken_count + 1))
        FAIL=$((FAIL + 1))
    fi
done < <(find "$HOME" -maxdepth 3 -type l -name ".*" -not -path "$DOTFILES_ROOT/*" -print0 2>/dev/null || true)

if [ "$broken_count" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} No broken symlinks found in ~/"
    PASS=$((PASS + 1))
fi

# Summary
echo ""
echo "========================================"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
