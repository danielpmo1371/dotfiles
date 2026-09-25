#!/usr/bin/env bash
#
# Tests for the rm() trash override (config/shell/aliases.sh).
#
# Why this exists: rm() is a safety net that moves files to the trash instead
# of deleting them. It dispatches to trash-put (trash-cli), then to trash
# (macOS 14+), then falls back to a plain mv into the platform trash dir. A bug
# here either deletes for real or loses files on a name collision, so every
# path is pinned: option stripping, each dispatch target's exact argv, the
# fallback destination per OS, and collision handling.
#
# Hermetic: fakes HOME and PATH. PATH holds only a stub dir (controls which of
# trash-put / trash exist, stubs log their argv and touch nothing) plus a dir of
# symlinks to the real mkdir/mv/date, so the host's /usr/bin/trash can never be
# picked up. Every snippet asserts what `command -v` resolves to before
# calling rm. Runs under bash AND zsh, because aliases.sh is sourced by both.
#
# OSTYPE is a shell-set variable. Both bash and zsh let a script reassign it,
# so the darwin and linux fallback paths are forced explicitly rather than
# relying on the host OS. If a shell ever refuses the assignment, the cases
# that need the non-native value are reported as SKIP with the reason.

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

# Real binaries the function and the snippets need, captured BEFORE PATH is
# restricted. Only these are reachable from inside a test shell.
SYSBIN_CMDS=(mkdir mv date ls cat touch)

# Set up an isolated case dir: home/, work/, bin/ (stubs), sysbin/ (symlinks).
# Args: case_dir stub...   (stubs: any of trash-put, trash)
setup_case() {
    local dir="$1"; shift
    mkdir -p "$dir/home" "$dir/work" "$dir/bin" "$dir/sysbin"
    local c
    for c in "${SYSBIN_CMDS[@]}"; do
        ln -s "$(command -v "$c")" "$dir/sysbin/$c"
    done
    local stub
    for stub in "$@"; do
        cat > "$dir/bin/$stub" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > '$dir/$stub.argv'
exit 0
EOF
        chmod +x "$dir/bin/$stub"
    done
}

# Run a snippet in a clean shell with aliases.sh sourced, HOME/PATH faked and
# OSTYPE forced. cwd is the case's work/ dir.
# Args: shell case_dir ostype snippet
run_in() {
    local shell="$1" dir="$2" ostype="$3" snippet="$4"
    # The restricted PATH hides the shell too, so resolve it here first.
    shell="$(command -v "$shell")"
    HOME="$dir/home" PATH="$dir/bin:$dir/sysbin" "$shell" -c "
        [ -n \"\${BASH_VERSION:-}\" ] && shopt -s expand_aliases
        source '$ALIASES' >/dev/null 2>&1
        OSTYPE='$ostype'
        cd '$dir/work' || exit 1
        $snippet
    " 2>&1
}

# Guard prelude: prove exactly which trash commands are visible to the shell.
# Prints "PUT=<path> TRASH=<path>" so a test can pin the dispatch precondition.
SEEN='echo "PUT=$(command -v trash-put) TRASH=$(command -v trash)"'

for SHELL_BIN in bash zsh; do
    command -v "$SHELL_BIN" >/dev/null || { echo "=== $SHELL_BIN not installed, skipping ==="; continue; }
    echo "=== $SHELL_BIN ==="

    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    NATIVE_OSTYPE="$("$SHELL_BIN" -c 'echo "$OSTYPE"')"
    CAN_SET_OSTYPE=no
    "$SHELL_BIN" -c 'OSTYPE=linux-gnu; [ "$OSTYPE" = linux-gnu ]' 2>/dev/null && CAN_SET_OSTYPE=yes

    # Returns 0 when the given OSTYPE can be used in this shell, else prints SKIP.
    ostype_usable() {
        local want="$1" label="$2"
        [[ "$CAN_SET_OSTYPE" == yes || "$NATIVE_OSTYPE" == $want ]] && return 0
        echo "  SKIP $label — $SHELL_BIN refuses to reassign OSTYPE and host is $NATIVE_OSTYPE"
        return 1
    }

    # ── 1. trash-put present → `trash-put -- files`, file untouched ──────────
    D="$TMP/put"; setup_case "$D" trash-put trash
    touch "$D/work/a.txt" "$D/work/b.txt"
    OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "$SEEN; rm -rf a.txt b.txt; echo rc=\$?")"
    check "1 trash-put visible and preferred over trash" \
        "PUT=$D/bin/trash-put TRASH=$D/bin/trash" "$(echo "$OUT" | grep '^PUT=')"
    check "1 trash-put called with -- then the files" \
        $'--\na.txt\nb.txt' "$(cat "$D/trash-put.argv" 2>/dev/null)"
    check "1 trash stub not called when trash-put exists" \
        "absent" "$([[ -e "$D/trash.argv" ]] && echo called || echo absent)"
    check "1 files untouched by mv (stub owns the move)" \
        "both" "$([[ -e "$D/work/a.txt" && -e "$D/work/b.txt" ]] && echo both || echo missing)"
    check "1 returns the stub's exit status" "rc=0" "$(echo "$OUT" | grep '^rc=')"

    # ── 2. trash only → `trash files`; "-weird" passed as "./-weird" ─────────
    D="$TMP/trash"; setup_case "$D" trash
    touch "$D/work/a.txt"
    OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "$SEEN; rm a.txt; echo rc=\$?")"
    check "2 only trash visible" \
        "PUT= TRASH=$D/bin/trash" "$(echo "$OUT" | grep '^PUT=')"
    check "2 trash called with plain files, no --" \
        $'a.txt' "$(cat "$D/trash.argv" 2>/dev/null)"
    # Options are recognised anywhere (GNU rm accepts `rm file -v`), so a
    # dash-leading operand only survives after --, and macOS trash gets it
    # prefixed with ./ because it does not understand -- itself.
    D="$TMP/trash-dash"; setup_case "$D" trash
    touch "$D/work/a.txt" "$D/work/-weird"
    run_in "$SHELL_BIN" "$D" darwin22 "rm a.txt -- -weird" >/dev/null
    check "2 dash-leading operand after -- passed as ./-weird" \
        $'a.txt\n./-weird' "$(cat "$D/trash.argv" 2>/dev/null)"

    # ── 3. no trash cmd, darwin → mv into ~/.Trash ──────────────────────────
    if ostype_usable 'darwin*' "3 darwin fallback"; then
        D="$TMP/darwin"; setup_case "$D"
        touch "$D/work/a.txt"
        OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "$SEEN; rm a.txt; echo rc=\$?")"
        check "3 neither trash command visible" "PUT= TRASH=" "$(echo "$OUT" | grep '^PUT=')"
        check "3 file landed in ~/.Trash" "yes" "$([[ -f "$D/home/.Trash/a.txt" ]] && echo yes || echo no)"
        check "3 file gone from source" "yes" "$([[ ! -e "$D/work/a.txt" ]] && echo yes || echo no)"
        check "3 returns 0" "rc=0" "$(echo "$OUT" | grep '^rc=')"
    fi

    # ── 4. no trash cmd, linux → XDG trash; XDG_DATA_HOME honoured ──────────
    if ostype_usable 'linux*' "4 linux fallback"; then
        D="$TMP/linux"; setup_case "$D"
        touch "$D/work/a.txt"
        OUT="$(run_in "$SHELL_BIN" "$D" linux-gnu "unset XDG_DATA_HOME; $SEEN; rm a.txt; echo rc=\$?")"
        check "4 neither trash command visible" "PUT= TRASH=" "$(echo "$OUT" | grep '^PUT=')"
        check "4 file landed in ~/.local/share/Trash/files" "yes" \
            "$([[ -f "$D/home/.local/share/Trash/files/a.txt" ]] && echo yes || echo no)"
        check "4 nothing in ~/.Trash on linux" "yes" "$([[ ! -e "$D/home/.Trash" ]] && echo yes || echo no)"

        D="$TMP/linux-xdg"; setup_case "$D"
        touch "$D/work/a.txt"
        run_in "$SHELL_BIN" "$D" linux-gnu "export XDG_DATA_HOME='$D/xdg'; rm a.txt" >/dev/null
        check "4 XDG_DATA_HOME honoured" "yes" \
            "$([[ -f "$D/xdg/Trash/files/a.txt" ]] && echo yes || echo no)"
        check "4 default XDG dir untouched when overridden" "yes" \
            "$([[ ! -e "$D/home/.local/share/Trash" ]] && echo yes || echo no)"
    fi

    # ── 5. fallback collision: same basename twice → suffixed, nothing lost ─
    if ostype_usable 'darwin*' "5 collision"; then
        D="$TMP/collide"; setup_case "$D"
        mkdir -p "$D/work/one" "$D/work/two"
        echo first  > "$D/work/one/same.txt"
        echo second > "$D/work/two/same.txt"
        run_in "$SHELL_BIN" "$D" darwin22 "rm one/same.txt; rm two/same.txt" >/dev/null
        check "5 first copy kept under its own name" "first" "$(cat "$D/home/.Trash/same.txt" 2>/dev/null)"
        SUFFIXED="$(ls "$D/home/.Trash" | grep -E '^same\.txt\.[0-9]+$')"
        check "5 second copy got an epoch suffix" "1" "$(echo "$SUFFIXED" | grep -c .)"
        check "5 second copy content intact" "second" "$(cat "$D/home/.Trash/$SUFFIXED" 2>/dev/null)"
        check "5 both sources gone" "yes" \
            "$([[ ! -e "$D/work/one/same.txt" && ! -e "$D/work/two/same.txt" ]] && echo yes || echo no)"

        # Same-second triple collision must fall through to the counter.
        D="$TMP/collide3"; setup_case "$D"
        mkdir -p "$D/work/one" "$D/work/two" "$D/work/three"
        echo 1 > "$D/work/one/x"; echo 2 > "$D/work/two/x"; echo 3 > "$D/work/three/x"
        run_in "$SHELL_BIN" "$D" darwin22 "rm one/x; rm two/x; rm three/x" >/dev/null
        check "5 three collisions → three distinct entries" "3" "$(ls "$D/home/.Trash" | grep -c '^x')"
        check "5 all contents preserved" $'1\n2\n3' "$(cat "$D"/home/.Trash/x* | sort)"
    fi

    # ── 6. rm -rf dir → directory moved; flags never reach mv ───────────────
    if ostype_usable 'darwin*' "6 rm -rf dir fallback"; then
        D="$TMP/rfdir"; setup_case "$D"
        mkdir -p "$D/work/proj/sub"; touch "$D/work/proj/sub/f"
        OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "rm -rf proj; echo rc=\$?")"
        check "6 directory moved to trash with contents" "yes" \
            "$([[ -f "$D/home/.Trash/proj/sub/f" ]] && echo yes || echo no)"
        check "6 no entry named -rf created in trash" "yes" "$([[ ! -e "$D/home/.Trash/-rf" ]] && echo yes || echo no)"
        check "6 returns 0" "rc=0" "$(echo "$OUT" | grep '^rc=')"
        # Trailing slash (tab-completion form) must not yield an empty name.
        D="$TMP/rfdir-slash"; setup_case "$D"
        mkdir -p "$D/work/proj"; touch "$D/work/proj/f"
        run_in "$SHELL_BIN" "$D" darwin22 "rm -rf proj/" >/dev/null
        check "6 trailing slash handled" "yes" "$([[ -f "$D/home/.Trash/proj/f" ]] && echo yes || echo no)"
    fi
    D="$TMP/rfdir-stub"; setup_case "$D" trash-put
    mkdir -p "$D/work/proj"
    run_in "$SHELL_BIN" "$D" darwin22 "rm -rf proj" >/dev/null
    check "6 flags stripped before trash-put" $'--\nproj' "$(cat "$D/trash-put.argv" 2>/dev/null)"
    D="$TMP/flags-stub"; setup_case "$D" trash-put
    touch "$D/work/a"
    run_in "$SHELL_BIN" "$D" darwin22 "rm -r -f -i -v --force --recursive -rfv a" >/dev/null
    check "6 every leading option form stripped" $'--\na' "$(cat "$D/trash-put.argv" 2>/dev/null)"
    D="$TMP/trailing-opt"; setup_case "$D" trash-put
    touch "$D/work/a.txt"
    run_in "$SHELL_BIN" "$D" darwin22 "rm a.txt -v" >/dev/null
    check "6 option after the operand is stripped (rm a.txt -v)" $'--\na.txt' "$(cat "$D/trash-put.argv" 2>/dev/null)"
    D="$TMP/trailing-dashdash"; setup_case "$D" trash-put
    touch "$D/work/a.txt" "$D/work/-v"
    run_in "$SHELL_BIN" "$D" darwin22 "rm a.txt -- -v" >/dev/null
    check "6 everything after -- is an operand (rm a.txt -- -v)" $'--\na.txt\n-v' "$(cat "$D/trash-put.argv" 2>/dev/null)"
    D="$TMP/lone-dash"; setup_case "$D" trash-put
    touch "$D/work/-"
    run_in "$SHELL_BIN" "$D" darwin22 "rm -" >/dev/null
    check "6 a lone - is an operand" $'--\n-' "$(cat "$D/trash-put.argv" 2>/dev/null)"

    # ── 7. `rm -- -weird` → "--" dropped, file handled ──────────────────────
    D="$TMP/dashdash-put"; setup_case "$D" trash-put
    touch "$D/work/-weird"
    run_in "$SHELL_BIN" "$D" darwin22 "rm -- -weird" >/dev/null
    check "7 -- dropped, trash-put gets its own --" $'--\n-weird' "$(cat "$D/trash-put.argv" 2>/dev/null)"
    D="$TMP/dashdash-trash"; setup_case "$D" trash
    touch "$D/work/-weird"
    run_in "$SHELL_BIN" "$D" darwin22 "rm -- -weird" >/dev/null
    check "7 -- dropped, trash gets ./-weird" "./-weird" "$(cat "$D/trash.argv" 2>/dev/null)"
    if ostype_usable 'darwin*' "7 -- fallback"; then
        D="$TMP/dashdash-fb"; setup_case "$D"
        touch "$D/work/-weird"
        run_in "$SHELL_BIN" "$D" darwin22 "rm -- -weird" >/dev/null
        check "7 -- dropped, fallback moves -weird" "yes" "$([[ -f "$D/home/.Trash/-weird" ]] && echo yes || echo no)"
    fi

    # ── 8. no args → "missing operand" on stderr, return 1 ──────────────────
    D="$TMP/noargs"; setup_case "$D" trash-put
    OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "rm 2>err.txt; echo rc=\$?; cat err.txt")"
    check "8 no args returns 1" "rc=1" "$(echo "$OUT" | grep '^rc=')"
    check "8 error on stderr" "rm: missing operand" "$(echo "$OUT" | grep 'missing operand')"
    check "8 trash-put not invoked" "absent" "$([[ -e "$D/trash-put.argv" ]] && echo called || echo absent)"

    # ── 9. rm -rf with no files → same error ────────────────────────────────
    D="$TMP/rfnoargs"; setup_case "$D" trash-put
    OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "rm -rf 2>err.txt; echo rc=\$?; cat err.txt")"
    check "9 rm -rf alone returns 1" "rc=1" "$(echo "$OUT" | grep '^rc=')"
    check "9 error on stderr carries the -- hint" \
        "rm: missing operand (names starting with '-' need '--' before them)" \
        "$(echo "$OUT" | grep 'missing operand')"
    check "9 trash-put not invoked" "absent" "$([[ -e "$D/trash-put.argv" ]] && echo called || echo absent)"
    OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "rm -- 2>err.txt; echo rc=\$?; cat err.txt")"
    check "9 rm -- alone returns 1" "rc=1" "$(echo "$OUT" | grep '^rc=')"
    check "9 rm -- alone gets the plain message" "rm: missing operand" "$(echo "$OUT" | grep 'missing operand')"
    # A dash-leading filename with no -- looks like an option; the hint must
    # tell the user how to get it through, and the stub must not be called.
    D="$TMP/dashfile"; setup_case "$D" trash-put
    touch "$D/work/-weird-file.txt"
    OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "rm -weird-file.txt 2>err.txt; echo rc=\$?; cat err.txt")"
    check "9 rm -weird-file.txt returns 1" "rc=1" "$(echo "$OUT" | grep '^rc=')"
    check "9 rm -weird-file.txt prints the -- hint" \
        "rm: missing operand (names starting with '-' need '--' before them)" \
        "$(echo "$OUT" | grep 'missing operand')"
    check "9 rm -weird-file.txt does not reach trash-put" "absent" \
        "$([[ -e "$D/trash-put.argv" ]] && echo called || echo absent)"
    check "9 rm -weird-file.txt leaves the file alone" "yes" "$([[ -f "$D/work/-weird-file.txt" ]] && echo yes || echo no)"

    # ── 10. multiple files in one call all handled ──────────────────────────
    D="$TMP/multi-put"; setup_case "$D" trash-put
    touch "$D/work/a" "$D/work/b" "$D/work/c d"
    run_in "$SHELL_BIN" "$D" darwin22 "rm -v a b 'c d'" >/dev/null
    check "10 all files (incl. one with a space) reach trash-put" $'--\na\nb\nc d' "$(cat "$D/trash-put.argv" 2>/dev/null)"
    if ostype_usable 'darwin*' "10 multi fallback"; then
        D="$TMP/multi-fb"; setup_case "$D"
        touch "$D/work/a" "$D/work/b" "$D/work/c d"
        OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "rm a b 'c d'; echo rc=\$?")"
        check "10 fallback moved all three" "yes" \
            "$([[ -f "$D/home/.Trash/a" && -f "$D/home/.Trash/b" && -f "$D/home/.Trash/c d" ]] && echo yes || echo no)"
        check "10 returns 0" "rc=0" "$(echo "$OUT" | grep '^rc=')"
        # A missing operand in the middle is reported, the rest still moves.
        D="$TMP/multi-partial"; setup_case "$D"
        touch "$D/work/a" "$D/work/c"
        OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "rm a nope c; echo rc=\$?")"
        check "10 partial failure returns non-zero" "rc=1" "$(echo "$OUT" | grep '^rc=')"
        check "10 partial failure reported" "yes" "$(echo "$OUT" | grep -q "cannot move 'nope'" && echo yes || echo no)"
        check "10 remaining files still moved" "yes" \
            "$([[ -f "$D/home/.Trash/a" && -f "$D/home/.Trash/c" ]] && echo yes || echo no)"
    fi

    # ── 11. symlinks: the link itself moves, its target is never touched ────
    D="$TMP/symlink-stub"; setup_case "$D" trash-put
    echo keep > "$D/work/real.txt"; ln -s real.txt "$D/work/link"
    run_in "$SHELL_BIN" "$D" darwin22 "rm link" >/dev/null
    check "11 link name passed unchanged to trash-put" $'--\nlink' "$(cat "$D/trash-put.argv" 2>/dev/null)"
    if ostype_usable 'darwin*' "11 symlink fallback"; then
        D="$TMP/symlink-file"; setup_case "$D"
        echo keep > "$D/work/real.txt"; ln -s real.txt "$D/work/link"
        OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "rm link; echo rc=\$?")"
        check "11 symlink-to-file: moved entry is still a symlink" "yes" \
            "$([[ -L "$D/home/.Trash/link" ]] && echo yes || echo no)"
        check "11 symlink-to-file: target untouched" "keep" "$(cat "$D/work/real.txt" 2>/dev/null)"
        check "11 symlink-to-file: link gone from source" "yes" "$([[ ! -L "$D/work/link" ]] && echo yes || echo no)"
        check "11 symlink-to-file: returns 0" "rc=0" "$(echo "$OUT" | grep '^rc=')"

        D="$TMP/symlink-dir"; setup_case "$D"
        mkdir -p "$D/work/realdir"; echo keep > "$D/work/realdir/f"; ln -s realdir "$D/work/linkdir"
        OUT="$(run_in "$SHELL_BIN" "$D" darwin22 "rm -rf linkdir; echo rc=\$?")"
        check "11 symlink-to-dir: moved entry is still a symlink" "yes" \
            "$([[ -L "$D/home/.Trash/linkdir" ]] && echo yes || echo no)"
        check "11 symlink-to-dir: target dir and contents untouched" "keep" "$(cat "$D/work/realdir/f" 2>/dev/null)"
        check "11 symlink-to-dir: link gone from source" "yes" "$([[ ! -L "$D/work/linkdir" ]] && echo yes || echo no)"
        check "11 symlink-to-dir: returns 0" "rc=0" "$(echo "$OUT" | grep '^rc=')"

        # A dangling link is still an entry worth trashing, and the collision
        # check must see it via -L even though -e is false.
        D="$TMP/symlink-dangling"; setup_case "$D"
        mkdir -p "$D/home/.Trash"; ln -s nowhere "$D/home/.Trash/ghost"
        ln -s nowhere "$D/work/ghost"
        run_in "$SHELL_BIN" "$D" darwin22 "rm ghost" >/dev/null
        check "11 dangling link collides with an existing dangling link" "2" \
            "$(ls "$D/home/.Trash" | grep -c '^ghost')"
    fi

    rm -rf "$TMP"
    trap - EXIT
done

echo
echo "=== Summary ==="
echo "  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
