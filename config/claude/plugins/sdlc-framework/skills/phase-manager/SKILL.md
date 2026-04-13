---
name: phase-manager
description: |
  Manages SDLC phase transitions, stopping decisions, and complexity assessment.
  Used internally by the Team Lead agent. Not typically invoked directly by users.
---

# Phase Manager

## Role

You provide phase transition logic for the SDLC Team Lead. You assess task complexity, select which phases to run, determine when to stop for user input, and validate that phase prerequisites are met before advancing.

This skill is used internally by the Team Lead orchestrator. It is not typically invoked directly by users.

## Complexity Assessment

Assess complexity from scope analysis results. Use these inputs from the Scope Analyst output:

| Input Field | Type | Source |
|---|---|---|
| `affectedFiles` | number | Count of files that need changes |
| `affectedRepos` | number | Count of repos impacted |
| `hasArchitecturalChanges` | boolean | Structural/pattern changes required |
| `hasSecurityImplications` | boolean | Auth, crypto, or access control changes |
| `hasDatabaseChanges` | boolean | Schema, migration, or data model changes |
| `hasApiChanges` | boolean | Public API surface changes |

### Decision Matrix

**Complex** (any one true):
- `affectedFiles > 10`
- `affectedRepos > 3`
- `hasArchitecturalChanges == true`
- `hasSecurityImplications == true` AND `hasDatabaseChanges == true`

**Simple** (all must be true):
- `affectedFiles <= 3`
- `affectedRepos <= 1`
- `hasArchitecturalChanges == false`
- `hasSecurityImplications == false`
- `hasDatabaseChanges == false`

**Medium** — everything else.

## Phase Selection

Based on assessed complexity, select which phases to execute:

| Tier | Phases | Rationale |
|---|---|---|
| **Simple** | 1, 6, 7, 8 | Bootstrap, plan, implement, verify. Skip scope/audit/reporting overhead. |
| **Medium** | 1, 2, 6, 7, 8, 9 | Add scope analysis and PR delivery. Skip deep audit and retrospective. |
| **Complex** | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 | Full lifecycle with all quality gates. |

**Override:** If `.sdlc.json` provides custom `phases.complexity` config, use that instead of defaults.

**Early complexity estimation:** Before Phase 2 completes, use the story description and AC count as rough indicators:
- 1 AC, single component mentioned -> likely Simple
- 2-4 ACs, multiple components -> likely Medium
- 5+ ACs, cross-cutting concerns -> likely Complex

Refine after Phase 2 scope results are available.

## Stopping Criteria

### Autonomous Mode

Auto-advance unless a stop condition is met. Each phase has specific triggers:

**Phase 1 — Bootstrap:**
- STOP if requirements are unclear or contradictory
- STOP if acceptance criteria are missing entirely
- STOP if conflicting stakeholder requirements detected
- ADVANCE if work item parsed cleanly with clear AC

**Phase 2 — Scope Discovery:**
- STOP if blast radius > 10 files (user should validate scope)
- STOP if > 5 repos affected (cross-team coordination may be needed)
- STOP if unfamiliar subsystems detected (user knowledge needed)
- ADVANCE if scope is contained and well-understood

**Phase 3 — Audit:**
- STOP if any CRITICAL or HIGH severity findings
- STOP if total issues > 50 (noise level too high, prioritization needed)
- STOP if conflicting package versions across repos
- ADVANCE if only LOW/MEDIUM findings with clear fixes

**Phase 4 — Scope Refinement:**
- STOP if audit revealed architectural trade-offs needing user decision
- STOP if scope grew significantly from audit findings
- ADVANCE if refinements are incremental and clear

**Phase 5 — Reporting:**
- ADVANCE always (reporting is informational, no decisions needed)

**Phase 6 — Planning:**
- STOP if multiple valid approaches exist with different trade-offs
- STOP if any HIGH risk items identified in the plan
- ADVANCE if single clear approach with acceptable risk

**Phase 7 — Execution:**
- STOP if build failures after 3 retry attempts
- STOP if test failures that aren't obviously related to the change
- STOP if merge conflicts requiring human judgment
- ADVANCE after each successful step (continue to next step)

**Phase 8 — Verification:**
- STOP if ANY verification failures (tests, build, AC check)
- ADVANCE only when all checks pass

**Phase 9 — PR/Delivery:**
- STOP if pre-commit hook failures
- STOP if review feedback received that needs addressing
- ADVANCE if PR created successfully with all checks passing

**Phase 10 — Retrospective:**
- STOP if critical incident occurred during the workflow
- ADVANCE for normal completion

### Guided Mode

STOP at every phase boundary. Present:
1. **Phase summary** — what was accomplished
2. **Key findings** — important outputs or decisions made
3. **Recommendation** — suggested next action
4. **Options** — continue, re-run phase, skip, or abort

## Phase Transition Checklist

Before advancing to the next phase, verify:

1. **Current phase output exists** — the expected deliverable file is written to the phase folder
2. **No unresolved blockers** — check workflow_state.md for open blockers
3. **State updated** — workflow_state.md reflects phase completion
4. **Memory synced** — Memory MCP updated with phase results (if available)
5. **Specialist reported** — the phase specialist sent their completion summary

## Handling Phase Failures

When a phase fails:

1. **Log the failure** in workflow_state.md with error details
2. **Assess retryability:**
   - Transient errors (network, timeout) -> retry once automatically
   - Logic errors (wrong approach) -> stop, report to user
   - Environment errors (missing tools, auth) -> stop, report setup issue
3. **Retry strategy** (Autonomous mode only):
   - Maximum 3 retries per phase
   - Escalate to user after 3rd failure
   - Never retry Phase 7 (Execution) failures automatically — code changes should be deliberate
4. **Fallback:**
   - If a specialist agent fails to spawn, the Team Lead can attempt the phase directly
   - If a delegated skill is unavailable, use the base specialist capabilities

## Phase Dependencies

Some phases have hard dependencies that must be validated:

| Phase | Requires |
|---|---|
| 2 (Scope) | Phase 1 output (story-context.md) |
| 3 (Audit) | Phase 2 output (scope-analysis.md) |
| 4 (Refinement) | Phase 3 output (audit-summary.md) |
| 5 (Reporting) | Phases 1-4 outputs |
| 6 (Planning) | Phase 1 output minimum; Phase 2 output if medium/complex |
| 7 (Execution) | Phase 6 output (execution-plan.md) |
| 8 (Verification) | Phase 7 output (execution-log.md) |
| 9 (PR/Delivery) | Phase 8 passed (all verifications green) |
| 10 (Retrospective) | Phase 8 or 9 complete |

If a dependency phase was skipped (e.g., Simple tier skips Phase 2), the dependent phase uses available information or asks the Team Lead to provide the missing context inline.

## Model Override Guidance

The Team Lead can override the default model for a specialist:

| Condition | Override |
|---|---|
| Scope Analyst with >5 repos | Upgrade to Opus |
| Audit with security-critical findings | Upgrade to Opus |
| Implementation with major refactoring | Upgrade to Opus |
| QA with complex test strategy needed | Upgrade to Opus |
| Retrospective after critical incident | Upgrade to Opus |
