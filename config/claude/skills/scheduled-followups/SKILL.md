---
name: scheduled-followups
description: Schedule a future Claude follow-up session (a systemd user timer that opens Claude in tmux with a prepared prompt) via the claude-task CLI. Use when work needs checking later ("check in 24h", "health check tomorrow", "revisit after the rollback window"), when a plan awaits the user's review, when a metric's growth must be measured over time, or when the user asks for a reminder for Claude to come back to something. Also covers listing, verifying and cancelling scheduled follow-ups.
---

# Scheduled Follow-ups

## Role

Queue a future, interactive Claude session that picks up a specific thread: a read-only check, or a plan for the user to approve. Always through `claude-task` — never hand-write systemd units, prompt copies or registry rows.

`claude-task` is on PATH (source: `~/repos/dotfiles/util-scripts/claude-task`). Units live in `~/.local/share/systemd/user/claude-task-<name>.{service,timer}`, prompts and the registry in `~/.local/state/claude-tasks/`. Each task fires `util-scripts/tmux-claude-task.sh`, which opens a window in a tmux session and starts `cdang` with the prompt. `claude-task help` is the authoritative usage.

For a full end-to-end run (draft prompt, schedule, verify, store), delegate to the `followup-scheduler` agent. This skill is the rulebook it follows.

## Quick start

```bash
claude-task list                                   # what is queued; pick a free slot
# draft <scratchpad>/<name>.md from TEMPLATES.md § Prompt template
claude-task schedule <name> "YYYY-MM-DD 20:30" <dir> <scratchpad>/<name>.md --purpose "<one line>"
claude-task list && claude-task dry-run <name>     # verify
```

Then `mcp__memory__memory_store` (duty 1) and tell the user (duty 3) — see below.

## When to schedule (automatically, no need to ask)

The user decided that Claude **creates** follow-ups on its own initiative. Schedule one when any of these is true at the end of a task:

| Trigger | Follow-up | Mode |
|---|---|---|
| Upgrade, migration or config cutover just finished | ~24h health check of the thing changed | READ-ONLY |
| A plan is written and awaits the user's approval | Present the plan again / re-validate it next evening | PLAN-ONLY |
| A rollback window (backups, old images, kept venvs) will expire | Inventory what can go and give the user the commands | PLAN-ONLY |
| A metric needs time to show a trend (log size, disk, memory) | Measure growth, decide against a stated threshold | READ-ONLY |

Don't schedule when the check can be done now, or when the user said not to.

## The three mandatory duties (EVERY task, no exceptions)

A task is not "scheduled" until all three are done. Copy this checklist into your working notes and tick each item:

```
- [ ] 1. Memory MCP: stored (or fallback used AND failure reported to the user)
- [ ] 2. Registry: row present in `claude-task list` (written by the CLI, never hand-edited)
- [ ] 3. User told: what, when (absolute, local time), tmux session, `claude-task cancel <name>`
```

1. **Memory MCP.** Call `mcp__memory__memory_store` (load it with ToolSearch `select:mcp__memory__memory_store` if deferred) with the content and tags in [TEMPLATES.md](TEMPLATES.md) § Memory record. If the tool errors or is unavailable, use the REST fallback in the same section, then **tell the user the MCP store failed** and which path succeeded. If both fail, say so plainly; never skip silently.
2. **Registry.** `claude-task schedule` appends the row to `~/.local/state/claude-tasks/SCHEDULED.md` itself. Confirm it with `claude-task list`. Never edit that file by hand; status changes go through `claude-task cancel` / `claude-task mark-fired`.
3. **Tell the user** in your reply, using [TEMPLATES.md](TEMPLATES.md) § User report.

## Workflow

1. **Name** — `^[a-z0-9][a-z0-9-]*$`, short and specific (`jellyfin-24h`, `leftovers-plan`). The CLI refuses a name whose unit files already exist (even for fired/cancelled tasks) — pick a new one, never work around it.
2. **Time** — apply the timing rules below. Run `claude-task list` first to see what is already queued.
3. **Prompt** — write it to your session scratchpad from [TEMPLATES.md](TEMPLATES.md) § Prompt template. Every guardrail line in the template is mandatory; only the bracketed parts change.
4. **Schedule**:
   ```bash
   claude-task schedule <name> "YYYY-MM-DD HH:MM" <dir> <prompt-file> --purpose "<one line, no '|'>" [--session <s>]
   ```
   The CLI copies the prompt to `~/.local/state/claude-tasks/prompts/<fire-date>-<name>.md`; the scratchpad file is only the draft.
5. **Verify** — `claude-task list` (row + timer present, fire time as expected), then `claude-task dry-run <name>` (fires the launcher into a throwaway tmux server with a stub command; the real timer and tmux server are untouched). Dry-run must report the prompt arrived verbatim.
6. **Duties 1 and 3** from the checklist above.

## Timing rules

- **Absolute timestamps only**: `"YYYY-MM-DD HH:MM"` in local time (the machine's timezone, NZ). No relative specs like `tomorrow`; compute the date and write it out.
- **Never in the past**: the CLI rejects it; check `date` before choosing.
- **Evening default 20:30** unless the thing being checked dictates otherwise (e.g. exactly 24h after a change).
- **Stagger ≥10 min** from every other task firing the same evening (20:30, 20:40, 20:50, ...), so sessions don't start together.
- **Session**: default tmux session `followups`; use `--session <s>` only when the follow-up belongs with an existing session's work.
- Timers are `Persistent=true`: a task missed while the machine slept fires on wake. Keep that in mind when a check only makes sense at a specific time.

## Managing tasks

```bash
claude-task list            # every task: fire time, session, dir, status, timer state
claude-task show <name>     # the stored prompt
claude-task cancel <name>   # disables the timer, status -> cancelled; files are kept
```

- Cancel or change **only tasks you created in this session**, or ones the user explicitly names.
- To change a task: `cancel` it and schedule a new one under a **new** name (unit files are never overwritten or removed — No-Delete). Update the memory record by storing a new one that says it supersedes the old name.

## Rules

1. **Scheduled prompts are READ-ONLY or PLAN-ONLY.** A future session must never change infrastructure, code or data on its own; any change becomes a plan with `Status: NEEDS_PLAN_APPROVAL`.
2. **No-Delete** applies inside the prompt too: leftover clean-ups produce commands for the user to run.
3. **Never put secret values in a prompt, the purpose, or the memory record.** Refer to keys by name.
4. **Report failures honestly.** If `schedule`, `list` or `dry-run` fails, show the error and don't claim the task is scheduled.
5. Do not run `systemctl --user enable/disable` on `claude-task-*` units directly; the CLI keeps timers and the registry in sync.

## References

- [TEMPLATES.md](TEMPLATES.md) — prompt template, memory record, user report, worked example
- `~/repos/dotfiles/CLAUDE.md` "Scheduled Claude tasks" — launcher and file layout
- `~/.local/state/claude-tasks/tasks.log` — launch log (did the window actually open?)
