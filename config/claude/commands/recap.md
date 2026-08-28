---
description: Inspect this pane's shell history/scrollback and summarize what we were up to
argument-hint: [optional focus, e.g. "the docker stuff", "last hour"]
allowed-tools: Bash(tmux capture-pane:*), Bash(tmux display-message:*), Bash(tail:*), Bash(wc:*), Grep, Read
---

<!--
Usage: /recap [optional focus]
Reconstructs what was happening in THIS terminal pane before/around this
Claude session, from tmux scrollback. Read-only; never re-runs anything.
-->

Inspect this pane's shell history and figure out what we were up to.
Focus (if given): $ARGUMENTS

## Step 1 — Capture this pane's scrollback

The shell config uses `append_history` + `no_share_history`, so the live
pane's commands are NOT in `~/.zsh_history` until the shell exits. The
authoritative source is tmux scrollback for THIS pane.

Target `$TMUX_PANE` explicitly — `tmux display-message`/`capture-pane`
without `-t` acts on the currently ACTIVE pane, which may be a different
one:

```bash
tmux capture-pane -p -t "$TMUX_PANE" -S -2000 > "$CLAUDE_SCRATCHPAD_OR_TMP/pane-recap.txt"
wc -l "$CLAUDE_SCRATCHPAD_OR_TMP/pane-recap.txt"
```

(Use the session scratchpad dir if available, otherwise a temp file.)
If 2000 lines doesn't reach back far enough for the story (or the user
asked about something older), re-capture with `-S -10000` or `-S -`
(full history; limit is 50000 lines).

Fallbacks, in order:
- `$TMUX_PANE` unset but inside tmux → `tmux display-message -p '#{pane_id}'` and confirm with the user it's the right pane.
- Not in tmux at all → `tail -300 ~/.zsh_history` (strip the `: <ts>:0;` prefixes) and say the live session's commands may be missing.

## Step 2 — Read and reconstruct

Read the capture (Grep for prompt lines / commands first if it's large,
then Read the interesting regions). Reconstruct:

1. **What was being worked on** — project/dir (cd, git commands, paths in prompts), branches touched.
2. **The narrative** — the sequence of commands and their visible output: what was tried, what failed (error output matters), what eventually worked.
3. **Where it left off** — the last few commands before this Claude session started, and any unfinished thread (failing test, half-done rebase, a server left running).

Ignore noise: prompt decorations, `ls`/`clear`, completion menus, this
Claude session's own output at the tail of the capture.

## Step 3 — Report

Reply with a short summary:
- **TL;DR** — one or two sentences: what we were up to.
- **Timeline** — brief bullet sequence of the meaningful activity.
- **Loose ends** — anything that looked unfinished or broken, with the exact command/error to pick it back up.

Read-only rule: do NOT re-run commands from the history to "check" them —
only summarize what the scrollback shows. Never echo secrets/tokens that
appear in the capture; refer to them by name only.
