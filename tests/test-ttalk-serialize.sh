#!/usr/bin/env bash
#
# Tests for ttalk's speaker lock (util-scripts/ttalk).
#
# Why this exists: several Claude sessions finishing together each ran ttalk,
# and every call played at once, so none of the messages could be understood.
# ttalk now serializes playback behind a lock. These tests pin that: concurrent
# calls never overlap and all get spoken; a message that can't get the lock
# within TTALK_WAIT is dropped, not retried on another engine; the mkdir
# fallback (macOS has no flock) serializes too and reclaims a stale lock.
# Also pins the --disable/--enable mute toggle and the --volume setting
# (state file under HOME).
#
# Hermetic: PATH holds only a stub dir (fake piper-tts / pw-play / espeak-ng
# that log to files) plus a dir of symlinks to the few real tools ttalk needs.
# flock is linked in only for the cases that want it. No audio is ever played.

set -uo pipefail

TTALK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/util-scripts/ttalk"

PASS=0
FAIL=0

ok()   { echo "  PASS $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL $1"; echo "       expected: $2"; echo "       actual:   $3"; FAIL=$((FAIL + 1)); }
check() {
    local label="$1" expected="$2" actual="$3"
    [[ "$actual" == "$expected" ]] && ok "$label" || bad "$label" "$expected" "$actual"
}

# Real tools ttalk and the stubs use. flock is optional per case.
SYSBIN_CMDS=(bash sh mktemp cat rm mkdir sleep printf)
# Seconds each fake playback lasts: long enough that unserialized calls overlap.
PLAY_SECONDS=0.4
# Upper bound for a case to finish before it is failed.
CASE_TIMEOUT=20

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-ttalk.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT

# Args: case_dir with_flock(yes|no) play_seconds
setup_case() {
    local dir="$1" with_flock="$2" play="$3" c
    mkdir -p "$dir/bin" "$dir/sysbin" "$dir/tmp"
    for c in "${SYSBIN_CMDS[@]}"; do
        ln -s "$(command -v "$c")" "$dir/sysbin/$c"
    done
    [[ "$with_flock" == yes ]] && ln -s "$(command -v flock)" "$dir/sysbin/flock"
    : > "$dir/play.log"
    # piper-tts: "synthesize" by writing the message text into the -f file.
    cat > "$dir/bin/piper-tts" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do [[ "$1" == -f ]] && out="$2"; shift; done
cat > "$out"
EOF
    # pw-play: log start and end around a sleep, so overlap is visible. The
    # wav is the last argument; the --volume value goes to volume.log.
    cat > "$dir/bin/pw-play" <<EOF
#!/usr/bin/env bash
[[ "\$1" == --volume ]] && echo "\$2" >> '$dir/volume.log'
m=\$(cat "\${@: -1}")
echo "S \$m" >> '$dir/play.log'
sleep $play
echo "E \$m" >> '$dir/play.log'
EOF
    # espeak-ng: must NOT be reached when Piper works; logs if it is.
    cat > "$dir/bin/espeak-ng" <<EOF
#!/usr/bin/env bash
echo "espeak \$*" >> '$dir/espeak.log'
EOF
    : > "$dir/voice.onnx"
    chmod +x "$dir/bin/"*
}

# Args: case_dir wait_seconds message
run_ttalk() {
    local dir="$1" wait="$2"; shift 2
    env -i PATH="$dir/bin:$dir/sysbin" HOME="$dir" TMPDIR="$dir/tmp" \
        PIPER_VOICE="$dir/voice.onnx" TTALK_LOCK="$dir/ttalk.lock" \
        TTALK_WAIT="$wait" bash "$TTALK" "$@"
}

# Wait until play.log holds N end lines, or CASE_TIMEOUT passes.
wait_for_ends() {
    local dir="$1" want="$2" deadline=$((SECONDS + CASE_TIMEOUT))
    while (( $(grep -c '^E ' "$dir/play.log") < want )) && (( SECONDS < deadline )); do
        sleep 0.1
    done
}

# Serialized means the log strictly alternates S x / E x for the same message.
is_serialized() {
    awk '
        NR % 2 == 1 { if ($1 != "S") bad = 1; cur = $2 }
        NR % 2 == 0 { if ($1 != "E" || $2 != cur) bad = 1 }
        END { print (bad || NR % 2) ? "overlap" : "serialized" }
    ' "$1/play.log"
}

# Case dirs are named by slug: a ':' in a dir would split PATH.
concurrent_case() {
    local slug="$1" name="$2" with_flock="$3" n=4 i
    local dir="$ROOT/$slug"
    echo "$name"
    setup_case "$dir" "$with_flock" "$PLAY_SECONDS"
    for i in $(seq 1 "$n"); do run_ttalk "$dir" 60 "msg$i"; done
    wait_for_ends "$dir" "$n"
    check "all $n messages spoken" "$n" "$(grep -c '^E ' "$dir/play.log")"
    check "playbacks never overlap" "serialized" "$(is_serialized "$dir")"
    check "system engine not used" "absent" "$([[ -e "$dir/espeak.log" ]] && echo present || echo absent)"
    check "lock released afterwards" "absent" "$([[ -e "$dir/ttalk.lock.d" ]] && echo present || echo absent)"
}

concurrent_case flock-concurrent "flock: concurrent calls play one at a time" yes
concurrent_case mkdir-concurrent "mkdir fallback: concurrent calls play one at a time" no

timeout_case() {
    local slug="$1" name="$2" with_flock="$3"
    local dir="$ROOT/$slug"
    echo "$name"
    setup_case "$dir" "$with_flock" 3
    run_ttalk "$dir" 60 first
    sleep 0.5   # let "first" take the lock
    run_ttalk "$dir" 1 late
    wait_for_ends "$dir" 1
    sleep 1.5   # past the late message's 1s wait; give it time to misbehave
    check "only the lock holder spoke" "S first|E first" "$(paste -sd'|' "$dir/play.log")"
    check "timed-out message not retried on espeak" "absent" "$([[ -e "$dir/espeak.log" ]] && echo present || echo absent)"
}

timeout_case flock-timeout "flock: message past TTALK_WAIT is dropped" yes
timeout_case mkdir-timeout "mkdir fallback: message past TTALK_WAIT is dropped" no

echo "mkdir fallback: stale lock from a dead process is reclaimed"
dir="$ROOT/stale"
setup_case "$dir" no "$PLAY_SECONDS"
mkdir "$dir/ttalk.lock.d"
bash -c 'exit 0' & dead_pid=$!; wait "$dead_pid"
echo "$dead_pid" > "$dir/ttalk.lock.d/pid"
run_ttalk "$dir" 5 reclaimed
wait_for_ends "$dir" 1
check "message spoken despite stale lock" "S reclaimed|E reclaimed" "$(paste -sd'|' "$dir/play.log")"

echo "caller is not blocked while speech plays"
dir="$ROOT/nonblocking"
setup_case "$dir" yes 2
start=$SECONDS
run_ttalk "$dir" 60 quick
check "ttalk returns before playback ends" "fast" "$( (( SECONDS - start < 2 )) && echo fast || echo slow)"
wait_for_ends "$dir" 1

echo "--disable mutes and --enable unmutes"
dir="$ROOT/toggle"
setup_case "$dir" yes "$PLAY_SECONDS"
ln -s "$(command -v jq)" "$dir/sysbin/jq"
run_ttalk "$dir" 5 --disable >/dev/null
check "--disable writes the state file" '{"isEnabled": false, "volume": 40}' "$(cat "$dir/.local/state/ttalk/state.json")"
run_ttalk "$dir" 5 muted
sleep 1   # past a PLAY_SECONDS playback, had one started
check "muted message not spoken" "" "$(cat "$dir/play.log")"
run_ttalk "$dir" 5 --enable >/dev/null
run_ttalk "$dir" 5 unmuted
wait_for_ends "$dir" 1
check "message spoken after --enable" "S unmuted|E unmuted" "$(paste -sd'|' "$dir/play.log")"

echo "--disable still mutes without jq (grep fallback)"
dir="$ROOT/toggle-nojq"
setup_case "$dir" yes "$PLAY_SECONDS"
ln -s "$(command -v grep)" "$dir/sysbin/grep"
run_ttalk "$dir" 5 --disable >/dev/null
run_ttalk "$dir" 5 muted
sleep 1   # past a PLAY_SECONDS playback, had one started
check "muted message not spoken" "" "$(cat "$dir/play.log")"
run_ttalk "$dir" 5 --enable >/dev/null
run_ttalk "$dir" 5 unmuted
wait_for_ends "$dir" 1
check "message spoken after --enable" "S unmuted|E unmuted" "$(paste -sd'|' "$dir/play.log")"

echo "volume defaults to 40% and --volume changes it"
dir="$ROOT/volume"
setup_case "$dir" yes "$PLAY_SECONDS"
ln -s "$(command -v jq)" "$dir/sysbin/jq"
run_ttalk "$dir" 5 first
wait_for_ends "$dir" 1
check "default volume passed to pw-play" "0.40" "$(cat "$dir/volume.log")"
check "missing state file created with default volume" '{"isEnabled": true, "volume": 40}' "$(cat "$dir/.local/state/ttalk/state.json")"
check "--volume prints the current volume" "ttalk volume: 40%" "$(run_ttalk "$dir" 5 --volume)"
run_ttalk "$dir" 5 --volume 75 >/dev/null
check "--volume 75 reported back" "ttalk volume: 75%" "$(run_ttalk "$dir" 5 --volume)"
: > "$dir/volume.log"
run_ttalk "$dir" 5 second
wait_for_ends "$dir" 2
check "new volume passed to pw-play" "0.75" "$(cat "$dir/volume.log")"
run_ttalk "$dir" 5 --volume 100% >/dev/null
check "a trailing % is accepted" "ttalk volume: 100%" "$(run_ttalk "$dir" 5 --volume)"
for bad_value in 101 -5 abc 4.5; do
    run_ttalk "$dir" 5 --volume "$bad_value" 2>/dev/null
    check "--volume $bad_value rejected" "1 ttalk volume: 100%" "$? $(run_ttalk "$dir" 5 --volume)"
done
run_ttalk "$dir" 5 --volume 5 >/dev/null
check "single-digit volume formatted for pw-play" "0.05" "$(: > "$dir/volume.log"; run_ttalk "$dir" 5 third; wait_for_ends "$dir" 3; cat "$dir/volume.log")"
run_ttalk "$dir" 5 --disable >/dev/null
check "--disable keeps the volume" '{"isEnabled": false, "volume": 5}' "$(cat "$dir/.local/state/ttalk/state.json")"
run_ttalk "$dir" 5 --volume 60 >/dev/null
check "--volume keeps ttalk disabled" '{"isEnabled": false, "volume": 60}' "$(cat "$dir/.local/state/ttalk/state.json")"
printf '{"isEnabled": true, "volume": "loud"}\n' > "$dir/.local/state/ttalk/state.json"
check "invalid stored volume falls back to the default" "ttalk volume: 40%" "$(run_ttalk "$dir" 5 --volume)"

echo "--volume works without jq (grep fallback)"
dir="$ROOT/volume-nojq"
setup_case "$dir" yes "$PLAY_SECONDS"
ln -s "$(command -v grep)" "$dir/sysbin/grep"
run_ttalk "$dir" 5 --volume 30 >/dev/null
check "--volume 30 reported back" "ttalk volume: 30%" "$(run_ttalk "$dir" 5 --volume)"
run_ttalk "$dir" 5 quiet
wait_for_ends "$dir" 1
check "stored volume passed to pw-play" "0.30" "$(cat "$dir/volume.log")"

echo
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
