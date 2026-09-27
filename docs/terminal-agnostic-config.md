# Principle: keep configuration out of the terminal emulator

**Put behaviour in the most portable layer that can do the job. Terminal-emulator
config is the last resort, not the first.**

## Why

Every setting that lives in `config/ghostty/config` is a setting that does not
exist in Kitty, WezTerm, Alacritty, iTerm2, Windows Terminal, the VS Code
integrated terminal, or an SSH session from someone else's machine. The moment a
second terminal is used — new laptop, a Linux box, a colleague's screen-share, a
remote shell — the workflow silently degrades and the fix is to write the same
behaviour again in a second dialect.

That is how you end up maintaining N terminal configurations that must be kept in
sync by hand, with N different keybind syntaxes and N sets of bugs. The cost is
not the first file; it is every file after it, forever.

The workflow this repo is built around (tmux + shell + nvim) is already portable.
Anything pushed down into the emulator breaks that portability for no gain.

## The layer order

Implement a behaviour at the **highest-numbered layer that can do it**:

1. **tmux** (`config/tmux/tmux.conf`) — panes, windows, sessions, copy-mode,
   scrollback, status line, popups. Works identically under every emulator and
   over SSH. This is the default home for anything navigational.
2. **Shell** (`config/shell/`, `config/zsh/`, `config/bash/`) — aliases,
   functions, prompt, keybinds via ZLE/readline, env.
3. **Application config** (`config/nvim/`, git, etc.) — behaviour that belongs to
   one program.
4. **Terminal emulator** (`config/ghostty/`) — *only* what no other layer can
   express.

## What legitimately belongs in the emulator

Short list, and it should stay short:

- Rendering: font, font size, theme, opacity, shaders, cursor style.
- Window/OS integration: quick-terminal hotkey, window decorations, startup size.
- Translating a key the OS swallows (e.g. macOS `cmd`) into a byte sequence the
  portable layers can see.

That last one is the pragmatic exception in this repo: macOS `super+<key>` is
invisible to tmux and the shell, so `config/ghostty/config` maps `super+X` to the
corresponding control code. Note the shape of that hack — the emulator only
*forwards* the key; the actual behaviour still lives in tmux or the shell. Keep it
that way. An emulator binding that *implements* a behaviour (splitting, tab
switching, resizing) is the thing to avoid.

## Test before adding an emulator setting

Ask, in order:

1. Can tmux do this? → do it in tmux.
2. Can the shell do this? → do it in the shell.
3. Does it only work because of *this* emulator? → then either accept it is
   cosmetic/OS-level, or find the portable equivalent.
4. If it must go in the emulator: add a comment saying **why** no portable layer
   could do it. Future-you will otherwise assume it was arbitrary.

## Consequence for new terminals

If a second emulator is ever added to this repo, the correct outcome is that its
config is *small* — fonts, theme, and the same `super+` forwarding table. If it
turns out to be large, that is evidence behaviour leaked into layer 4 and should
be migrated down.
