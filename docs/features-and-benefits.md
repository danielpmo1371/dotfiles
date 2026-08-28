# Features & Benefits

What these dotfiles actually do for the daily workflow — trigger, behaviour,
and the benefit each feature buys. The [README](../README.md) covers *what's
installed and how*; this covers *why it's worth it*.

Keyboard note: on macOS, Ghostty translates `Cmd+<key>` into control codes, so
the tmux prefix `C-e` is typed as **`Cmd+e`**. Binds below are written in tmux
notation.

## 1. A new machine in one command

| Feature | Benefit |
|---|---|
| `curl … bootstrap.sh \| bash` | Zero-to-configured from a fresh OS: installs git (any package manager, or Xcode CLT on macOS), clones, and runs the installer. |
| Two-phase install (`--all` = dotfiles core, then Claude Code handover) | The terminal/tmux workflow is self-contained; the AI layer is an add-on, not a dependency. `--dotfiles` gives you just the core. |
| Resilient steps with timing | One broken component never aborts the run — failures are collected and summarized at the end, and every step's duration is logged so slow spots are visible. |
| Timestamped backups + `--restore` / `--list-backups` / `--cleanup-backups` | Installing over an existing setup is reversible. Every replaced file lands in `~/.dotfiles-backup-<timestamp>/` with a manifest. |
| Dialog mode with Minimal/Developer/Full profiles | Non-experts (or future-you) can cherry-pick components without memorizing flags. |
| Docker e2e tests (`tests/test-docker.sh`) across Arch, Ubuntu, Debian, Fedora | The claim "works on Linux" is continuously provable, not aspirational. |

## 2. A workflow that survives switching terminals

Behaviour lives in the most portable layer that can implement it —
**tmux → shell → app config → terminal emulator** (rationale:
[terminal-agnostic-config.md](terminal-agnostic-config.md)). Concretely:

- **Ghostty stays thin**: rendering, OS integration, and a `Cmd→Ctrl` bridge
  that forwards `super+<key>` as control codes. That bridge is what makes tmux
  feel native on macOS — `Cmd+e` is the prefix, `Cmd+q/a/w/s` reach the popups.
- **Kitty config is a documented translation** of the Ghostty one, with every
  missing capability recorded as a `# No Kitty equivalent:` comment. Switching
  emulators costs a font-and-theme file, not a workflow rewrite.
- **Benefit**: no lock-in. The muscle memory works in Ghostty, Kitty, over
  SSH, and in whatever terminal comes next.

## 3. Tmux as the command center

Prefix is `C-e` (`Cmd+e` on macOS).

### Never lose state
- **resurrect + continuum**: autosave every 15 minutes, auto-restore on tmux
  start, scrollback and nvim sessions included. *A reboot costs nothing.*
- **Pane border labels**: every pane shows its index, cwd, and title on its
  border — no guessing which shell is where.

### Floating popups instead of window juggling
| Bind | Popup |
|---|---|
| `C-a` | Neovim in the current pane's directory |
| `C-w` | lazygit in the current pane's directory |
| `C-s` | clean zsh shell |
| `C-q` | Claude Code scratchpad (see §4) |

All open as 80% floating overlays and close without disturbing the layout —
quick edit, quick commit, quick command, back to work.

### Navigation without thinking
`C-h/j/k/l` and `M-h/j/k/l` move between panes prefix-free;
`vim-tmux-navigator` makes nvim splits and tmux panes one continuous space;
`S-Left/Right` switch windows and `S-Up/Down` switch whole sessions
(`Cmd+[`/`Cmd+]` and `Cmd+Shift+j/k` via the Ghostty bridge).

### Focus modes
- `prefix Z` — **zen mode**: status bar and borders vanish.
- `prefix V` — **cinema mode**: makes the whole stack transparent (tmux styles
  *and* Ghostty opacity, shaders auto-disabled) for video-behind-terminal;
  toggling off restores the exact previous config.

### The setup teaches itself
- `prefix ?` — help menu: full keybinding cheat sheet, or type a question
  straight to Claude.
- `prefix t` — random curated tip; a background timer also surfaces one every
  10 minutes while you're attached. Discoverability is built in, so features
  don't rot unused.
- `tmux-which-key` and a command palette (`C-p`) cover the rest.

## 4. AI one keystroke away

- **`q "question"`** — instant terminal answer, tuned for lowest
  time-to-first-token (Groq by default; `AI_PROVIDER`/`AI_MODEL` switch
  provider or model). Renders as markdown, copies the answer to the clipboard,
  and appends every Q&A to `~/.q_history.md` — a searchable log of everything
  you've asked.
- **`* how do I …`** — typing `*` before a question at the prompt routes it to
  `q`. No command to remember; asking the AI is as cheap as typing the thought.
  (Implemented as a ZLE widget so the text is never shell-evaluated.)
- **`C-q`** — persistent Claude Code scratchpad popup. True toggle: same key
  opens and hides it, and the underlying session survives, so a long-running
  conversation is always one keystroke away from any pane.
- **`prefix i`** — Claude pane picker: fzf list of *every* pane in every
  session running Claude Code, with a live preview of each conversation; Enter
  jumps straight to it. Running five Claudes across projects stops being
  confusing.
- **`prefix u`** — session summaries for the current project: what was asked,
  which tools ran, which files changed — rendered from the logging hooks (§5).
- **In nvim**: `<leader>a…` drives claudecode.nvim (toggle, send selection,
  accept/deny diffs), so AI assistance is available inside the editor too.

## 5. Claude Code that remembers, logs, and can't hurt you

### Memory
Session-start hooks inject relevant memories (recent decisions, git context,
tagged knowledge) and auto-capture new decisions/errors/learnings as you work
— with `#skip` / `#remember` inline overrides. **Claude starts each session
already knowing what you decided last time.**

### Session logging
Every session gets a human-readable folder under `tmp/claude/sessions/`
(project, date, time): every prompt (`requests.log`), the evolving goal
(`goals.log`), and an AI-written summary per turn (`summaries.log` — metadata
is written first so a hung summarizer can never lose the record). This is the
data behind `prefix u`.

### Safety hooks — each removes a specific risk
| Guard | Risk removed |
|---|---|
| `destructive-ops-guard.sh` | An agent irreversibly deleting cloud resources or unversioned files (`az/aws/gcloud/kubectl/docker/gh/helm` deletes, `terraform destroy`, `rm` outside a git work tree). |
| `pipeline-trigger-guard.sh` | Pipeline triggers via raw `az`/`curl` that would bypass validation — everything is forced through the one auditable MCP path. |
| `pipeline-guard.sh` | Accidental production deploys: blocks `pre/prd/prod` stages and terraform apply, **fails closed** when its keychain config is absent, and writes a JSONL audit trail. |
| `pipeline-registry-write-guard.sh` | An agent granting itself production access by editing the stage allow-list; only humans edit and commit the registry. |

All guards fail closed on missing `jq` or unparseable input, and force the
agent to surface the block to you rather than quietly working around it.

### Scale when needed
Agent teams (`/setup-machine`, `/test-all-distros`, `/review-changes`) run
parallel installs, per-distro Docker tests, and multi-angle pre-commit reviews.
Custom commands cover the rest of the loop: `/review-before-commit`,
`/pipe-deploy` (guarded CI/CD), `/sdlc-start` (a ten-agent Azure DevOps
workflow), and a `learn-from-mistake` skill that turns errors into documented
safeguards in `docs/learning/`.

## 6. Safety nets under everyday commands

- **`rm` never deletes** — it's a function that moves arguments to a trash
  directory. The "oops, wrong file" class of data loss is gone.
- **Secrets live in the OS keychain** (macOS Keychain / Linux libsecret) via
  `secret_set` / `secret` / `secret_list`. A legacy plaintext
  `~/.accessTokens` is auto-migrated on first shell load, then never again.
  API keys are fanned out to the env vars each tool expects — nothing lands in
  plaintext config (including MCP server definitions, which reference secrets
  as `secret:KEY` and are rewritten to env placeholders on sync).
- **`Ctrl-D` won't kill your shell** (`ignore_eof`) — the key is reserved for
  scrolling.
- **Backups before every install** (§1).

## 7. Small ergonomics that compound

- `cd` auto-lists the directory (`lsd`) on arrival; **zoxide** makes `z dot`
  jump anywhere by fragment.
- **fzf everywhere, in tmux popups**: `flg` (fuzzy git log with commit
  preview), `nzz` (ripgrep → preview → open nvim at the exact line), `fvim`
  (fuzzy-open a file), `**<Tab>` completion.
- **`add-shortcut <name>`** — promotes the previous command from history to a
  permanent alias in your rc file. Friction to automate a habit: one command.
- **Git configured idempotently on every shell start**: histogram diffs,
  `push.autoSetupRemote` (no more `--set-upstream`), `co/s/ds/cm/ca/lg`
  aliases — a fresh machine gets them with zero setup.
- **`copy-last-cmd-n-output-tmux.sh`** — prompt markers printed by the shell
  make "copy exactly the last command's output" reliable; `tmux-capture-context.sh`
  dumps every pane for handing context to an AI.
- **Prompt & startup**: Powerlevel10k with vi mode, syntax highlighting,
  autosuggestions; a fastfetch banner cached for 24h so the visual payoff
  costs ~0ms of startup.
- **`Cmd+`` anywhere**: Ghostty's global quick-terminal drops down over any
  app, instantly.
- `prefix S` — fzf picker for Ghostty GLSL shaders (30 curated effects),
  live-applied.

## 8. One visual identity

Gruvbox across tmux, nvim (`contrast=hard`), and the status bar; MesloLGS
Nerd Fonts installed by `--fonts` so p10k glyphs render everywhere — including
macOS Terminal.app, whose default profile font is set automatically (the one
thing `defaults write` can't do reliably).

---

*Building blocks not yet bound to keys: `tmux-corner-pane.sh` (pinned
top-right info popup — generic toggle, currently shell-invoked only).*
