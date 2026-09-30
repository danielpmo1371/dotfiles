---
name: ntfy-notifications
description: Send a push notification to Daniel's phone via ntfy (ntfy.sh) using the ntfy-send CLI. Use when the user asks to be notified, pinged, alerted or told "on my phone" / "via ntfy" when something finishes or fails, when a long-running task (build, migration, upgrade, backup, scheduled follow-up) completes after the user said they are stepping away, or when an alert needs to reach the user urgently. Also covers testing delivery and troubleshooting a missing NTFY_TOPIC_URL. Not for spoken desk notifications (that is ttalk).
---

# ntfy notifications

## Role

Reach the user away from the desk. `ttalk` speaks at the desk; `ntfy-send` pushes to the phone. Use the CLI, never a hand-built `curl` to the topic URL: the CLI keeps the topic URL (a secret) out of commands, logs and transcripts.

## When to send

Send when **any** of these holds:
- The user asked for it ("ping me", "notify my phone", "let me know via ntfy").
- An instruction (CLAUDE.md, a scheduled follow-up prompt) says to notify on completion.
- A long task the user is waiting on finished or failed, and they said they would be away ("going for lunch", "I'll check later"). Claude cannot see whether the user is at the desk, so do not guess it.

Do NOT send:
- For routine turn completions the user is watching; `ttalk` covers the desk.
- More than one push per outcome. Combine results into one message rather than streaming progress.
- Anything containing secrets, tokens, credentials, customer data or internal URLs. Anyone who knows the topic can read the topic, and ntfy.sh keeps messages for 12 hours.

## Quick start

```bash
ntfy-send "Jellyfin upgrade done, health check green"
ntfy-send -t "dotfiles" -g white_check_mark "All 20 tests passed"
ntfy-send -t "Backup FAILED" -p high -g warning "Immich DB backup exited 1, see /var/log/immich-backup.log"
```

`ntfy-send [-t TITLE] [-p PRIORITY] [-g TAGS] MESSAGE`. It is on PATH via `util-scripts/`, with its source at `~/repos/dotfiles/util-scripts/ntfy-send`.

| Flag | Meaning |
|------|---------|
| `-t` | Title, e.g. the repo or task name |
| `-p` | `1-5` or `min` / `low` / `default` / `high` / `max` (alias `urgent`) |
| `-g` | Comma-separated tags. Emoji shortcodes such as `warning`, `white_check_mark` and `rotating_light` render as icons |

**Priority:** leave it at the default for completions. Use `high` for failures that need action today, and `max` only for something broken right now. Use `low`/`min` for FYI messages.

## Writing the message

- Lead with the outcome, in under 4,096 bytes (the ntfy.sh limit). Aim for one or two lines readable on a lock screen: what happened, plus where to look.
- Say FAILED plainly in the title when something failed; never soften a failure into a success.
- No markdown. The phone shows it as plain text by default.

## Example

The user says "run the full distro test suite, I'm heading out, ping me when it's done". The suite finishes with 1 of 4 distros failing:

```bash
ntfy-send -t "dotfiles e2e: FAILED 1/4" -p high -g warning "Fedora failed at zsh.sh (missing zsh-syntax-highlighting); Arch, Ubuntu, Debian passed"
echo "exit=$?"   # 0 → tell the user a push was sent; non-zero → say it was not
```

One push for the whole outcome, the failure first, and no secrets or paths beyond what is needed to act.

## Exit codes (act on them)

| Exit | Meaning | Do |
|------|---------|----|
| 0 | Accepted by the server | Nothing more is needed. Mention in the reply that a push was sent |
| 1 | No topic configured, or delivery failed (stderr says which) | Report it to the user as a failure. Do not claim they were notified. See Troubleshooting |
| 2 | Usage error | Fix the arguments and resend once |

`ttalk` always exits 0, but `ntfy-send` does not. A caller that must not fail (hooks, scripts) appends `|| true`, yet Claude itself must still check the exit code.

## Troubleshooting

1. **"no topic"**: `NTFY_TOPIC_URL` is not in the keychain. Run `secrets-doctor NTFY_TOPIC_URL` (see the `secrets-debugging` skill). Ask the user to run `secret_set NTFY_TOPIC_URL https://ntfy.sh/<topic>` themselves; never handle the value yourself. `STORE ok` with `ENV MISSING` is fine: the session is only older than the export, and `ntfy-send` falls back to the keychain.
2. **Delivery failed**: work through the layers in order: DNS for `ntfy.sh`, then the network (`curl -sS -m 5 https://ntfy.sh/v1/health` should return `{"healthy":true}`), then an HTTP error from the server. A 429 means the rate limit was hit: ntfy.sh allows 250 messages a day and a burst of 60, then 1 every 5 seconds. Stop sending and tell the user.
3. **Did it arrive?** Proof is server-side, not the exit code alone. Poll the topic's recent messages without printing the URL:
   ```bash
   curl -s -m 10 "$(zsh -lic 'printf %s "$NTFY_TOPIC_URL"' 2>/dev/null)/json?poll=1&since=10m" | jq -c '{time:(.time|todate),title,message}'
   ```
   Then ask the user whether the phone showed it. That confirms the app's subscription, which the server cannot tell you.

## Rules

1. Never print, echo or paste the topic URL or `NTFY_TOKEN`. Refer to them by name.
2. Report a failed push as a failure, and say what failed.
3. One push per outcome. Never loop, retry-spam or send progress ticks.
4. The server is public ntfy.sh for now; self-hosting on the homelab is planned. If the server changes, only the keychain value changes (plus `NTFY_TOKEN` if the new server needs access control). This skill and the CLI stay the same.
