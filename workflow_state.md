# Workflow State

## DONE: memory hooks dead for 2 days — vendored module drift (2026-09-21)

### State
- **Status**: COMPLETE (verified)
- **Branch**: main
- **Commits**: `11e7cf5`, `35f50e8`, `e0fc8a0`

### Origin
Came out of a request to "intercept terminal/tmux close to exit Claude sessions
gracefully". That premise did not survive measurement (see next block); the real
data loss was here.

### Root cause
`installers/memory-hooks.sh` vendors hooks by curl-ing a hardcoded filename list
from `doobidoo/mcp-memory-service@main`. Upstream refactored two shared modules
out (`config-loader.js`, `tls-options.js`); the list never named them. The
2026-09-19 13:08 install pulled newer hooks requiring files it never fetched.
curl errors were `2>/dev/null` + log_warn, so it failed silently and reported
success. Four of five hooks then died at module load (MODULE_NOT_FOUND):
SessionStart, SessionEnd, UserPromptSubmit (transitively via memory-client ->
tls-options), PostToolUse. Only permission-request.js survived. Every automatic
memory read/write lost 2026-09-19 13:08 → 2026-09-21.

Not graceful: the hooks' own fail-open logic never runs, because the process
dies before it is reached.

### Fix (all 5 approved steps)
1. `11e7cf5` — committed the working-tree jq merge fix + `tests/test-memory-hooks-merge.sh`.
   HEAD still carried the destructive `.hooks * $new_hooks` form, which replaces
   arrays wholesale; that was a live landmine for any clean checkout.
2. `35f50e8` — pinned `MEMORY_SERVICE_TAG=v11.13.0` (byte-identical to what was
   on disk → zero-diff pin), added the two missing filenames.
3. `35f50e8` — downloads now fail the install (temp file + mv, no `2>/dev/null`);
   new `verify_hook_requires()` walks the require() graph from HOOK_FILES and
   refuses to touch settings.json if anything is unresolved.
4. Ran `./installers/memory-hooks.sh`; verified.
5. `e0fc8a0` — committed the vendored sync incl. the two restored modules.

### Verification
- `tests/test-memory-hooks-merge.sh`: 29/29 PASS (hermetic; copies real settings.json read-only).
- All 5 entry points load; require() graph fully resolves.
- Live session: 0 × MODULE_NOT_FOUND (was ~1.1 KB of stack trace per session).
- Memory service `http://memory-mcp:8000/api/health` → HTTP 200 in 0.045 s.
  (Earlier claim that the service was down was WRONG — 127.0.0.1:8000 is only
  the hooks' hardcoded fallback, a symptom of the config load crashing.)
- settings.json: installer was a no-op vs its own pre-run backup; 15 hook
  commands before and after, none dropped.

### Open / for user
- A PostToolUse `Write|Edit` MacDown hook present at HEAD was already gone before
  this run — almost certainly eaten by the original destructive merge on
  2026-09-19. macOS-only, inert on this Linux box. NOT restored; user decides.
- `config/claude/settings.json` is symlinked into this repo and Claude Code writes
  its own UI settings (model, theme, autoUpdatesChannel) straight into the tracked
  file. Left unstaged as unrelated drift; worth a decision on whether to keep
  tracking a file the app mutates.
- Deferred: replace the filename list with a pinned whole-tree tarball fetch, so a
  new upstream module can never be missed. Needs a keep/drop call on extra
  upstream files (memory-retrieval.js, session-end-harvest.js, topic-change.js,
  auto-capture-hook.ps1, session-cache.json).
- Known-inert: `dynamic-context-updater.js:265` requires `../core/topic-change`,
  unresolvable because the installer flattens upstream `core/` into `memory/`.
  Dead code, unreferenced by settings.json.

## MEASURED: Claude exit is already graceful on signals (2026-09-21)

Probe on an isolated tmux socket, throwaway sessions, secret-word resume test:

| Teardown | Exits in | `claude --resume` returns secret | SessionEnd | reason |
|---|---|---|---|---|
| `/exit` | 1.7 s | yes | fired | `prompt_input_exit` |
| SIGTERM | 1.2 s | yes | fired | `other` |
| SIGHUP | 1.0 s | yes | fired | `other` |

Claude Code 2.1.278 catches HUP/INT/TERM and flushes; transcripts stayed
well-formed (every line parses). tmux kill-* sends SIGHUP; at shutdown each
`tmux-spawn-*.scope` gets SIGTERM with a 90 s TimeoutStopUSec. So every close
path already delivers a graceful signal with ~75× the grace needed — the
requested interception layer guards a failure that does not occur.

### Hint loss — the one real gap, now FIXED (`8e0ffb8`)

Signals DO print `claude --resume <id>` (identical for /exit, SIGTERM, SIGHUP;
all match the cres scraper). Mid-tool-call SIGTERM is also clean: exits ~2s,
62/62 transcript lines parse, no orphaned children, and the resumed session
narrates the interruption instead of wedging on the dangling `tool_use`.

But the REAL shutdown path loses the hint. tmux already puts every pane in a
`tmux-spawn-*.scope` (`KillMode=control-group`), so this was tested for real via
`systemctl --user stop`, not simulated:

| | scope stop | control: single-PID SIGTERM |
|---|---|---|
| Exit | 1.18s / 1.07s (`Result=success`, no SIGKILL) | ~3s |
| SessionEnd | fired | fired |
| Resumable | yes | yes |
| Hint in pane | **NO** | YES |
| `cres` | **fails** | works |

Cause: control-group signals the pane's SHELL too. Shell exits first, tmux stops
rendering, claude's hint (~1s later) has nowhere to go. Claude shut down fine.

Compounding: a RUNNING claude is in alt-screen, which has no scrollback. Verified
`~/.local/share/tmux/resurrect/pane_contents.tar.gz` (current, 23 panes, all 5
sessions): **zero** resume hints. So continuum's 15-min autosave can never
capture one; only tmux-restart.sh's exit→settle→save ordering can.

Fix chosen: `cres` falls back to `~/.claude/projects/<cwd with / as ->/<id>.jsonl`
(filename IS the session id, newest wins). Scrollback still takes precedence
because it is pane-accurate; the fallback is directory-scoped and says so on
stderr. Works after reboot, crash, SIGKILL and power loss — none of which a
shutdown drain could cover. No new processes, no systemd ordering.

`tests/test-cres-fallback.sh`: 16/16 under bash AND zsh, hermetic (fake HOME,
isolated tmux socket, claude stubbed). It caught two real bugs during
development: zsh `nomatch` erroring on an unmatched glob, and `cdang` being an
ALIAS (expanded at function-parse time, so it cannot be stubbed after sourcing;
bash also needs `expand_aliases` non-interactively).

### Not done (deliberately)
No shutdown-interception layer: nothing tested ever became non-resumable, so it
would guard a failure that does not occur. `tmux-restart.sh` left as-is — its
`/exit` dance is redundant as to SIGNAL TYPE (SIGTERM is equivalent and faster)
but its ORDERING and TARGETING are load-bearing: claude must exit before the
resurrect save, and only claude may be signalled, or the pane shell dies first
and the hint is lost.

Systemd trap worth remembering: `kitty-*.scope` and every `tmux-spawn-*.scope`
already declare `Before=shutdown.target` + `Conflicts=shutdown.target`, so a
drain unit declaring only those is stopped CONCURRENTLY with them, not before.

## Blocked on user: `q` broken — Groq key not on this machine (2026-09-18)

### Diagnosis (root cause traced, no fixes guessed)
- Error: `q hello` → `Unknown model: groq/openai/gpt-oss-20b`.
- llm-groq 0.9 registers Groq models dynamically: cached `~/.config/io.datasette.llm/groq_models.json` OR live API fetch using the key. No cache + no key → zero groq models → "Unknown model".
- Chain break: nuvemlabs/secrets library was NOT installed on this Arch machine → `secret` fn undefined → `secrets.sh` exports of GROQ_API_KEY/LLM_GROQ_KEY silently empty.

### Log
- Ran `./install.sh --secrets` → library installed at `~/.local/lib/secrets/secrets.sh`; `secret` fn verified working; libsecret (`secret-tool`) present.
- STORE check (names-only): `GROQ_API_KEY` MISSING from libsecret store on this machine.
- Note: `~/repos/secrets` clone has no `bin/secrets-doctor` (older repo state); installer's doctor check can never pass → `secrets-doctor` still unavailable. Fix belongs in nuvemlabs/secrets repo, not here.

### Log (2026-09-19)
- Second root cause found: NO Secret Service provider on this Arch/Hyprland machine — `org.freedesktop.secrets` not activatable (kwallet present only as dependency, ksecretd not claiming the name via D-Bus activation, gnome-keyring absent). `secret_set` therefore had nowhere to write (file backend refuses writes by design).
- User chose gnome-keyring (over persisting ksecretd via Hyprland exec-once) and installed it (1:50.0-1). Verified: D-Bus activation file present, gnome-keyring-daemon auto-activates and owns `org.freedesktop.secrets`, `secret-tool` lookup returns clean not-found. Stopgap ksecretd stopped.
- Optional polish (not done): PAM auto-unlock of the login keyring (`pam_gnome_keyring.so`) to avoid unlock prompts per login.

### Waiting on user
1. Fresh shell, then `secret_set GROQ_API_KEY <value>` (user only — value never handled by agent). First store may prompt to create/set a password for the default keyring.
2. `q hello` (first llm call fetches + caches Groq model list)

## BLUEPRINT: shell-init "file not found" + dead Claude hooks (2026-09-19)

### State
- **Status**: NEEDS_PLAN_APPROVAL
- **Branch**: main

### Issue A — shell init: "no such file or directory: backends\nsecrets.sh\n..."

**Root cause (confirmed, byte-for-byte reproduced):**
- `config/shell/aliases.sh:13` defines `cd() { builtin cd "$@" && lsd; }` — it writes a
  directory listing to **stdout** on every `cd`.
- `~/.local/lib/secrets/secrets.sh:32` (source: `~/repos/secrets/secrets.sh:32`) computes
  `SECRETS_DIR="$(cd "$(dirname ...)" && pwd)"`. Inside command substitution the `lsd`
  output is captured as data, so `SECRETS_DIR` becomes
  `backends\nsecrets.sh\n/home/dan/.local/lib/secrets`, and lines 64/70 then source a
  non-existent path.
- Sourcing order makes it inevitable: `aliases.sh` (zshrc:106 / bashrc line before) is
  sourced BEFORE `secrets.sh` (zshrc:110 / bashrc:100).
- Proof: `bash -c 'cd(){ builtin cd "$@" && ls; }; echo "$(cd /home/dan/.local/lib/secrets && pwd)"'`
  reproduces the exact string. A clean shell resolves `SECRETS_DIR` correctly in both bash and zsh.
- Blast radius: this corrupts **any** `$(cd ... && pwd)` in any script sourced into an
  interactive shell — a latent landmine well beyond secrets.sh.

**Ruled out (evidence, not assumption):**
- zsh `can't change option: monitor/zle` and `gitstatus failed to initialize` appear only
  under `zsh -i -c` with no tty. Re-run under a real PTY (`script -qec`): both gone.
  NOT real bugs — no action.

### Issue B — Claude Code hooks

**Root cause:** `~/.claude/hooks/` **does not exist**. All 13 hook commands referenced by
`config/claude/settings.json` resolve to missing files. Verified MISS for every one:
logging/{session-goal-tracker,user-request-logger,response-summarizer}.sh,
memory/{session-start,session-end,permission-request,auto-capture-hook,mid-conversation}.js,
pipeline-{guard,trigger-guard,registry-write-guard}.sh, destructive-ops-guard.sh,
.config/.claude/notification.sh.

All sources DO exist in `config/claude/hooks/`. The three installers that populate
`~/.claude/hooks/` (`memory-hooks`, `logging-hooks`, `claude-azdo-pipeline-hooks`) are
`off` by default in the interactive menu (install.sh:231-233) and were never run on this
machine. `~/.claude/*` symlinks date to Sep 17 17:47 (i.e. `--claude` ran), but its
auto-invoke of the pipeline-hooks installer left no directory. Dry-runs of all three
installers pass cleanly today.

**Two defects found while tracing (NOT installer-fixable):**
1. **SAFETY GAP** — `config/claude/hooks/destructive-ops-guard.sh` exists in the repo and
   global CLAUDE.md states it enforces the No-Delete Rule as a PreToolUse Bash hook. It is
   **neither installed nor registered in settings.json** (`grep destructive` → no match).
   The No-Delete guard has been inert on this machine.
2. **Stale/dead hook entries in settings.json:**
   - Notification → `$HOME/.config/.claude/notification.sh` — exists nowhere, not even in
     the repo. Path shape (`.config/.claude`) looks like a typo for `$HOME/.claude/`.
   - PostToolUse → `open -a 'MacDown 3000'` — macOS-only; `open` is absent on Arch, so it
     fails on every Write/Edit. Cross-platform violation per repo standards.

### Plan

**A1 — dotfiles: make the `cd` wrapper safe in command substitution** (`config/shell/aliases.sh:13`)
```bash
# Auto-ls after cd. Guarded on stdout being a terminal: inside command
# substitution ($(cd x && pwd)) the listing is captured as data and silently
# corrupts the caller's variable.
cd() {
    builtin cd "$@" || return
    if [ -t 1 ]; then lsd; fi
}
```
Also preserves `cd`'s exit status on failure (current `&&` form already did, but the
explicit `|| return` keeps it true once the body grows).

**A2 — nuvemlabs/secrets source repo: harden the path detection** (`~/repos/secrets/secrets.sh:32`)
Per the External Dependency rule, fix at SOURCE, then re-install — never edit
`~/.local/lib/secrets/`.
```bash
SECRETS_DIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%x}}")" >/dev/null 2>&1 && pwd -P)"
```
`builtin` bypasses any user `cd` function (works in bash and zsh); `>/dev/null` on the
`cd` alone still lets `pwd` write to stdout. Defense in depth with A1.
Then: `./install.sh --secrets` to redeploy, and verify `diff -r` source vs installed.

**B1 — install the missing hooks**
`./install.sh --memory-hooks --logging-hooks --claude-azdo-pipeline-hooks`
(all three dry-run clean). Then re-run the 13-path existence check; expect 0 MISS
except the two dead entries in B2.

**B2 — repair settings.json** (needs decisions, see Open Questions)
- Register + install `destructive-ops-guard.sh` as a PreToolUse Bash hook so CLAUDE.md's
  No-Delete Rule is actually enforced.
- Resolve the `notification.sh` entry (remove, or point at a real script).
- Resolve the MacDown PostToolUse entry (remove, or make it platform-guarded).

**B3 — close the gap that caused this**
`installers/claude.sh` already auto-invokes the pipeline-hooks installer. Extend the same
dependency pattern to `logging-hooks.sh` and `memory-hooks.sh`, OR flip them `on` in the
`--all` path, so `~/.claude/hooks/` can never again be empty while settings.json
references it. (Scope decision required.)

**Verification**
- `script -qec "zsh -i -c 'echo OK'" /dev/null` and the bash equivalent → zero stderr.
- `secrets-doctor` if present; otherwise assert `SECRETS_DIR` is a single clean path.
- Re-run the 13-hook existence + executability check.
- `tests/test-pipeline-hooks.sh`, `tests/test-pipeline-validator.sh`, `tests/validate-symlinks.sh`.
- `./install.sh --secrets` idempotency: run twice, second run no-ops.

### Decisions (user, 2026-09-19) — PLAN APPROVED
1. **A2**: do BOTH A1 + A2, commit in both repos.
2. **notification.sh**: repoint to `$HOME/.claude/hooks/notification.sh` and supply the script
   (cross-platform notify-send → osascript → no-op; best-effort, always exit 0).
3. **MacDown PostToolUse**: remove the entry.
4. **B3**: extend `installers/claude.sh` to auto-invoke logging-hooks and memory-hooks too,
   reusing the existing pipeline-hooks dependency pattern.

### Log
- 2026-09-19: Root causes traced and reproduced (see above). Plan approved.
- 2026-09-19: Dispatched two parallel agents. Track A = aliases.sh cd guard + secrets.sh:32
  hardening. Track B = settings.json repair (destructive-ops-guard registration,
  notification.sh, MacDown removal) + claude.sh dependency wiring + repo CLAUDE.md update.
  Both dispatched with hard no-git-mutation constraints; lead performs all git ops and
  runs all installers (per 2026-05-01 sub-agent dispatch hygiene lesson).
- 2026-09-19: **Issue A RESOLVED + VERIFIED.** aliases.sh cd() tty-gated; secrets.sh:32
  hardened with `builtin cd ... >/dev/null && pwd -P`, committed at source as
  `d189c16` in ~/repos/secrets (not pushed), redeployed via `./install.sh --secrets`,
  installed copy diff-identical to source. Real `zsh -i` and `bash -i` under a PTY now
  emit zero stderr. Hardened library resolves correctly even with a hostile cd wrapper
  in scope (proven in both shells). `--secrets` re-run is idempotent.

- 2026-09-19: **CRITICAL defect found in `installers/memory-hooks.sh` (blocks B1).**
  `update_settings_json` merges with `.hooks = (.hooks // {}) * $new_hooks`. jq's `*`
  recurses into objects but REPLACES arrays wholesale, and every hook event is an array.
  Reproduced by replaying the installer's own dry-run `$new_hooks` against the current
  settings.json: PreToolUse collapses 5 hooks -> 1 and these 8 registrations vanish:
  destructive-ops-guard.sh, pipeline-guard.sh, pipeline-trigger-guard.sh,
  pipeline-registry-write-guard.sh, logging/user-request-logger.sh, and
  logging/session-goal-tracker.sh (x3: SessionStart, SessionEnd, UserPromptSubmit).
  Because `~/.claude/settings.json` is a symlink, this lands in the TRACKED repo file.
  `./install.sh --memory-hooks` MUST NOT be run until fixed — explicit invocation is
  exactly as destructive as auto-invocation. `installers/logging-hooks.sh` is by
  contrast safe: `if == null` guards plus `unique_by(.command)`.
  Dispatched to track-b as tasks 6 (order-preserving append/dedupe merge + wire into
  claude.sh) and 7 (hermetic regression test).

- 2026-09-19: Runtime gap — `notify-send` ABSENT on this machine (no libnotify), so the
  new Notification hook would silently no-op. dunst IS installed and running as the
  daemon. No code change needed: `installers/tools.sh` already declares
  `notify-send|libnotify|libnotify-bin|libnotify` for non-Darwin. Operational fix only:
  install libnotify. Needs user action (sudo).

## In Progress: Investigation-traceable installation logging (2026-09-18)

### State
- **Status**: NEEDS_PLAN_APPROVAL
- **Branch**: main

### Goal
Installation runs currently leave zero persistent record (audit confirmed: no tee/redirect/log-file anywhere; only artifacts are `~/.dotfiles_pkg_manager` and orphaned backup dirs). Make installs verbose and investigation-traceable: a persistent per-run log with timestamps, run context, per-component framing, real exit codes, and truthful success/failure reporting.

### Audit findings (agent sweep + spot-checked by lead)
1. **No file logging exists.** All `log_*` helpers (lib/install-common.sh:22-54) print to terminal only; `log_error` is the sole stderr writer. No timestamps anywhere — only elapsed durations (install.sh:641).
2. **CRITICAL — failure accounting is dead.** `run_installer` (install.sh:627-646) runs `$func`, then `SCRIPT_DIR=…`, then the timing `log_info` — so it always returns 0. Every `|| { ((failures++)) }` branch and `_run_step`'s counter never fire on real installer failures. The exit code of `./install.sh` is a lie.
3. **Logs would lie today — success asserted without verification:** `ln -s` unchecked then `[OK] Linked` (install-common.sh:128-129); secrets external installer rc unchecked then `[OK] Installed` (secrets.sh:51-52); `claude --version` failure prints `installed` (claude.sh:69); four `$(jq …)`-merge sites can truncate settings.json to 0 bytes and still print `[OK] Updated` (logging-hooks.sh:172, memory-hooks.sh:250, claude.sh:135, mcp.sh:142); dialog mode prints `Installation complete!` unconditionally (install.sh:537).
4. **No run context recorded:** command line, mode, OS/distro, package manager (silent when cached), repo git SHA/dirty state, user/host, tool versions — none captured.
5. **Attribution impossible:** package-manager output raw and unframed; `install_packages_fast` discards batch rc via `|| true` (install-packages.sh:507-515); only one exit code is ever printed in the whole tree.
6. **~30 suppression sites** discard error causes (memory-hooks curl ×21 files, tmux source-file, hyprctl reload, jq probes, …). Full inventory in audit report.
7. **Structural:** everything dispatches via `source` into one process → a single capture point is feasible; but dialog-ui writes to /dev/tty and returns selections on stdout → global fd redirect is hostile to dialog mode. 17/20 installers have standalone self-run guards (bypass install.sh entirely). Three installers double-run via unguarded `main "$@"` (mcp.sh:284, memory-hooks.sh:408, logging-hooks.sh:249). `claude-azdo-pipeline-hooks.sh:30` leaks `set -euo pipefail` into the whole run when sourced.

### Plan

**Phase A — persistent capture (new `lib/install-log.sh`, sourced by install-common.sh)**
- A1. `install_log_init`: create `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/logs/install-<YYYYmmdd-HHMMSS>-<pid>.log`; export `DOTFILES_LOG_FILE`; re-init guard so sourced installers reuse the run's log; works for standalone `bash installers/x.sh` runs via their self-run guards. Print log path at run start and end. Retention: prune to last 20 logs.
- A2. Dual-write `log_*` helpers: terminal output unchanged (colored); file gets `<ISO-8601 ts> [LEVEL] [component] msg`, color-free. Component tracked via a `_LOG_COMPONENT` var set by run_installer. Honor `NO_COLOR`.
- A3. Run-context header (once per run): argv, mode (cli/dialog/non-interactive), user@host, `uname -srm`, os-release ID/VERSION, package manager + source (cache/prompt), repo `git rev-parse HEAD` + branch + dirty flag, versions of git/curl/jq/node/tmux/zsh when present, HOME/CWD.
- A4. `run_logged <label> <cmd…>` wrapper: frames external commands (`BEGIN <label>` / `END <label> rc=N dur=…`), tees their raw output into the log while showing it live. Applied to package-manager calls in install-packages.sh and heavy externals (git clone, curl|bash, npm -g, brew bundle, make, TPM). No global `exec` fd redirect → dialog mode unaffected.
- A5. Per-component framing in `run_installer`: `=== BEGIN <component> (<installer>::<func>) ===` / `=== END <component> rc=N (<dur>) ===` — covers _run_step, CLI single-flag, and dialog paths uniformly.
- A6. End-of-run summary to terminal AND log: per-component status + rc + duration; failed list with reasons; log file path.

**Phase B — exit-code integrity (a verbose log must not lie)**
- B1. Fix `run_installer` to capture `$func`'s rc immediately and return it (resurrects all failure accounting; finding 2).
- B2. `create_symlink_with_backup`: check `rm`/`backup_item`/`ln -s`, log cause on failure, return nonzero; callers count failures.
- B3. Fix the four `$(jq)`-merge truncation sites: verify jq rc before writing settings.json.
- B4. secrets.sh:51 — check external installer rc; claude.sh:69 — report failed version probe honestly.
- B5. `install_packages_fast`: log batch rc instead of `|| true` silence; per-package fallback logged as such.
- B6. Capture (not suppress) error causes at high-value sites: memory-hooks curl downloads (log URL + error), tmux.sh:50/54 source-file errors → log, hyprctl reload errors → log.
- B7. Dialog mode: wire run_installer results into failure accounting; make `Installation complete!` conditional.

**Phase C — flagged for separate work (NOT in this change; user to scope)**
- Double-run `main "$@"` in mcp/memory-hooks/logging-hooks (corrupts settings.json.bak).
- `set -euo pipefail` leak from claude-azdo-pipeline-hooks.sh when sourced.
- Backup manifest lifecycle broken → `--restore` cannot restore most backups; `tail -r` BSD-only breaks cleanup on Linux.
- `--brew` failure mislabeled `tools` (install.sh:763-767); mcp.sh `exit 1` kills whole run when sourced; browsh.sh dead/broken.

**Verification**
- V1. New hermetic `tests/test-install-logging.sh` (sandbox HOME): log created; header fields present; BEGIN/END rc framing; injected failure → rc≠0 in log AND process exit code; NO_COLOR/pipe → clean file.
- V2. Fix test-docker.sh:55 (currently discards the entire second install's stdout and its exit code via `2>&1 >/dev/null;`).
- V3. Docker e2e on Arch (`tests/test-docker.sh arch`) asserting a complete, parseable log from `--all`.
- V4. `tests/validate-symlinks.sh` still green; atomic commits per phase step.

### Log
- 2026-09-18: Explore agent full logging audit (install.sh, lib/, installers/, tests/) — no file logging confirmed; suppression inventory ~30 sites; structural map of entry points. Lead spot-checked: install-common.sh:105-131, install.sh:530-540/627-646, secrets.sh:48-53, pipeline-hooks set line — all confirmed. Lead found finding 2 (run_installer always returns 0) during spot-check.
- 2026-09-18: Blueprint written. Status → NEEDS_PLAN_APPROVAL.

---

## In Progress: Keybinding sweep on Arch/Hyprland/kitty (2026-09-18)

### State
- **Status**: DONE (plan approved by user 2026-09-18; all 5 steps executed, verified, committed: 8873b28, cea2609, b9ae401 + docs/tests commit)
- **Branch**: main

### Goal
User reports keybindings "not working as expected" on Arch + Hyprland + kitty. Sweep all layers (Hyprland → kitty → tmux → shell), report working vs broken per binding, identify root causes.

### Plan (sweep)
1. Enumerate live env: kitty config state, Hyprland binds, tmux linkage. [done]
2. Explore agent: decode hyprland.lua binds, tmux.conf key table, shell bindings.
3. Live tests: kitty --debug-config on repo kitty.conf (Linux build validity); tmux byte-sequence injection on throwaway session (C-e prefix, shift-arrows).
4. Cross-layer conflict matrix (Super grabs vs kitty cmd+ table).
5. Report + remediation plan → NEEDS_PLAN_APPROVAL.

### Sweep results (2026-09-18)
- **XKB**: `ctrl:swap_lalt_lctl` ACTIVE and intentional (user: mac cmd-position muscle memory). Left-side only. Duplicate `kb_options` lines in hyprland.lua (:228 empty, :230 real).
- **tmux**: 13/13 live PTY byte-injection tests PASS on real server (prefix C-e, S-Left/Right window nav, S-Up/Down session switch, C-S-Left/Right swap, C-hjkl + M-hjkl pane nav, popups C-q/C-a/C-w/C-s all registered). Gap: copy-mode yank has only pbcopy/clip.exe branches; Wayland relies on OSC 52 only.
- **kitty**: `~/.config/kitty/` empty dir → stock defaults; repo kitty.conf never linked (`--terminals` not run since file added Sep 17; installer verified to handle empty dir via backup). Configless effects: font = Noto Sans Mono (MesloLGS NF installed but unused → p10k glyphs broken), TERM=xterm-kitty (tmux RGB override targets xterm-256color only). Repo kitty.conf itself is unfit for Linux: cmd+ table parses as SUPER (verified via kitty config loader, mods=8) → ~26 maps dead under Hyprland grabs; clear_all_shortcuts would kill working defaults; cmd+v paste dead (SUPER+V grabbed) → no paste at all; SF Mono absent (ghostty config deliberately dropped it).
- **Hyprland**: stock example lua + small customizations. Working: SUPER+{Q,C,E,V,P,S,hjkl,arrows,1-0,SHIFT+1-0,SHIFT+h/l,mouse}, media/brightness (wpctl/brightnessctl/playerctl present). BROKEN: SUPER+R double-bound (launcher + resize submap) AND hyprlauncher NOT installed → no app launcher at all; SUPER+M exit — hyprshutdown missing + malformed fallback (`hyprctl dispatch 'hl.dsp.exit()'` = invalid dispatcher) → cannot exit Hyprland by key. Missing: screenshot binds (grim/slurp installed, unbound), clipboard history (cliphist absent), lock. Config NOT managed by dotfiles.
- **zsh**: fzf owns C-r/C-t (working); zshrc:54 ^R bind is dead code (fzf overrides); ^A/^E unreachable inside tmux (root C-a popup / prefix C-e) — accepted tradeoff, same on macOS.

### Plan (remediation — BLUEPRINT, awaiting approval)
1. **Keep the XKB swap** (endorsed: it is the Linux analogue of the ghostty super+key table, implemented at the correct layer). Clean duplicate kb_options line.
2. **Bring Hyprland config into dotfiles** (`config/hypr/` + installer + symlink): fix SUPER+M exit fallback, resolve SUPER+R conflict (resize submap → SUPER+SHIFT+R; SUPER+R → launcher after choosing/installing one, e.g. fuzzel/wofi), add grim+slurp screenshot binds; optional cliphist.
3. **Rewrite `config/kitty/kitty.conf` for Linux**: drop super/cmd table, clear_all_shortcuts, macos_* options; set font MesloLGS NF, term xterm-256color, scrolling QoL (shift+page/home/end); then run `./install.sh --terminals` to link.
4. **tmux**: add wl-copy copy-mode branch for Wayland.
5. Verify e2e (fresh kitty window: glyphs, prefix, popups, window nav; hyprctl binds re-dump), update workflow_state, commit atomically per component.

### Log
- 2026-09-18: Recon: `~/.config/kitty/` is an EMPTY DIR (not symlink) → kitty runs stock defaults; repo `config/kitty/kitty.conf` (Sep 17, macOS-translated from ghostty) never delivered. `~/.config/hypr/hyprland.lua` = autogenerated example config (slightly customized: SUPER+hjkl focus). Hyprland grabs SUPER+{Q,C,M,E,V,R,P,S,hjkl,arrows,0-9,shift variants} — conflicts with kitty.conf cmd+ table (cmd=Super on Linux). ~/.tmux.conf correctly symlinked. SF Mono font absent. No wtype/ydotool for compositor-level injection.
- 2026-09-18: Explore agent decoded hyprland.lua/tmux.conf/zsh/installers (full report in session). Live tmux PTY sweep 13/13 PASS (script: scratchpad/tmux_key_sweep.py; throwaway sessions kbsweep/kbsweep2, cleaned up). kitty.conf parsed with kitty's own loader: 0 bad lines, cmd≡super (mods=8) on Linux. Verified live: kb_options swap active, hyprlauncher/hyprshutdown/cliphist MISSING, dolphin/wpctl/brightnessctl/playerctl/wl-copy/grim/slurp present. fc-match monospace = Noto Sans Mono; MesloLGS NF installed. User confirmed swap is intentional (mac cmd position); open to better solution → recommendation: keep swap.
- 2026-09-18 (CONSTRUCT, plan approved): Step 1 — config/hypr/hyprland.lua (faithful port + fixes: wofi launcher on SUPER+R, resize submap → SUPER+SHIFT+R, SUPER+M → hl.dsp.exit(), kb_options deduped w/ intent comment, SHIFT+l workspace scroll normalized to e+1, Print/SHIFT+Print grim+slurp binds), installers/hypr.sh (Linux guard, dep warnings, live hyprctl reload), install.sh wired (--hypr, --all flow, dialog, verify manifest, help). Ran --hypr: backup+symlink+reload OK; verified configerrors empty, swap kept, single SUPER+R, Print binds live, screenshot command e2e OK (file + wl-copy). Commit 8873b28 (repo-local git identity set: Daniel Paiva <danielpmo@gmail.com>, matching history; machine had none). Step 2 — kitty.conf rewritten for Linux (no super table, no clear_all_shortcuts, no macos_*, MesloLGS NF, term xterm-256color, shift+page/home/end scrollback; kitty parser: 0 bad lines, defaults intact); --terminals run (backup empty dir + symlink), all 4 live kitty instances reloaded via SIGUSR1. Commit cea2609. Step 3 — tmux.conf Wayland clipboard block (wl-copy, after WSL block); reloaded live server; e2e: copy-mode y → wl-paste PASS. Commit b9ae401. VERIFY — tmux sweep re-run 13/13 PASS; tests/validate-symlinks.sh extended (kitty, hypr Linux-only, source checks) → 23/23 PASS; CLAUDE.md --hypr documented.

---

## In Progress: Clean claude exit on tmux restart + fastfetch once per boot (2026-09-08)

### State
- **Status**: DONE (phase 1 committed 2026-09-16: 1e3cbde, e2b4d63; phase 2 = /rename before /exit, backburner)
- **Branch**: main

### Decisions (2026-09-16)
- Phase 1 = plan below as written. `/rename` before `/exit` is BACKBURNER (phase 2).
- Trigger: `prefix` + `C-q` (Ghostty forwards cmd+q as \x11) and `prefix` + `M-q`; `prefix+q` stays the claude popup. Must resurrect-save AFTER claude exits, BEFORE kill-server.
- fastfetch: once per boot (fastfetch is being phased out anyway).
- Issue-15 WIP (tmux.conf plugins, `ff` alias) stashed as `issue-15 wip`; `git stash apply` after commit.

### Goal
1. `tmux-restart`: exit every running interactive `claude` cleanly (so it prints its `claude --resume <id>` hint into the pane), resurrect-save, then `kill-server`, so `cres` / `prefix+R` works after `start` restores the layout.
2. fastfetch banner prints only on the first interactive shell after boot, not on every pane/restore.

### Plan
1. `util-scripts/tmux-restart.sh`: enumerate panes whose process tree contains `claude`; per pane `send-keys C-c`, then `/exit` Enter; poll until claude gone (timeout, configurable); run resurrect `save.sh`; `kill-server`. Refuse/abort list on timeout unless `--force`.
2. `config/tmux/tmux.conf`: `bind C-q` and `bind M-q` → `confirm-before` → `run-shell -b '~/repos/dotfiles/util-scripts/tmux-restart.sh'`.
3. `config/shell/tmux.sh`: `alias trs='~/repos/dotfiles/util-scripts/tmux-restart.sh'` for use from an outer shell.
4. `config/zsh/zshrc` fastfetch block: keep daily cache; print only when a boot-id marker in `$XDG_CACHE_HOME` differs from current boot id (`sysctl -n kern.boottime` / `/proc/sys/kernel/random/boot_id`), then update marker.
5. Tests: `tests/test-tmux-restart.sh` against a throwaway tmux socket (`-L`) with a fake `claude` script that prints the resume hint on `/exit`.

### Log
- 2026-09-08: explored `cres` (aliases.sh:102), fastfetch block (zshrc:167), tmux.conf (no kill-server binding, resurrect capture-pane-contents on), docs on Claude Code exit semantics (transcripts written incrementally; no external graceful-exit IPC; SessionEnd fires on SIGTERM).
- 2026-09-16: Phase 1 implemented (uncommitted). New `util-scripts/tmux-restart.sh` (pane discovery via `ps -Ao pid=,ppid=,args=` tree walk in awk, `(^|/)claude( |$)`; C-c → [Escape i if vimMode] → `/exit` Enter; poll to `TMUX_RESTART_TIMEOUT`; `--force`/`--dry-run`/`-L`; resurrect save.sh run with `TMUX=<socket_path>,<pid>,0` so -L/out-of-tmux invocations save the right server; kill-server last). `tmux.conf`: `bind C-q` + `bind M-q` → confirm-before → run-shell -b (M-q verified unused in prefix table). `tmux.sh`: `trs` alias. `zshrc`: fastfetch gated on boot id (`/proc/sys/kernel/random/boot_id` | `sysctl -n kern.boottime`) vs `$XDG_CACHE_HOME/fastfetch-boot-id`, block wrapped in `# fetch-banner:begin/end` markers for the test; bashrc has no fastfetch block (uses show-start) → untouched. Help popup + tips updated. `tests/test-tmux-restart.sh`: 29 PASS / 0 FAIL (no-server, dry-run, happy path incl. resume hint in saved contents, timeout, --force, vimMode, fastfetch gate ×3). `bash -n`/`zsh -n` clean; tmux.conf loads on a throwaway socket.
- 2026-09-16 (fix after real-claude smoke test): resurrect save was skipped in production because tmux.conf's `set-environment -g TMUX_PLUGIN_MANAGER_PATH '~/.tmux/plugins/'` reaches run-shell as a literal tilde. `tmux-restart.sh` now resolves the plugin path like TPM (server `show-environment -g` → process env → `$HOME/.tmux/plugins`), expands a leading `~`, strips a trailing `/`; a missing save.sh is now fatal (exit 1, server left running) unless `--force`; `--dry-run` reports the resolved save.sh path. Tests: 3 new groups (tilde+slash env, path read from server set-environment with process env unset, server env precedence, missing save.sh with and without --force); test server now starts with `-f /dev/null` + scrubbed client env so the user's tmux.conf/TPM never leak into the suite. Suite: 44 PASS / 0 FAIL. Real-server `--dry-run` resolves `/Users/daniel/.tmux/plugins/tmux-resurrect/scripts/save.sh`.
- 2026-09-16 (retry loop after real-claude probe): a `/exit` typed ~0.3s after C-c is swallowed while claude re-renders the interrupt. `tmux-restart.sh` now re-sends only `/exit`+Enter (never a second C-c: that is the double-Ctrl-C hard exit, which skips the hint) every `TMUX_RESTART_RETRY` s (default 5) to panes still running claude, logging `attempt N`; defaults raised to `TMUX_RESTART_KEY_PAUSE=1`, `TMUX_RESTART_TIMEOUT=30`. Header notes: empty session exits without a hint (expected); regex also matches `claude --chrome-native-host` but only pane descendants count. Test: fake claude that swallows the first `/exit` → exit 0, exactly one retry logged, hint saved; stuck/--force cases keep `TIMEOUT=2` and assert no retry fires. Suite: PASS: 50  FAIL: 0; `bash -n` clean.
- 2026-09-16 (single-pane test mode): `tmux-restart.sh --pane <id>` (repeatable) runs the same C-c → `/exit` → retry/timeout sequence on just the given pane(s), then stops: no resurrect save, no kill-server; unknown pane id → exit 1; pane without claude → warning + exit 0 (safe on a plain shell); `--force` rejected with `--pane`; `--dry-run --pane` lists only those panes and states it would neither save nor kill; success prints `claude exited in %N; prefix+R (cres) resumes it`. `tmux.conf`: `bind X` → confirm-before → `run-shell -b '... --pane #{pane_id}'` (X verified unused; `x` kill-pane untouched). Help popup + tips updated. Tests: 26 new checks (two-claude-pane isolation incl. other pane never receives `/exit`, hint printed in targeted pane, dry-run, --force rejection, unknown id, plain-shell no-op, stuck timeout leaves server). Suite: PASS: 77  FAIL: 0; `bash -n` clean; tmux.conf loads and `list-keys` shows `prefix X`.
- 2026-09-16 (real-claude e2e): `tests/e2e-tmux-restart.sh` (opt-in via `E2E_TMUX_RESTART=1`, else SKIP/exit 0; exit 2 on missing prereqs) drives the REAL `claude` + REAL resurrect save.sh on a `-L e2e-tmux-restart-$$ -f /dev/null` server with a temp `@resurrect-dir`, `set-environment -g TMUX_PLUGIN_MANAGER_PATH '~/.tmux/plugins/'` (tilde path exercised), claude cwd `~/.cache/tmux-restart-e2e`, trust-prompt handler (Down+Enter), CLAUDE* env scrubbed from the server (inherited `CLAUDE_CODE_CHILD_SESSION` turns transcript saving OFF → no resume hint; first run failed on exactly this), ANSI stripped before matching archive contents (save.sh captures with `-e`), default resurrect dir checked for our session name (tmux-continuum autosaved the default server mid-run; `last` change alone is not a failure). Scenarios: idle+1 turn → hint saved; mid-turn → hint saved, retry fired once; empty session → no hint (soft); `--pane` round-trip → other claude untouched, no save, `claude --resume <uuid>` from cres regex restores the conversation (TOKEN_A visible, TOKEN_B absent). Run: PASS 29 / FAIL 0, 70s wall. Also fixed `tmux-restart.sh` vim detection: user settings use `"editorMode": "vim"` (not `"vimMode": true`) → now detects both (+3 hermetic cases). Hermetic suite: 83 PASS / 0 FAIL. `cres` itself is not typed in the e2e: pane shells have no rc files and cdang's `--rc --dangerously-skip-permissions` are unwanted in a test.

---

## In Progress: Features & benefits documentation (2026-07-30)

### State
- **Status**: CONSTRUCT
- **Branch**: main (docs-only, reversible)

### Goal
Document the features the dotfiles provide and the concrete workflow benefits
of each — the "why it matters" companion to the README's "what it is".

### Plan
1. Explore agent inventories all user-facing features: tmux binds +
   util-scripts, shell aliases/functions, git niceties, Claude Code
   commands/skills/agents/hooks, machine lifecycle, nvim highlights, extras.
2. Write docs/features-and-benefits.md organized by workflow benefit
   (terminal workflow, AI-assisted dev, safety nets, portability,
   reproducible setup) — each feature: trigger, what it does, benefit.
3. Link it from README.md.

### Log
- 2026-07-30: Inventory agent dispatched.
- 2026-07-30: Inventory returned (tmux binds+scripts, shell layer, git,
  Claude hooks/commands/skills, lifecycle, nvim, ghostty/kitty extras).
  Wrote docs/features-and-benefits.md (8 benefit-led sections). Fixed my own
  README error: floax listed as active plugin but it's commented out in
  tmux.conf — replaced with the real active set; linked the new doc from
  README. Spot-verified rm()→~/bin, `*`→q ZLE widget, C-q popup bind.
- **Status**: COMPLETED (staged with previous docs work)

---

## Completed: Documentation review & README overhaul (2026-07-29)

### State
- **Status**: CONSTRUCT
- **Branch**: main (docs-only change, reversible)

### Goal
Review the repo, bring the main README.md in line with reality (install.sh
flags, directory structure, features), and tighten supporting docs.

### Plan
1. Explore agent audits docs vs code (install.sh flags, installers/, config/,
   docs/, tests/) — identify stale claims, missing coverage, duplication.
2. Rewrite README.md: correct the flag list and directory tree, add missing
   features (MCP sync, `q` quick-query, agent teams, pipeline guards, test
   harness, fonts/casks/llm installers), keep it lean — deep detail stays in
   CLAUDE.md / docs/.
3. Fix any stale statements found in docs/*.md only if clearly wrong (no
   scope creep).

### Log
- 2026-07-29: Audit dispatched; README read. Awaiting audit report.
- 2026-07-29: Audit returned — README covered 11/23 flags, `--secrets`
  description stale in 3 places, directory tree/features incomplete.
  Spot-checked contested claims: secrets.sh confirmed keychain-migration;
  claude.sh:151-163 confirmed it DOES auto-run pipeline hooks (audit's doubt
  on CLAUDE.md was wrong, claim kept).
- 2026-07-29: Fixed stale `--secrets` text in install.sh:16, install.sh:590,
  CLAUDE.md:24. Rewrote README.md: two-phase model, all 23 flags grouped,
  design-principle section, secrets/keychain, `q`, MCP sync, agent hooks,
  test harness, corrected tree, post-install now uses secret_set. Verified
  tmux keybind claims against tmux.conf and all relative links resolve.
- **Status**: COMPLETED (uncommitted; note docs/terminal-agnostic-config.md
  is untracked — README links dangle on GitHub until it's committed)

---

## Completed: Interactive Claude pane picker (2026-07-12)

### State
- **Status**: COMPLETED
- **Branch**: main

### Goal
Replace the passive Claude-processes corner monitor (Cmd+e i) with an
interactive picker: select a running Claude and jump to its session/window/pane.

### Plan (approved)
1. NEW `util-scripts/tmux-claude-picker.sh` — fzf over panes with a claude
   child process (detection logic carried over from show-claude-processes.sh);
   preview = live `tmux capture-pane` of the highlighted pane; Enter =
   select-window/select-pane/switch-client; ctrl-r = reload list; `--list`
   mode feeds the reload binding. fzf PATH guard for popup shells.
2. EDIT `config/tmux/tmux.conf` — `prefix C-i` / `prefix i` now
   `display-popup -E` (top-right, 80%x70%) running the picker.
3. DELETE `util-scripts/tmux-claude-corner.sh`, `util-scripts/show-claude-processes.sh`
   (dead after replacement). `tmux-corner-pane.sh` kept as generic utility.

### Log
- 2026-07-12: Script created; `--list` verified against 12 live Claude panes;
  capture-pane preview verified (ANSI ok); config reloaded; both bindings
  confirmed via `tmux list-keys`. Interactive Enter-jump path needs a manual
  user test (can't drive fzf/switch-client without hijacking the live client).
- 2026-07-12 (fix 1): user got a persistent blank popup. Root cause: tmux
  global env carries `FZF_DEFAULT_OPTS=... --tmux center,75% ...`, so fzf
  tried to open a *nested* tmux popup inside display-popup and wedged.
  Fix: unset FZF_DEFAULT_OPTS/FZF_DEFAULT_OPTS_FILE/FZF_DEFAULT_COMMAND in
  the picker — it owns all its flags. Verified fzf renders in popup.
- 2026-07-12 (fix 2): slow open (~1.2s) — old detection spawned
  pgrep+xargs+ps per pane. Replaced with one `ps -axo ppid=,comm=` pass
  joined against pane pids: 0.18s (6.5x). No spinner needed.
- 2026-07-12 (vi mode): picker now opens in vi normal mode — prompt is the
  mode state ([N]/[I]); transform bindings on j/k/i/esc consult $FZF_PROMPT.
  Esc from insert keeps the filter; esc from normal closes. All 8 key/mode
  transform outputs verified.

---

## Paused: Claude Session Summary Viewer (TUI) + Summarizer Improvements (2026-06-29)

### State
- **Status**: NEEDS_PLAN_APPROVAL
- **Phase**: Blueprint
- **Branch**: main (will branch before construct)

### Problem
The `response-summarizer.sh` Stop hook writes per-session `summaries.log`
(1552 sessions to date) into `~/repos/dotfiles/tmp/claude/sessions/`, but
**nothing reads them**. The `conversation-history` skill is an empty stub.
Goal: a TUI viewer launched via tmux popup so the user can quickly recall the
last context of any past session; then improve what the summarizer captures.

### Plan
**Part A — TUI viewer (build first)**
1. NEW `config/claude/scripts/claude-sessions.sh`:
   - List source = parse session **folder names** (`{project}_{date}_{time}_{id}`)
     → instant, no per-file reads. Sort newest-first.
   - `fzf` picker: fuzzy search over `date │ project │ id` lines.
   - Preview pane = lazily read that session's `summaries.log` (jq → AI summary,
     tools, files), `goals.log`, `requests.log`; render via `bat` (markdown).
   - Keys: Enter = exit (read-only), Ctrl-Y = copy latest AI summary (pbcopy),
     Ctrl-O = open session folder, Ctrl-E = open native transcript.
   - Path via `${CLAUDE_SESSIONS_DIR:-$HOME/repos/dotfiles/tmp/claude/sessions}`
     (no magic value; mirrors `lib-session-dir.sh`). `bat`/`batcat` fallback.
2. EDIT `config/shell/aliases.sh`: add `csessions` → `~/.claude/scripts/claude-sessions.sh`.
3. EDIT `config/tmux/tmux.conf`: `bind-key S display-popup -E -w 90% -h 85% '<script>'`.
4. Deps: add `brew "fzf"`, `brew "bat"` to `config/brew/Brewfile`; ensure
   fzf/bat in Linux tools install path. (jq/tmux already present.)
5. Verify scripts symlink path for `config/claude/scripts/` in `installers/claude.sh`.

**Part B — Summarizer content improvements (after A)**
6. EDIT `config/claude/hooks/logging/response-summarizer.sh`:
   - Widen window: last 20→~50 msgs; raise 500-char + 4000-char caps.
   - Sharper prompt: "goal, key decisions, current state, next step" (not generic recap).
   - Save raw last-N messages verbatim (so preview shows the real exchange, not just paraphrase).

### Decisions (defaults chosen, override on request)
- TUI engine: `fzf` + `bat` preview (zero new heavy deps; all installed).
- Launch: tmux `prefix + S` popup, plus `csessions` shell alias.
- List built from folder names for instant load across 1552 sessions.
- Viewer is **read-only** (No-Delete rule); no session mutation.

### Out of scope
- Wiring the `conversation-history` skill (separate follow-up if wanted).
- Rich HTML dashboard; native transcript indexing/search.
- Changing the sessions storage path or folder-naming scheme.

### Log
- 2026-06-29 — Blueprint drafted. Awaiting plan approval.

---

## Active: Claude AZDO Pipeline Hooks Installer (2026-04-30)

### State
- **Status**: CONSTRUCT
- **Phase**: Implementation
- **Branch**: main

### Goal
Add proper installation for the Claude Code Azure DevOps pipeline guard hooks
(`pipeline-guard.sh`, `pipeline-trigger-guard.sh`) so they are symlinked into
`~/.claude/hooks/` automatically, and so any component that depends on them
(agent, command, skill) declares and triggers that dependency.

### Background
- `~/.claude/hooks/` is a real directory (not a symlink) because three different
  installers populate it: `claude.sh`, `memory-hooks.sh`, `logging-hooks.sh`.
  The first two cohabit subdirs (`memory/`, `utilities/`, `logging/`).
- `pipeline-guard.sh` and `pipeline-trigger-guard.sh` were committed to
  `config/claude/hooks/` but never had an installer step — they exist as
  manual symlinks on this machine only.
- `config/claude/settings.json` already registers both hooks under
  `PreToolUse`, and that file is whole-symlinked by `claude.sh`. So no jq
  merge is needed — registration travels with the symlink.

### Plan
1. Create `installers/claude-azdo-pipeline-hooks.sh` (modelled on
   `logging-hooks.sh`; symlinks the two hook files; warns on missing prereqs).
2. Wire `--claude-azdo-pipeline-hooks` flag into `install.sh` (help text,
   dispatch, picker, `--all`).
3. Auto-trigger from `install_claude_config()` in `installers/claude.sh`
   so the agent/command/skill always have their hook dependency.
4. Document the hook dependency in:
   - `config/claude/agents/pipeline-runner.md`
   - `config/claude/commands/pipe-deploy.md`
   - `config/claude/skills/pipeline-ops/SKILL.md`
5. Update project `CLAUDE.md` with the new flag and a one-liner under the
   Claude Code Setup section.

### Decisions
- **Naming**: `claude-azdo-pipeline-hooks` (per user direction).
- **Auto-run from `--claude`**: yes.
- **Settings.json**: not modified at install time.
- **Prereq check**: warn (not fail) if `pipeline-validator.sh` /
  `pipeline-registry.sh` are missing.
- **No formal dependency-resolution framework** — direct invocation +
  human-readable doc strings.

### Out of scope
- New dependency-graph system.
- Changes to `memory-hooks.sh` / `logging-hooks.sh`.
- Reorganisation of `~/.claude/hooks/`.

### Log
- 2026-04-30 — Plan approved by user. Entering CONSTRUCT.
- 2026-04-30 — Created `installers/claude-azdo-pipeline-hooks.sh` (idempotent, --dry-run, warn-on-missing-prereq).
- 2026-04-30 — Wired `--claude-azdo-pipeline-hooks` into `install.sh` (help, dispatch, picker, --all, --flag).
- 2026-04-30 — Added auto-trigger from `install_claude_config()` in `installers/claude.sh`.
- 2026-04-30 — Added Dependencies sections to pipeline-runner.md, pipe-deploy.md, pipeline-ops/SKILL.md.
- 2026-04-30 — Updated project CLAUDE.md.
- 2026-04-30 — Verified: dry-run OK, live run OK, idempotent re-run OK, `--claude-azdo-pipeline-hooks` flag end-to-end OK, syntax check across all touched scripts OK.
- State.Status = CONSTRUCT_COMPLETE — ready for review/commit.

---

## Archived: Open-Source Dotfiles Public Repo Build

## State
- **Status**: CONSTRUCT
- **Phase**: Create reusable learning system from judgment error analysis
- **Previous Work**: Comprehensive error analysis + safety protocols added
- **Scope**: Layer 2 (Learning Skill) + Layer 3 (Reference Docs) - Skip Layer 1 (hooks to avoid bloat)

## Decisions (Approved)
- D1: PATs — revoke AFTER new solution is ready (user decision)
- D2: claude.json — gitignore it, use settings.json for tracked settings
- D3: bash_aliases — referenced in installer/tests, keep but clean (WSL/employer content out)
- D4: GitHub — `nuvemlabs` public, `danielpmo1371` private
- D5: Architecture — Overlay model, lightweight templating, gitleaks
- D6: History — Fresh repo (no surgical scrub)
- D7: Migration — Build public first, test, then clean private. Never break current setup

## Plan: Learning System Integration

### Analysis: Best Approach

After reviewing the previous agent's work, I recommend **OPTION 5: Combination Strategy**

**Rationale:**
1. **Prevention (Hook)**: Catches mistakes BEFORE they happen
2. **Learning (Skill)**: Guides through analysis AFTER mistakes
3. **Reference (Docs)**: Existing docs/learning/ stays as knowledge base

**Architecture:**
- PreToolUse Hook: `file-ownership-guard.sh` - blocks edits to non-repo files
- Skill: `learn-from-mistake` - guides post-mortem analysis
- Supporting: Keep existing docs/learning/ as reference library

### Phase 1: Create Prevention Hook
**File**: `config/claude/hooks/file-ownership-guard.sh`
- Intercepts Edit/Write tool calls
- Validates file is tracked in git or symlinked to repo
- Warns about installation directories
- Provides helpful guidance on finding source
- Exit 0 = allow, exit 2 = block with reason

**Features:**
- Check `git ls-files --error-unmatch <path>`
- Check `readlink -f <path>` for symlinks
- Pattern matching for known install dirs (`~/.local/lib/`, etc.)
- Clear error messages explaining what to do instead

### Phase 2: Create Learning Skill
**File**: `config/claude/skills/learn-from-mistake/SKILL.md`
- Triggers when user says "I made a mistake", "that was wrong", etc.
- Guides through structured analysis process
- Creates documentation in docs/learning/
- Updates CLAUDE.md with new safeguards
- Stores in MCP memory
- Uses previous agent's work as template

**Workflow:**
1. Understand what happened
2. Root cause analysis (mental model failure)
3. Identify red flags that were missed
4. Document proper workflow
5. Create/update safety rules
6. Store in persistent memory
7. Generate summary and analysis docs

### Phase 3: Hook Configuration
**File**: `config/claude/hooks/config.json`
- Add file-ownership-guard to PreToolUse hooks array
- Configure to run before Edit and Write tools
- Set appropriate priority

### Phase 4: Documentation & Integration
- Update CLAUDE.md to reference the new assets
- Update docs/learning/README.md with skill usage
- Create examples in skill directory
- Add to installer (already handled via symlinks)

## File Categorization

### Clean (copy as-is): 140+ files
- config/nvim/* (entire directory)
- config/ghostty/* (entire directory)
- config/tmux/tmux.conf
- config/git/ignore
- config/shell/git.sh, path.sh, tmux.sh, mcp.sh
- config/claude/settings.json, commands/*, skills/*, agents/*, hooks/*, scripts/*
- lib/install-common.sh, install-packages.sh, secrets.sh, dialog-ui.sh, backup.sh
- installers/* (all)
- tests/* (all)
- images/*
- config/nushell/config.nu, env.nu, scripts/*, README.md, QUICK_START.md

### Dirty (need sanitization): ~15 files
- config/shell/env.sh — remove AZDO_ORG value
- config/shell/aliases.sh — remove employer aliases (lines 85-86)
- config/shell/secrets.sh — review PAT export variable names
- config/bash/bash_aliases — strip to useful generic aliases only
- config/zsh/zshrc — check for keychain PAT retrieval
- config/nushell/aliases.nu — remove employer aliases (lines 69-70)
- config/mcp/servers.json — create template version
- config/mcp/README.md — replace private IPs
- config/mcp/mcp-env.template — replace private IPs
- config/claude/hooks/config.json — replace memory-mcp hostname
- azcli-scripts/ado-task — parameterize DEFAULT_ORG
- bootstrap.sh — replace danielpmo1371 with nuvemlabs
- index.html — replace username references
- README.md — rewrite for public
- util-scripts/copy-bootstraph-line.sh — update username

### Exclude (don't copy):
- config/claude/claude.json (gitignored)
- util-scripts/copy-mbie-pat.sh (private only)
- router-backups/* (private only)
- docs/plans/* (planning docs)
- config/claude/settings.json.bak (backup file)
- .bashrc (root level — legacy)
- brew-gadgets.md, term-gadgets.md, todo.md, todos.md, wishlist.md (personal notes)
- issues/* (personal issue tracking)

### New files to create:
- lib/template.sh — lightweight envsubst wrapper
- lib/overlay.sh — private overlay detection
- .gitignore — comprehensive
- .gitleaks.toml — secret scanning config
- LICENSE — MIT
- config/shell/env.local.template — example private env vars
- docs/customization.md — how to personalize

## Private Data Patterns (for agents to scan/avoid)
- `<azdo-org-slug>` (employer)
- `<subscription-a>`, `<subscription-b>` (Azure subscriptions)
- `10.0.0.102` (private IP)
- `192.168.1.107` (private IP)
- `memory-mcp:8000` (private hostname)
- `danielpmo1371` (private GitHub username) — replace with `nuvemlabs`
- `danielpmo@gmail.com` (email)
- Any PAT/token values
- `/c/repos/`, `/mnt/c/Users/daniel.paiva/` (WSL paths)

## Log
- [2026-03-04] Audit complete: identified all private data across 215 tracked files
- [2026-03-04] Planning phase complete: 3 documents in docs/plans/
- [2026-03-04] User approved: from-scratch build, overlay model, gitignore claude.json
- [2026-03-04] Starting Phase 1: Build public repo
- [2026-03-04] Phase 1 COMPLETE: 222 files in dotfiles-public
  - 195 clean files copied
  - 15 config files sanitized (config-builder agent)
  - 10 scripts/entry points sanitized (scripts-builder agent, found bonus fixes in azcli-scripts)
  - 7 new infrastructure files created (infra-docs agent)
  - Full private data scan: ZERO matches
  - Excluded files verified absent (PAT scripts, claude.json, router backups)
- NEXT: Phase 2 — Test public repo (Docker e2e, install.sh validation)
- [2026-03-11] JUDGMENT ERROR ANALYSIS & LEARNING
  - Identified critical error: edited installed library instead of source
  - Created comprehensive analysis: docs/judgment-error-analysis.md
  - Applied proper fix to source repo: ~/repos/secrets/secrets.sh
  - Committed fix to nuvemlabs/secrets repo (commit 2a32583)
  - Reinstalled library to apply fix: ./install.sh --secrets
  - Verified fix works in both bash and zsh
  - Updated CLAUDE.md (project + global) with External Dependency Safety Rules
  - Stored lesson in MCP memory with tags
  - New protocol: Always verify file ownership with git ls-files before editing
- [2026-03-11] LEARNING SYSTEM INTEGRATION (Planning)
  - Analyzed previous agent's excellent work (467+ lines of documentation)
  - Designed combination strategy: Prevention hook + Learning skill
  - Plan created: docs/plans/2026-03-11-learning-system-integration.md (682 lines)
  - User decision: Skip Layer 1 (hooks) to avoid hook bloat
  - Approved scope: Layer 2 (learn-from-mistake skill) + Layer 3 (docs/learning/ enhancement)
- [2026-03-11] LEARNING SYSTEM INTEGRATION (Implementation Complete)
  - Layer 2: Created learn-from-mistake skill (2001 lines total)
    - SKILL.md (451 lines): 8-step guided process, auto-discoverable
    - TEMPLATES.md (438 lines): Copy-paste templates for all doc types
    - REFERENCE.md (681 lines): Detailed guides for each step
    - EXAMPLES.md (431 lines): Real incident from 2026-03-11
  - Layer 3: Enhanced docs/learning/ knowledge base
    - Updated README.md with skill usage instructions
    - Linked to skill templates and examples
    - Made historical incidents easily discoverable
  - Integration: Updated CLAUDE.md (project) with learning skill reference
  - Skill is auto-discoverable: triggers on "I made a mistake", "that was wrong", etc.
  - Total documentation for learning system: 2600+ lines (skill + existing incidents)
- [2026-03-11] CRITICAL FIX: learn-from-mistake Skill Context Issues (COMPLETE)
  - Problem identified: skill uses context:fork but references relative paths without context
  - Used skill-forge to review: validation passes but manual review found context ambiguity
  - Critical issue: Agent in forked context doesn't know it should work in dotfiles repo
  - Affected paths: docs/learning/, CLAUDE.md, workflow_state.md (all relative without anchor)
  - Meta-issue: skill-forge skill exists but wasn't used during creation (ironic!)
  - Created comprehensive review: skill-forge-review-learn-from-mistake.md (185 lines)
  - Applied Priority 1 fixes:
    - Added Environment Context section to SKILL.md (61 lines with repo detection + path table)
    - Updated Step 5 with explicit path examples ($DOTFILES_REPO anchor)
    - Updated Step 6 to distinguish project vs global CLAUDE.md
    - Updated Integration Points with full paths
    - Fixed EXAMPLES.md: removed hardcoded /Users/daniel paths
    - Fixed REFERENCE.md: updated cross-referencing diagram with $DOTFILES_REPO
  - Re-validated: 21 pass, 1 warning (512 lines, acceptable for critical fix)
  - Skill now provides clear context for forked agents
  - Next: Use /learn-from-mistake to document the skill-forge-not-used mistake
- [2026-03-11] TERRAFORM PLAN VERIFICATION FAILURE ANALYSIS
  - Identified critical verification error: 39 destroys in build 270486 (SIT/AE) marked as PASS
  - Created analysis: docs/learning/incident-2026-03-11-terraform-destroys-missed.md
  - Created summary: docs/learning/SUMMARY-2026-03-11-terraform-destroys.md
  - Enhanced iac MEMORY.md with "Terraform Plan Verification Protocol -- HARD GATE" section
  - Updated docs/learning/README.md with incident entry
  - New protocol: Destroy count is FIRST check, >0 = automatic FAIL, no exceptions
  - MCP memory not available for storage (tools not loaded)
  - Project: iac, Story 193236, Branch: feature/193236-Refactor-ServiceBus

## LEARN-FROM-MISTAKE SESSION: Skill-Forge Not Used
- [2026-03-11] Starting systematic learning analysis
- Mistake: Created learn-from-mistake skill without using skill-forge for validation
- Impact: Context ambiguity issues requiring Priority 1 fixes after creation
- Status: Fixed (61+ lines of context setup added)
- Date: 2026-03-11
- Incident analyzed using /learn-from-mistake skill (all 8 steps completed)
- Analysis document: docs/learning/incident-2026-03-11-skill-forge-not-used.md (created)
- Summary document: docs/learning/SUMMARY-2026-03-11-skill-forge.md (created)
- Safeguard: Skill Creation Protocol added to ~/.claude/CLAUDE.md (Level 2 checklist)
- Documentation: docs/learning/README.md updated with new incident
- MCP memory: Stored with tags (lesson-learned, skill-creation, expertise-bias, etc.)
- Files ready to commit

## SESSION: Homebrew Casks Installer (2026-06-05)
- Goal: Add macOS cask management to dotfiles (gap found after manual `brew install --cask little-snitch`)
- Plan (approved by user): Option 1 - Brewfile + brew bundle
- Actions:
  - Created config/brew/Brewfile seeded from `brew bundle dump --casks` (24 casks + nikitabobko/tap, deduped docker/zulu aliases)
  - Created installers/casks.sh (install_casks: macOS guard, ensure_brew_in_path, brew bundle)
  - Wired install.sh: --casks CLI flag, install_all (after tools), dialog checklist + dispatch + change report, help texts
  - Updated CLAUDE.md: install command, directory structure, casks pattern doc
- Verification:
  - bash -n syntax OK on install.sh and casks.sh
  - `brew bundle check` parses Brewfile; only unmet item = aerospace pending upgrade (genuine drift, expected)
  - --help shows --casks
- Not run: full `./install.sh --casks` (would live-upgrade aerospace window manager mid-session; left to user)

## SESSION: Pipeline commits review + registry doc (2026-07-08)
- Goal: Review today's pipeline-ops harness commits (bd2dac7 validator registry-aware CD validation, 1fff831 pipeline-runner tools) for design soundness; close identified gaps
- Review verdict: both sound — validator consumes pre-existing registry schema (stages.allowed/blocked, cd.id) already used by pipeline-guard.sh and present in ~/repos/td registry; hardcoded PRE/PRD blocklist still runs first; fallback preserves old behavior; agent frontmatter now matches tools its body already required
- Gaps found: (1) td registry untracked [user committed it], (2) no validator tests [design proposed, pending user approval], (3) no registry authoring doc [fixed]
- Actions:
  - Created config/claude/skills/pipeline-ops/REGISTRY.md: schema, consumers, validator check order, silent-fallback + empty-allowed caveats, authoring checklist
  - SKILL.md: replaced drifted hardcoded service-ID table (app-app CI 450 = 2022-inactive) with registry jq query + REGISTRY.md pointer
  - pipe-deploy.md: schema doc pointer in Step 2
  - skill-forge validation: 0 errors; 2 warnings false-positive (multiline YAML description, jq backslashes); added TOC to REGISTRY.md (>100 lines checklist item)
  - Committed f6f7bf0 (docs only; first attempt swept user-staged shell files — reset --soft, split, re-staged them)
- Verification: validate-skill.sh passes; ~/.claude/skills/pipeline-ops/REGISTRY.md live via whole-dir symlink

## SESSION UPDATE: Pipeline validator test suite (2026-07-08)
- Created tests/test-pipeline-validator.sh: 27 hermetic black-box cases (temp workspaces, fixture registries, HOME override); all green
- Coverage: input validation (exit 2 rules), CI approval + branch normalization, hardcoded blocklist supremacy (preae blocked even when registry allows it), registry exact-match (default-deny, case-insensitive, blocked-wins, cd.id fallback, stagesToSkip), prefix fallback, empty-allowed caveat, malformed-registry fail-closed, terraform plan-only (registry-driven + no-registry fallback)
- Empirical finding: unparseable registry aborts hard (exit 5, no decision JSON) instead of falling back — REGISTRY.md caveat corrected
- Committed 439804b (tests + REGISTRY.md fix + CLAUDE.md test-harness entry) via pathspec to avoid sweeping unrelated staged files

## SESSION: Independent re-review of 2026-07-08 pipeline-ops commits (2026-07-09)
- Goal: Verify the registry-aware validation commit set (bd2dac7, 1fff831, f6f7bf0, 439804b) was aligned with harness purpose, not a shortcut/anti-pattern, no cross-repo breakage
- Method: dispatched read-only review agent; empirically probed validator with adversarial registries; ran hermetic test suite
- Verdict: directionally aligned (hardcoded PRE/PRD blocklist still supreme, registry default-deny, docs match code, tests real) BUT 4 confirmed issues:
  1. HIGH: CD allow-authority now lives solely in workspace-writable .claude/pipeline-registry.json — agent (Edit/Write/Bash) can modify it, takes effect uncommitted, no independent code layer for non-pre/prd-substring prod stages (verified: PROD_SHARED_STAGE approved when listed)
  2. MED fail-open: stages.blocked ignored when allowed empty (validator :158 gate skips whole registry branch); papered over in REGISTRY.md prose instead of code fix (verified: blocked sitae approved via prefix fallback)
  3. MED: test suite HOME misbinding (run() :99 — HOME= binds to printf, not validator across pipe) pollutes real ~/.claude/logs/pipeline-validator.log with fake "approved" fixture entries
  4. LOW: validator matches registry by name-first, guard hook by ID-only — name/ID mismatch validates against wrong service
- Status: findings reported to user; fixes NOT applied (awaiting direction)

## Plan (approved by user 2026-07-09): fix the 4 review findings
1. tests: fix HOME misbinding in run() so validator (not printf) gets FAKE_HOME — stops audit-log pollution
2. validator: honor registry stages.blocked unconditionally (before the empty-allowed gate); pin with tests (sitae-in-blocked-with-empty-allowed = BLOCKED)
3. validator: match registry entry by cd.id FIRST (aligns with pipeline-guard ID-only), service name as fallback for ID-less calls; pin with mismatch test
4. structural registry protection: (a) new PreToolUse hook pipeline-registry-write-guard.sh blocking Edit/Write/NotebookEdit/Bash mutations of pipeline-registry.json; (b) validator + pipeline-guard fail CLOSED when a found registry is untracked/modified/outside a git work tree (verified: real td registry is tracked+clean, so no breakage); register hook in settings.json + installer
5. tests: new tests/test-pipeline-hooks.sh covering pipeline-guard.sh, pipeline-trigger-guard.sh, and the new write-guard
Commits: atomic per item, suite green before each; pathspec staging (zshrc is user-dirty)
- Actions (all committed, suites green after each):
  - 9028215 tests: HOME herestring binding — validator suite no longer pollutes real audit log (verified via mtime/line-count)
  - a14bb7f validator: stages.blocked honored unconditionally; REGISTRY.md caveat rewritten; sitae-in-blocked pinned BLOCKED
  - 8e83d05 validator: registry entry matched by cd.id first (guard-aligned); mismatch test pinned
  - ebc15fc structural protection: registry_committed_or_die in validator (CD+terraform) + mirrored check in pipeline-guard; new pipeline-registry-write-guard.sh hook (Edit/Write/NotebookEdit/Bash) registered in settings.json + installer; REGISTRY.md documents enforcement
  - 1e79b86 tests/test-pipeline-hooks.sh: 32 cases across all three hooks incl. dirty-registry fail-closed and no-registry permissive fallback (pinned as known weakness); CLAUDE.md updated
- Verification: 33+32 tests green; live example workspace re-validated (sitae approved, PROD_SHARED_STAGE blocked); installer delivered write-guard symlink; only user-dirty zshrc + this file remain uncommitted
- Remaining known gaps (not in approved scope, surfaced to user): guard skips checks 0-2 with no registry; guard terraform constants (802) still hardcoded; agent-doc diagram claims guard invokes validator; stagesToSkip derived from caller allStages not registry stages.all

## SESSION: Terminal.app font config in dotfiles (2026-07-20)
- Symptom: Nerd Font glyphs/emoji not rendering in macOS built-in Terminal.app
- Diagnosis (empirical): fonts are present (~/Library/Fonts has MesloLGS NF x4 + Hack Nerd Font set); LANG=en_US.UTF-8 OK. Root cause is the profile font — Terminal.app default settings set is "Homebrew", font AndaleMono 12 (confirmed twice: NSKeyedArchiver plist decode AND `osascript ... get font name of settings set "Homebrew"`)
- Constraint discovered: Terminal.app rewrites com.apple.Terminal.plist from memory on quit, so `defaults write` while it runs is silently clobbered. Symlinking prefs is impossible (whole-file rewrite).
- Chosen mechanism: AppleScript against the RUNNING app (`tell application "Terminal" to set font name of settings set <default> to "MesloLGS-NF-Regular"`). Applies live, persists on quit, idempotent. Automation permission already granted on this machine (read-only probe returned rc=0).
- PostScript name resolved via fc-scan: "MesloLGS-NF-Regular" (NSName in the plist is the PostScript name, not the display family "MesloLGS NF")
- Policy check: docs/terminal-agnostic-config.md explicitly lists font/rendering as legitimate layer-4 emulator config. Compliant.

## Plan (NEEDS_PLAN_APPROVAL)
1. installers/terminals.sh: add `install_terminal_app()` — macOS-only guard; resolve the default profile name from `defaults read com.apple.Terminal "Default Window Settings"`; set ONLY the font family via osascript; leave size/colors untouched. No-op + warn (non-fatal) if the font is missing or osascript is denied.
2. Wire it into `install_terminals()` alongside Ghostty/Kitty; no new install.sh flag (runs under --terminals).
3. Font name constant shared with installers/fonts.sh conventions (MesloLGS NF); no new config dir — nothing to symlink, so a config file would be dead weight.
4. Docs: one line in CLAUDE.md terminals section + README if it lists terminals.
5. Verify: re-run osascript read-back to prove font changed; visually confirm glyphs; re-run installer to prove idempotency.
- Explicitly OUT of scope: Terminal.app is 256-color only (no truecolor) — p10k/tmux colors will still be approximated. Not fixing that here.

## Log — 2026-07-20 MCP secret-interpolation verification

Verified `${VAR}` expansion after removing literal PAT from `~/.claude.json`.
- `~/.claude.json` contains no literal credential; `AZURE_DEVOPS_PAT` / `ADO_MCP_AUTH_TOKEN` = `${AZDO_PAT}`.
- Live MCP calls OK: core_list_projects, repo_list_repos_by_project, wit_my_work_items, search_code, pipelines_get_build_definitions.
- `az account show` OK (INZ_TDS_SIT); `az devops project list` OK (AZURE_DEVOPS_EXT_PAT path); `az group list` OK.
- Drift found: 4 `AZURE_DEVOPS_*` env keys exist in `~/.claude.json` but not in `config/mcp/servers.json` (not reproducible on a fresh machine).
- Incident: PAT value echoed into session transcript during verification — rotation recommended.

## Actions (approved 2026-07-20, implemented)
- installers/terminals.sh: added install_terminal_app() (macOS-only guard, dynamic default-profile resolution via `defaults read ... "Default Window Settings"`, osascript sets font family only, non-fatal warn on missing font / denied Automation / unreadable profile); wired into install_terminals(); added summary line. Font constant TERMINAL_APP_FONT="MesloLGS-NF-Regular" (PostScript name).
- CLAUDE.md: documented the font mechanism + 256-color caveat under Key Patterns.
- Verify: bash -n OK; live run set Homebrew profile font; osascript read-back = MesloLGS-NF-Regular; second run idempotent (same OK output, no error). No new config dir, no install.sh flag.
- Status: COMPLETE. Not committed (awaiting user per git-workflow rules).

## Log — 2026-07-29 MCP server pruning (approved by user)

Assessment: transcript analysis (window since 2026-06-07) showed real tool-call usage only for
azure-devops (156 calls), claude-in-chrome extension (109), context7 plugin (14), browser-network (4).
sequential-thinking / fetch / puppeteer had a `u/` package-name typo since first commit (never worked);
browser-local had zero calls and drops connection (needs BrowserMCP extension, not in use).

Actions:
- config/mcp/servers.json: removed sequential-thinking, fetch, puppeteer, browser-local (kept memory, browser-network, azure-devops).
- ~/.claude.json: removed same 4 via `claude mcp remove -s user` (installer only merges, never deletes).
- ~/.claude.json: cleared now-dead disabledMcpServers entries in nuvemlabs.site and archer-pro-active projects.
- config/mcp/README.md: updated server list, noted removals + the merge-doesn't-delete caveat.
- config/claude/CLAUDE.md: dropped sequencial-thinking instruction; replaced "Browser-Tools MCP" /
  "Prefer browse mcp to chrome-for-claude" with claude-in-chrome (local) + browser-network (remote) guidance.
- memory server KEPT: hostname memory-mcp currently unresolvable; user fixing DNS + /etc/hosts separately.

## Log — 2026-07-31 secrets-doctor util-script (approved by user)

Motivation: diagnosing secret propagation kept requiring an ad-hoc three-command pipeline
(env test + keychain grep + secrets.sh grep) whose no-value-leak property was implicit.

Actions:
- util-scripts/secrets-doctor: new single-purpose diagnostic — reports STORE (via secret_list,
  names only) → EXPORTS (config/shell/secrets.sh line) → ENV per key; prefix expansion
  (e.g. PIPELINE_GUARD); derived vars (aliases like AZURE_DEVOPS_PAT) marked n/a for store;
  exit 0 intact / 1 broken / 2 setup error. Never reads secret values — structural guarantee.
- CLAUDE.md: documented under shell features (uncommitted — file already had unrelated WIP hunk).
- Verified: default run (7 keys, all green), prefix match, derived key, bogus key (exit 1),
  env -u AZDO_PAT break detection (exit 1), --help.

## Log — 2026-07-31 secrets-debugging skill (skill-forge)

- config/claude/skills/secrets-debugging/SKILL.md: new skill making secrets-doctor the canonical
  secret-propagation debugging method. Triggers on missing tokens / 401s / keychain questions.
  Contains chain diagram, failure-pattern→fix table, worked example, names-only + no-bypass rules.
- Validated with skill-forge validate-skill.sh: 17 pass, 0 warnings, 0 errors (EXCELLENT).
- Live immediately via existing ~/.claude/skills symlink.
- CLAUDE.md secrets-doctor line extended to reference the skill (still uncommitted with user WIP).

## Log — 2026-07-31 secrets-doctor --probe / --match (approved by user)

- util-scripts/secrets-doctor: opt-in value validation. --probe reads value in-process (bash
  built-ins only: never stdout/argv/child-env) and flags EMPTY / ctrl-chars; --match REGEX adds
  shape check on store+env values, reporting pass/fail only. Default mode unchanged (names-only).
  xtrace defense (set +x) verified: probed value absent from bash -x trace.
- Tested: real keys probe ok*, --match pass/fail (exit 0/1), unknown flag (exit 2), stub-lib
  unit test covering EMPTY / ctrl-chars / ok* branches, default-mode regression.
- skills/secrets-debugging: table gains EMPTY/ctrl-chars row + probe escalation guidance;
  re-validated EXCELLENT.

## Log — 2026-07-31 secrets-doctor moved to nuvemlabs/secrets repo (approved by user)

- util-scripts/secrets-doctor removed: source of truth is now ~/repos/secrets/bin/secrets-doctor
  (commit bf5914f there), installed to ~/.local/bin (already on PATH via path.sh) with chmod +x.
- installers/secrets.sh: already-installed check now also requires ~/.local/bin/secrets-doctor,
  so existing machines pick up the CLI on next ./install.sh --secrets.
- config/shell/secrets.sh: exports SECRETS_EXPORTS_FILE (self-declaration) so the now-generic
  doctor finds the exports mapping from any child process.
- CLAUDE.md + secrets-debugging skill updated to new location + fix-at-source warning;
  skill re-validated EXCELLENT.
- Verified: installer run installs 755 copy; fresh login shell resolves ~/.local/bin/secrets-doctor
  and full chain check passes (exit 0); secrets repo test suite 20/20.

## 2026-09-03 — Terraform apply allowlist: finish uncommitted guard/validator change
State.Status = CONSTRUCT (plan approved by user in session)
### Plan
1. Commit A: existing diff (pipeline-guard.sh Check 4 + pipeline-validator.sh apply policy) + docs (pipeline-runner.md, pipe-deploy.md, REGISTRY.md) + tests for the allowlist path in tests/test-pipeline-hooks.sh and tests/test-pipeline-validator.sh.
2. Commit B: pipeline-guard.sh Check 4 keyed off registry terraform.id of the matched service (covers 810/811), env var kept as fallback; tests for a second terraform pipeline.
3. Do NOT commit out.json (untracked AzDO dump).
### Log
- Dispatched docs agent + tests agent (forks, no git mutations). Git mutations done by lead.
- Commit B design: terraform detection = registry `.terraform.id` of matched service OR env var (fallback); apply stages = `stages.all` names starting with "apply" ∪ env-var stage; destroy-prefixed stages ALWAYS required in stagesToSkip; apply allowed only via applyAllowedEnvironments + deployToggle=deploy + requireManualApproval=True; requireManualApproval also required on plan-only runs when registry defaultParameters declares it (keeps 802 behaviour, doesn't break 810/811 plan runs); terraform pipeline with no discoverable apply stage -> fail closed.
- Commit A committed by user. Starting Commit B.
- TODO (user): ensure a BLOCK always overrides an ALLOW in every layer (registry blocked lists, env blocklist, allowlists) — audit hook + validator precedence, add tests proving block wins.
- Validator precedence audit (read-only, hermetically proven) found allow-over-block violations: V3 applyAllowedEnvironments strips apply* even when in stages.blocked/alwaysSkipStages; V1 registry terraform.parameters.environment.{blocked,allowed} never read; V2 plan-only path does not skip destroy*; V5 defaultParameters.deployToggle passed through unfiltered on plan-only; V4 comments say "contains apply" but code is startswith; V6/V7 CD stagesToSkip derived from caller allStages not registry stages.all; V8 CD with no registry in CWD ancestry falls back to prefix allow; V9 unregistered pipelineId falls back to caller-chosen service name. Safe: hardcoded env blocklist first, terraform fails closed without registry, CD both-lists -> blocked, integrity check first.
- Decision: reverse Commit A's documented override — blocked/alwaysSkip WIN over applyAllowedEnvironments (hook via Commit B redirect; validator + REGISTRY.md in Commit C). td registry will then need a human edit (remove apply_travellerdirectives from blocked/alwaysSkip) before dev apply works again — correct fail-closed outcome.
- Commit C scope (terraform, in-scope): V1 V2 V3 V4 V5 + docs. V6-V9 change CD behaviour (fail closed on unregistered/no-registry) — needs user go.
- Commit B (hook) and Commit C (validator+REGISTRY.md) implemented by agents; suites 57/57 and 44/44; whitespace/syntax clean; real audit log untouched. Real td registry: 802 dev apply now BLOCKED as registry contradiction in both layers until a human removes apply_travellerdirectives from alwaysSkipStages/stages.blocked; 810 empty-skip now blocked; fch sit now ENVIRONMENT_NOT_ALLOWED.
- Adversarial read-only review of the hook diff dispatched before committing B.
- Hook review found 3 fail-OPEN bugs (jq crash -> exit 5 -> hook non-blocking; empty pipelineId -> all checks skipped; duplicate terraform.id -> ambiguous match -> treated as non-terraform) + 2 lenient risks (CSV allowlist round-trip; malformed defaultParameters relaxes approval). Fixing before committing B.
- Confirmed from official hooks docs (code.claude.com/docs/en/hooks-guide): only exit 2 blocks a PreToolUse; any other non-zero exit with empty/plain stdout = non-blocking error, tool call proceeds. jq crash in pipeline-guard.sh (exit 5) was therefore fail-open. ERR trap -> exit 2 is the fix.
- Committed: 8e27a10 (hook: registry-keyed Check 4, block>allow, fail-closed) and f4481c7 (validator: block>allow terraform path, REGISTRY.md precedence). Live via symlink/identical copy.
- OPEN: (1) td registry human edit — remove apply_travellerdirectives from alwaysSkipStages + stages.blocked to re-enable dev apply; (2) CD-path V6–V9 fail-closed changes await user go (Commit D); (3) hook: missing tool_name passes through (matcher guarantees it) and no-registry-in-CWD + non-keychain pipeline gets zero checks (V8) — untouched; (4) out.json untracked AzDO dump in repo root, do not commit.
State.Status = DONE (pending user decisions above)

## Log — 2026-09-09 keychain secrets "gone"
- secrets-doctor: STORE ok / EXPORTS ok / ENV MISSING for all 7 keys (user shell, SECRETS_SERVICE=dotfiles).
- Keychain inventory (names only): 18 items under service `dotfiles` in login.keychain-db — nothing lost.
- Root cause: `security find-generic-password -w` exits 36 (errSecInteractionNotAllowed); `show-keychain-info` also "User interaction is not allowed". Library maps that to "not found" → empty exports.
- tmux server (pid 3357, started 10:21 via `tmux new-session -A -s main`) runs in launchd `Background` manager, not `Aqua` → cannot reach SecurityAgent to unlock/confirm keychain access. Terminal restart doesn't recreate the tmux server, hence no change.
- Fix (user): unlock login keychain from an Aqua-context window; if still failing inside tmux, restart tmux server from a GUI terminal. Verify with `secrets-doctor` (exit 0).
- Follow-up candidate: secrets lib should distinguish rc 36/locked keychain from "not found" (fix in ~/repos/secrets, not installed copy).

## Plan — keychain-locked handling (approved by user 2026-09-09)
1. nuvemlabs/secrets (source ~/repos/secrets): keychain backend returns real `security` rc (36 locked / 44 not found), `__secret_keychain_locked`, `secret_unlock` (TTY prompt via `security unlock-keychain`, never -p), `secret()` reports locked (rc 2) instead of "not found", opt-in `SECRETS_AUTO_UNLOCK=1` prompts once at source time when a TTY exists.
2. secrets-doctor: STORE=`locked` + footer + exit 1 when keychain locked.
3. dotfiles config/shell/secrets.sh: `export SECRETS_AUTO_UNLOCK=1` before sourcing lib.
4. Hermetic tests (stubbed `security`) in secrets repo; all suites green.
5. Install (`~/repos/secrets/install.sh` → ~/.local), then validate on the REAL locked state inside this tmux server: (a) non-TTY zsh → hint only, no hang; (b) pty via `script` → prompt shown, Ctrl-C → graceful skip; (c) user runs `exec zsh` in their pane, enters password → `secrets-doctor` exit 0.
6. Git: I commit (agent edits only). secrets repo first, then dotfiles.
State.Status = CONSTRUCT
- CONSTRUCT done by agent (file-only); reviewed diff; added INT trap around unlock prompt (zsh aborts rest of sourced rc on untrapped Ctrl-C — proven via pty: SECRETS_MIGRATED_FLAG missing after Ctrl-C).
- Tests: keychain 21/21, api 37/37, doctor 30/30, file 9/9 (live tests ran after keychain unlocked). Installed to ~/.local.
- Real-env: non-TTY `secret` → rc 2 + locked hint; doctor STORE=locked, exit 1. TTY (pty) → prompt shown, unlock → doctor all `set`, exit 0 from Background shell → root cause = lock, not ACL.
- FINDING: on this macOS 27 beta `security unlock-keychain -p <wrong>` and `-p ''` both return 0 and unlock a locked login keychain from a Background non-TTY process. Skip paths (Ctrl-C/empty) untestable here — covered by hermetic tests only. Security concern surfaced to user.
- Committed: secrets 233f005, dotfiles bbc5345. Keychain left UNLOCKED. User must `exec zsh` / open new panes for env to populate.
- OPEN: why the keychain locked this morning (log shows only Df noise); whether keychain password is empty / beta bug.
State.Status = DONE

## 2026-09-09 fastfetch banner
- Disabled startup fastfetch banner in `config/zsh/zshrc` via `DOTFILES_FETCH_BANNER` toggle (default 0). Verified: off by default, on with `=1`. Not committed.

## Done: tmux undersized-pane after resurrect restore (2026-09-17)

### Root cause
- WORK:3 layout saved as `125x32,0,0` (since 2026-09-16 17:13) inside a 169x38 window -> dotted fill, zoom/pane-switch no-ops (single pane).
- tmux (3.7b and 3.7c) applies `select-layout <string>` verbatim; a layout smaller than the window is never rescaled. resurrect restore replays it every restart. Only `resize-window -A` snaps it back.
- Origin of the 125x32 shrink not in the server log: continuum option polling floods the 1000-line message-limit within a minute.

### Actions (config/tmux/tmux.conf)
1. `set -g message-limit 10000`.
2. `bind F resize-window -A` (prefix+F) — manual fix for the current window.
3. `set -g @resurrect-hook-post-restore-all` -> `resize-window -A` on every window after restore.
- Verified on isolated sockets and a scratch session on the live server (hook run via bash eval like resurrect's execute_hook). Live config reloaded.
- Not committed with this change: issue-15 "New packages" plugin hunk in the same file (left unstaged).

## Plan — `q` markdown rendering (literal `*` in Groq answers) — 2026-09-18

### Problem (evidence, not assumption)
- `q` pipes the answer through `bat --style=plain --language=md`. `bat` is a *syntax highlighter*,
  not a renderer: `**bold**` is printed with the asterisks intact (verified via pty capture —
  `**` emitted as literal text, coloured magenta). Same for `* ` bullets.
- Measured streaming on the current path (pty, 3s-gap generator): line 1 displayed at T+1.0s,
  line 2 at T+3.0s -> `bat | less -RFX` DOES stream per line. A true markdown renderer cannot
  (block rendering needs the whole document), so this is a real trade-off, not a free win.

### Blocking side-finding (separate from this fix)
- Groq is non-functional on this machine: no `GROQ_API_KEY` (empty export), `secret`/`secrets-doctor`
  not installed (`--secrets` never ran here), no `groq_models.json` -> `llm-groq` registers ZERO
  models -> `llm -m groq/openai/gpt-oss-20b` => `Error: 'Unknown model'`.
- Consequence: the render fix can be verified against fixture markdown, but NOT end-to-end through
  a live Groq answer until a key is stored. Will be reported as such, never claimed as passing.

### Decision
Render properly with `glow` (charmbracelet, `extra/glow` 3.0.0 on Arch, `glow` on brew; other
distros reach it through `install_package`'s existing brew fallback). Keep the streaming path
reachable via an explicit toggle rather than deleting it.

### Steps
1. `config/shell/env.sh` — add `export Q_RENDER="pretty"` beside `AI_PROVIDER`, documented
   `pretty | raw` (no magic literals at the call site).
2. `config/shell/aliases.sh` — split `q`'s output stage:
   - `pretty` + stdout is a tty + `glow` present -> `llm ... > "$tmp"`, then
     `glow -s auto -w "$(tput cols)" "$tmp" | less -RFX` (explicit `-w`: glow falls back to 80
     cols when its stdout is a pipe).
   - otherwise -> today's `llm ... | tee "$tmp" | bat ...` streaming path (unchanged).
   - non-tty (`q` piped into something) -> raw markdown, no ANSI. Unchanged guard.
   - Renderer fallback chain: glow -> bat -> cat. A machine without glow keeps working.
   - `$tmp` stays RAW markdown: clipboard copy and the `~/.q_history.md` append are display-agnostic
     and must not gain ANSI escapes. `.q_history.md` is a markdown file by design.
   - Update the function's header comment (it currently claims markdown "rendered" through bat).
3. `installers/llm.sh` — source `lib/install-packages.sh`, `install_package "glow" ...` as a
   non-fatal step (warn + continue if unavailable; `q` degrades to the bat path).
4. `CLAUDE.md` (repo) — extend the "Quick AI query (`q`)" paragraph with the renderer + `Q_RENDER`.
5. Verify: fixture markdown (bold/bullets/code fence/table) through both paths in a pty; assert no
   literal `**` survives the pretty path and that the raw path is byte-identical to today's.
   Re-measure streaming on the raw path. Report the Groq end-to-end gap honestly.

### Out of scope (flagged, not touched)
- `pbcopy` in `q` is macOS-only; on this Wayland/Hyprland box the clipboard copy silently no-ops.
  `wl-copy` would be the fix. Unrelated to `*` — raising it, not changing it.
- Storing the Groq API key (needs the user's secret).

State.Status = NEEDS_PLAN_APPROVAL

### Log — CONSTRUCT (2026-09-18)
- User approved `pretty` as default with a `raw` escape hatch.
- `config/shell/env.sh`: `Q_RENDER=pretty` (pretty|raw), `Q_PAGER="less -RFX"`, `Q_FALLBACK_WIDTH=80`.
- `config/shell/aliases.sh`: `q` output stage split into `_q_show_pretty` (glow -> bat -> cat) and
  `_q_show_raw` (bat -> cat, streaming filter); `_q_render_width` feeds glow an explicit `--width`
  (glow falls back to 80 cols when its stdout is a pipe). Non-tty stays raw markdown. `$tmp` stays
  raw so clipboard + `~/.q_history.md` never get ANSI. Unknown `$Q_RENDER` -> rc 2.
  Pager passed via `PAGER=... glow --pager` (no `eval`, single source of truth).
  glow flags confirmed against official docs (Context7 /charmbracelet/glow): `-s/--style`,
  `-w/--width`, `-p/--pager`, honours `$PAGER`.
- `installers/llm.sh`: sources `lib/install-packages.sh`, installs glow non-fatally.
- `CLAUDE.md`: `q` paragraph documents the renderer + `Q_RENDER`.
- `tests/test-installer.sh`: new opt-in `llm` component (llm, glow, llm-groq plugin); deliberately
  NOT in `all`, mirroring `--llm` not being in `--all`.
- `tests/test-q-render.sh`: new hermetic regression test (stubbed `llm`, pty via `script`).

### Verification (evidence)
- `bash -n` + `zsh -n` clean on aliases.sh / env.sh; `bash -n` clean on llm.sh + both test files.
- `./tests/test-q-render.sh` -> 6 passed, 0 failed, 1 SKIPPED.
- Measured raw-path streaming with a 2s-gap stub: line 1 at T+1.05s, remainder at T+2.05s ->
  streaming contract intact.
- GAP (not a pass): glow is NOT installed (pacman needs a password I cannot supply), so the
  decisive assertion "pretty path shows no literal `**`" has NOT run. Reported as skipped, not green.
- GAP: no Groq key on this machine, so nothing was verified against a live Groq answer.
State.Status = VERIFIED_EXCEPT_GLOW

## Log — 2026-09-21 Hyprland Alt+Tab window cycling

Request: "add alt+tab to hyprland". Scope kept to `config/hypr/hyprland.lua` (symlinked to
`~/.config/hypr`), no unrelated edits.

### Change
`hl.bind("ALT + Tab")` / `hl.bind("ALT + SHIFT + Tab")` -> a shared `cycleWindows(forward)`
closure dispatching `hl.dsp.window.cycle_next({ next = forward })` then
`hl.dsp.window.bring_to_top()` (cycle_next only focuses; floating windows stay buried without
bring_to_top).

### Keyboard-swap caveat (documented inline, do not "fix")
`input.kb_options = "ctrl:swap_lalt_lctl"` means the ALT modifier is emitted by the *physical
left Ctrl* key, not the key labelled Alt. Binding the switcher on CTRL instead would shadow every
in-app tab switcher (browsers, terminals), so it stays on ALT.

### Sources
Hyprland 0.56.2. API confirmed against the official wiki via Context7 (`/hyprwm/hyprland-wiki`):
`cycle_next({ window?, next?, tiled?, floating? })`, and the wiki's own Alt+Tab snippet
(cycle_next + bring_to_top). Cross-checked against `/usr/share/hypr/stubs/hl.meta.lua`.

### Verification (evidence)
- `luac -p config/hypr/hyprland.lua` -> LUA SYNTAX OK.
- `hyprctl reload` -> ok, no config error.
- `hyprctl binds` -> two Tab binds registered: modmask 8 (ALT) and modmask 9 (ALT|SHIFT).
- Direction proven live with 3 scratch kitty windows on ws10:
  `next = true` -> A->B->C->A; `next = false` -> C->B->A->C. Opposite directions, as intended.
- Control run: `cycle_next({ nextt = true })` also returns `ok` -> unknown keys are silently
  ignored, so an `ok` alone proves nothing. Hence the 3-window ordering test above.
- Scratch windows terminated, ws10 empty, focus restored to ws1 (pre-test state).
- GAP (not a pass): the keypress path itself was not simulated -- no wtype/ydotool on this box.
  Verified bind registration + dispatcher behaviour, not a synthetic ALT+Tab keystroke.
State.Status = VERIFIED_EXCEPT_KEYSTROKE_SIM

## SUPER+I — show current workspace number (2026-09-21)

### Goal
User asked how to identify the current workspace number. No status bar runs on this box
(waybar is installed but the autostart block in `hyprland.lua` is commented out and
`~/.config/waybar/` does not exist). User explicitly declined a bar, asked for the keybind.

### Change
`config/hypr/hyprland.lua`, inserted after the mainMod+[0-9] workspace loop:
`SUPER + I` -> `hl.dsp.exec_cmd` running
`sh -c 'hyprctl notify -1 2000 0 "workspace $(hyprctl activeworkspace -j | jq -r .id)"'`.
Notify args are named via locals (`notifyNoIcon`, `notifyDurationMs`, `notifyDefaultColor`)
rather than bare numbers. Wrapped in an explicit `sh -c` to match the screenshot binds' style.

### Dependency
Adds a runtime dependency on `jq` (present: /usr/bin/jq). Parsing `hyprctl activeworkspace -j`
was chosen over cutting the human-readable output, which is not a stable interface.
`hyprctl notify` is rendered by Hyprland itself, so no notification daemon is required.

### Verification (evidence)
- `luac -p config/hypr/hyprland.lua` -> LUA SYNTAX OK.
- Command run standalone via `/bin/sh -c` BEFORE binding -> `ok`, notification rendered.
- `hyprctl reload` -> ok; `hyprctl configerrors` -> empty.
- `hyprctl binds -j` -> `modmask=64 (SUPER) key=I -> __lua`, i.e. registered.
- `~/.config/hypr` is a symlink to `config/hypr/` (`readlink -f` confirmed), so the repo edit
  is the live config; no re-install needed.
- GAP (not a pass): the keypress itself was not simulated (no wtype/ydotool here). Bind
  registration + the underlying command were verified; the SUPER+I keystroke was not.
State.Status = VERIFIED_EXCEPT_KEYSTROKE_SIM

### Open (not done, not asked for)
`SUPER+SHIFT+right` uses workspace `"+1"` while `SUPER+SHIFT+left` uses `"e-1"` — asymmetric.
No relative "move window to next/prev workspace" bind exists. Both left untouched.

## DONE: SUPER+Tab toggles to the last-focused workspace (2026-09-21)

### State
- **Status**: COMPLETE (verified live)
- **Branch**: main

### Origin
User asked whether SUPER+Tab could cycle workspaces. SUPER+Tab was free — Tab was only
bound with CTRL (window cycling, `hyprland.lua:327-328`), and SUPER is unaffected by the
`ctrl:swap_lalt_lctl` kb_option. Offered cycle-all (`e+1`/`e-1`), per-monitor (`m+1`/`m-1`)
and last-used toggle; user chose the last-used toggle (cmd-tab feel), so SUPER+SHIFT+Tab
is deliberately left unbound.

### Change
`config/hypr/hyprland.lua`, inserted after the mainMod+[0-9] workspace loop:
`SUPER + Tab` -> `hl.dsp.focus({ workspace = "previous" })`.
Used `previous` (global last-focused) rather than `previous_per_monitor`; both are documented
workspace selectors (wiki `configuring/naming-conventions.md`, confirmed via Context7 against
hyprwm/hyprland-wiki, not from memory).

### Verification (evidence)
- `hyprctl reload` -> ok; `hyprctl configerrors` -> empty.
- `hyprctl binds -j` -> `modmask=64 (SUPER) key=Tab -> __lua`, i.e. registered (the pre-existing
  modmask 4 / 5 Tab binds are the CTRL window-cycling ones, unchanged).
- Behavioural round-trip via `hyprctl dispatch`: active workspace 2 -> `previous` -> 1 ->
  `previous` -> 2. Toggle confirmed and state restored.
- `~/.config/hypr` is a symlink to `config/hypr/`, so the repo edit is the live config.
- GAP (not a pass): the SUPER+Tab keystroke itself was not simulated (no wtype/ydotool here).
  Bind registration + the dispatcher were verified; the physical keypress was not.

### Open (not done, not asked for)
Still open from the SUPER+I block: `SUPER+SHIFT+right` uses workspace `"+1"` (creates empty
workspaces, clamps at 1) while `SUPER+SHIFT+left` uses `"e-1"` (existing only, wraps) —
asymmetric. Left untouched.

---

## 2026-09-21 — bash: `~` doesn't go home + startup stdout pollution

### Diagnosis
Not a broken HOME. `HOME=/home/dan`, passwd entry and `cd ~` all correct. `~` is an
*expansion*, not a command: bash rewrites the bare word to `/home/dan` and tries to
execute it -> `bash: /home/dan: Is a directory`. It "worked" in zsh only because
`config/zsh/zshrc:33` sets `setopt autocd`; bash had no equivalent (`shopt autocd` -> off).
Login shell is bash, hence the mismatch.

### Changes (two isolated commits, main)
- `4c3df96` — `shopt -s autocd` added to the Bash options block, matching zsh.
- `791615c` — removed two startup debug echoes in `config/bash/bashrc`
  (`DEBUG: DOTFILES_DIR set to: ...` at old line 29, and `echo 'sourcing path'` spliced
  into the path.sh source line). Both traced to `ade7eb1` (2025-12-22); one was labelled
  "remove after testing".

### Verification (evidence)
- `bash -n config/bash/bashrc` -> clean, both times.
- Before: interactive bash startup wrote 67 bytes to stdout. After: 0 bytes.
- No regression: `DOTFILES_DIR=/home/dan/repos/dotfiles`, `$HOME/.local/bin` still on PATH
  (proves path.sh is still sourced after the `&&`-chain edit), `shopt autocd` -> on.
- Functional: from `/tmp`, bare `~` -> `cd -- /home/dan`, `PWD=/home/dan`.
- Startup-chain sweep: `config/shell/mcp.sh` echoes are gated behind `$SHOW_MCP_STATUS`
  (opt-in) and `config/shell/tmux.sh` printf is a deliberate `$TMUX`-gated prompt marker.
  Neither is pollution; left untouched.

### Open (not done, not asked for)
`config/bash/bashrc` still carries an uncommitted, pre-existing change:
`PNPM_HOME` hardcoded `/home/dan` -> `$HOME`. Deliberately kept out of both commits and
left unstaged — not mine to commit. Nothing pushed.

---

## 2026-09-21 — bash: no keybinding to edit the command line in $EDITOR

### Diagnosis (evidence, before any change)
User expected `alt/ctrl/super+x` to drop the current command line into vim. Nothing is
bound to it in the shell actually running. Five independent layers, all confirmed:

1. Login shell is bash (`$SHELL=/usr/bin/bash`). The working binding exists ONLY in
   `config/zsh/zshrc:60-63` (`autoload edit-command-line`, `bindkey '^x^x'`,
   `bindkey -M vicmd 'v'`). That file never loads. `config/bash/bashrc` has no
   equivalent and there is no `~/.inputrc`.
2. Readline's `edit-and-execute-command` default is `\C-x\C-e` in the **emacs keymap
   only**. `config/bash/bashrc:31` sets `set -o vi`, so it is unreachable. Verified via
   `bind -m <keymap> -q`: vi-insert `"\C-x": self-insert`, vi-command "not bound",
   emacs `can be invoked via "\C-x\C-e"`.
3. It was never one keypress in either shell — `C-x C-e` / `^x^x` are two-key sequences.
   `Ctrl-X` alone is a prefix.
4. `super+x` is not a distinct key: `config/ghostty/config:146` → `super+x=text:\x18`,
   i.e. it forwards the Ctrl-X control code. Same prefix, same dead end.
5. `alt+x` is also Ctrl-X: `config/hypr/hyprland.lua:225` sets
   `kb_options = "ctrl:swap_lalt_lctl"`, so physical left Alt emits Ctrl.

Already working and unchanged: `Esc` then `v` — bash binds vi-command
`"v": vi-edit-and-execute-command` by default; `$EDITOR`/`$VISUAL` are both `nvim`.

### Plan — APPROVED by user
Fix in the shell layer, not the emulator (per `docs/terminal-agnostic-config.md`: the
behaviour is shell-ownable, so Ghostty must not implement it). Add to
`config/bash/bashrc`, after the Bash options block:

    bind -m vi-insert  '"\C-x\C-x": edit-and-execute-command'
    bind -m vi-command '"\C-x\C-x": edit-and-execute-command'

`^x^x` chosen to match `config/zsh/zshrc:62` (not `^x^e`, which collides with the tmux
prefix C-e). Safe to run unguarded: bashrc returns early for non-interactive shells
(lines 8-11), so `bind` always has a readline instance.

### Verification (evidence)
- `bash -n config/bash/bashrc` -> clean.
- Real interactive bash under a PTY, reading the live `~/.bashrc` symlink
  (`readlink -f ~/.bashrc` -> `config/bash/bashrc`):
  - `bind -m vi-insert  -q edit-and-execute-command` -> `can be invoked via "\C-x\C-x"`
  - `bind -m vi-command -q edit-and-execute-command` -> `can be invoked via "\C-x\C-x"`
  - No regression: `bind -m vi-command -q vi-edit-and-execute-command` -> still `"v"`.
- `$EDITOR`/`$VISUAL` both `nvim`, so the chord lands in nvim.
- Not verified: the physical keypress itself (no wtype/ydotool here). The chord is
  registered in readline; `super+x super+x` reaching it depends on the Ghostty
  `super+x=text:\x18` forward, which is pre-existing and unchanged.

### Changes (two isolated commits, main)
- `b9cf922` — workflow_state: previous session's log, committed on its own.
- (this) — the two `bind` lines in `config/bash/bashrc` + this entry.

### Open (not done, not asked for)
`config/bash/bashrc` still carries the pre-existing uncommitted `PNPM_HOME`
`/home/dan` -> `$HOME` change. Staged around via a hunk-level `git apply --cached`;
left unstaged again, as in the previous session. Nothing pushed.

### Status
VERIFIED
