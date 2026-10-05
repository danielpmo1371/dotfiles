#!/usr/bin/env bash
#
# Tests for util-scripts/mem-pressure-watch and installers/memwatch.sh.
#
# Pins: a snapshot lists PSI, memory, swap and the top processes by RSS (with
# cmdline, cwd and cgroup leaf; kernel threads skipped); pressure above the
# trigger is logged; notifications fire only above the notify threshold and
# respect their cooldown; a missing notifier never stops logging; without PSI
# trigger support it falls back to polling; the units carry the oomd
# preferences; the installer copies the oomd drop-in and enables systemd-oomd.
#
# Hermetic: /proc and the PSI file are fakes under a temp dir, notify-send,
# ntfy-send, sudo and systemctl are stubs that record their argv.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$REPO/util-scripts/mem-pressure-watch"

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
lacks() {
    local label="$1" needle="$2" haystack="$3"
    [[ "$haystack" != *"$needle"* ]] && ok "$label" || bad "$label" "no '$needle'" "$haystack"
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-mem-pressure-watch.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
PROC="$ROOT/proc"
STUB="$ROOT/bin"
mkdir -p "$PROC" "$STUB"

cat > "$PROC/meminfo" <<'EOF'
MemTotal:       32505856 kB
MemFree:          524288 kB
MemAvailable:    1048576 kB
SwapTotal:       4194304 kB
SwapFree:         209715 kB
EOF

# fake_proc PID RSS_KB CMDLINE CWD CGROUP_PATH  (RSS 0 = kernel thread)
fake_proc() {
    local d="$PROC/$1"
    mkdir -p "$d"
    if [[ "$2" -gt 0 ]]; then
        printf 'Name:\tx\nVmRSS:\t%s kB\n' "$2" > "$d/status"
    else
        printf 'Name:\tkworker\n' > "$d/status"
    fi
    printf '%s' "$3" | tr ' ' '\0' > "$d/cmdline"
    echo "${3%% *}" > "$d/comm"
    ln -s "$4" "$d/cwd"
    echo "0::$5" > "$d/cgroup"
}
fake_proc 100 17301504 "/usr/bin/dotnet exec UnitTests.dll" /work/td-api /user.slice/app.slice/tmux-spawn-abc.scope
fake_proc 200 524288 "brave --type=renderer" /home /user.slice/session-4.scope
fake_proc 300 0 "" / /
fake_proc 400 102400 "zsh" /home /user.slice/app.slice/tmux-spawn-def.scope

set_psi() {
    printf 'some avg10=%s avg60=1.00 avg300=1.00 total=1\nfull avg10=%s avg60=0.50 avg300=0.50 total=1\n' "$1" "$2" > "$ROOT/psi"
}

for cmd in notify-send ntfy-send; do
    cat > "$STUB/$cmd" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$ROOT/$cmd.log"
EOF
    chmod +x "$STUB/$cmd"
done

run_watch() {
    PATH="$STUB:$PATH" MEMWATCH_PROC="$PROC" MEMWATCH_PSI_FILE="$ROOT/psi" \
        MEMWATCH_STATE_DIR="$ROOT/state" MEMWATCH_INTERVAL=0 timeout 10 "$WATCH" "$@"
}
reset_logs() { rm -f "$ROOT/notify-send.log" "$ROOT/ntfy-send.log" "$ROOT/state/events.log"; }

echo "snapshot (--once)"
set_psi 42.50 30.25
out=$(run_watch --once)
first=$(head -1 <<<"$out")
contains "PSI averages" "some=42.5% full=30.2% (avg10)" "$first"
contains "available memory" "available=1.0G/31.0G" "$first"
contains "swap used" "swap=3.8G/4.0G" "$first"
check "biggest process first" "16.5G pid 100 /usr/bin/dotnet exec UnitTests.dll [cwd /work/td-api] [tmux-spawn-abc.scope]" "$(sed -n 2p <<<"$out" | sed 's/^ *//')"
contains "second process" "pid 200 brave --type=renderer" "$(sed -n 3p <<<"$out")"
lacks "kernel thread skipped" "pid 300" "$out"
out=$(MEMWATCH_TOP=1 run_watch --once)
check "MEMWATCH_TOP limits the list" "2" "$(wc -l <<<"$out" | tr -d ' ')"

echo "pressure above notify threshold"
reset_logs
set_psi 50.00 20.00
run_watch --poll --max-events 1 2>/dev/null
contains "event logged" "pid 100 /usr/bin/dotnet" "$(cat "$ROOT/state/events.log" 2>/dev/null)"
contains "desktop notification" "-u critical -a mem-pressure-watch Memory pressure 50% Top: dotnet 16.5G (pid 100)" "$(cat "$ROOT/notify-send.log" 2>/dev/null)"
contains "phone push" "-t Memory pressure 50% -p high -g warning Top: dotnet 16.5G (pid 100)" "$(cat "$ROOT/ntfy-send.log" 2>/dev/null)"

echo "pressure above trigger, below notify threshold"
reset_logs
set_psi 12.00 1.00
run_watch --poll --max-events 1 2>/dev/null
contains "event logged" "some=12.0%" "$(cat "$ROOT/state/events.log" 2>/dev/null)"
check "no desktop notification" "no" "$([[ -e "$ROOT/notify-send.log" ]] && echo yes || echo no)"
check "no phone push" "no" "$([[ -e "$ROOT/ntfy-send.log" ]] && echo yes || echo no)"

echo "cooldowns"
reset_logs
set_psi 60.00 40.00
MEMWATCH_LOG_INTERVAL=0 run_watch --poll --max-events 3 2>/dev/null
check "three events logged" "3" "$(grep -c 'memory pressure:' "$ROOT/state/events.log")"
check "one desktop notification" "1" "$(wc -l < "$ROOT/notify-send.log" | tr -d ' ')"
check "one phone push" "1" "$(wc -l < "$ROOT/ntfy-send.log" | tr -d ' ')"
reset_logs
MEMWATCH_LOG_INTERVAL=0 MEMWATCH_DESKTOP_COOLDOWN=0 run_watch --poll --max-events 2 2>/dev/null
check "no cooldown, one per event" "2" "$(wc -l < "$ROOT/notify-send.log" | tr -d ' ')"

echo "below trigger"
reset_logs
set_psi 5.00 1.00
run_watch --poll --max-events 1 >/dev/null 2>&1 &
pid=$!
sleep 1
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
check "nothing logged" "no" "$([[ -e "$ROOT/state/events.log" ]] && echo yes || echo no)"

echo "missing notifiers"
reset_logs
set_psi 50.00 20.00
MEMWATCH_NOTIFY_CMD=no-such-notifier MEMWATCH_PHONE_CMD="" run_watch --poll --max-events 1 2>/dev/null
check "exit 0" "0" "$?"
contains "still logged" "pid 100" "$(cat "$ROOT/state/events.log" 2>/dev/null)"

echo "fallback without trigger support"
reset_logs
err=$(run_watch --max-events 1 2>&1 >/dev/null)
contains "falls back to polling" "polling $ROOT/psi" "$err"
contains "still logged" "pid 100" "$(cat "$ROOT/state/events.log" 2>/dev/null)"

echo "units"
unit="$REPO/config/systemd-services/user/mem-pressure-watch.service"
contains "watcher omitted by oomd" "ManagedOOMPreference=omit" "$(cat "$unit")"
contains "watcher ExecStart" "ExecStart=%h/repos/dotfiles/util-scripts/mem-pressure-watch" "$(cat "$unit")"
contains "tmux server avoided by oomd" "ManagedOOMPreference=avoid" "$(cat "$REPO/config/systemd-services/user/claude-rc-sessions.service")"
dropin="$REPO/config/systemd-oomd/user@.service.d/90-mem-pressure-kill.conf"
contains "drop-in kills on pressure" "ManagedOOMMemoryPressure=kill" "$(cat "$dropin")"
contains "drop-in limit" "ManagedOOMMemoryPressureLimit=40%" "$(cat "$dropin")"
if command -v systemd-analyze >/dev/null; then
    out=$(systemd-analyze --user verify "$unit" 2>&1 | grep -v "graphical-session" || true)
    check "systemd-analyze verify" "" "$out"
fi

echo "installer: oomd drop-in"
cat > "$STUB/sudo" <<'EOF'
#!/usr/bin/env bash
"$@"
EOF
cat > "$STUB/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$ROOT/systemctl.log"
[[ "\$1" == "is-active" ]] && exit 3
exit 0
EOF
chmod +x "$STUB/sudo" "$STUB/systemctl"
if [[ -x /usr/lib/systemd/systemd-oomd ]]; then
    out=$(PATH="$STUB:$PATH" MEMWATCH_OOMD_DROPIN_DIR="$ROOT/etc/user@.service.d" \
        bash -c "source '$REPO/installers/memwatch.sh'; _install_oomd" 2>&1)
    check "drop-in copied verbatim" "same" "$(cmp -s "$dropin" "$ROOT/etc/user@.service.d/90-mem-pressure-kill.conf" && echo same || echo differs)"
    contains "daemon-reload" "daemon-reload" "$(cat "$ROOT/systemctl.log")"
    contains "oomd enabled" "enable --now systemd-oomd" "$(cat "$ROOT/systemctl.log")"
else
    echo "  SKIP systemd-oomd not installed"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]]
