---
name: sdlc-start
description: Start SDLC workflow for a work item from Azure DevOps
arguments:
  - name: work_item
    description: "Work item ID, reference (US#12345), or Azure DevOps URL"
    required: true
  - name: mode
    description: "Workflow mode: autonomous or guided (default: ask user)"
    required: false
---

## SDLC Start: $ARGUMENTS

### Step 1: Parse Work Item Reference

Parse the `work_item` argument to extract a numeric ID. Supported formats:
- `US#170514` or `Bug#170514` or `Task#170514` → extract `170514`
- `#170514` or `170514` → use directly
- Full Azure DevOps URL containing `_workitems/edit/170514` → extract `170514`

If the argument cannot be resolved to a numeric ID, report the error and stop.

Store the extracted ID as `WORK_ITEM_ID`.

### Step 2: Choose Workflow Mode

Check if `mode` argument was provided:
- If `autonomous` → set `WORKFLOW_MODE=autonomous`
- If `guided` → set `WORKFLOW_MODE=guided`
- If not provided, ask the user:

Use AskUserQuestion:
- **Question:** "Which workflow mode should the SDLC framework use?"
- **Option 1:** "Autonomous (Recommended)" — Team Lead advances phases automatically, stops only on critical decisions or ambiguity
- **Option 2:** "Guided" — Team Lead pauses at every phase boundary for your review and approval

### Step 3: Check for Existing Workflow

Search for existing `user_story-{WORK_ITEM_ID}-*/` folders in the current working directory:

```bash
ls -d user_story-${WORK_ITEM_ID}-*/ 2>/dev/null
```

If a folder exists:
- Read its `workflow_state.md` to determine current phase
- Warn: "Found existing workflow for {WORK_ITEM_ID} at phase {N} ({phase_name})."
- Ask: "Resume existing workflow? (Use `/sdlc-resume {WORK_ITEM_ID}` instead)"
- If user wants to start fresh, confirm deletion of existing folder before proceeding

### Step 4: Load Project Configuration

Check for `.sdlc.json` in the project root:

```bash
test -f .sdlc.json && cat .sdlc.json
```

If found:
- Parse project name, AZDO config, repositories, environments, phase configuration
- Store as `PROJECT_CONFIG` for the Team Lead

If not found:
- Warn: "No .sdlc.json found. Using default SDLC configuration."
- Proceed with generic defaults (all 10 phases, no project-specific extensions)

### Step 5: Spawn Team Lead

Use the Task tool to spawn the `sdlc-team-lead` agent (subagent_type from the plugin's agents) with the following context:

```
SDLC Workflow Initialization

Work Item: {WORK_ITEM_ID}
Mode: {WORKFLOW_MODE}
Project Config: {PROJECT_CONFIG or "none"}
Working Directory: {CWD}

Instructions:
1. Begin Phase 1 (Bootstrap) — spawn the sdlc-bootstrap-specialist agent
2. The bootstrap specialist should:
   a. Fetch work item {WORK_ITEM_ID} from Azure DevOps via MCP
   b. Create folder structure: user_story-{WORK_ITEM_ID}-{sanitized_title}/
   c. Initialize workflow_state.md from template
   d. Write story context document with requirements, AC, stakeholders
3. After bootstrap completes, proceed according to {WORKFLOW_MODE} mode:
   - Autonomous: auto-advance through phases, stop only on critical decisions
   - Guided: pause after each phase for user review
4. Track all state in workflow_state.md and Memory MCP (tag: sdlc:{WORK_ITEM_ID})
```

### Step 6: Report

After spawning, report to user:
- "SDLC workflow started for {WORK_ITEM_ID} in {WORKFLOW_MODE} mode"
- "Team Lead is bootstrapping the work item..."
- "Use `/sdlc-status` to check progress at any time"
