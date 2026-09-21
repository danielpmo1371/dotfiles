#!/usr/bin/env bash
#
# Tests for cres's transcript fallback (config/shell/aliases.sh).
#
# Why this exists: claude prints its `claude --resume <id>` hint on every exit
# path, but at shutdown systemd stops each pane's tmux-spawn-*.scope with
# KillMode=control-group, which signals the pane's SHELL too. The shell exits,
# tmux stops rendering, and the hint never lands in the pane. A running claude
# is also in alt-screen (no scrollback), so tmux-continuum's periodic save never
# captures one either. After an unplanned reboot the scrollback is therefore
# empty and the fallback is the only way back to the session.
#
# Hermetic: fakes HOME, never reads the real ~/.claude, never runs claude.
# Runs the suite under bash AND zsh, because aliases.sh is sourced by both.

set -uo pipefail

ALIASES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/shell/aliases.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL $1"; echo "       expected: $2"; echo "       actual:   $3"; FAIL=$((FAIL + 1)); }
check() {
    local label="$1" expected="$2" actual="$3"
    [[ "$actual" == "$expected" ]] && ok "$label" || bad "$label" "$expected" "$actual"
}

# Run a snippet in a clean shell with aliases.sh sourced and a faked HOME.
#
# cres calls `cdang`, which is an ALIAS, and aliases expand when the function
# body is parsed -- so restubbing cdang after sourcing has no effect. Stub
# `claude` instead: it is resolved at call time, so a function shadows whatever
# the alias expanded to. bash also needs expand_aliases, off by default in a
# non-interactive shell, to expand cdang inside cres at all.
run_in() {
    local shell="$1" home="$2" workdir="$3" snippet="$4"
    HOME="$home" "$shell" -c "
        [ -n \"\${BASH_VERSION:-}\" ] && shopt -s expand_aliases
        source '$ALIASES' >/dev/null 2>&1
        claude() { for a; do :; done; echo \"RESUME:\$a\"; }
        cd '$workdir' || exit 1
        $snippet
    " 2>&1
}

for SHELL_BIN in bash zsh; do
    command -v "$SHELL_BIN" >/dev/null || { echo "=== $SHELL_BIN not installed, skipping ==="; continue; }
    echo "=== $SHELL_BIN ==="

    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    FAKE_HOME="$TMP/home"
    WORK="$TMP/work/project"
    mkdir -p "$FAKE_HOME" "$WORK"

    # Claude's layout: ~/.claude/projects/<cwd with / turned into ->/<id>.jsonl
    SLUG="${WORK//\//-}"
    PROJ="$FAKE_HOME/.claude/projects/$SLUG"
    mkdir -p "$PROJ"

    OLD_ID="11111111-1111-1111-1111-111111111111"
    NEW_ID="22222222-2222-2222-2222-222222222222"
    echo '{}' > "$PROJ/$OLD_ID.jsonl"
    sleep 1.1   # mtime granularity: make "newest" unambiguous
    echo '{}' > "$PROJ/$NEW_ID.jsonl"

    check "lookup returns the newest session id" \
        "$NEW_ID" \
        "$(run_in "$SHELL_BIN" "$FAKE_HOME" "$WORK" '_cres_session_from_transcripts')"

    check "cres falls back when not in tmux and no hint exists" \
        "RESUME:$NEW_ID" \
        "$(run_in "$SHELL_BIN" "$FAKE_HOME" "$WORK" 'unset TMUX; cres' | grep '^RESUME:')"

    check "fallback announces itself on stderr" \
        "yes" \
        "$(run_in "$SHELL_BIN" "$FAKE_HOME" "$WORK" 'unset TMUX; cres' \
            | grep -q 'no hint in scrollback' && echo yes || echo no)"

    # A directory claude has never run in has no project dir at all.
    EMPTY="$TMP/work/untouched"
    mkdir -p "$EMPTY"
    check "lookup fails for a directory with no recorded sessions" \
        "1" \
        "$(run_in "$SHELL_BIN" "$FAKE_HOME" "$EMPTY" '_cres_session_from_transcripts >/dev/null; echo $?')"

    check "cres errors, does not resume, when nothing is recorded" \
        "" \
        "$(run_in "$SHELL_BIN" "$FAKE_HOME" "$EMPTY" 'unset TMUX; cres' | grep '^RESUME:')"

    # An existing but empty project dir must not yield an empty session id.
    EMPTYPROJ="$TMP/work/emptyproj"
    mkdir -p "$EMPTYPROJ" "$FAKE_HOME/.claude/projects/${EMPTYPROJ//\//-}"
    check "lookup fails for an existing but empty project dir" \
        "1" \
        "$(run_in "$SHELL_BIN" "$FAKE_HOME" "$EMPTYPROJ" '_cres_session_from_transcripts >/dev/null; echo $?')"

    # Precedence: a hint in THIS pane's scrollback names the session that ran
    # here, which beats the directory-newest fallback. Losing this would
    # silently resume a sibling pane's session.
    if command -v tmux >/dev/null; then
        SOCKET="crestest-$$-$SHELL_BIN"
        PANE_ID="99999999-9999-9999-9999-999999999999"
        HINT_SCRIPT="$TMP/hint-$SHELL_BIN.sh"
        OUT="$TMP/cres-out-$SHELL_BIN.txt"

        cat > "$HINT_SCRIPT" <<EOF
[ -n "\${BASH_VERSION:-}" ] && shopt -s expand_aliases
source '$ALIASES' >/dev/null 2>&1
claude() { for a; do :; done; echo "RESUME:\$a"; }
cd '$WORK' || exit 1
echo 'claude --resume $PANE_ID'
cres > '$OUT' 2>&1
EOF

        HOME="$FAKE_HOME" tmux -L "$SOCKET" new-session -d -x 80 -y 24 \
            "$SHELL_BIN '$HINT_SCRIPT'" >/dev/null 2>&1
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            [[ -s "$OUT" ]] && break
            sleep 0.3
        done
        tmux -L "$SOCKET" kill-server >/dev/null 2>&1

        check "scrollback hint wins over the transcript fallback" \
            "RESUME:$PANE_ID" \
            "$(grep '^RESUME:' "$OUT" 2>/dev/null)"

        check "no fallback notice when a hint was found" \
            "no" \
            "$(grep -q 'no hint in scrollback' "$OUT" 2>/dev/null && echo yes || echo no)"
    else
        echo "  SKIP tmux not installed — scrollback precedence untested"
    fi

    rm -rf "$TMP"
    trap - EXIT
done

echo
echo "=== Summary ==="
echo "  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
