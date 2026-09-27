# Incident: Concurrent ttalk Notifications Talked Over Each Other

**Date**: 2026-09-27
**Severity**: Medium (notifications lost, no data or system harm)
**Status**: Fixed (3ad4555)
**Affected**: `util-scripts/ttalk`, every Claude session that follows the global "After finishing tasks: `ttalk ...`" rule

---

## The Error

Three or four `ttalk` completion announcements played at the same moment.
The voices overlapped and none of the messages could be understood, so the
whole point of the notification (telling Daniel *which* work finished,
without looking at the screen) was lost.

`ttalk` ran speech in the background (`speak >/dev/null 2>&1 &`) and exited
straight away. Nothing coordinated one call with another, so N callers meant
N simultaneous `pw-play` streams on the same speakers.

---

## Root Cause Analysis (Five Whys)

1. **What happened?** Several `ttalk` processes played audio at the same
   time.
2. **Why?** Each call backgrounded its own synthesis and playback, and there
   was no lock or queue between calls. The audio device mixes concurrent
   streams instead of rejecting them, so nothing failed. It just became noise.
3. **Why did the design allow that?** `ttalk` was built (7c21c6c, 98d92ae)
   with a one-session mental model: one Claude, one completion, one message.
   The effective workload is many sessions: several tmux panes each running
   Claude, sub-agents and teammates (Agent Teams are enabled), and parallel
   tool calls inside one session, all under a global rule that says *every*
   task completion calls `ttalk`. Completions cluster (a batch of agents
   finishing, a coordinated fan-out), so collisions were built in.
4. **Why wasn't it caught?** No test exercised concurrency. The manual check
   was "does one call speak?", which it did. The failure only shows up under
   load, and it fails silently, since every process exits 0 by design.
5. **Why doesn't the system prevent it?** Caller-side discipline cannot fix
   it. Separate Claude sessions don't know about each other, so no prompt
   rule ("don't call ttalk while another session is talking") is enforceable.
   The only place that sees every call is `ttalk` itself, and it had no
   mutual exclusion.

**Mental model failure**: a speaker is a shared, exclusive device, but the
script treated it as a per-caller resource, like printing to one's own
terminal.

---

## Red Flags That Should Have Stopped Me

1. **Unconditional `&` on a side effect in a shared resource**
   - Why it matters: backgrounding removes the only natural serialization
     (the caller waiting) without putting anything in its place.
   - What should have happened: ask "what if two of these run at once?"
     whenever a background job touches a device, file or port that other
     processes also use.
2. **A global rule that makes every session call the tool**
   - Why it matters: `~/.claude/CLAUDE.md` makes `ttalk` a hot path for
     *all* concurrent sessions, not an occasional manual command.
   - What should have happened: design for the real caller count.
3. **Agent Teams and multi-pane Claude were already in use**
   - Why it matters: the concurrency was documented in this repo's own
     CLAUDE.md (Agent Teams, `claude-rc`, per-pane relaunch).
   - What should have happened: test with parallel callers.
4. **"Exits 0 no matter what" hides failure**
   - Why it matters: a silent-success contract means garbled output never
     surfaces as an error, so it needs an explicit test.

---

## Proper Workflow

### Before building a notifier or any tool that touches a shared resource
1. List the resource's consumers across the machine, not just the caller at
   hand (other panes, sub-agents, cron, Hyprland binds).
2. Decide on the concurrency policy: serialize, coalesce, or drop.
3. Put the policy **in the tool**, since callers cannot coordinate.

### Action steps (what was done)
1. Lock around playback only: `flock -w "$TTALK_WAIT"` on
   `$XDG_RUNTIME_DIR/ttalk.lock` (per-user, tmpfs). The kernel releases a
   flock when its holder dies, so a killed `ttalk` cannot wedge the queue.
2. Piper synthesizes *before* the lock, so the next message is ready when the
   speaker frees up and queued messages play back-to-back.
3. The one-step system engines (`say`, `espeak-ng`, `spd-say -w`) run fully
   inside the lock. `-w` keeps `spd-say` from returning while speech-dispatcher
   is still talking.
4. A message still waiting after `TTALK_WAIT` (default 120 s) is dropped. It
   returns a distinct status (75, EX_TEMPFAIL) so it is not retried on the
   next engine, which would double the wait and still be stale.
5. macOS has no `flock`, so it falls back to an atomic `mkdir` lock with the
   holder's pid for stale-lock reclaim.
6. The caller still returns immediately (speech stays backgrounded).

### After completion
1. `tests/test-ttalk-serialize.sh`: 4 concurrent calls, strictly alternating
   start/end log, on both the flock and mkdir paths. Also covers timeout drop
   without espeak retry, stale-lock reclaim, and a non-blocking caller.
2. Real-engine check: 3 concurrent `ttalk` calls with Piper and `pw-play`,
   sampled every 100 ms. At most 1 `pw-play` ever ran.

### Edge cases
- **Killed holder, flock path**: the kernel frees the lock. No action needed.
- **Killed holder, mkdir path**: the next waiter sees a dead pid and reclaims
  the lock. If two waiters reclaim the same stale lock at once, one pair of
  messages can overlap one time (documented in the script).
- **Burst larger than `TTALK_WAIT` of speech**: the tail is dropped. This is
  deliberate: a notification that arrives minutes late is misleading.

---

## Bugs the New Test Caught During the Fix

- The mkdir lock first recorded `$$`. Inside the backgrounded subshell, `$$`
  is the *parent* script, which has already exited, so every waiter judged
  the live lock stale and broke it. The overlap assertion failed on the first
  run. `BASHPID` would fix it but needs bash 4, and macOS ships 3.2, so the
  pid now comes from `sh -c 'echo "$PPID"'`.
- This is the argument for the test: the macOS path cannot be exercised on
  this Linux host without forcing it hermetically.

---

## Learning Mechanisms Implemented

| Level | Mechanism |
|-------|-----------|
| 4, Architecture | Mutual exclusion inside `ttalk`, so callers cannot collide whatever they do |
| 3, Automation | `tests/test-ttalk-serialize.sh`, hermetic, both lock paths |
| 1, Documentation | Project `CLAUDE.md` Key Patterns entry and test list; global `CLAUDE.md` Learned Lesson |

---

## Takeaway

A background job that writes to a shared device has to bring its own
serialization. When callers are independent sessions, the fix belongs in the
tool, not in instructions to the callers.
