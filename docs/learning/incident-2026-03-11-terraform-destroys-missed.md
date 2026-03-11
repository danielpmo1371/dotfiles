# Root Cause Analysis: Failed to Flag 39 Terraform Destroys in Plan Output

## Date: 2026-03-11

## The Error

When reviewing the terraform plan output for build 270486 (SIT/AE, Pipeline 802), the agent marked the plan as PASS despite the output containing 39 destroy actions. The project MEMORY.md explicitly states: "If destroys appear in plan, use `removed` blocks in Terraform config (code fix, not state fix)." The CLAUDE.md has strict terraform safety rules that treat any unexpected plan output as a critical issue requiring code fixes, not approval. The 39 destroys should have been immediately flagged as a critical blocker.

### What Was Done

The reviewing agent (likely in the Task 10 verification flow) analyzed the plan output for build 270486 on SIT/AE and concluded it was safe to proceed, marking the test plan as PASS. The destroys were either:
1. Not noticed in the plan output at all, or
2. Noticed but rationalized away as acceptable

Both scenarios represent a critical verification failure.

### What Should Have Been Done

1. Parse the plan summary line: `Plan: X to add, Y to change, Z to destroy`
2. If `Z > 0` -- STOP IMMEDIATELY
3. Identify every resource marked for destruction
4. Cross-reference against existing infrastructure (Service Bus subscriptions, rules, RBAC, SAS policies)
5. Report as CRITICAL FAILURE with a detailed breakdown of each destroy action
6. Recommend `removed` blocks as the code-level fix
7. Never mark a plan with destroys as PASS under any circumstances in this project

## Root Cause Analysis

### 1. Why This Mistake Happened

**Mental Model Failure: "Previous Plans Were Clean, So This One Must Be Too"**
- Previous plan verifications for builds 269262 (UAT) and 269263 (SIT) had shown clean results: 0 destroys, 28 moved blocks
- The pattern of clean plans may have created a false sense of security
- The agent may have been operating on autopilot, expecting the same clean results from the latest build
- Confirmation bias: looking for evidence of success rather than evidence of failure

**Missing Verification Step: "Hard Gate on Destroy Count"**
- There was no enforced, automated check that would force a FAIL verdict when destroys > 0
- The verification was a human/agent judgment call rather than an algorithmic rule
- The Task 10 definition says "If plan shows destroys, STOP and investigate the code" but this was a guideline, not a hard gate
- No structured checklist item explicitly required counting destroys and comparing to zero

**Context Blindness**
- MEMORY.md line 11: "If destroys appear in plan, use `removed` blocks in Terraform config (code fix, not state fix)" -- this rule exists precisely because destroys are dangerous
- Task 09 explicitly states: "If `terraform plan` shows unexpected destroys, the fix is in the CODE, not the state"
- The entire Service Bus refactoring story was about safely moving resources WITHOUT destroying them
- The build-analysis.md conclusion states: "If destroys appear, add `removed` blocks"
- Every piece of documentation in this project treats destroys as a critical red flag

### 2. What Signals Should Have Triggered "Wait..."

**Red Flags That Should Have Stopped Me:**

1. **Plan Summary with Destroy Count > 0**: The plan output would have contained a line like `Plan: X to add, Y to change, 39 to destroy`
   - What it means: Terraform intends to DELETE 39 resources from Azure
   - What should happen: Immediate FAIL verdict, full listing of every destroy action, recommendation for `removed` blocks

2. **Service Bus Resources in Destroy List**: The 39 destroys would include Service Bus subscriptions, subscription rules, SAS authorization policies, or RBAC role assignments
   - What it means: The refactoring removed configuration for resources that exist in the Terraform state, so Terraform wants to delete them from Azure
   - What should happen: Add `removed { from = ... }` blocks for every resource that needs to be forgotten from state without being destroyed in Azure

3. **Deviation from Previous Plan Pattern**: Previous SIT builds (269263) showed `0 to destroy`; this one showed 39
   - What it means: Something changed between runs that introduced new destroy actions -- likely import blocks targeting resources in state that were removed from config, or module configuration changes that dropped resources
   - What should happen: Compare the plan diff between the two builds to identify what changed

4. **The Number 39 Itself**: In the context of a Service Bus refactoring that manages ~12 topics with multiple subscriptions, rules, and SAS policies each, 39 destroys strongly correlates to the full set of application-level SB dependencies being removed
   - What it means: The refactoring successfully removed subscriptions/rules/SAS from the Terraform config, but the state still tracks them -- so Terraform plans to destroy them in Azure
   - What should happen: This is the exact scenario described in Task 09: "If destroys appear, add `removed` blocks"

5. **Context of the Refactoring**: The entire purpose of Story 193236 was to remove app-level SB dependencies from the platform stack. Removing them from config while they exist in state is a textbook scenario for Terraform destroys.
   - What it means: The code change is working as designed (removing config), but the state cleanup needs `removed` blocks to prevent actual Azure destruction
   - What should happen: This outcome was PREDICTED and DOCUMENTED in the task files

### 3. Proper Workflow for Terraform Plan Verification

**Correct Approach:**

**Step 1: Parse Plan Summary**
```
Look for: "Plan: X to add, Y to change, Z to destroy"
If Z > 0: FAIL immediately
```

**Step 2: Hard Gate Check**
```
IF destroys > 0:
  - Set verdict = CRITICAL FAILURE
  - Do NOT proceed to other analysis
  - List every single resource in the destroy set
  - Categorize by resource type (SB subscription, SB rule, SB SAS, RBAC, etc.)
```

**Step 3: Identify Destroy Root Cause**
```
For each destroy action:
  - What resource is being destroyed?
  - Why does Terraform want to destroy it? (removed from config? module change?)
  - Is this resource in Azure and still needed?
  - What is the correct remediation? (removed block, config fix, etc.)
```

**Step 4: Recommend Remediation**
```
For resources that should be forgotten (not destroyed):
  - Draft `removed { from = <resource_address> }` blocks
  - Explain that these tell Terraform to forget the resource from state
    without deleting it from Azure
  - This is a CODE change, committed and pushed through the pipeline
```

**Step 5: Document and Report**
```
- Report verdict as FAIL with full justification
- List every destroy action with its remediation
- Reference MEMORY.md and Task 09 rules
- Block any apply until destroys are resolved
```

## Learning Mechanisms Implemented

### A. Documentation
**File**: `~/.claude/projects/-Users-daniel-repos-td-td-iac/memory/MEMORY.md`
**Section**: Terraform Safety -- ABSOLUTE RULE (enhanced)
**Content**: Added explicit rule about destroy count verification being a hard gate, not a judgment call

### B. Process Changes
**Workflow**: Terraform Plan Verification (Task 10 and future equivalents)
**Changes**:
- Destroy count > 0 is an automatic FAIL -- no exceptions, no rationalizing
- Every plan verification MUST start with the destroy count check BEFORE analyzing anything else
- The destroy count check is binary: 0 = proceed, >0 = STOP
**Enforcement**: Added to MEMORY.md and project CLAUDE.md as explicit rules

### C. CLAUDE.md Safety Rules
**File**: `~/.claude/CLAUDE.md` (global)
**Section**: Terraform Plan Verification Protocol
**Content**: Added specific protocol for plan review that mandates destroy count as first check

### D. Memory Storage
**MCP Memory**: Yes
**Tags**: `lesson-learned`, `terraform`, `plan-verification`, `destroys-missed`, `high-severity`
**Key**: `lesson-2026-03-11-terraform-destroys-missed`

## Takeaway

**A terraform plan with destroys > 0 is NEVER a PASS in this project. Destroys are a hard gate, not a judgment call.**

This was not a coding error or a terraform configuration error -- it was a **verification process failure**. The code changes (removing SB app dependencies) were working correctly. The plan accurately reflected that Terraform would destroy resources no longer in config but still in state. The agent's job was to catch this and recommend `removed` blocks. Instead, it failed to enforce the project's most critical safety rule.

The lesson extends beyond this specific incident: when reviewing infrastructure plans, the destroy count is the FIRST thing to check, and it is binary. Zero means proceed with analysis. Non-zero means STOP and investigate. There is no middle ground. Previous clean plans do not predict future clean plans. Every plan must be verified independently with the same rigor.

**New habit: Every terraform plan review starts with: "How many destroys?" If the answer is not zero, the verdict is FAIL. Period.**
