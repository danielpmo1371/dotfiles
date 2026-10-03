#!/usr/bin/env bash
#
# Tests for util-scripts/tmux-weather.sh (weather in the tmux status bar).
#
# Pins: --refresh formats icon, current temperature and today's low/high; the
# default mode never blocks (prints "…" before the first fetch, the cached
# line after); a fresh cache is not refetched; a failed refresh keeps the last
# good line and is not retried before TMUX_WEATHER_RETRY; @weather-location
# reaches the URL with spaces as "+".
#
# Hermetic: curl and tmux are stubs, the cache is a temp dir, nothing touches
# the network or a real tmux server.

set -uo pipefail

WEATHER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/util-scripts/tmux-weather.sh"
readonly JSON='{"current_condition":[{"weatherCode":"116","temp_C":"9"}],"weather":[{"mintempC":"8","maxtempC":"11"}]}'
readonly EXPECTED="⛅ 9° 8–11°"
readonly BG_WAIT_TRIES=50

PASS=0
FAIL=0

ok()  { echo "  PASS $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $1"; echo "       expected: $2"; echo "       actual:   $3"; FAIL=$((FAIL + 1)); }
check() {
    local label="$1" expected="$2" actual="$3"
    [[ "$actual" == "$expected" ]] && ok "$label" || bad "$label" "$expected" "$actual"
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-tmux-weather.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
STUB="$ROOT/bin"
mkdir -p "$STUB"

# curl stub: logs its URL, answers with $ROOT/response, fails if that is absent.
cat >"$STUB/curl" <<EOF
#!/bin/bash
echo "\${@: -1}" >>"$ROOT/curl-urls"
[ -f "$ROOT/response" ] || exit 22
cat "$ROOT/response"
EOF
# tmux stub: only answers the @weather-location lookup.
cat >"$STUB/tmux" <<EOF
#!/bin/bash
cat "$ROOT/location" 2>/dev/null
EOF
chmod +x "$STUB/curl" "$STUB/tmux"

run() {
    PATH="$STUB:$PATH" TMUX_WEATHER_CACHE="$ROOT/cache" TMUX_WEATHER_URL="https://wttr.test" \
        TMUX_WEATHER_TTL="${TTL:-900}" TMUX_WEATHER_RETRY="${RETRY:-60}" "$WEATHER" "$@"
}
curl_calls() { [ -f "$ROOT/curl-urls" ] && wc -l <"$ROOT/curl-urls" | tr -d ' ' || echo 0; }
wait_for_lock_release() {
    local i
    for ((i = 0; i < BG_WAIT_TRIES; i++)); do
        [ -d "$ROOT/cache/refresh.lock" ] || return 0
        sleep 0.1
    done
}
reset() { rm -rf "$ROOT/cache" "$ROOT/curl-urls" "$ROOT/response" "$ROOT/location"; }

echo "--refresh"
reset; printf '%s' "$JSON" >"$ROOT/response"
check "formats icon, temperature and low/high" "$EXPECTED" "$(run --refresh)"
reset
run --refresh >/dev/null 2>&1; check "fails without a response" "1" "$?"

echo "status mode"
reset; printf '%s' "$JSON" >"$ROOT/response"
check "prints the loading marker before the first fetch" "…" "$(run)"
wait_for_lock_release
check "shows the fetched line once cached" "$EXPECTED" "$(run)"
check "fresh cache is not refetched" "1" "$(curl_calls)"

echo "failure keeps the last line"
rm -f "$ROOT/response"
touch -d '-1 hour' "$ROOT/cache/current" "$ROOT/cache/last-attempt"
check "stale cache still prints" "$EXPECTED" "$(run)"
wait_for_lock_release
check "stale cache triggers one attempt" "2" "$(curl_calls)"
check "failed refresh keeps the last good line" "$EXPECTED" "$(run)"
wait_for_lock_release
check "no retry before TMUX_WEATHER_RETRY" "2" "$(curl_calls)"

echo "location"
reset; printf '%s' "$JSON" >"$ROOT/response"; echo "New York" >"$ROOT/location"
run --refresh >/dev/null
check "location goes into the URL with + for spaces" "https://wttr.test/New+York?format=j1" "$(cat "$ROOT/curl-urls")"
reset; printf '%s' "$JSON" >"$ROOT/response"
run --refresh >/dev/null
check "no location lets wttr.in guess" "https://wttr.test/?format=j1" "$(cat "$ROOT/curl-urls")"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
