# Learning Summary: Missed 39 Terraform Destroys in Plan Verification

**Date**: 2026-03-11
**Error Type**: Verification process failure -- failed to flag critical terraform plan output
**Severity**: High (39 Azure resources could have been destroyed if pipeline apply proceeded)
**Status**: Documented and safeguarded
**Project**: td-iac (Service Bus Refactoring, Story 193236)

---

## What Happened

### The Issue
Build 270486 (SIT/AE, Pipeline 802, branch feature/193236-Refactor-ServiceBus) produced a terraform plan with 39 destroy actions. These destroys represent Service Bus application-level resources (subscriptions, subscription rules, SAS authorization policies) that exist in the Terraform state but were removed from the configuration as part of the Service Bus refactoring.

### The Mistake
The reviewing agent marked the plan as PASS despite the 39 destroys. The correct action was to immediately flag this as a critical failure and recommend `removed` blocks in the Terraform configuration -- code changes that tell Terraform to forget the resources from state without destroying them in Azure.

### Why This Is Critical
- If the pipeline had applied this plan, 39 Azure Service Bus resources would have been DELETED
- Service Bus subscriptions and rules are consumed by live function apps -- deleting them would break message routing
- The project MEMORY.md and task documentation explicitly predicted this scenario and documented the correct response
- Previous plan verifications (builds 269262, 269263) showed 0 destroys, creating false confidence

---

## Root Cause: Verification Process Failure

### What Went Wrong
1. **Confirmation Bias**: Previous plans were clean (0 destroys), leading to an expectation that this one would be too
2. **Soft Gate Instead of Hard Gate**: The destroy count check was treated as one of many criteria rather than an absolute binary gate
3. **Context Available But Not Applied**: MEMORY.md, Task 09, Task 10, and build-analysis.md all state that destroys require `removed` blocks -- this documented knowledge was not enforced
4. **Autopilot Mode**: The verification may have followed the same analytical pattern used for clean plans, missing the critical deviation

### What Should Have Been Done
1. First action on any plan: check the destroy count
2. Destroy count = 39 --> immediate FAIL verdict
3. List all 39 resources marked for destruction
4. Identify them as Service Bus subscriptions, rules, and SAS policies removed from config
5. Recommend adding `removed { from = ... }` blocks for each resource
6. Report as critical blocker -- no apply until destroys = 0

---

## The Proper Fix

### 1. Remediation via Removed Blocks

**Approach**: For each resource Terraform wants to destroy, add a `removed` block:
```hcl
removed {
  from = module.servicebus_topics.azurerm_servicebus_subscription.topic_subscriptions["topic_sub"]

  lifecycle {
    destroy = false
  }
}
```

This tells Terraform: "forget this resource from state, but do NOT destroy it in Azure."

### 2. Re-run Plan After Code Fix

After adding `removed` blocks, the plan should show:
- 0 destroys (the removed blocks prevent destruction)
- Resources will be dropped from state on next apply
- Azure resources remain untouched

### 3. Verification

The updated plan MUST show `0 to destroy` before any apply is permitted.

---

## Learning Mechanisms Implemented

### 1. Enhanced MEMORY.md Rules
**File**: `~/.claude/projects/-Users-daniel-repos-td-td-iac/memory/MEMORY.md`
- Added explicit "Terraform Plan Verification Protocol" section
- Destroy count > 0 is a HARD GATE -- automatic FAIL, no exceptions
- Must be the FIRST check performed on any plan output

### 2. Comprehensive Analysis Document
**File**: `~/repos/dotfiles/docs/learning/incident-2026-03-11-terraform-destroys-missed.md`
- Full root cause analysis with Five Whys methodology
- Red flags identification (5 specific signals that were missed)
- Proper verification workflow documented step-by-step
- Mental model failures catalogued

### 3. MCP Memory Storage
**Stored**: Lesson with queryable tags
- Tags: `lesson-learned`, `terraform`, `plan-verification`, `destroys-missed`, `high-severity`
- Enables future query: "What lessons exist about terraform plan verification?"

### 4. Updated README for Learning Documentation
**File**: `~/repos/dotfiles/docs/learning/README.md`
- Added this incident to the incidents table
- Updated metrics

---

## New Safety Protocol

### Terraform Plan Verification -- Mandatory Sequence:

**Step 1**: Check destroy count (HARD GATE)
```
Parse: "Plan: X to add, Y to change, Z to destroy"
If Z > 0: VERDICT = FAIL. Full stop. Do not proceed.
```

**Step 2**: If destroys > 0, enumerate every destroy action
```
List each resource address and resource type.
Group by category (SB subscription, SB rule, SAS policy, RBAC, etc.).
```

**Step 3**: Determine if destroys are intentional
```
In this project: destroys are NEVER intentional unless explicitly documented.
Default assumption: every destroy needs a `removed` block.
```

**Step 4**: Only if destroys = 0, proceed to analyze changes
```
Check moved blocks count.
Verify in-place changes are pre-existing drift.
Check for new warnings or errors.
```

### Exception Cases
There are NO exceptions to the destroy = FAIL rule in this project. If a future task explicitly requires resource destruction, it will be documented in the task definition with a justification and approval.

---

## Impact

### Immediate
- Destroys were caught before any apply ran (the pipeline requires manual approval for apply stage)
- No Azure resources were actually deleted
- The gap in verification process is now documented

### Long-Term
- Hard gate rule prevents this class of error from recurring
- Future plan verifications will follow the mandatory sequence
- The pattern is documented for any agent performing plan verification
- MEMORY.md now explicitly distinguishes between "soft checks" (warnings, drift) and "hard gates" (destroys)

---

## Takeaway

**Terraform destroys are a binary signal, not a nuance to be analyzed. Zero = proceed. Non-zero = FAIL.**

This was a verification process failure, not a coding error. The terraform code was correctly removing app-level SB dependencies from the config. The plan was correctly showing that state-tracked resources would be destroyed. The agent's role was to CATCH this and flag it. The failure was treating the destroy count as one data point among many, rather than as the primary hard gate it must be.

### New Habit
**Every terraform plan review begins with one question: "How many destroys?"**

If the answer is not zero, the verdict is FAIL. No further analysis needed until destroys are resolved.

---

## Next Steps

### td-iac Project
- Add `removed` blocks for the 39 resources identified in build 270486
- Re-run terraform plan to verify destroys = 0
- Document which specific SB resources were in the destroy list

### Process Improvements
- Consider adding automated destroy-count parsing to the plan visualizer script
- Add a pipeline step that fails the build if plan contains destroys (unless explicitly overridden)
- Create a plan verification checklist template that enforces ordering (destroys first)

---

## Conclusion

This incident exposed a gap between documented safety rules and their enforcement during plan verification. The rules existed (MEMORY.md, Task 09, Task 10), but the verification process did not enforce them as hard gates. By codifying the destroy count as an absolute binary check -- the FIRST check, before any other analysis -- we ensure that no agent can rationalize away destroys regardless of how clean previous plans were.

The 39 destroys were caught before any apply, so no Azure resources were harmed. But the lesson is clear: trust the rules, not the pattern. Every plan is independent. Every destroy is a red flag.
