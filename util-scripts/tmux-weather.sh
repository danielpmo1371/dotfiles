#!/bin/bash
# tmux-weather.sh - Print today's weather for the tmux status-right segment:
# condition icon, current temperature and today's low/high, e.g. "⛅ 9° 8–11°".
#
# tmux re-runs #() every status-interval (1s here), so this only ever reads a
# cache file. When the cache is older than TMUX_WEATHER_TTL it starts one
# background refresh from wttr.in (a mkdir lock stops parallel refreshes from
# several clients). A failed refresh keeps the last good line and is retried
# after TMUX_WEATHER_RETRY seconds, not on every redraw.
#
# Location: tmux option @weather-location (any wttr.in location, e.g.
# "Christchurch"); unset means wttr.in guesses from the public IP.
#
# Overrides: TMUX_WEATHER_CACHE (cache dir), TMUX_WEATHER_TTL (seconds),
# TMUX_WEATHER_RETRY (seconds between failed attempts),
# TMUX_WEATHER_TIMEOUT (curl seconds), TMUX_WEATHER_URL (base URL).
# Usage: tmux-weather.sh            print the cached line, refresh if stale
#        tmux-weather.sh --refresh  fetch now, in the foreground

CACHE_DIR="${TMUX_WEATHER_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux-weather}"
TTL="${TMUX_WEATHER_TTL:-900}"
RETRY="${TMUX_WEATHER_RETRY:-60}"
TIMEOUT="${TMUX_WEATHER_TIMEOUT:-10}"
BASE_URL="${TMUX_WEATHER_URL:-https://wttr.in}"
CACHE_FILE="$CACHE_DIR/current"
LOCK_DIR="$CACHE_DIR/refresh.lock"
ATTEMPT_FILE="$CACHE_DIR/last-attempt"
LOADING="…"

# wttr.in reports World Weather Online condition codes.
icon_for_code() {
    case "$1" in
        113) echo "☀️" ;;
        116) echo "⛅" ;;
        119|122) echo "☁️" ;;
        143|248|260) echo "🌫️" ;;
        176|263|266|293|296|353) echo "🌦️" ;;
        299|302|305|308|356|359|281|284|311|314) echo "🌧️" ;;
        200|386|389|392|395) echo "⛈️" ;;
        179|182|185|227|230|317|320|323|326|329|332|335|338|350|362|365|368|371|374|377) echo "🌨️" ;;
        *) echo "🌡️" ;;
    esac
}

file_age() {
    local mtime
    mtime=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null) || return 1
    echo $(( $(date +%s) - mtime ))
}

refresh() {
    local location json line tmp
    mkdir -p "$CACHE_DIR" || return 1
    location=$(tmux show -gqv @weather-location 2>/dev/null)
    # wttr.in takes spaces in a location as "+".
    json=$(curl -fsS -m "$TIMEOUT" "$BASE_URL/${location// /+}?format=j1") || return 1
    line=$(printf '%s' "$json" | jq -r '
        [.current_condition[0].weatherCode, .current_condition[0].temp_C,
         .weather[0].mintempC, .weather[0].maxtempC] | @tsv' 2>/dev/null) || return 1
    local code temp low high
    IFS=$'\t' read -r code temp low high <<<"$line"
    [ -n "$temp" ] && [ -n "$low" ] && [ -n "$high" ] || return 1
    tmp=$(mktemp "$CACHE_DIR/current.XXXXXX") || return 1
    printf '%s %s° %s–%s°\n' "$(icon_for_code "$code")" "$temp" "$low" "$high" >"$tmp"
    mv -f "$tmp" "$CACHE_FILE"
}

refresh_in_background() {
    # A lock left by a killed refresh is reclaimed once it is older than TTL.
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        local age
        age=$(file_age "$LOCK_DIR") || return 0
        [ "$age" -gt "$TTL" ] || return 0
        rmdir "$LOCK_DIR" 2>/dev/null
        mkdir "$LOCK_DIR" 2>/dev/null || return 0
    fi
    touch "$ATTEMPT_FILE"
    ( refresh; rmdir "$LOCK_DIR" 2>/dev/null ) >/dev/null 2>&1 &
}

if [ "$1" = "--refresh" ]; then
    refresh || { echo "tmux-weather: refresh failed" >&2; exit 1; }
    cat "$CACHE_FILE"
    exit 0
fi

mkdir -p "$CACHE_DIR" 2>/dev/null
age=$(file_age "$CACHE_FILE") || age=""
if [ -z "$age" ] || [ "$age" -ge "$TTL" ]; then
    attempt_age=$(file_age "$ATTEMPT_FILE") || attempt_age=""
    if [ -z "$attempt_age" ] || [ "$attempt_age" -ge "$RETRY" ]; then
        refresh_in_background
    fi
fi
if [ -s "$CACHE_FILE" ]; then
    cat "$CACHE_FILE"
else
    echo "$LOADING"
fi
