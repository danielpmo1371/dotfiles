# Workflow State

## Active: Portable Cmd/Alt meta-layer keybindings (2026-07-13)

### State
- **Status**: CONSTRUCT_COMPLETE — awaiting user smoke test + merge
- **Phase**: Verification (user-assisted)
- **Branch**: worktree-alt-meta-keybindings (worktree at .claude/worktrees/alt-meta-keybindings)
- **Baseline**: 65/65 hermetic tests green (validator 33, hooks 32)

### Goal
Make the Cmd-key conveniences portable to Linux (Alt) by moving keybinding
*semantics* out of Ghostty into zsh/tmux, leaving Ghostty as a thin adapter:
Cmd+X → the same ESC-prefix bytes Alt+X produces natively on Linux (and
Option+X already produces on macOS via `macos-option-as-alt`).
Result: Cmd (Mac) ≡ Option (Mac) ≡ Alt (Linux), one binding vocabulary,
defined once in repo-tracked shell/tmux config, portable to any emulator.

### Key design constraints
1. **vi-mode ESC hazard**: zshrc uses `bindkey -v`. An *unbound* meta sequence
   (ESC+x) in vi insert mode = exit to normal mode + run `x` as a vi command
   (destructive). Therefore: NO blanket a–z transliteration. Ghostty emits
   meta ONLY for keys with an explicit zsh/tmux consumer; unused Cmd combos
   are dropped from the config entirely.
2. **tty line-discipline keys can't move to shell**: SIGINT/SIGTSTP/EOF are
   kernel reactions to literal bytes \x03/\x1A/\x04. Cmd+C/Z/D stay as
   control-byte mappings in Ghostty.
3. **Shift-arrow alias group stays**: super+[/]/shift+hjkl send Shift/
   Ctrl-Shift-arrow escape sequences whose semantics ALREADY live in tmux
   (S-Left/S-Right window nav etc., tmux.conf:114-123). On Linux, real
   Shift+arrows produce the same sequences natively — nothing to migrate.
   (Deliberately NOT binding tmux `M-[` — ESC-[ is the CSI introducer and
   collides with arrow-key parsing.)

### Inventory: what each Cmd combo actually drives (verified against tmux.conf)
| Cmd combo | bytes | Real consumer today |
|---|---|---|
| Cmd+E | C-e | tmux prefix (tmux.conf:10) |
| Cmd+A | C-a | tmux root: nvim scratch popup (:148) |
| Cmd+Q | C-q | tmux root: Claude popup (:133) |
| Cmd+W | C-w | tmux root: lazygit popup (:151) |
| Cmd+H/J/K/L | C-h/j/k/l | tmux root: pane nav (:89-92) |
| Cmd+E Cmd+I / i | prefix C-i / i | Claude picker popup (:138-139) |
| Cmd+E Cmd+N / q | prefix C-n / q | Claude popup (:134-135) |
| Cmd+E Cmd+E | prefix C-e | copy-mode (:61 overrides :12 send-prefix) |
| Cmd+E Cmd+S / Cmd+R | prefix C-s / C-r | tmux-resurrect save / restore (plugin) |
| Cmd+R | C-r | shell history search (zshrc:53; bash vi-mode) |
| Cmd+U | C-u | shell kill-line-back (vi-insert ^u) — likely unintended |
| Cmd+C / Z / D | \x03/\x1A/\x04 | kernel tty: SIGINT / SIGTSTP / EOF (C-d explicitly unbound in tmux root :35) |
| Cmd+[ ] / Cmd+Shift+hjkl,[ ] | Shift(/C-S)-arrow seqs | tmux window/client nav (:114-123) |
| Cmd+V | (commented) | native macOS paste |
| Cmd+B F G I M N O P Q(std) S T X Y, Cmd+1–0, Cmd+`, Cmd+- | assorted | no consumer / nonsensical — DROP (approved) |

### Revised design (user feedback 2026-07-13 incorporated)
- **Bash included**: identical meta bindings in `config/bash/bashrc`
  (readline `bind` in vi-insert + vi-command keymaps) mirroring zsh bindkeys.
  Both shells are vi-mode → same unbound-ESC hazard, same fix.
- **Every current tmux shortcut keeps working** — guaranteed by phasing:
  Phase 1 is purely ADDITIVE (M- mirrors alongside existing C- bindings);
  nothing existing is removed until the M- layer is proven.
- **Scrolling (priority)**: NEW tmux root `M-u` = `copy-mode -u` (enter
  scrolled up one page), `M-d` = page down in copy-mode context; mouse wheel
  stays (mouse on). Works identically on Mac (Cmd/Option+U) and Linux (Alt+U),
  incl. bare TTY. Ghostty ctrl+u/d native-scrollback bindings KEPT for the
  outside-tmux case (shadowing shell C-u kill-line accepted by user).
- **vim-tmux-navigator (christoomey) adopted** for tmux + nvim (LazyVim spec):
  vim-aware C-hjkl pane/split nav. Manual root C-hjkl binds (:89-92) removed
  in favor of the plugin's; M-hjkl binds (:241-244) rewrapped with the same
  is_vim check; nvim gets <C-h/j/k/l> + <A-h/j/k/l> → TmuxNavigate* maps.
  Ctrl family already portable (exists on both OSes); meta family added for
  Cmd/Alt symmetry.
- **tmux-sensible**: ALREADY INSTALLED (tmux.conf:184). Its options defer to
  explicitly-set user values (escape-time, history-limit, display-time etc.
  all set in this conf) and it skips already-bound keys (prefix C-n popup is
  safe). Verdict: keep, no action; it neither helps nor hinders migration.

### Plan — Phase 1 (additive M- layer; zero behavior removed)
1. tmux.conf:
   a. `set -g prefix2 M-e`; prefix-table mirrors: `bind M-e copy-mode`,
      `bind M-i` → picker, `bind M-n` → Claude popup.
   b. Root mirrors: `M-a` scratch nvim, `M-q` Claude popup, `M-w` lazygit.
   c. Scroll: root `M-u` `copy-mode -u`; `M-d` page-down (copy-mode table).
   d. resurrect: prefix `M-s`/`M-r` mirrors → ASK (Q2) or defer.
2. vim-tmux-navigator: tmux @plugin + replace :89-92 and rewrap :241-244
   with is_vim-aware binds; NEW `config/nvim/lua/plugins/tmux-navigator.lua`.
3. zshrc meta block: `\ea`…`\el`, `\eq`, `\ew`, `\er` (history search),
   `\eu`, `\ed`, `\ee` — bound in viins+vicmd. Outside tmux these are the
   only consumers; each gets a sensible/harmless action (documented inline)
   so no meta key ever falls through to raw vi-command execution.
4. bashrc meta block: same keys via readline `bind`, vi-insert + vi-command.
5. Verify Phase 1 (isolated tmux server `-L kbtest`, list-keys diff before/
   after; zsh/bash binding listings; 65-test baseline; manual smoke on Mac).
   Commit atomically per file-group: tmux → navigator(nvim+tmux) → zsh → bash.

### Plan — Phase 2 (flip Ghostty to meta adapter; separate commits, revertable)
6. Ghostty keep-set → meta: super+e/a/q/w/r/u/d/i/n/s → `text:\x1b<key>`;
   hjkl → meta; c/z stay control bytes (tty semantics); v stays commented;
   shift-arrow alias group unchanged; DROP super+b f g m o p t x y,
   super+1–0, super+`, super+- and redundant ctrl+z (approved).
   NOTE Cmd+D: becomes M-d (scroll down); EOF remains on physical Ctrl+D.
7. Update comments: adapter contract ("Cmd→meta; semantics live in tmux/shell").
8. Docs: CLAUDE.md Key Patterns paragraph (adapter-vs-semantics layering;
   Linux/TTY needs zero emulator config; Option+X = test harness on Mac).
9. Full verification: ghostty +validate-config (if available), re-run
   baseline, manual smoke of every inventory row on Mac (user-assisted).

### Open questions
- Q1: "Cmd+E U" — prefix+u is NOT currently bound (no plugin provides it).
  What do you use it for / what should it do?
- Q2: Mirror resurrect save/restore on prefix M-s/M-r (reaches into plugin
  binding conventions), or leave resurrect on prefix C-s/C-r only?
- Q3: Cmd+S standalone — no tmux root binding; C-s is XOFF terminal-freeze
  risk in bash outside tmux. Assumed you meant prefix C-s (resurrect save).
  Confirm?

### Log
- 2026-07-13 — Worktree created, baseline green, blueprint drafted.
- 2026-07-13 — User feedback: include bash; preserve ALL tmux shortcuts;
  scrolling priority; oddballs approved for drop; evaluate vim-tmux-navigator
  (wants tmux+nvim) and tmux-sensible. Plan revised to phased additive
  design; tmux-sensible found already installed. Awaiting approval.
- 2026-07-13 — Plan approved (both shells confirmed in scope; skip prefix+u
  [it's TPM clean_plugins, verified]; no resurrect M-s/M-r mirrors).
- 2026-07-13 — CONSTRUCT complete, commits (all gitleaks-clean):
  - 7f39d68 tmux meta layer (prefix2 M-e, popup mirrors, vim-aware C-/M-hjkl
    with is_vim, M-u scrollback via copy-mode, copy-mode-vi M-u/M-d paging)
  - 3d89848 nvim vim-tmux-navigator spec (C-hjkl + A-hjkl)
  - 27051da zsh+bash meta blocks, viins+vicmd / vi-insert+vi-command,
    13 keys each (a e r h j k l i n q w u d), mirrored files
  - f7edf49 ghostty flip: Cmd→meta adapter (13 keys), C/Z stay control
    bytes, all dead mappings dropped
- 2026-07-13 — Verified: isolated tmux server (-L kbtest) shows prefix2 +
  all M- binds in root/prefix/copy-mode-vi tables; zsh/bash binding
  listings green in both keymaps; ghostty +validate-config exit 0;
  65/65 suite re-run green.
- BEHAVIOR CHANGES to smoke-test after merge: Cmd+D no longer sends EOF
  (physical Ctrl+D unchanged); Cmd+M / Cmd+- no longer send Enter;
  resurrect save = Cmd+E Ctrl+S (Cmd+E Cmd+S dropped per user);
  Cmd+B/F/G/O/P/S/T/X/Y and Cmd+digits do nothing now.
- NOTE: nothing is live yet — installed configs symlink to the MAIN
  checkout, not this worktree. After merge: tmux source-file, fresh
  shells, Ghostty reload config, nvim :Lazy sync (installs navigator).

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
- `mbie-immigrationnz-prod` or `mbie` (employer)
- `INZ_TDS_DEV`, `INZ_TDS_SIT` (Azure subscriptions)
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
  - Enhanced td-iac MEMORY.md with "Terraform Plan Verification Protocol -- HARD GATE" section
  - Updated docs/learning/README.md with incident entry
  - New protocol: Destroy count is FIRST check, >0 = automatic FAIL, no exceptions
  - MCP memory not available for storage (tools not loaded)
  - Project: td-iac, Story 193236, Branch: feature/193236-Refactor-ServiceBus

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
  1. HIGH: CD allow-authority now lives solely in workspace-writable .claude/pipeline-registry.json — agent (Edit/Write/Bash) can modify it, takes effect uncommitted, no independent code layer for non-pre/prd-substring prod stages (verified: INZ_PaaS_SHARED approved when listed)
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
- Verification: 33+32 tests green; live td workspace re-validated (sitae approved, INZ_PaaS_SHARED blocked); installer delivered write-guard symlink; only user-dirty zshrc + this file remain uncommitted
- Remaining known gaps (not in approved scope, surfaced to user): guard skips checks 0-2 with no registry; guard terraform constants (802) still hardcoded; agent-doc diagram claims guard invokes validator; stagesToSkip derived from caller allStages not registry stages.all
