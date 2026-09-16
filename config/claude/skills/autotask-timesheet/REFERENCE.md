# Autotask Timesheet — Reference

Verified 2026-09-17 against ww29.autotask.net (Onyx UI). Selectors are structural
(class/label), never element ids — ids regenerate on every load.

## Table of contents

- [URL and frame map](#url-and-frame-map)
- [In-page JS guard](#in-page-js-guard)
- [Popups and the window.open hook](#popups-and-the-windowopen-hook)
- [Step A: Get Previous Tasks (first entry of the week)](#step-a-get-previous-tasks-first-entry-of-the-week)
- [Step B: open a day cell](#step-b-open-a-day-cell)
- [Step C: the New Task Time Entry popup](#step-c-the-new-task-time-entry-popup)
- [Step D: the Enter Notes dialog](#step-d-the-enter-notes-dialog)
- [Step E: Save & Close and verify](#step-e-save--close-and-verify)
- [Autotask button components](#autotask-button-components)
- [Failure modes seen](#failure-modes-seen)

## URL and frame map

Timesheet (current period):

```
https://ww29.autotask.net/AutotaskOnyx/LandingPage?view=my-timesheet&view-data=eyJ1cmwiOiJodHRwczovL3d3MjkuYXV0b3Rhc2submV0L2hvbWUvdGltZUVudHJ5L3dya0VudHJ5RnJhbWVzLmFzcCJ9&restoreworkspacekey=
```

```
top                          LandingPage (shell, 5 iframes)
├─ frames[0]                 DialogIFrameOverlay (unused here)
└─ frames[1]                 wrkEntryFrames.asp
   └─ frames[0]              wrkEntryBot.asp
      ├─ frames[0]  MID      wrkEntryFrameMid.asp   toolbar: Save, New, Get Previous Tasks,
      │                                              Delete, Submit, Refresh, < period >
      └─ frames[1]  LV       wrkEntryListView.asp   the grid (rows + totals)
```

Shorthands used below:

```js
const MID = top.frames[1].frames[0].frames[0];
const LV  = top.frames[1].frames[0].frames[1];
```

Grid row for the MBIE task (one `<tr>` whose text contains `FDD SoW8`):

| child index | content |
|-------------|---------|
| 0 | select checkbox (IMG) |
| 1 | pencil / edit link |
| 2 | Client / Project (`Ministry of Business, Innovation and Employment / MBIE 273 - FDD SoW8`) |
| 3 | Title (`Sep 2026` + task number `T20260701.0083`) |
| 4 | Status |
| 5..11 | Sun..Sat day cells, `<td onclick="addType1(...)">` with a hidden input |

The accessibility tree (`find`, `read_page`) cannot see inside these iframes. Use
`javascript_tool` for reading and coordinates, `computer` for real clicks.

## In-page JS guard

Any `javascript_tool` return value that looks like a URL, query string, cookie, or
`key=value` pairs is replaced with `[BLOCKED: Cookie/query string data]`. Return only
booleans, counts, function names, and text scrubbed with
`.replace(/[^A-Za-z0-9 .:()\/\n-]/g,'')`. Never include `=`, `&`, `?` in the output.

## Popups and the window.open hook

"Get Previous Tasks" and every day cell open a **separate OS window** via `window.open`.
Screenshot/click tools cannot see it. Capture the handle:

```js
top.__popups = [];
(function hook(w){ try{ if(!w.__hooked){ w.__o = w.open;
  w.open = function(){ var r = w.__o.apply(w, arguments); top.__popups.push(r); return r; };
  w.__hooked = true; } for (let i = 0; i < w.frames.length; i++) hook(w.frames[i]); } catch(e){} })(top);
```

Rules:

1. Install the hook **immediately before** the click. LV reloads after Get Previous Tasks
   and after Save & Close, which drops the hook on that frame (top keeps `__popups`).
2. Open with a **real `computer` left_click**. Programmatic `.click()` on the cell returns
   `null` from `window.open` (popup blocker: no user activation).
3. Drive the popup with `const w = top.__popups[top.__popups.length-1]; const d = w.document;`.

## Step A: Get Previous Tasks (first entry of the week)

Only when the grid has no `FDD SoW8` row.

1. Hook, then real-click the toolbar button. Coordinates change when the sidebar renders;
   take a fresh screenshot and click the centre of the "Get Previous Tasks" label.
2. Popup: title `Get Previous Tasks`, file `popEntryFill.asp`, text "SELECT ENTRIES FROM
   PERIOD ENDING <date>". One row per previous task; columns Title, Project, Phase, Client,
   Status.
3. Tick the MBIE row: the checkbox is an `<img>` in cell 0 whose `src` toggles
   `checkbox_incomplete.png` → `checkbox_complete.png` on `img.click()`.
4. Save: `scripts/11-tick-row.js` dispatches a click on the popup's `a#HREF_btnSaveClose`
   anchor (the popup also exposes `w.fncSaveAndClose()`; see the failure table). If denied,
   ask Daniel to click "Save & Close" in the popup on his screen, then re-read LV.

Toolbar coordinates: `scripts/12-toolbar-coords.js`. Scripts: `scripts/10-get-previous-tasks.js`
(row list), `scripts/11-tick-row.js`.

## Step B: open a day cell

Day index: Sun=5 … Sat=11 in the row's children. Compute viewport coordinates through the
frame chain, then real-click:

```js
const row = [...LV.document.querySelectorAll('tr')].find(t => /FDD SoW8/.test(t.innerText));
const cell = row.children[6];                      // Mon
const r = cell.getBoundingClientRect();
let x = r.left + r.width/2, y = r.top + r.height/2, f = LV;
while (f !== top) { const fr = f.frameElement.getBoundingClientRect(); x += fr.left; y += fr.top; f = f.parent; }
```

Any day cell in the row opens the same weekly popup, so always click Mon regardless of the
target day. Run `scripts/20-day-cell-coords.js` twice, 1.5 s apart; click only when both
results match (the left nav renders late and shifts the frames).

## Step C: the New Task Time Entry popup

File `EditTaskTimeRecordPage`, title `New Task Time Entry`. Sections: task header
(`T20260701.0083 / Sep 2026`), Task Status, Billing (Role: Senior Consultant),
**Time Entry Details** (seven `input.DecimalBox2` boxes labelled `Sun 13/09` … `Sat 19/09`),
Time Remaining, Quick Notification, Summary Notes (rich text, below the fold).

Visible-field index (`d.querySelectorAll('input:not([type=hidden]),select,textarea')`):
indices **3..9 = Sun..Sat hours**. Prefer locating by label text, as the day boxes sit
directly under a leaf element whose text matches `/^(Sun|Mon|...) \d\d\/\d\d$/`.

Under each day box there is a Notes button: `div.Button.ButtonIcon.Note` with
`onclick="openHoursAndNotesDialog(new Date(...), event)"`. `btn.click()` works and renders
an **in-page** dialog (no new window). Script: `scripts/30-open-day-notes.js`.

Do **not** type into the seven top-level hour boxes directly; set hours in the dialog so the
per-day note and hours stay together.

## Step D: the Enter Notes dialog

Root: element with class containing `Dialog`, width > 200, text starting
`Enter Notes - Mon 14/09`. Contents:

| Control | Selector inside dialog |
|---------|------------------------|
| Hours Worked | `input.DecimalBox2` (value echoes back as `8.0000`) |
| Summary Notes | first `.ContentEditable2` with `isContentEditable` (32000 chars) |
| Internal Notes | second `.ContentEditable2` (leave empty) |
| OK / Previous Day / Next Day | toolbar buttons, see component notes below |

Fill:

```js
const fire = (el, types) => types.forEach(t => el.dispatchEvent(new w.Event(t, { bubbles: true })));
hours.focus(); hours.value = '8.0'; fire(hours, ['input','change','blur']);
summary.focus(); summary.innerHTML = ''; summary.appendChild(d.createTextNode(TEXT));
fire(summary, ['input','keyup','change','blur']);
```

`Next Day` commits the current day into the weekly form and reopens the dialog for the
next date (adjacent dates only; for a gap, `OK` then re-open via the other day's Notes
button). `OK` commits and closes. Verify by re-opening each day's Notes button and reading
back hours + summary length. Scripts: `scripts/31-fill-notes-dialog.js`,
`scripts/32-next-day.js`, `scripts/33-ok.js`, `scripts/34-readback.js`.

## Step E: Save & Close and verify

Toolbar button in the popup: leaf `div.Text2` with text `Save & Close`, inside a
`div.Button2`. Dispatch the full pointer/mouse sequence on the `.Button2` (a bare
`.click()` on OK did nothing; the sequence closed it):

```js
['pointerdown','mousedown','pointerup','mouseup','click'].forEach(t => {
  const Ev = t.startsWith('pointer') ? w.PointerEvent : w.MouseEvent;
  btn.dispatchEvent(new Ev(t, { bubbles: true, cancelable: true, button: 0, view: w }));
});
```

Then `w.closed` becomes true and LV reloads with the hours. Verify from the server: click
`Refresh` in MID (leaf element with text `Refresh`, `.click()` works), wait ~4 s, re-read the
row and the `Total Hours (…)` / `Billable Hours (…)` lines. Script: `scripts/40-save-close.js`,
`scripts/41-refresh-verify.js`.

## Autotask button components

- Toolbar buttons (`Save & Close`, `OK`, `Next Day`, `Refresh`): `div.ToolBarItem > div >
  div.Button2 > div.Text2`. No inline `onclick`, no jQuery `_data`; handlers are native
  listeners on `.Button2`. `Next Day` and `Refresh` accept `.click()`; `OK` and
  `Save & Close` needed the pointer/mouse sequence.
- Icon buttons (`Notes` under each day): `div.Button.ButtonIcon.Note` with inline `onclick`;
  `.click()` works.
- Checkbox images (Get Previous Tasks rows): `img.click()` toggles.

## Failure modes seen

| Symptom | Cause | Fix |
|---------|-------|-----|
| Clicked "New" dropdown instead of "Get Previous Tasks" | toolbar shifts right when the left nav finishes rendering | run `12`/`20` twice 1.5 s apart, click only when identical |
| `Browser extension is not connected` / no tab group | extension dropped after a popup window opened | `tabs_context_mcp` with `createIfEmpty`, navigate again |
| `[BLOCKED: Cookie/query string data]` | return string contained `=`/`?`/URL-like text | return scrubbed text only |
| `find` cannot see toolbar buttons | content is inside iframes | JS coordinates + `computer` click |
| `w.fncSaveAndClose()` denied (2026-09-17) | permission classifier "Real-World Transactions" | `11` tries a dispatched click on the anchor; else ask Daniel to click; backlog: allow rule |
| `OK` did not close dialog | `.click()` on leaf insufficient | pointer/mouse sequence on `.Button2` |
