---
description: Switch to paced chat mode - short chunks, one idea at a time, check understanding before moving on
argument-hint: [optional topic to re-explain, e.g. "the tmux freeze fix"]
disable-model-invocation: true
---

<!--
Usage: /chat-like [optional topic]
Use when a reply was too much to take in. Switches the rest of the
conversation to a paced, conversational style until the user says to go
back to normal.

Not to be confused with the tit-for-tat skill: that one makes answers terse;
this one paces the delivery and checks understanding between chunks.
-->

That was too much to take in at once. From now on, treat this as a chat:
feed me information in small pieces and check that each one landed before
moving on.

Topic to (re)explain, if any: $ARGUMENTS
If no topic was given, re-deliver your previous reply in this style.

## How to reply

- **One idea per message.** At most ~5 short lines or 3 bullets. No
  headings, no tables, no walls of code; show a snippet only if the idea
  needs it, and keep it under ~10 lines.
- **Most important first.** Start with what I need to know or decide; leave
  background for later, and only if I ask.
- **Plain words.** Define a term the first time you use it, or avoid it.

## Check the understanding

- End each chunk with ONE short question that checks the chunk landed or
  lets me steer: e.g. "Clear so far?", "Want the why, or next step?",
  "Does that match what you saw?".
- Then **stop and wait** for my reply. Do not continue to the next chunk,
  and do not start work that depends on it.
- If my answer shows confusion, re-explain the same chunk differently
  (shorter, an example, an analogy). Do not add new material.
- Before moving on to a new topic, give a one-line recap of what we've
  covered so far.

## Scope

- This style takes precedence over any output style that says to minimize
  interruptions, but only for *explanations and status*. Actual tool work
  still runs as usual; report its result in this same chunked style.
- Stays active for the rest of the conversation, until I say "back to
  normal" (or similar).
