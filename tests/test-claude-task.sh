#!/bin/bash

# Hermetic tests for util-scripts/claude-task (and its use of
# util-scripts/tmux-claude-task.sh through `dry-run --direct`).
#
# Unit files and the registry live in a temp dir (CLAUDE_TASK_UNIT_DIR,
# CLAUDE_TASK_STATE_DIR); tasks are scheduled with --no-enable, and a stub
# `systemctl` first on PATH records every call, so no real timer is touched.
# systemd-analyze stays real: calendar parsing and `verify` must really run.
# dry-run uses its own private tmux server (-L); ZDOTDIR points at an empty
# dir with an empty .zshrc so the window's `zsh -lic` skips the user's zshrc.
#
# Usage: ./tests/test-claude-task.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
CLAUDE_TASK="$DOTFILES_ROOT/util-scripts/claude-task"
LAUNCHER="$DOTFILES_ROOT/util-scripts/tmux-claude-task.sh"

PARALLEL_TASKS=5
DRYRUN_TIMEOUT=20
FUTURE_WHEN="$(date -d '+2 days' '+%F 20:30')"
FUTURE_ON_CALENDAR="$(date -d '+2 days' '+%F') 20:30:00"
FUTURE_DATE="$(date -d '+2 days' '+%F')"
PAST_WHEN="$(date -d '-1 day' '+%F 09:00')"

PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

WORK="$(mktemp -d)"

cleanup() {
    # Only dry-run servers started by this test's claude-task runs.
    local socket
    for socket in $(sed -n "s/.*private tmux server '\([^']*\)'.*/\1/p" "$WORK"/dryrun*.out 2>/dev/null); do
        tmux -L "$socket" kill-server 2>/dev/null
    done
    rm -rf "$WORK"
}
trap cleanup EXIT

export CLAUDE_TASK_UNIT_DIR="$WORK/units"
export CLAUDE_TASK_STATE_DIR="$WORK/state"
export CLAUDE_TASK_DRYRUN_TIMEOUT="$DRYRUN_TIMEOUT"
export ZDOTDIR="$WORK/zdotdir"
REGISTRY="$CLAUDE_TASK_STATE_DIR/SCHEDULED.md"
SYSTEMCTL_LOG="$WORK/systemctl.log"
PROJ="$WORK/proj"
mkdir -p "$WORK/bin" "$PROJ" "$ZDOTDIR"
# An existing (empty) .zshrc: with none, zsh opens its interactive new-user wizard.
: > "$ZDOTDIR/.zshrc"

# Stub systemctl: record the call; answer is-enabled/is-active like a live timer.
cat > "$WORK/bin/systemctl" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> '$SYSTEMCTL_LOG'
case "\$*" in
    *is-enabled*) echo enabled ;;
    *is-active*)  echo active ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/systemctl"
export PATH="$WORK/bin:$PATH"

# The prompt every scheduled task gets: quotes, expansions, backticks, a
# command substitution, a backslash, a % and several lines. None may be
# interpreted anywhere between the file and the stub command.
PROMPT="$WORK/prompt.md"
cat > "$PROMPT" <<'EOF'
Check the "deploy" and don't forget: $HOME ${PATH} `whoami` $(rm -rf /tmp/nothing)
Line two \n with a backslash \ and 100% sure; a | pipe & ampersand *glob*

Last line after a blank one.
EOF

unit_path() {
    if [[ "$1" == "$HOME/"* ]]; then printf '%%h/%s' "${1#"$HOME"/}"; else printf '%s' "$1"; fi
}

ct() { "$CLAUDE_TASK" "$@"; }

schedule() {
    ct schedule "$1" "${2:-$FUTURE_WHEN}" "$PROJ" "$PROMPT" --purpose "${3:-test purpose}" --no-enable
}

registry_row() { grep -E "^\| [^|]+ \| [^|]+ \| $1 \|" "$REGISTRY"; }

echo -e "${BLUE}claude-task: validation${NC}"

for bad in "Bad" "-lead" "has space" "semi;colon" "dot.name" "under_score" ""; do
    ct schedule "$bad" "$FUTURE_WHEN" "$PROJ" "$PROMPT" --purpose p --no-enable > /dev/null 2>&1
    check "name '$bad' rejected with exit 2" "[[ $? -eq 2 ]]"
done

ct schedule past-task "$PAST_WHEN" "$PROJ" "$PROMPT" --purpose p --no-enable > "$WORK/out" 2>&1
check "past <when> rejected with exit 2" "[[ $? -eq 2 ]] && grep -q 'past' '$WORK/out'"

ct schedule garbage-task "not-a-date" "$PROJ" "$PROMPT" --purpose p --no-enable > /dev/null 2>&1
check "garbage <when> rejected with exit 2" "[[ $? -eq 2 ]]"

ct schedule nopurpose "$FUTURE_WHEN" "$PROJ" "$PROMPT" --no-enable > /dev/null 2>&1
check "missing --purpose rejected" "[[ $? -eq 2 ]]"

ct schedule pipepurpose "$FUTURE_WHEN" "$PROJ" "$PROMPT" --purpose "a | b" --no-enable > /dev/null 2>&1
check "purpose with '|' rejected" "[[ $? -eq 2 ]]"

ct schedule nodir "$FUTURE_WHEN" "$WORK/missing" "$PROMPT" --purpose p --no-enable > /dev/null 2>&1
check "missing dir rejected" "[[ $? -eq 2 ]]"

: > "$WORK/empty.md"
ct schedule emptyprompt "$FUTURE_WHEN" "$PROJ" "$WORK/empty.md" --purpose p --no-enable > /dev/null 2>&1
check "empty prompt file rejected" "[[ $? -eq 2 ]]"

for badchar in "sp ace" "per%cent" "quo'te" 'dq"uote' 'back\slash' 'dol$lar'; do
    mkdir -p "$WORK/$badchar"
    ct schedule badpath "$FUTURE_WHEN" "$WORK/$badchar" "$PROMPT" --purpose p --no-enable > /dev/null 2>&1
    check "dir with '$badchar' rejected (exit 1)" "[[ $? -eq 1 ]]"
done
check "nothing written by rejected schedules" "[[ ! -e '$CLAUDE_TASK_UNIT_DIR' || -z \"\$(ls -A '$CLAUDE_TASK_UNIT_DIR')\" ]]"

ct nosuchcommand > /dev/null 2>&1
check "unknown command exits 2" "[[ $? -eq 2 ]]"

echo -e "${BLUE}claude-task: schedule${NC}"

schedule alpha "$FUTURE_WHEN" "alpha 100% done" > "$WORK/out" 2>&1
check "schedule alpha exits 0" "[[ $? -eq 0 ]]"
SERVICE="$CLAUDE_TASK_UNIT_DIR/claude-task-alpha.service"
TIMER="$CLAUDE_TASK_UNIT_DIR/claude-task-alpha.timer"
STORED_PROMPT="$CLAUDE_TASK_STATE_DIR/prompts/$FUTURE_DATE-alpha.md"
check "output names cancel command and memory reminder" \
    "grep -q 'claude-task cancel alpha' '$WORK/out' && grep -q 'memory MCP (tag scheduled-followup)' '$WORK/out'"

expected_exec="ExecStart=$(unit_path "$LAUNCHER") followups alpha $(unit_path "$PROJ") $(unit_path "$STORED_PROMPT")"
check "ExecStart uses %h and the launcher line" "grep -qxF '$expected_exec' '$SERVICE'"
check "ExecStartPost runs mark-fired" \
    "grep -qxF 'ExecStartPost=$(unit_path "$(readlink -f "$CLAUDE_TASK")") mark-fired alpha' '$SERVICE'"
check "service Type=oneshot" "grep -qx 'Type=oneshot' '$SERVICE'"
check "service comment names session" \
    "grep -qxF '# window of the \"followups\" tmux session (see util-scripts/tmux-claude-task.sh).' '$SERVICE'"
check "Description escapes % as %%" "grep -qxF 'Description=Claude follow-up: alpha 100%% done' '$TIMER'"
check "OnCalendar normalized to absolute" "grep -qxF 'OnCalendar=$FUTURE_ON_CALENDAR' '$TIMER'"
check "Persistent/AccuracySec/WantedBy" \
    "grep -qx 'Persistent=true' '$TIMER' && grep -qx 'AccuracySec=1min' '$TIMER' && grep -qx 'WantedBy=timers.target' '$TIMER'"
check "systemd-analyze --user verify passes" "systemd-analyze --user verify '$SERVICE' '$TIMER' > /dev/null 2>&1"
check "prompt copied byte-for-byte" "cmp -s '$PROMPT' '$STORED_PROMPT'"
check "--no-enable never calls systemctl" "[[ ! -s '$SYSTEMCTL_LOG' ]]"
check "registry created with header" \
    "head -n 1 '$REGISTRY' | grep -qx '# Scheduled Claude follow-ups' && grep -qxF '| Created | Fires (NZ) | Name | tmux session | Dir | Purpose | Status |' '$REGISTRY'"
fires_col="${FUTURE_WHEN}"
check "registry row appended as scheduled" \
    "registry_row alpha | grep -qF '| $fires_col | alpha | followups | $PROJ | alpha 100% done | scheduled |'"

schedule alpha > /dev/null 2>&1
check "existing task refused (exit 1)" "[[ $? -eq 1 ]]"
check "refused schedule left files untouched" "grep -qxF 'OnCalendar=$FUTURE_ON_CALENDAR' '$TIMER' && [[ \$(registry_row alpha | wc -l) -eq 1 ]]"

ct schedule beta "$FUTURE_WHEN" "$PROJ" "$PROMPT" --purpose p --session other-sess --no-enable > /dev/null 2>&1
check "--session sets the tmux session" "grep -q 'tmux-claude-task.sh other-sess beta ' '$CLAUDE_TASK_UNIT_DIR/claude-task-beta.service'"

echo -e "${BLUE}claude-task: concurrency${NC}"

for ((i = 1; i <= PARALLEL_TASKS; i++)); do
    schedule "par-$i" > "$WORK/par-$i.out" 2>&1 &
done
wait
rows=0
for ((i = 1; i <= PARALLEL_TASKS; i++)); do
    [[ $(registry_row "par-$i" | wc -l) -eq 1 ]] && rows=$((rows + 1))
done
check "$PARALLEL_TASKS parallel schedules all land exactly once" "[[ $rows -eq $PARALLEL_TASKS ]]"
check "registry has no malformed rows" "! grep -E '^\|' '$REGISTRY' | awk -F'|' 'NF != 9' | grep -q ."
check "registry header appears once" "[[ \$(grep -c '^# Scheduled Claude follow-ups' '$REGISTRY') -eq 1 ]]"

echo -e "${BLUE}claude-task: cancel / mark-fired${NC}"

ct mark-fired alpha > /dev/null 2>&1
check "mark-fired: scheduled -> fired" "registry_row alpha | grep -qE '\| fired [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \|$'"
ct cancel beta > /dev/null 2>&1
check "cancel exits 0" "[[ $? -eq 0 ]]"
check "cancel ran systemctl disable --now" "grep -qxF -- '--user disable --now claude-task-beta.timer' '$SYSTEMCTL_LOG'"
check "cancel status recorded" "registry_row beta | grep -qE '\| cancelled [0-9]{4}-[0-9]{2}-[0-9]{2} \|$'"
check "cancel keeps unit and prompt files" \
    "[[ -f '$CLAUDE_TASK_UNIT_DIR/claude-task-beta.service' && -f '$CLAUDE_TASK_UNIT_DIR/claude-task-beta.timer' && -f '$CLAUDE_TASK_STATE_DIR/prompts/$FUTURE_DATE-beta.md' ]]"
ct mark-fired beta > /dev/null 2>&1
check "mark-fired leaves a cancelled task alone (exit 0)" "[[ $? -eq 0 ]] && registry_row beta | grep -q '| cancelled '"
before="$(cat "$REGISTRY")"
ct mark-fired alpha > /dev/null 2>&1
check "mark-fired twice keeps the first fired time" "[[ \"\$before\" == \"\$(cat '$REGISTRY')\" ]]"
ct mark-fired ghost > /dev/null 2>&1
check "mark-fired with no row exits 0" "[[ $? -eq 0 ]]"
ct cancel ghost > /dev/null 2>&1
check "cancel of unknown task exits 1" "[[ $? -eq 1 ]]"

echo -e "${BLUE}claude-task: list / show${NC}"

ct list > "$WORK/list.out" 2>&1
check "list exits 0" "[[ $? -eq 0 ]]"
check "list shows every task" "[[ \$(grep -cE '^(alpha|beta|par-[0-9]+) ' '$WORK/list.out') -eq $((PARALLEL_TASKS + 2)) ]]"
check "list line: fires, timer state, status, session" \
    "grep -E '^alpha ' '$WORK/list.out' | grep -F '${FUTURE_WHEN}' | grep -F 'enabled/active' | grep -F 'fired ' | grep -qF 'followups'"
ct show alpha > "$WORK/show.out" 2>&1
check "show exits 0" "[[ $? -eq 0 ]]"
check "show prints the prompt verbatim" "sed '1,/^--- prompt ---\$/d' '$WORK/show.out' | cmp -s - '$PROMPT'"

echo -e "${BLUE}claude-task: dry-run --direct${NC}"

ct dry-run alpha --direct > "$WORK/dryrun.out" 2>&1
status=$?
check "dry-run --direct delivers the prompt verbatim" "[[ $status -eq 0 ]] && grep -q '^PASS' '$WORK/dryrun.out'"
[[ $status -eq 0 ]] || sed 's/^/      /' "$WORK/dryrun.out"
socket="$(sed -n "s/.*private tmux server '\([^']*\)'.*/\1/p" "$WORK/dryrun.out")"
check "dry-run used a private socket and shut it down" \
    "[[ '$socket' == claude-task-dryrun-* ]] && ! tmux -L '$socket' has-session 2>/dev/null \
        && [[ ! -e '${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$socket' ]]"
check "dry-run left the registry status alone" "registry_row alpha | grep -q '| fired '"

# dry-run reads the prompt path from the unit's ExecStart, not from its name.
printf 'other prompt\n' > "$WORK/other.md"
sed -i "s|$(unit_path "$CLAUDE_TASK_STATE_DIR/prompts/$FUTURE_DATE-par-1.md")|$(unit_path "$WORK/other.md")|" \
    "$CLAUDE_TASK_UNIT_DIR/claude-task-par-1.service"
ct dry-run par-1 --direct > "$WORK/dryrun-par.out" 2>&1
check "dry-run follows the ExecStart prompt path" \
    "[[ $? -eq 0 ]] && grep -q '^PASS.*(12 bytes)' '$WORK/dryrun-par.out'"

echo ""
echo -e "${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}"
[ "$FAIL" -eq 0 ]
