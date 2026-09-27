# cmd keybinds: restore scroll-down, add tab/session navigation

## 1. cmd+d should scroll down again

`super+d` was sending `^D` (EOF) and closing shells, so it is currently
`keybind = super+d=unbind` (`config/ghostty/config:112`). It used to scroll down.
Rebind it to `scroll_page_down` (the same action `ctrl+d` already has at line 92)
so the old behaviour is back without the EOF side effect.

## 2. Tab / session navigation

Wanted:

| Key     | Action       |
|---------|--------------|
| cmd+u   | tab left     |
| cmd+i   | tab right    |
| cmd+n   | session down |
| cmd+m   | session up   |

Caveat — all four are already bound in `config/ghostty/config`, so this is not a
free grab. Check what actually depends on them before overwriting:

- `super+u` → `text:\x15` (^U, kill-line)
- `super+i` → `text:\x09` (^I, **Tab**)
- `super+n` → `text:\x0E` (^N, next in history/completion)
- `super+m` → `text:\x0D` (^M, **Enter**)

`super+i` and `super+m` are the risky two: they currently deliver Tab and Enter.

**Constraint on the fix** — see `docs/terminal-agnostic-config.md`. "Tab" and
"session" here must mean **tmux windows and sessions**, not Ghostty tabs. Ghostty's
only job is forwarding `super+<key>` to a control code; the navigation itself is
bound in `config/tmux/tmux.conf`. Binding these to Ghostty tab actions would make
the workflow exist only under Ghostty and require reimplementing it in every other
terminal.

Item 1 (`cmd+d` → `scroll_page_down`) is a genuine emulator-layer setting:
scrollback is owned by the emulator when not inside tmux, and `ctrl+d` is already
bound the same way at line 92.
