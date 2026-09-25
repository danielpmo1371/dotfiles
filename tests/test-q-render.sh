#!/bin/bash

# Hermetic tests for the `q` quick-query output stage (config/shell/aliases.sh).
#
# Regression target: `q` used to pipe answers through `bat --language=md`, which
# only SYNTAX HIGHLIGHTS markdown — `**bold**` reached the screen with its
# asterisks intact. The pretty path now renders through glow.
#
# Hermetic by construction: `llm` is stubbed, so no API key, network or model
# list is involved. A pty is required to exercise the tty branches, so the tty
# tests run under `script`.
#
# Usage: ./tests/test-q-render.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
ALIASES="$DOTFILES_ROOT/config/shell/aliases.sh"

PASS=0
FAIL=0
SKIP=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "  ${YELLOW}SKIP${NC} $1"; SKIP=$((SKIP + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Stub llm: emits fixture markdown, with a gap so streaming is observable.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/llm" <<'STUB'
#!/bin/bash
printf '**Panes** are splits:\n\n'
sleep 1
printf '*   `prefix %%` vertical\n'
STUB
chmod +x "$WORK/bin/llm"

# Shared preamble: stubbed llm first on PATH, q's settings pinned so the test
# does not depend on the tester's exported environment.
cat > "$WORK/preamble.sh" <<PREAMBLE
export PATH="$WORK/bin:\$PATH"
export COLUMNS=100
export AI_PROVIDER=groq
export Q_PAGER="less -RFX"
export Q_FALLBACK_WIDTH=80
export Q_LOG_FILE="$WORK/history.md"
source "$ALIASES"
PREAMBLE

# Drop ANSI escapes and OSC queries so assertions see the visible text only.
strip_ansi() { sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b][0-9];?\x07//g' | tr -d '\007\r'; }

run_tty() {  # run_tty <shell-code> -> visible text on stdout
    script -qec "source $WORK/preamble.sh; $1" /dev/null 2>/dev/null | strip_ansi
}

echo -e "\n${BLUE}=== q output stage ===${NC}"

# --- Piped output must stay machine-readable ---------------------------------
out="$(bash -c "source $WORK/preamble.sh; Q_RENDER=pretty q 'x'" 2>/dev/null)"
if printf '%s' "$out" | grep -q '\*\*Panes\*\*'; then
    pass "piped output is raw markdown (renderer bypassed when stdout is not a tty)"
else
    fail "piped output lost the raw markdown"
fi
if printf '%s' "$out" | grep -qP '\x1b'; then
    fail "piped output contains ANSI escapes"
else
    pass "piped output contains no ANSI escapes"
fi

# --- The history file is a markdown document, not a screen capture -----------
if [ -s "$WORK/history.md" ] && ! grep -qP '\x1b' "$WORK/history.md"; then
    pass "\$Q_LOG_FILE holds raw markdown, free of ANSI escapes"
else
    fail "\$Q_LOG_FILE is empty or contains ANSI escapes"
fi

# --- An unknown renderer is rejected, not silently ignored -------------------
bash -c "source $WORK/preamble.sh; Q_RENDER=bogus q 'x'" >/dev/null 2>&1
if [ $? -eq 2 ]; then
    pass "unknown \$Q_RENDER exits 2"
else
    fail "unknown \$Q_RENDER did not exit 2"
fi

# --- raw keeps the streaming contract ---------------------------------------
raw="$(run_tty "Q_RENDER=raw q 'x'")"
if printf '%s' "$raw" | grep -q '\*\*Panes\*\*'; then
    pass "raw path leaves markdown markers visible (streaming, highlight-only)"
else
    fail "raw path did not emit the markdown source"
fi

# --- THE REGRESSION: pretty must not show markdown markers ------------------
if command -v glow &>/dev/null; then
    pretty="$(run_tty "Q_RENDER=pretty q 'x'")"
    if printf '%s' "$pretty" | grep -q 'Panes'; then
        pass "pretty path renders the answer"
    else
        fail "pretty path produced no answer text"
    fi
    if printf '%s' "$pretty" | grep -q '\*\*'; then
        fail "pretty path still shows literal '**' markers (regression)"
    else
        pass "pretty path shows no literal '**' markers"
    fi
    # glow execs $PAGER itself and prints nothing when it is missing, so a
    # machine without the pager must still see the answer (unpaged).
    nopager="$(run_tty "Q_PAGER='q-test-missing-pager -R' Q_RENDER=pretty q 'x'")"
    if printf '%s' "$nopager" | grep -q 'Panes'; then
        pass "pretty path renders unpaged when \$Q_PAGER is not installed"
    else
        fail "pretty path produced nothing when \$Q_PAGER is not installed"
    fi
else
    skip "glow not installed — pretty-path rendering not exercised"
    # The fallback still has to work, or a glow-less machine loses `q` entirely.
    fb="$(run_tty "Q_RENDER=pretty q 'x'")"
    if printf '%s' "$fb" | grep -q 'Panes'; then
        pass "pretty path falls back to bat/cat when glow is absent"
    else
        fail "pretty path produced nothing without glow"
    fi
fi

echo ""
echo -e "${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}  ${YELLOW}Skipped: $SKIP${NC}"
[ "$FAIL" -eq 0 ]
