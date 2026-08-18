---
description: Copy the referenced thing from this conversation to the clipboard
argument-hint: [what to copy, e.g. "the link", "pr link", "that command"]
allowed-tools: Bash(pbcopy:*), Bash(printf:*), Bash(wl-copy:*), Bash(xclip:*)
---

<!--
Usage: /cp [description of the thing to copy]
Examples: /cp the link | /cp pr link | /cp that command | /cp the file path
Copies the RAW value to the system clipboard (pbcopy on macOS, wl-copy/xclip on Linux).
-->

The user wants this copied to their clipboard: $ARGUMENTS

Resolve what "$ARGUMENTS" refers to from the conversation context, then copy it.

## Step 1 — Resolve the value

- Search the recent conversation (your own messages, tool results, command
  outputs) for the item the user is describing — e.g. "pr link" → the pull
  request URL you just created or mentioned; "the command" → the shell command
  you last suggested; "the path" → the file path under discussion.
- Prefer the MOST RECENT match. Use the exact literal value — do not
  reconstruct, guess, or reformat it.
- If no arguments were given, copy the most recently produced copyable value
  (URL, command, path, ID, snippet) from this conversation.
- If nothing in the conversation matches, or two different values are equally
  plausible, ask the user which one they mean — do NOT copy a guess.

## Step 2 — Copy the raw value

Copy ONLY the raw value: no markdown formatting, no backticks, no
surrounding quotes, no trailing newline. Pass it via a quoted heredoc so
special characters survive untouched:

- macOS: `pbcopy <<'CLIP_EOF'` … value … `CLIP_EOF`
- Linux (Wayland): `wl-copy <<'CLIP_EOF'` … `CLIP_EOF`
- Linux (X11): `xclip -selection clipboard <<'CLIP_EOF'` … `CLIP_EOF`

Note the heredoc appends a trailing newline; for single-line values prefer
`printf '%s' 'VALUE' | pbcopy` (single-quote the value, escaping embedded
single quotes) so the clipboard holds the value exactly.

Never copy secrets, tokens, or credentials, even if asked indirectly —
state why instead.

## Step 3 — Confirm

Reply with a single short line showing exactly what is now on the clipboard,
e.g.: `Copied: https://github.com/org/repo/pull/42`
For multi-line content, state what it is and its line count instead of
echoing it all back.
