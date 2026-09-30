#!/usr/bin/env bash
#
# Tests for util-scripts/ntfy-send (phone notifications via ntfy).
#
# Pins: the message and optional headers reach curl verbatim; NTFY_TOKEN adds
# a Bearer header only when set; a curl failure is reported (exit 1) and the
# topic URL (a secret) never appears in the output; bad usage exits 2; a
# missing topic exits 1 with a hint.
#
# Hermetic: curl is a stub that records its argv, HOME is a temp dir (so the
# keychain fallback finds no secrets library), nothing touches the network.

set -uo pipefail

NTFY_SEND="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/util-scripts/ntfy-send"
readonly FAKE_TOPIC="https://ntfy.example/secret-topic-123"

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

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-ntfy-send.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
STUB="$ROOT/bin"
ARGV_LOG="$ROOT/curl-argv"
mkdir -p "$STUB" "$ROOT/home"

# Fake curl: one argv element per line; exits with $CURL_EXIT (default 0).
cat > "$STUB/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGV_LOG"
exit "\${CURL_EXIT:-0}"
EOF
chmod +x "$STUB/curl"

run() {
    rm -f "$ARGV_LOG"
    env -i PATH="$STUB:/usr/bin:/bin" HOME="$ROOT/home" "$@" "$NTFY_SEND" "${ARGS[@]}" 2>&1
}

echo "message and headers"
ARGS=(-t "Build done" -p high -g "robot,tada" 'multi word $msg "quoted"')
out=$(run NTFY_TOPIC_URL="$FAKE_TOPIC"); rc=$?
check "exit 0 on success" "0" "$rc"
argv=$(cat "$ARGV_LOG")
contains "message verbatim"  $'--data-binary\nmulti word $msg "quoted"' "$argv"
contains "title header"      "Title: Build done" "$argv"
contains "priority header"   "Priority: high" "$argv"
contains "tags header"       "Tags: robot,tada" "$argv"
check    "topic is last arg" "$FAKE_TOPIC" "$(tail -n1 "$ARGV_LOG")"
lacks    "no auth by default" "Authorization" "$argv"

echo "optional headers omitted"
ARGS=("plain")
run NTFY_TOPIC_URL="$FAKE_TOPIC" >/dev/null
argv=$(cat "$ARGV_LOG")
lacks "no title header"    "Title:" "$argv"
lacks "no priority header" "Priority:" "$argv"
lacks "no tags header"     "Tags:" "$argv"

echo "token"
ARGS=("hi")
run NTFY_TOPIC_URL="$FAKE_TOPIC" NTFY_TOKEN="tk_abc" >/dev/null
contains "bearer header when NTFY_TOKEN set" "Authorization: Bearer tk_abc" "$(cat "$ARGV_LOG")"

echo "failures"
ARGS=("hi")
out=$(run NTFY_TOPIC_URL="$FAKE_TOPIC" CURL_EXIT=22); rc=$?
check    "curl failure exits 1"      "1" "$rc"
contains "failure reported"          "delivery failed" "$out"
lacks    "topic URL never printed"   "secret-topic-123" "$out"

out=$(run); rc=$?
check    "missing topic exits 1"     "1" "$rc"
contains "missing topic hint"        "secret_set NTFY_TOPIC_URL" "$out"
[[ -e "$ARGV_LOG" ]] && bad "curl not called without topic" "no call" "called" || ok "curl not called without topic"

ARGS=()
run NTFY_TOPIC_URL="$FAKE_TOPIC" >/dev/null; check "no message exits 2" "2" "$?"
ARGS=(one two)
run NTFY_TOPIC_URL="$FAKE_TOPIC" >/dev/null; check "two messages exit 2" "2" "$?"
ARGS=(-x hi)
run NTFY_TOPIC_URL="$FAKE_TOPIC" >/dev/null; check "unknown flag exits 2" "2" "$?"

echo
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
