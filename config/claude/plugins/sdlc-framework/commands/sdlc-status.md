---
name: sdlc-status
description: Display status of active SDLC workflows (read-only, no agent spawning)
arguments:
  - name: work_item
    description: "Work item ID (optional — shows all active if omitted)"
    required: false
---

## SDLC Status: $ARGUMENTS

This is a **read-only** command. Do NOT spawn any agents or make any changes.

### Step 1: Find Active Workflows

If `work_item` argument provided:
- Parse the ID (support `US#170514`, `170514`, `#170514`)
- Look for `user_story-{WORK_ITEM_ID}-*/workflow_state.md`

If no argument:
- Scan for all `user_story-*/workflow_state.md` files in CWD:
  ```bash
  ls -d user_story-*/workflow_state.md 2>/dev/null
  ```

If none found: report "No active SDLC workflows found." and stop.

### Step 2: Parse Each Workflow

For each `workflow_state.md` found, extract:
- **Work Item ID** and **Title** (from `## Story Context`)
- **Current Phase** number and name (from `## Current State`)
- **Mode** (autonomous/guided)
- **Complexity** tier
- **Active Specialist** (from `## Current State → Active Specialist`)
- **Current Task** description
- **Progress** (count of checked phases vs total)
- **Blockers** (from `## Blockers & Issues`, count non-empty entries)
- **Last updated** timestamp (from file footer)
- **Key recent decisions** (last 3 from `## Key Decisions`)

### Step 3: Display Status

For a **single workflow**, display detailed view:

```
SDLC Status: {WORK_ITEM_ID} - {title}
================================================

Phase Progress:
  [x] 1. Bootstrap
  [x] 2. Scope Discovery
  [>] 3. Audit              <-- CURRENT
  [ ] 4. Scope Refinement
  [ ] 5. Reporting
  [ ] 6. Planning
  [ ] 7. Execution
  [ ] 8. Verification
  [ ] 9. PR/Delivery
  [ ] 10. Retrospective

Current State:
  Phase:      3. Audit
  Specialist: audit-specialist
  Task:       Running NuGet package analysis on td-api
  Mode:       Autonomous
  Complexity: Complex
  Progress:   2/10 phases complete

Blockers:
  (none)

Recent Decisions:
  - Scope includes td-api, app-app (2 repos)
  - Complexity assessed as "complex" (>5 files affected)
  - Using candidate/8.12.0 as base branch
```

For **multiple workflows**, display summary table:

```
Active SDLC Workflows
======================
ID       Title                          Phase        Progress  Mode        Blockers
170514   Add validation to TD forms     3. Audit     2/10      Autonomous  0
170520   Fix FCH timeout handling       7. Execution 6/8       Guided      1
```

Then ask: "Use `/sdlc-status <ID>` for detailed view of a specific workflow."

### Step 4: Check Staleness

If the last-updated timestamp is more than 24 hours old, add a warning:

```
Warning: This workflow was last active {time_ago}. Consider:
  - /sdlc-resume {WORK_ITEM_ID}  to continue
  - Check if the work item status changed in Azure DevOps
```
