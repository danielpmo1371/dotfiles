---
name: sdlc-resume
description: Resume an in-progress SDLC workflow for a work item
arguments:
  - name: work_item
    description: "Work item ID or reference (optional — auto-detects if only one active)"
    required: false
---

## SDLC Resume: $ARGUMENTS

### Step 1: Find Workflow Folder

If `work_item` argument is provided:
- Parse it the same way as `/sdlc-start` (support `US#170514`, `170514`, `#170514`, full URL)
- Search for `user_story-{WORK_ITEM_ID}-*/` folder in the current working directory

If no argument provided:
- Scan for all `user_story-*/workflow_state.md` files in CWD:
  ```bash
  ls -d user_story-*/workflow_state.md 2>/dev/null
  ```
- If **none found**: report "No active SDLC workflows found. Use `/sdlc-start <work_item>` to begin one." and stop.
- If **exactly one found**: use it automatically
- If **multiple found**: present a numbered list with story ID, title, current phase, and last-updated timestamp. Ask the user to select one.

### Step 2: Read Workflow State

Read the `workflow_state.md` from the selected folder. Extract:
- **Work Item ID** (from `## Story Context`)
- **Title**
- **Current Phase** (from `## Current State → Active Phase`)
- **Mode** (autonomous/guided)
- **Complexity tier**
- **Phase completion status** (which phases are checked off)
- **Active Specialist** (if any)
- **Blockers** (from `## Blockers & Issues`)
- **Last updated timestamp**

### Step 3: Cross-Check with Memory MCP

Query Memory MCP for entries tagged `sdlc:{WORK_ITEM_ID}`:
- Compare memory state with workflow_state.md
- If discrepancies found (e.g., memory says Phase 3 complete but file says Phase 2):
  - Report the discrepancy to user
  - Ask which source to trust (file is generally authoritative)
- If memory has entries not in the file (decisions, findings), note them for the Team Lead

### Step 4: Present Resume Summary

Display a formatted summary:

```
SDLC Workflow Resume
====================
Story:     {WORK_ITEM_ID} - {title}
Phase:     {N}. {phase_name} ({status})
Mode:      {mode}
Complexity: {complexity}
Progress:  {completed}/{total} phases
Last Active: {timestamp}
Blockers:  {blocker_count or "None"}
```

### Step 5: Ask Resume Strategy

Use AskUserQuestion:
- **Question:** "How would you like to resume this workflow?"
- **Option 1:** "Continue from Phase {N} (Recommended)" — pick up where you left off
- **Option 2:** "Restart from a specific phase" — choose which phase to restart from
- **Option 3:** "Change mode" — switch between autonomous and guided

If "Restart from a specific phase":
- Present the phase list (only completed + current phases selectable)
- User selects a phase number
- Reset all subsequent phases to unchecked in workflow_state.md

If "Change mode":
- Ask: Autonomous or Guided?
- Update workflow_state.md with new mode

### Step 6: Load Project Configuration

Check for `.sdlc.json` in the project root (same as sdlc-start Step 4).

### Step 7: Spawn Team Lead with Restored State

Use the Task tool to spawn the `sdlc-team-lead` agent with restored context:

```
SDLC Workflow Resume

Work Item: {WORK_ITEM_ID}
Title: {title}
Mode: {WORKFLOW_MODE}
Current Phase: {N}. {phase_name}
Complexity: {complexity}
Completed Phases: {list of completed phases}
Project Config: {PROJECT_CONFIG or "none"}
Working Directory: {CWD}
Story Folder: {folder_path}

Restored Context:
- Key Decisions: {decisions from workflow_state.md}
- Blockers: {blockers}
- Memory Entries: {relevant memory entries}
- Specialist Log: {recent specialist activity}

Instructions:
1. Resume from Phase {N} ({phase_name})
2. Review any blockers before proceeding
3. Continue in {WORKFLOW_MODE} mode
4. All existing state in {folder_path}/workflow_state.md is authoritative
```

### Step 8: Report

Report to user:
- "Resumed SDLC workflow for {WORK_ITEM_ID} from Phase {N} ({phase_name})"
- "Mode: {WORKFLOW_MODE}"
- "Use `/sdlc-status` to check progress at any time"
