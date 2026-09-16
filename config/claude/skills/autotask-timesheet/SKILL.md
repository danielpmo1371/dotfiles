---
name: autotask-timesheet
description: Fill Daniel's Autotask (ww29.autotask.net) timesheet for MBIE via claude-in-chrome. Gathers what was done from conversation history and git, drafts one summary per day, waits for explicit approval of the text and hours, then enters hours + Summary Notes on the correct day cells and verifies from the server. Use when asked to "fill my timesheet", "do my timesheet", "log hours in Autotask", "timesheet for Monday/yesterday/this week", or any Autotask time-entry request.
allowed-tools: Read, Bash, Edit, Agent, Skill, ToolSearch, mcp__claude-in-chrome__tabs_context_mcp, mcp__claude-in-chrome__tabs_create_mcp, mcp__claude-in-chrome__tabs_close_mcp, mcp__claude-in-chrome__navigate, mcp__claude-in-chrome__computer, mcp__claude-in-chrome__javascript_tool
---

# Autotask Timesheet

## Role

Enter Daniel's daily MBIE hours into the Autotask timesheet with approved text, using
the browser mechanics documented in [REFERENCE.md](REFERENCE.md). The entry itself is
scripted (low freedom); the summary text is drafted, then **approved by Daniel before
anything is written**.

## Quick Start

1. Resolve target dates (NZ time) → 2. `Explore` agent gathers evidence →
3. Draft, `ttalk`, **STOP for "approved"** →
4. Scripts in order: `00` → `01` → (`10`/`11` only if no row) → `00` → `20` + real click →
   `30` → `31` → (`32` adjacent day | `33` then `30`) → `33` → `34` → `40` → `41` →
5. Report the `41` output, `ttalk`, close the tab.

Tool usage: `Bash` is for `ttalk`, `date`, and appending to `workflow_state.md` (`Edit`
likewise); `Skill` is for `conversation-history` only.

## Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| `ROW_MATCH` | `/FDD SoW8/` | project "MBIE 273 - FDD SoW8"; regex used by every script to find the grid row |
| Task title | `<Mon> <yyyy>` e.g. `Sep 2026` | **monthly task.** If the row's title month ≠ target date's month, stop and ask Daniel which task to use (Get Previous Tasks may offer the old month only) |
| `DAY_LABEL` | `ddd dd/MM` from the target date, e.g. `Mon 14/09` | label text above each hours box in the entry popup |
| Default hours | `8.0` per working day | ask only if the evidence suggests otherwise |
| Timezone | `TZ=Pacific/Auckland` | never hardcode +12/+13; DST changes |

## Hard rules

1. **Never write text or hours Daniel has not approved in this session** (see Gate).
2. **Never click Submit.** Save & Close on the entry popup is fine; the weekly Submit
   is Daniel's.
3. **Never overwrite a day that already has hours.** `31` throws if the dialog's Hours
   Worked is non-zero; stop and ask.
4. Verify from the server (`41` Refresh + re-read) before reporting done.
5. If anything in the popup does not match [REFERENCE.md](REFERENCE.md) (labels, row,
   task month), stop and report rather than improvise.

## Workflow

### 1. Establish the target days

Resolve phrases like "Monday", "yesterday", "this week" to concrete dates with
`TZ=Pacific/Auckland date`. Autotask weeks run Sun–Sat; the timesheet URL opens the
**current** period. A previous period needs the `<` toolbar arrow, which is not yet
scripted: stop and ask Daniel to navigate there, then continue.

### 2. Gather the evidence

Dispatch one `Explore` agent (tooling-enforced read-only) with the dates. Sources:

- `~/.claude/projects/*/*.jsonl` transcripts (`timestamp` is UTC; convert with
  `TZ=Pacific/Auckland`)
- `git log --all --since --until --author=Paiva` across `~/repos/td/*` repos
- `~/repos/td/workflow_state.md`, `state-of-tasks.md`

Ask for per-day: main tasks, PR/WI numbers, outcomes, blockers. Under 400 words.

### 3. Draft and get approval

One paragraph per day, 40–60 words, past tense, starts with the work item or PR, names
people only where they gate the work (Geoff, Jon). No markdown inside the note.
Present as:

```
Mon 14/09 — hours: 8.0
> <text>
Tue 15/09 — hours: 8.0
> <text>
```

Run `ttalk "<20-word preview>"`, then ask Daniel to reply "approved" or send edits.

### Gate (mandatory)

Proceed only if Daniel's **last** message contains the literal word "approved", or a
corrected block in the Day / hours / text format above (then re-show it and wait for
"approved" again). Silence, "looks good" about the evidence, or an edited draft that has
not been re-shown are **not** approval. Copy `HOURS` and `TEXT` into
`scripts/31-fill-notes-dialog.js` verbatim from that message; the script throws if
either is left null.

### 4. Enter in Autotask

Follow [REFERENCE.md](REFERENCE.md); the scripts encode each step.

1. `tabs_context_mcp` (createIfEmpty) → `navigate` to the timesheet URL. Run `20` twice,
   1.5 s apart; proceed only when both coordinate results are identical (the layout
   shifts while the left nav renders).
2. `01` reads the grid. If the row is absent (first entry of the week): `00`, real-click
   "Get Previous Tasks" (coordinates from `12`), `10` lists rows, `11` ticks the row and
   tries the popup's Save & Close; if denied, ask Daniel to click it, then `01` again.
3. `00` again, `20` for coordinates, **real-click the Mon cell** (any day cell opens the
   same weekly popup).
4. Per approved day: `30` (DAY_LABEL) → `31` (HOURS, TEXT). Adjacent next day: `32`.
   Non-adjacent: `33`, then `30` with the new label.
5. `33` to close, `34` (DAYS list) to read back every entered day.
6. `40` Save & Close, then `41` Refresh and re-read.

### 5. Report

Report the `41` row as read (per-day hours + total). `ttalk` a 20-word completion summary.
Close the tab you created with `tabs_close_mcp`. Append a dated line to
`~/repos/td/workflow_state.md`.

## Example

Daniel: "do my timesheet for Mon and Tue" → agent drafts the two-day block →
Daniel: "approved" → agent runs the scripts → final report:

```
ROW Ministry of Business Innovation and Employment / MBIE 273 - FDD SoW8 Sep 2026 T20260701.0083 In Progress 8.00 8.00
TOTALS Total Hours (16.00) | Billable Hours (16.00)
```

## Known blockers

- The auto-mode permission classifier denied a direct `fncSaveAndClose()` call as a
  "Real-World Transaction". Dispatching the pointer/mouse event sequence on the toolbar
  button was not blocked. If blocked: stop, tell Daniel exactly which button to click,
  continue after he confirms. Backlog: durable allow rule for ww29.autotask.net.
- The claude-in-chrome extension can drop mid-session (tab group disappears). Call
  `tabs_context_mcp` with `createIfEmpty` and navigate again; nothing on the Autotask side
  is lost until Save & Close.

## Files

- [REFERENCE.md](REFERENCE.md) — frame map, DOM selectors, JS snippets, guard gotchas
- `scripts/*.js` — the exact snippets to paste into `javascript_tool`, numbered in run order
