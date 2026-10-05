# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles repository with modular installation system. Supports macOS and Linux with cross-platform package manager detection (brew, apt, dnf, pacman, choco).

## Installation Commands

```bash
# Full installation (Phase 1: dotfiles core, then handover to Phase 2: Claude Code)
./install.sh --all

# Just the dotfiles core — terminal & tmux workflow, stops before Claude Code
./install.sh --dotfiles

# Interactive dialog installer
./install.sh

# Individual components
./install.sh --tools        # Dev tools (git, nvim, ripgrep, etc.)
./install.sh --casks        # macOS GUI apps from config/brew/Brewfile (macOS only)
./install.sh --secrets      # Keychain-backed secrets library + secrets-bridge (migrates ~/.accessTokens; clones ~/repos/secrets and ~/repos/secrets-bridge if missing; accepts brew/AUR packages)
./install.sh --tmux         # Tmux + TPM + plugins (requires: git)
./install.sh --bash         # Bash configuration
./install.sh --zsh          # Zsh configuration (requires: git, zsh, curl)
./install.sh --zsh-completions  # Custom zsh completions (config/zsh/completions/_*), auto-run by --zsh
./install.sh --terminals    # Terminal emulators (Ghostty, etc.)
./install.sh --hypr         # Hyprland compositor config (Linux only; binds, XKB ctrl/alt swap)
./install.sh --quickshell   # Quickshell control hub: Omarchy's panels + desktop themes (auto-run by --hypr)
./install.sh --fonts        # Nerd Fonts for Powerlevel10k (requires: curl)
./install.sh --config-dirs  # Symlink nvim to ~/.config/
./install.sh --claude       # Claude Code CLI and settings (requires: node, npm)
./install.sh --claude-azdo-pipeline-hooks  # Pipeline guard hooks (auto-run by --claude)
./install.sh --claude-hooks  # General Claude hooks: No-Delete guard, notifications (auto-run by --claude)
./install.sh --llm          # llm CLI + Groq plugin, powers the `q` quick-query (requires: python3)
./install.sh --memwatch     # Memory pressure watcher + systemd-oomd kill policy (Linux; sudo for oomd)
./install.sh --services     # claude-rc Remote Control service: systemd (Linux) / launchd (macOS) (requires: Claude Code)

# After shell config changes
source ~/.zshrc  # or ~/.bashrc
```

## Architecture

### Directory Structure

```
installers/          # Individual installer scripts (bash.sh, zsh.sh, etc.)
lib/                 # Shared functions
  install-common.sh  # Logging, symlink helpers, backup utilities
  install-packages.sh # Cross-platform package installation
config/              # Configuration files organized by tool
  brew/              # Brewfile for macOS GUI apps (casks)
  shell/             # Shared configs sourced by both bash and zsh
  bash/              # Bash-specific (bashrc, bash_aliases, bash_path)
  zsh/               # Zsh-specific (zshrc)
  tmux/              # Tmux configuration (tmux.conf)
  nvim/              # Neovim (LazyVim-based)
  claude/            # Claude Code settings, commands, skills
  ghostty/           # Ghostty terminal config
```

### Key Patterns

**Installation Flow**: `install.sh` dispatches to `installers/*.sh` scripts which source `lib/install-common.sh` for utilities. Order matters for `--all`:
1. tools.sh → casks.sh (macOS only) → secrets.sh → terminals.sh → fonts.sh → tmux.sh → bash.sh → zsh.sh → config-dirs.sh → claude.sh → services.sh

**Casks (macOS GUI apps)**: Declared in `config/brew/Brewfile`, installed by `installers/casks.sh` via `brew bundle`. To add an app, add a `cask "name"` line to the Brewfile and run `./install.sh --casks`. No-op on Linux.

**Symlink Strategy**:
- `config/` subdirs symlink to `~/.config/` via `link_config_dirs()`
- Individual files use `link_home_files()` for `source:target` mapping
- Claude files use `link_target_files()` to `~/.claude/`

**Shell Config**: Modular design where `~/.zshrc` and `~/.bashrc` source shared files from `config/shell/` (env.sh, path.sh, aliases.sh, git.sh, tmux.sh).

**Custom zsh completions**: Completion functions live in `config/zsh/completions/` (one `_<cmd>` file per command). `installers/zsh-completions.sh` (auto-invoked by `installers/zsh.sh`, standalone via `./install.sh --zsh-completions`) symlinks them per file into `~/.local/share/zsh/completions/`, the directory `zshrc` prepends to `fpath`. That directory is never whole-symlinked because it also holds generated completions (e.g. `_bat`). Because `zshrc` runs `compinit -C` unless `~/.zcompdump` is older than 24h, the installer backdates the dump's mtime so the next shell start does a full `compinit` and picks up new files. To add one: drop `_<cmd>` in `config/zsh/completions/` and run `./install.sh --zsh-completions`.

**Quick AI query (`q`)**: The `q` function (`config/shell/aliases.sh`) is a one-shot query over the `llm` CLI, optimized for low time-to-first-token (defaults to Groq's `openai/gpt-oss-20b`). Provider is a one-var switch: `AI_PROVIDER` in `env.sh` (`groq|gemini|openai|claude`) maps to a model id in the function; `AI_MODEL` pins a specific id. The Groq key lives in the keychain (`secret_set GROQ_API_KEY ...`) and is exported as `LLM_GROQ_KEY` by `secrets.sh`. Answers are rendered as markdown by `glow` (`Q_RENDER=pretty`, the default) so bold, bullets and code blocks display as formatting rather than literal `*`/backtick markers; `Q_RENDER=raw` restores the streaming `bat` path (lowest time-to-first-token, markers visible). Renderers are optional — the chain degrades glow → bat → cat, and piped output is always raw markdown. Installed via `./install.sh --llm` (standalone, not part of `--all` since it needs an API key), which also installs glow.

**Remote Control service (`claude-rc`)**: `installers/services.sh` (`--services`, last step of `--all`) runs `claude remote-control --permission-mode bypassPermissions` in `~/repos` as a background service, so spawned sessions skip permission prompts like `cdang` (`remote-control` has no `--dangerously-skip-permissions`). Linux: systemd user unit in `config/systemd-services/`, linked as `~/.config/systemd` (if that is a real dir or a foreign symlink, only `user/claude-rc.service` and `user/hyprland-session.target` are linked into it), then `enable --now`; linger is suggested, never enabled automatically. The unit is `WantedBy=graphical-session.target`, not `default.target`: with linger, `default.target` starts at boot, before login, when the keyring is locked and no display exists for its unlock prompt, which hung the shells. `hyprland.lua` starts `hyprland-session.target` (`BindsTo=graphical-session.target`, which refuses manual starts) on login; `claude-rc-sessions.service` hangs off the same target: it runs `rc-start.sh`, which starts one detached tmux session (`rc-<folder>`) with a bridge per folder listed in `~/.config/claude-rc/folders` (`rc-start.sh <dir>` adds one, `rc-stop.sh <dir>` stops and forgets one; both live in `util-scripts/`, linked into `~/bin` by the installer; macOS uses `config/launchd/com.nuvemlabs.claude-rc-sessions.plist`). A session counts as running only when its pane runs the bridge, so after tmux-resurrect restores the `rc-*` sessions as plain shells, the `@resurrect-hook-post-restore-all` hook runs `rc-start.sh --if-listed` to respawn the bridges (logged to `~/.local/state/claude-rc/restore.log`); `tests/test-rc-start.sh` is hermetic. Before starting, both units run `util-scripts/keyring-unlock-wait` (`ExecStartPre=-`): if any `service=dotfiles` item is locked it shows the keyring's unlock dialog and waits (`KEYRING_UNLOCK_TIMEOUT`, 300s; `TimeoutStartSec=330` outlasts it), because env vars are fixed when the shell starts and a later unlock never reaches the bridge or the sessions it spawns. Dismissed or timed out, the unit still starts, without secrets. `hyprland.lua` runs `dbus-update-activation-environment --systemd` before starting the target so the D-Bus-activated dialog can open a display. `tests/test-keyring-unlock-wait.sh` is hermetic (private bus and gnome-keyring, no display). It also links `config/environment.d/*.conf` per file into `~/.config/environment.d/`, which puts `~/.local/bin` and `~/bin` on PATH for every user unit and for the tmux server `rc-start.sh` forks (the manager's own PATH lacks them, so `claude` and `run-shell` bindings failed); systemd applies it at login, not on `daemon-reload`, so apply it immediately with `systemctl --user set-environment`. Secrets never go there. Without a systemd user bus (Docker/CI) it links but does not enable. macOS: LaunchAgent `config/launchd/com.nuvemlabs.claude-rc.plist`, copied (not linked — symlinked agents are unreliable) to `~/Library/LaunchAgents` and bootstrapped into `gui/<uid>`; runs only while logged in, errors in `~/Library/Logs/claude-rc.log`. Skipped entirely when `~/.local/bin/claude` is absent. Both run via `zsh -lic` so secrets are exported, and discard stdout because the TUI redraws every second (errors go to stderr). On Linux the bridge's debug log (reconnects after suspend/resume, session errors) goes to `~/.local/state/claude-rc/debug.log`, the previous run's to `debug.log.1`.

**Crash relaunch of Claude sessions (`tmux-claude-relaunch.sh`)**: after a crash or power loss, tmux-resurrect/continuum restore the layout and each pane that was running Claude resumes its own session. The Claude hook `config/claude/hooks/tmux-pane-registry.sh` (SessionStart/SessionEnd, installed by `claude-hooks.sh`) records `<session>:<window>.<pane>` → session id, cwd and transcript path in `${XDG_STATE_HOME:-~/.local/state}/claude-tmux/panes/`. The key is the pane's position, because pane ids (`%N`) don't survive a restore. It records only when exactly one `claude` process sits between the hook and the pane's shell, so a nested `claude -p` can't overwrite the pane's session. A deliberate exit (`prompt_input_exit`/`logout`) removes the record; a crash or SIGHUP keeps it. `util-scripts/tmux-claude-relaunch.sh`, backgrounded from `@resurrect-hook-post-restore-all`, types `<cmd> --resume <id>` into a pane only when the pane exists, the resurrect `last` snapshot shows `claude` there, the transcript exists, the pane is an idle shell and its cwd matches. A relaunched record is kept, marked `relaunched_at`, until the resumed session's SessionStart rewrites it: a shell still stuck in its rc files already looks idle, so the typed command may never run, and a still-marked record is retried on the next restore even when that snapshot shows a shell, up to `@claude-relaunch-max-attempts` (default 3) unconfirmed attempts, after which it is removed and logged with its resume command; a SessionStart drops other panes' records of the same session, so a manual resume elsewhere supersedes it. Every decision, with the session id, goes to `claude-tmux/relaunch.log`, which doubles as the manual-resume list for sessions it skipped (e.g. started after the last 5-minute continuum save). Tunables are tmux options: `@claude-relaunch` (on/off), `@claude-relaunch-cmd` (default `cdang`), `@claude-relaunch-timeout` (seconds). `tests/test-tmux-claude-relaunch.sh` is hermetic (private `tmux -L` server).

**Scheduled Claude tasks (`tmux-claude-task.sh`)**: `util-scripts/tmux-claude-task.sh <session> <window> <dir> <prompt-file>` opens a new window in a tmux session (created detached if missing) and starts `cdang` there with the prompt file's text, via `zsh -lic` so secrets are exported even from a bare timer environment; `TMUX_CLAUDE_TASK_CMD` overrides the command. Launches are logged to `${XDG_STATE_HOME:-~/.local/state}/claude-tasks/tasks.log`. One-off follow-ups are systemd user timers in `~/.local/share/systemd/user/claude-task-*.{service,timer}` (outside the repo, `Persistent=true` so a timer missed during sleep runs on wake) with prompts in `~/.local/state/claude-tasks/prompts/`; list them with `systemctl --user list-timers 'claude-task-*'`.

**tmux themes (`tmux-theme.sh`)**: colours are plain tmux config files in `config/tmux/themes/<name>.conf` (gruvbox-dark, the default, is a verbatim capture of what the dropped `egel/tmux-gruvbox` plugin produced; also gruvbox-light, catppuccin-mocha, tokyo-night, dracula, nord, rose-pine, hex from each project's official palette, named in the file header). Every theme sets the same option list, so sourcing one fully replaces the last; an option a theme leaves at tmux's default is `set -gu`. Every `status-right` must keep `#(…/continuum_save.sh)`, because continuum's autosave (and the crash relaunch) only runs while it is there. `util-scripts/tmux-theme.sh` `list` / `current` / `apply <name>` (not saved) / `apply-saved` / `set <name>` (apply and save; used by desktop themes, see Control hub); the saved name is in `${XDG_STATE_HOME:-~/.local/state}/tmux-theme/current`, and a missing or unknown one means `gruvbox-dark`. `tmux.conf` runs `apply-saved` with a blocking `run-shell` after TPM, so it applies on start and on `prefix+r`. `prefix + C-t` opens `--popup` (fzf: moving the cursor previews the theme live, Enter applies and saves, Esc or any other exit re-applies the saved one). `TMUX_THEME_DIR` / `TMUX_THEME_STATE` override the paths; it talks to the server in `$TMUX`. Clickable status-right segments are `#[range=user|<name>]` ranges handled by the `MouseDown1Status` binding in `tmux.conf`: `datetime` collapses the date/time to an icon (`@datetime_collapsed`), `power` swaps the battery for today's weather (`@power_weather`) from `util-scripts/tmux-weather.sh`, which only reads a cache and refreshes it from wttr.in in the background (`TMUX_WEATHER_TTL` 900s, failed attempts retried after `TMUX_WEATHER_RETRY` 60s; location from `@weather-location`, unset = guessed from the public IP), `bluetooth` (the Nerd Font glyph just before the date/time) runs `util-scripts/tmux-bt-popup.sh --popup #{q:client_name}` from a `run-shell -b`, so the popup opens on the client that clicked: `bt-fix` in a palette-style popup, its device list restyled through `BT_FIX_FZF_OPTS`, its progress lines and `[y/N]` question indented under the title row, the outcome held until a key (Esc in the list closes at once; `TMUX_BT_FIX`, `TMUX_BT_POPUP_HEIGHT` override). `wifi` (the glyph just before Bluetooth) does the same with `util-scripts/tmux-wifi-popup.sh` and `wifi-pick` (`WIFI_PICK_FZF_OPTS`; `TMUX_WIFI_PICK`, `TMUX_WIFI_POPUP_HEIGHT` override). `prefix + C-c` opens the control panel, `util-scripts/tmux-control-panel.sh --popup #{q:client_name}`: a palette-style list whose entries run the Wi-Fi or Bluetooth popup's run mode or `tmux-theme.sh --pick` inside the same popup (no nested popup), flip `@power_weather` / `@datetime_collapsed` and redraw that client, or `hub-shell toggle` (listed only when installed). The palette look (Ctrl+P menu) shared by those popups and the Claude picker (`prefix + C-i`) lives in the sourced `util-scripts/tmux-palette-style.sh`: theme colours from the palette's active theme via bun, falling back to Shades of Purple (`load_theme`, exported `THEME_*`), the fzf colour roles (`palette_fzf_colors`), the title row (`palette_title`), the borderless, centred, panel-coloured popup capped by the client (`palette_popup`), and for tool popups the picker's fzf options (`palette_picker_fzf_opts`), the indented output stream (`palette_stream_indent`; a line ending in `] ` or `> ` is a question) and the title/run/outcome/wait-for-a-key flow (`palette_tool_popup`); it stays bash 3.2 safe. Leaving zen (`prefix+Z`) or cinema (`prefix+V`) mode re-applies the saved theme instead of hardcoded border colours. `tests/test-tmux-theme.sh` is hermetic (private `tmux -L` server, stub fzf).

**Spoken notifications (`ttalk`)**: `util-scripts/ttalk "<msg>"` speaks via Piper (fallback `say`/`espeak-ng`/`spd-say`) in the background and always exits 0. Playback is serialized machine-wide by a per-user lock (`$XDG_RUNTIME_DIR/ttalk.lock`, `flock`; atomic `mkdir` lock where flock is missing), because many Claude sessions announce completions at once and unserialized calls talked over each other. Piper synthesizes before taking the lock so queued messages play back-to-back; a message still waiting after `TTALK_WAIT` seconds (default 120) is dropped as stale, not retried on another engine. Overrides: `TTALK_LOCK`, `TTALK_WAIT`. `ttalk --disable` / `--enable` mute or unmute every call for the user via `${XDG_STATE_HOME:-~/.local/state}/ttalk/state.json` (read with `jq`, `grep` fallback where `jq` is absent; anything but `"isEnabled": true` mutes, a missing or unparsable file means enabled); muted calls exit 0 silently and are logged to a dated `.log` in the same dir. `ttalk --volume N` stores the playback volume (0–100, percent of the system volume, default 40) in the same file and `ttalk --volume` prints it; it is mapped to each engine's own scale (`pw-play --volume` 0–1, `paplay` 0–65536, `espeak-ng -a`, `say [[volm]]`, `spd-say -i`), and an invalid stored value falls back to the default. `tests/test-ttalk-serialize.sh` is hermetic.

**Phone notifications (`ntfy-send`)**: `util-scripts/ntfy-send [-t TITLE] [-p PRIORITY] [-g TAGS] MESSAGE` pushes to ntfy (currently public `ntfy.sh`; self-hosting on the homelab is planned). The topic URL is the only access control on `ntfy.sh`, so it lives in the keychain (`secret_set NTFY_TOPIC_URL https://ntfy.sh/<topic>`), is exported by `secrets.sh`, and is read straight from the keychain when the caller's env lacks it (Hyprland binds, timers); it is never printed. `NTFY_TOKEN`, when set, is sent as a Bearer token for servers with access control; `NTFY_TIMEOUT` (default 10s) bounds the request. Unlike `ttalk`, failures exit non-zero (1 = no topic or delivery failed, 2 = usage) so a lost alert is visible; callers that must not fail add `|| true`. `tests/test-ntfy-send.sh` is hermetic (stub curl).

**Memory-exhaustion freezes (`mem-pressure-watch`, `--memwatch`)**: when RAM and zram fill up, everything (Hyprland and the cursor included) stalls on reclaim until the kernel OOM killer fires, which took ~12 minutes on 2026-10-05 (a leaking `dotnet test` host at 17 GB). Two layers, installed by `./install.sh --memwatch` (Linux, standalone; the oomd part asks for sudo). `util-scripts/mem-pressure-watch` (python3 stdlib, user unit `mem-pressure-watch.service`, `WantedBy=graphical-session.target`) registers a PSI trigger on `/proc/pressure/memory` (`some` 200ms per 2s window) and on each firing appends a snapshot to `${XDG_STATE_HOME:-~/.local/state}/mem-pressure/events.log`: PSI avg10, MemAvailable, swap and the top processes by RSS with cmdline, cwd and cgroup leaf (a `tmux-spawn-*.scope` names the pane), at most every `MEMWATCH_LOG_INTERVAL` (10s); above `MEMWATCH_NOTIFY_PCT` (20%) it also runs `notify-send -u critical` and `ntfy-send -p high`, with cooldowns of 120s and 900s. It only reports; `--once` prints a snapshot; a PSI file outside `/proc/pressure/` (tests) means polling avg10. Killing is systemd-oomd's job: `config/systemd-oomd/user@.service.d/90-mem-pressure-kill.conf` is copied (not linked; root reads it) to `/etc/systemd/system/user@.service.d/` and sets `ManagedOOMMemoryPressure=kill` at 40% over oomd's default 20s, so oomd SIGKILLs the leaf cgroup under `user@1000.service` with the most reclaim, in practice the runaway pane's scope. Hyprland runs in `session-N.scope`, outside `user@.service`, so it is never a candidate; `claude-rc-sessions.service` (the tmux server's cgroup) has `ManagedOOMPreference=avoid` and the watcher `omit` (respected because both cgroups and the monitored ancestor are owned by the same uid; check with `getfattr -d -m oomd /sys/fs/cgroup/.../<unit>`). No `ManagedOOMSwap` on `-.slice`: swap kills pick by swap size and ignore user-owned preferences. `oomctl` shows what oomd monitors. `tests/test-mem-pressure-watch.sh` is hermetic (fake /proc and PSI file, stub notifiers, sudo and systemctl).

**Bluetooth repair (`bt-fix`)**: `util-scripts/bt-fix [-a] [-y] [NAME]` scans, lists devices by name in fzf (nearby first; unnamed ones only with `-a`; falls back to `select` without fzf; `NAME` pre-filters and picks a single match) and gets the pick connected. A plain connect, from `bluetoothctl` or the wayle bar, reuses the saved pairing and just times out when either side has forgotten it, so bt-fix tries the saved pairing first and only then waits for pairing mode, removes the stale pairing (asked first unless `-y`) and pairs, trusts and connects. A device that returns in pairing mode on a new address (Logitech mice move address per Easy-Switch channel) is paired there and the old entry is left alone. Every `bluetoothctl` call gets `</dev/null`: it reads stdin, and inside a `while read` loop it swallowed the device list and hung. Exit 0 connected, 1 failed, 2 usage, 130 cancelled; `BT_FIX_SCAN`/`BT_FIX_CONNECT`/`BT_FIX_WAIT` tune the timeouts, and `BT_FIX_FZF_OPTS` (one fzf option per line, appended after bt-fix's own) restyles the picker. `tests/test-bt-fix.sh` is hermetic (stateful stub bluetoothctl and fzf).

**Wi-Fi (`wifi-pick`)**: `util-scripts/wifi-pick [-y] [NAME]` is `bt-fix`'s counterpart for NetworkManager (`nmcli`): it lists the networks in range in fzf (connected, then saved, then by signal; one row per SSID, the strongest access point; hidden networks left out; `select` fallback without fzf; `NAME` pre-filters) and connects the pick. A saved network comes up with its profile; when the saved password stops working it asks for the new one and retries. A new WPA network gets a profile (`wpa-psk`, or `sae` for WPA3-only) and the password; an open one connects directly; 802.1X and WEP are refused with a pointer to `nmtui`. Picking the connected network offers to disconnect, and a radio that is off is turned on after a yes (`-y` skips both questions). The password is read without echo and reaches NetworkManager only through `nmcli connection up … passwd-file` on a pipe, never argv; every `nmcli` call gets `</dev/null` so a missing secret fails instead of prompting behind the picker. Exit 0 done, 1 failed, 2 usage, 130 cancelled; `WIFI_PICK_CONNECT` (30s), `WIFI_PICK_RESCAN` (`yes`, falling back to the cache when a rescan is refused) and `WIFI_PICK_FZF_OPTS` tune it. `tests/test-wifi-pick.sh` is hermetic (stateful stub nmcli and fzf).

**Control hub (`config/quickshell`, `hub-shell`)**: a standalone Quickshell config (no bar; wayle and dunst stay) showing Omarchy's panels as a grid of tiles in a card on the right edge: Wi-Fi, Bluetooth, Audio, Power, Display, Tailscale, Calendar, Weather, World time, Dropbox (tiles whose command is missing are hidden, e.g. Dropbox), plus Themes and Wallpapers action tiles. `SUPER+A` toggles it; Hyprland starts it at login (`hub-shell start`, single instance). Omarchy (basecamp/omarchy, MIT) is vendored verbatim in its own commits so upstream syncs diff cleanly (`config/quickshell/UPSTREAM.md` names the commit): `Commons/`, `Ui/`, `plugins/panels/`, `plugins/image-picker/`, the helpers the panels exec (`omarchy/bin/omarchy-*`), the theme templates and the 22 theme palettes. The panels are Omarchy bar widgets; `Hub/HubBar.qml` stands in for Omarchy's bar (colours, sizes, one-popup-at-a-time) and each tile hosts the panel's own button scaled up, so the panels run unpatched and their popups open left of the card. `Hub/tiles.json` lists the tiles (`entry` = panel QML, or `summon`/`exec` for action tiles; `requires` hides a tile when the command is missing; `settings` are defaults under what a panel saves to `~/.local/state/omarchy-hub/settings.json`). `omarchy/shell` is a symlink to `..` and `hub-shell` sets `OMARCHY_PATH=~/.config/quickshell/omarchy` with `omarchy/bin` and `util-scripts` on PATH, so the panels' `$OMARCHY_PATH/...` paths and Omarchy's own `omarchy-shell` client reach this instance. Helpers that need the rest of Omarchy are local replacements under the same names: `omarchy-menu-select` (wofi), `omarchy-osd` (dunst progress notification), `omarchy-launch-floating-terminal-with-presentation` (floating Ghostty, class `org.omarchy.terminal`, floated by a rule in `hyprland.lua`), `omarchy-audio-tuning` (none), `omarchy-theme-set`. `hub-shell toggle|show|hide|open <panel-id>|summon <id> [json]|restart`. **Desktop themes**: `omarchy-theme-set <name>` renders `omarchy/themes/<name>/colors.toml` (overlaid by `~/.config/omarchy/themes/<name>`) through Omarchy's templates into `~/.local/state/omarchy/current/theme/`, then pushes the colours to the hub over IPC, reloads Hyprland (`hyprland.lua` `dofile`s the theme's `hyprland.lua` for tiled borders and `hyprland-hub.lua`, a local template, for floating borders: `hyprland_float_border` in colors.toml, default magenta), sends Ghostty SIGUSR2 (its config includes `?~/.local/state/omarchy/current/theme/ghostty.conf`) and runs `tmux-theme.sh set` when a tmux theme has the same name (`catppuccin`→`catppuccin-mocha`, `gruvbox`→`gruvbox-dark`). Nothing changes until a theme is picked. `dracula` is a local theme (pink tiled, purple floating). Theme picker previews are SVGs drawn from each palette by `omarchy-theme-preview --all` (rerun after editing a colors.toml; the test fails on a stale one). `util-scripts/wall-pick [--favorites]` opens the same picker over `$WALLPAPER_DIR` and applies the pick with awww. Installed by `./install.sh --quickshell` (auto-run by `--hypr`; links `~/.config/quickshell`, names missing packages: `quickshell`, `qrencode`, …). Logs: `qs log -p ~/.config/quickshell/omarchy/shell`, theme switches in `~/.local/state/omarchy-hub/theme-set.log`. `tests/test-quickshell-hub.sh` is hermetic; with `QS_BIN=<quickshell>` inside Wayland it also starts a copy of the config and fails on load warnings.

**Package Manager**: Auto-detects available managers, prompts user on first run, caches choice in `~/.dotfiles_pkg_manager`.

**Wallpaper cycling (`wall-next`) and favorites (`wall-fav`)**: `util-scripts/wall-next [--favorites] [next|prev]` cycles the FOCUSED Hyprland monitor's wallpaper via `awww`, in sorted order across every collection under `$WALLPAPER_DIR` (default `~/Pictures/walls`, image collections cloned there directly — not tracked in this repo). Focused monitor comes from `hyprctl monitors -j`; the current image comes from `awww query -j` (awww is the only state, no state file), so an unset or unrecognised current image falls back to the first image (`next`) or last image (`prev`) — matching first tries the exact path, then falls back to one batched `realpath` comparison, so switching between the full cycle and `--favorites` continues from the same picture instead of restarting. The list always wraps. `WALL_TRANSITION` (default `grow`) and `WALL_TRANSITION_DURATION` (default `1`) are env-overridable. `util-scripts/wall-fav` toggles the current image as a favorite: a symlink in `$WALL_FAVORITES_DIR` (default `~/Pictures/wall-favorites`, created on first add), named after the image's path relative to `$WALLPAPER_DIR` with `/` replaced by `__` (or its basename if outside `$WALLPAPER_DIR`) so same-named files across collections don't collide; toggling only ever adds/removes that symlink, never the target image. `util-scripts/wall-lib.sh` holds the helpers (`notify`/`fail`, focused-monitor lookup, current-image lookup, the two dir env-var defaults) shared by both scripts, sourced relative to each script's own resolved dir. `hyprland.lua` autostarts `awww-daemon` (replacing hyprpaper; the daemon restores each output's last image from its own cache on restart) and binds `SUPER+SHIFT+N`/`SUPER+SHIFT+B` to next/prev, `SUPER+SHIFT+F` to `wall-fav`, and `SUPER+CTRL+SHIFT+N`/`SUPER+CTRL+SHIFT+B` to favorites next/prev, all via the absolute `$HOME/repos/dotfiles/util-scripts/...` path since Hyprland's exec env may lack the shell PATH.

**Secrets diagnostics (`secrets-doctor`)**: `secrets-doctor [KEY|PREFIX ...]` (from `nuvemlabs/secrets`, installed to `~/.local/bin` by `./install.sh --secrets`; source lives in `~/repos/secrets/bin/` — fix bugs THERE, not in the installed copy) reports where the secret chain breaks (OS store → `config/shell/secrets.sh` export → shell env) without ever printing values — names-only by design. No args checks every key `secrets.sh` reads from the store; exit 0 = chain intact, 1 = broken. Use this instead of ad-hoc `security`/grep pipelines when a token (e.g. `AZDO_PAT`, `PIPELINE_GUARD_*`) isn't reaching a tool. The `secrets-debugging` skill (`config/claude/skills/secrets-debugging/`) makes this the canonical workflow for agent sessions.

**Terminal.app font (macOS)**: `installers/terminals.sh` sets the default profile's font to a Nerd Font (`MesloLGS-NF-Regular`) via AppleScript against the running app — Terminal.app rewrites its plist on quit, so `defaults write`/symlinks don't stick. Only the font family is changed; runs under `--terminals`. Requires the font (`--fonts`) and Automation permission; non-fatal warn otherwise. Note: Terminal.app is 256-color only, so p10k/tmux colors remain approximated.

### Terminal-Agnostic Configuration (binding decisions)

**Never reach for `config/ghostty/config` first.** Implement behaviour in the most
portable layer that can do it: tmux → shell → app config → emulator. Emulator
config is limited to rendering, OS/window integration, and forwarding keys the OS
swallows (the `super+<key>` → control-code table) — it must never *implement* a
behaviour tmux or the shell could own.

Rationale and the decision test: [docs/terminal-agnostic-config.md](docs/terminal-agnostic-config.md).
Adding a Ghostty setting that fails that test means the workflow breaks under
every other terminal and the config has to be rewritten per emulator.

### Neovim Setup

LazyVim-based configuration. Plugin definitions in `config/nvim/lua/plugins/`. Custom keymaps in `config/nvim/lua/config/keymaps.lua`.

### Claude Code Setup

Settings symlinked from `config/claude/` to `~/.claude/`:
- `CLAUDE.md` - Global user instructions
- `settings.json` - Permissions and config
- `commands/` - Custom slash commands
- `skills/` - Custom skills
- `scripts/pipeline-validator.sh` - Hard safety rules for pipeline triggers (blocks PRE/PRD)
- `scripts/pipeline-registry.sh` - CWD-based service detection and pipeline ID resolution
- `hooks/pipeline-guard.sh` - PreToolUse hook intercepting direct MCP pipeline calls; honours the registry's `terraform.applyWithoutApprovalEnvironments` (an apply run for a listed environment, SIT in practice, carries `requireManualApproval=False` and skips the ManualValidation gate; the list must be a subset of `applyAllowedEnvironments` and may never name pre/prd, or the registry fails closed)
- `hooks/pipeline-trigger-guard.sh` - PreToolUse Bash hook blocking direct curl/az/gh trigger attempts
- `hooks/pipeline-registry-write-guard.sh` - PreToolUse hook blocking AI mutations of pipeline-registry.json (the stage allow/block authority; humans edit + commit it); heredoc bodies and read targets that merely mention the file are not writes
- `hooks/destructive-ops-guard.sh` - PreToolUse Bash hook enforcing the No-Delete Rule (cloud/infra deletes, `terraform destroy`, `rm` outside a git work tree)
- `hooks/notification.sh` - Notification hook surfacing Claude Code notifications on the desktop (notify-send / osascript)
- `commands/pipe-deploy.md` - `/pipe-deploy` command for CI/CD orchestration
- `commands/wrap-up.md` - `/wrap-up` command: audits the CURRENT session's conversation for unverified claims and abandoned threads, reports, gates on approval, then lands it (verify → commit → handoff block in `workflow_state.md` + a session memory). Distinct from `/recap` (reconstructs tmux *scrollback*) and `/review-before-commit` (reviews the *diff*) — `/wrap-up` reviews the *conversation thread*. `disable-model-invocation: true`, so it is user-invoked only.
- `agents/pipeline-runner.md` - Autonomous pipeline trigger/monitor/recovery agent and the single source of the workflow: decision rules (SIT by default, CD stages from the registry allow-list, validator output passed through unchanged, no questions) and a `D<n>` decision line appended to `workflow_state.md` before every trigger; `commands/pipe-deploy.md` and `skills/pipeline-ops/` only dispatch it
- `skills/pipeline-ops/` - Auto-discoverable skill matching "deploy", "run pipeline" etc.
- `skills/ntfy-notifications/` - When and how to push to the phone with `ntfy-send` (what not to send, priorities, exit codes, delivery check)

The loose `hooks/*.sh` files (the three `pipeline-*-guard.sh`, `destructive-ops-guard.sh` and `notification.sh`) are not delivered by the whole-dir symlinks (because `~/.claude/hooks/` is shared with `memory-hooks` and `logging-hooks`). The pipeline guards are installed by `installers/claude-azdo-pipeline-hooks.sh` and the general ones (`destructive-ops-guard.sh`, `notification.sh`) by `installers/claude-hooks.sh`. Both are auto-invoked by `installers/claude.sh` (i.e. by `./install.sh --claude`) and can also be run standalone via `./install.sh --claude-azdo-pipeline-hooks` / `./install.sh --claude-hooks`. Their registration in `settings.json` is delivered through the existing `settings.json` whole-file symlink.

Because `settings.json` references them unconditionally, `installers/logging-hooks.sh` and `installers/memory-hooks.sh` are auto-invoked by `installers/claude.sh` too, so `hooks/logging/`, `hooks/memory/` and `hooks/utilities/` are never missing. Both can still be run standalone (`--logging-hooks`, `--memory-hooks`). Their `settings.json` merge is append-and-dedupe, per event and per matcher: it only ever adds entries, keeps existing hooks in their registered order (hook order is load-bearing for the guards, so no sorting), and is idempotent. `tests/test-memory-hooks-merge.sh` pins that behaviour.

Local files (not synced): `settings.local.json`, `.credentials.json`

### MCP Server Configuration

**IMPORTANT**: Claude Code reads MCP servers from `~/.claude.json` (the `mcpServers` key), NOT from `~/.claude/mcp.json` or `settings.json`.

**To add/remove/modify MCP servers:**
1. Edit `config/mcp/servers.json` (canonical source of truth)
2. Run `./install.sh --mcp` (or `./installers/mcp.sh`) to sync into `~/.claude.json`
3. Restart Claude Code to load changes

**Never** edit `~/.claude.json` directly for MCP servers — the installer will overwrite manual changes.

Files:
- `config/mcp/servers.json` - Server definitions (tracked in git)
- `config/mcp/mcp-env.local` - API keys (gitignored)
- `installers/mcp.sh` - Sync script that merges servers into `~/.claude.json`

## Agent Teams (Experimental)

Claude Code Agent Teams are enabled for parallel work on this repo. Teams coordinate multiple Claude Code instances working together with shared tasks and inter-agent messaging. Requires tmux (installed via `--tmux`).

### Available Team Commands

| Command | What it does |
|---------|-------------|
| `/setup-machine` | Spawns 4 teammates to install dotfiles in parallel (base tools, shells, dev env, claude/mcp) |
| `/test-all-distros` | Spawns 4 teammates to run Docker e2e tests on Arch, Ubuntu, Debian, and Fedora simultaneously |
| `/review-changes` | Spawns 3 teammates for pre-commit review (cross-platform compat, security, symlink validation) |

### Configuration

Agent teams are enabled in `config/claude/settings.json`:
- `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`: `"1"` enables the feature
- `teammateMode`: `"auto"` uses tmux split panes when inside tmux, in-process otherwise

### Test Harness

Test scripts in `tests/` that teammates (or manual runs) can use:
- `tests/test-installer.sh <component|all>` - Validates a single installer's results
- `tests/test-docker.sh <distro|all>` - Builds Docker image and runs full e2e test
- `tests/validate-symlinks.sh` - Checks all expected symlinks exist and point correctly
- `tests/test-pipeline-validator.sh` - Hermetic safety tests for the pipeline validator (blocklist layering, registry stage lists, registry integrity fail-closed, terraform plan-only)
- `tests/test-pipeline-hooks.sh` - Hermetic safety tests for the three PreToolUse guard hooks (MCP trigger, Bash trigger, registry write protection), the terraform approval-gate waiver and the write guard's heredoc handling
- `tests/test-memory-hooks-merge.sh` - Hermetic tests for the settings.json hook merge in `installers/memory-hooks.sh` (append-only, order-preserving, idempotent)
- `tests/test-tmux-claude-relaunch.sh` - Hermetic tests for the crash relaunch (pane registry hook + `tmux-claude-relaunch.sh`) on a private `tmux -L` server
- `tests/test-rc-start.sh` - Hermetic tests for `rc-start.sh`/`rc-stop.sh` (bridge detection, respawn into restored shells, idle timeout, SIGTERM stop, the tmux post-restore hook) on a private `tmux -L` server
- `tests/test-ttalk-serialize.sh` - Hermetic tests for `ttalk`'s speaker lock (no overlap under concurrent calls, timeout drop, stale-lock reclaim; flock and mkdir paths), its `--disable`/`--enable` mute toggle and its `--volume` setting
- `tests/test-keyring-unlock-wait.sh` - Hermetic tests for `keyring-unlock-wait` (unlocked/empty fast path, bounded wait when the dialog can't show or never answers, no Secret Service) on a private D-Bus session
- `tests/test-ntfy-send.sh` - Hermetic tests for `ntfy-send` (message and headers verbatim, optional Bearer token, failure exit codes, topic URL never printed)
- `tests/test-bt-fix.sh` - Hermetic tests for `bt-fix` (reconnect via saved pairing, fresh pair/trust/connect, stale pairing removed only after yes, new-address twin, never-seen device, listing and filtering, `BT_FIX_FZF_OPTS` appended verbatim)
- `tests/test-wifi-pick.sh` - Hermetic tests for `wifi-pick` (list order and dedupe, saved/changed-password/new WPA2/WPA3/open/802.1X flows, password never in argv, disconnect and radio-on only after a yes, NAME filter without fzf, `WIFI_PICK_FZF_OPTS` appended verbatim)
- `tests/test-tmux-wifi-popup.sh` - Hermetic tests for `tmux-wifi-popup.sh` (same contract as the Bluetooth popup, plus the hidden password question)
- `tests/test-tmux-control-panel.sh` - Hermetic tests for `tmux-control-panel.sh` (popup on the given client, entries and palette look, each entry runs its tool in the same popup, toggles redraw the client, hub only when installed, Esc runs nothing; stub tools, tmux and fzf)
- `tests/test-tmux-bt-popup.sh` - Hermetic tests for `tmux-bt-popup.sh` (borderless panel-coloured popup sized like the palette and opened on the given client; `BT_FIX_FZF_OPTS` carries the palette colour roles, prompt and title with `FZF_DEFAULT_OPTS` cleared; progress and question reach the popup; outcome waits for a key, Esc closes at once; stub tmux and bt-fix)
- `tests/test-tmux-weather.sh` - Hermetic tests for `tmux-weather.sh` (line format, non-blocking cache read, no refetch while fresh, failure keeps the last line with retry backoff, location in the URL; stub curl and tmux)
- `tests/test-quickshell-hub.sh` - Hermetic tests for the control hub (config layout and tile/plugin resolution, every helper the panels exec is shipped, previews match their palettes, `hub-shell` qs calls, the wofi/dunst helper replacements, `omarchy-theme-set` rendering and reloads); optional live load with `QS_BIN`
- `tests/test-mem-pressure-watch.sh` - Hermetic tests for `mem-pressure-watch` (snapshot content and order, trigger/notify thresholds, cooldowns, missing notifiers, poll fallback) and `installers/memwatch.sh` (unit oomd preferences, oomd drop-in copied, systemd-oomd enabled)
- `tests/test-tmux-theme.sh` - Hermetic tests for `tmux-theme.sh` and `config/tmux/themes/` (every theme sources cleanly, sets the same options, keeps continuum, the `%d/%m %a %H:%M` date/time and the Bluetooth segment before it in `status-right`; the bluetooth click wiring; apply/save/default/unknown name; picker Enter and Esc via stub fzf; `tmux.conf` wiring) on a private `tmux -L` server

## Learning from Mistakes

When judgment errors occur, use the **systematic learning skill** to transform mistakes into improvements:

**Skill**: `/learn-from-mistake`
- Auto-triggers when you say "I made a mistake" or "that was wrong"
- Guides structured 8-step post-mortem analysis
- Creates comprehensive documentation in `docs/learning/`
- Updates CLAUDE.md with new safeguards
- Stores lessons in MCP persistent memory

**Process**:
1. Fix the mistake properly first
2. Let skill guide you through root cause analysis
3. Create analysis + summary documentation
4. Determine appropriate safeguard level (docs → process → automation → architecture)
5. Commit all learning artifacts

**Templates**: `config/claude/skills/learn-from-mistake/TEMPLATES.md`
**Examples**: `config/claude/skills/learn-from-mistake/EXAMPLES.md`
**Historical incidents**: `docs/learning/`

## External Dependency Safety Rules

**CRITICAL: Never edit files outside this repository's git control**

Before editing ANY file, verify it's tracked in git or symlinked to the repo:

```bash
# Method 1: Check if tracked in repo
git ls-files --error-unmatch <file_path> 2>/dev/null

# Method 2: If symlink, verify target is in repo
readlink -f <file_path>  # Should point to repo directory
```

**Common External Dependencies:**
- `nuvemlabs/secrets` → Source: `~/repos/secrets/` → Installed: `~/.local/lib/secrets/` (library) + `~/.local/bin/secrets-doctor` (CLI), or packaged: `brew install nuvemlabs/tap/secrets` (tap repo `~/repos/homebrew-tap`) / AUR `nuvemlabs-secrets` (pending)
- `nuvemlabs/secrets-bridge` → Source: `~/repos/secrets-bridge/` → Installed: `~/.local/lib/secrets-bridge/` + `~/.local/bin/secrets-bridge` (by `--secrets`), or `brew install nuvemlabs/tap/secrets-bridge`
- System packages (brew, apt, etc.) → Never edit installed files
- Symlinked configs → Edit source in `config/`, not `~/.config/`

**If you find a bug in an external dependency:**
1. Find the SOURCE repository (check `installers/` scripts for clone paths)
2. Edit and commit the fix in the source repo
3. Re-run the installer to apply: `./install.sh --<component>`
4. Never edit files in `~/.local/lib/`, `~/.local/bin/`, or other install dirs

**Exception:** Symlinked files are OK to edit (e.g., `~/.config/nvim/` → `dotfiles/config/nvim/`)
- Use `readlink -f <path>` to verify the target is in this repo

## Adding New Configurations

1. Create config in appropriate `config/<tool>/` directory
2. Add installer in `installers/<tool>.sh` following existing pattern
3. Add dispatch case in `install.sh` if standalone option needed
4. Use `lib/install-common.sh` functions for symlinks and backups
