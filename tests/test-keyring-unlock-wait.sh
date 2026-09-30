#!/usr/bin/env bash
#
# Tests for util-scripts/keyring-unlock-wait (unlock the keyring before a
# login service exports secrets).
#
# Pins: unlocked items and a service with no items exit 0 without prompting;
# locked items with no way to show the dialog give up after
# KEYRING_UNLOCK_TIMEOUT (exit 1) instead of hanging, the failure that hung
# boot-time shells; an invalid timeout falls back to the default with a
# warning; no Secret Service exits 2.
#
# Hermetic: a private D-Bus session (dbus-run-session) with its own
# gnome-keyring-daemon, keyring files in a temp dir, and no DISPLAY or
# WAYLAND_DISPLAY, so no dialog can reach the real desktop.

set -uo pipefail

HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/util-scripts/keyring-unlock-wait"
readonly TEST_SERVICE="keyring-unlock-wait-test"
readonly KEYRING_PASSWORD="test-password"
readonly LOCKED_TIMEOUT=2
# Upper bound for the locked case: the timeout plus startup slack.
readonly LOCKED_MAX_SECONDS=$((LOCKED_TIMEOUT + 8))

for cmd in dbus-run-session gnome-keyring-daemon secret-tool busctl python3; do
    if ! command -v "$cmd" >/dev/null; then
        echo "SKIP: $cmd not installed"
        exit 0
    fi
done

# Re-run inside a private bus, with the display variables removed.
if [[ -z "${KEYRING_TEST_INNER:-}" ]]; then
    ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-keyring-unlock-wait.XXXXXX")
    trap 'rm -rf "$ROOT"' EXIT
    mkdir -p "$ROOT/data" "$ROOT/run"
    chmod 700 "$ROOT/run"
    env -u DISPLAY -u WAYLAND_DISPLAY KEYRING_TEST_INNER=1 HOME="$ROOT" \
        XDG_DATA_HOME="$ROOT/data" XDG_RUNTIME_DIR="$ROOT/run" \
        dbus-run-session -- "${BASH_SOURCE[0]}"
    exit $?
fi

PASS=0
FAIL=0

ok()  { echo "  PASS $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $1"; echo "       expected: $2"; echo "       actual:   $3"; FAIL=$((FAIL + 1)); }
check() {
    local label="$1" expected="$2" actual="$3"
    [[ "$actual" == "$expected" ]] && ok "$label" || bad "$label" "$expected" "$actual"
}
contains() {
    local label="$1" needle="$2" haystack="$3"
    [[ "$haystack" == *"$needle"* ]] && ok "$label" || bad "$label" "*$needle*" "$haystack"
}

# --unlock creates the "login" keyring with this password and unlocks it.
printf '%s' "$KEYRING_PASSWORD" | gnome-keyring-daemon --unlock --components=secrets >/dev/null
printf 'value' | secret-tool store --label=test service "$TEST_SERVICE" key K

echo "unlocked"
out=$("$HELPER" "$TEST_SERVICE" 2>&1); rc=$?
check    "exit 0"          "0" "$rc"
contains "reports items"   "1 '$TEST_SERVICE' items unlocked" "$out"

echo "no items"
"$HELPER" "$TEST_SERVICE-none" >/dev/null 2>&1; check "exit 0" "0" "$?"

echo "invalid timeout"
out=$(KEYRING_UNLOCK_TIMEOUT=soon "$HELPER" "$TEST_SERVICE" 2>&1); rc=$?
check    "exit 0"          "0" "$rc"
contains "warns"           "invalid KEYRING_UNLOCK_TIMEOUT 'soon'" "$out"

lock_keyring() {
    # Lock never prompts.
    busctl --user call org.freedesktop.secrets /org/freedesktop/secrets \
        org.freedesktop.Secret.Service Lock ao 1 /org/freedesktop/secrets/collection/login >/dev/null
}

# Runs the helper against the locked keyring; sets rc, out, elapsed.
run_locked() {
    local start=$SECONDS
    out=$(KEYRING_UNLOCK_TIMEOUT=$LOCKED_TIMEOUT timeout "$LOCKED_MAX_SECONDS" "$HELPER" "$TEST_SERVICE" 2>&1); rc=$?
    elapsed=$((SECONDS - start))
}

echo "locked, prompter cannot open a display (the boot-time case)"
lock_keyring
run_locked
check    "exit 1, not a hang (timeout(1) would give 124)" "1" "$rc"
contains "reports still locked" "still locked" "$out"

echo "locked, prompter never answers"
# A prompter that starts but never claims its bus name: only the helper's own
# timeout can end the wait. XDG_DATA_HOME service files take precedence.
mkdir -p "$XDG_DATA_HOME/dbus-1/services"
printf '#!/bin/sh\nexec sleep %s\n' "$LOCKED_MAX_SECONDS" >"$HOME/silent-prompter"
chmod +x "$HOME/silent-prompter"
printf '[D-BUS Service]\nName=org.gnome.keyring.SystemPrompter\nExec=%s\n' "$HOME/silent-prompter" \
    >"$XDG_DATA_HOME/dbus-1/services/org.gnome.keyring.SystemPrompter.service"
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null
run_locked
check    "exit 1 (timeout(1) would give 124)" "1" "$rc"
contains "reports the timeout" "no unlock within ${LOCKED_TIMEOUT}s" "$out"
[[ $elapsed -ge $LOCKED_TIMEOUT ]] && ok "waited the timeout (${elapsed}s)" \
    || bad "waited the timeout" ">= ${LOCKED_TIMEOUT}s" "${elapsed}s"

echo "no Secret Service"
DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/no-such-bus" "$HELPER" >/dev/null 2>&1
check "exit 2" "2" "$?"

echo
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
