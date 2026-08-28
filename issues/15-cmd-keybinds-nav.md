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
Decide whether tabs/sessions mean Ghostty tabs or tmux windows/sessions — if
tmux, the binding should send the tmux prefix sequence rather than a Ghostty
action, and the tmux side (`config/tmux/tmux.conf`) needs matching bindings.
