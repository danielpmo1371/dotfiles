#!/bin/bash

# Keybinding meta-layer parity test (hermetic — static parse, no tmux server)
#
# Enforces the single-brain invariants of the keybinding architecture
# (see CLAUDE.md "Keybinding architecture"):
#   1. Every trained meta key has a tmux consumer (root table or prefix2).
#      A trained key without a consumer falls through to the pane's vi-mode
#      shell, where an unbound ESC+char executes as a vi command.
#   2. The shells carry NO meta (ESC-prefix letter) bindings — tmux is the
#      only owner of meta semantics; bare shells are prevented by the
#      auto-attach invariant instead.
#   3. The auto-attach block exists in config/shell/tmux.sh.
#
# Adding trained key #14: bind it in tmux.conf AND add it to TRAINED_KEYS.
#
# Usage: ./tests/test-keybinding-parity.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

TMUX_CONF="$DOTFILES_ROOT/config/tmux/tmux.conf"
ZSHRC="$DOTFILES_ROOT/config/zsh/zshrc"
BASHRC="$DOTFILES_ROOT/config/bash/bashrc"
TMUX_SH="$DOTFILES_ROOT/config/shell/tmux.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }

# The trained meta vocabulary: keys the user's muscle memory emits (Cmd on
# macOS via ghostty key-remap, Alt on Linux natively) plus the hazard-cap
# keys consumed because their vi fall-through is destructive.
TRAINED_KEYS="e a q w r u d i n h j k l"
HAZARD_CAP_KEYS="x s c"

echo "1. Every trained meta key has a tmux consumer (root or prefix2)"
for k in $TRAINED_KEYS $HAZARD_CAP_KEYS; do
    if grep -Eq "^[[:space:]]*bind(-key)?[[:space:]]+-n[[:space:]]+M-$k\b" "$TMUX_CONF"; then
        pass "M-$k: root-table bind"
    elif grep -Eq "^[[:space:]]*set(-option)?[[:space:]]+-g[[:space:]]+prefix2[[:space:]]+M-$k\b" "$TMUX_CONF"; then
        pass "M-$k: prefix2"
    else
        fail "M-$k: NO root-table consumer in tmux.conf — falls through to vi-mode pane shells"
    fi
done

echo "2. Shells own no meta bindings (tmux is the single brain)"
if grep -Eq "bindkey[^#]*'\\\\e[a-z]'" "$ZSHRC"; then
    fail "zshrc: ESC-prefix letter bindkey found — meta semantics belong in tmux.conf"
else
    pass "zshrc: no meta letter bindings"
fi
if grep -Eq 'bind[[:space:]]+-m[^#]*"\\\\e[a-z]"' "$BASHRC"; then
    fail "bashrc: ESC-prefix letter bind found — meta semantics belong in tmux.conf"
else
    pass "bashrc: no meta letter bindings"
fi

echo "3. Auto-attach invariant present in config/shell/tmux.sh"
if grep -q 'exec tmux new-session -A' "$TMUX_SH"; then
    pass "auto-attach exec present"
else
    fail "auto-attach block missing — bare vi-mode shells would be unprotected"
fi
for guard in 'TMUX' 'NO_TMUX' 'SSH_TTY' '\-t 0'; do
    if grep -Eq "$guard" "$TMUX_SH"; then
        pass "auto-attach guard: $guard"
    else
        fail "auto-attach guard missing: $guard"
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
