# SDLC Orchestrator Examples

## Example 1: Simple Task — Fix a typo in the README

**Scenario:** User wants to fix a typo found in the README of svc-api.

```
User: "Start working on US#200100"
```

### What happens (Autonomous mode, ~45 min)

**Phase 1 — Bootstrap (5 min)**
- Bootstrap Specialist fetches US#200100 from AZDO
- Title: "Fix typo in svc-api README contributing section"
- Creates `user_story-200100-fix-typo-readme/`
- Writes story context with 1 acceptance criterion

**Complexity: Simple** (1 file, 1 repo, no architectural/security/DB changes)
**Selected phases: 1, 6, 7, 8**

**Phase 6 — Planning (5 min)**
- Planning Architect reads the README, identifies the typo location
- Plan: single file edit, no tests needed, no build impact

**Phase 7 — Execution (5 min)**
- Implementation Engineer fixes the typo
- Commits: `fix: correct typo in contributing section of README`

**Phase 8 — Verification (5 min)**
- QA Specialist confirms the fix, checks no other references broken
- Build passes (no code changes)

**Result:** Done in 4 phases. User sees a summary and can create a PR.

---

## Example 2: Medium Task — Add a new API endpoint

**Scenario:** Add a new health check endpoint to the svc-api widget function app.

```
User: "/sdlc start US#195432"
```

### What happens (Autonomous mode, ~2 hrs)

**Phase 1 — Bootstrap (5 min)**
- Fetches work item with 3 acceptance criteria
- Creates folder scaffold

**Phase 2 — Scope Discovery (15 min)**
- Scope Analyst searches svc-api for existing health endpoints
- Finds pattern in `HealthMonitor/` function app
- Maps: 2 files to create, 1 config to update, 3 test files needed
- Dependencies: svc-apim needs a new operation definition

**Complexity: Medium** (2 repos, ~12 files, API changes but no architectural overhaul)
**Selected phases: 1, 2, 6, 7, 8, 9**

**Phase 6 — Planning (15 min)**
- Planning Architect designs the endpoint following existing health check patterns
- Plan: new function class, DI registration, unit tests, APIM operation

**Phase 7 — Execution (60 min)**
- Implementation Engineer creates the endpoint in svc-api
- Adds unit tests following existing patterns (MSTest + Moq + FluentAssertions)
- Updates APIM operation definition in svc-apim
- Commits incrementally per component

**Phase 8 — Verification (20 min)**
- QA Specialist runs `dotnet test` with 32-worker parallelism
- Verifies all 3 acceptance criteria met
- Confirms no regressions in existing health endpoints

**Phase 9 — PR/Delivery (10 min)**
- Reporter creates PR with structured description
- Links to US#195432
- Lists affected repos and test results

**Result:** Done in 6 phases. PR ready for human review.

---

## Example 3: Complex Task — Multi-repo dependency update

**Scenario:** Update NuGet packages across svc-api, portal-app, and billing-api with breaking changes.

```
User: "Set up SDLC for work item 170514"
```

### What happens (Guided mode, ~5 hrs)

**Phase 1 — Bootstrap (5 min)**
- Fetches US#170514: "Update NuGet dependency packages across all .NET repos"
- 5 acceptance criteria, references 3 repos
- **Team Lead continues** (requirements clear)

**Phase 2 — Scope Discovery (20 min)**
- Scope Analyst examines svc-api, portal-app, billing-api
- Spawns 3 `feature-dev:code-explorer` agents in parallel (one per repo)
- Maps 45+ files affected, identifies breaking API changes in Azure.Core
- **[GUIDED STOP]** Presents: 3 repos, 45 files, HIGH complexity
- User reviews and approves proceeding

**Phase 3 — Audit (30 min)**
- Audit Specialist runs `dotnet list package --outdated` per repo
- Checks for security advisories via `dotnet list package --vulnerable`
- Finds: 12 outdated packages, 2 with known CVEs
- **[GUIDED STOP]** Presents audit findings — 2 CVEs flagged as HIGH
- User reviews CVEs, approves updating them

**Phase 4 — Scope Refinement (10 min)**
- Scope Analyst refines based on audit: 2 packages need major version bumps
- Adds breaking change analysis for Azure.Core 2.x -> 3.x
- **[GUIDED STOP]** Presents refined scope with breaking changes
- User approves

**Phase 5 — Reporting (10 min)**
- Reporter generates stakeholder report (HTML + MD)
- Includes: package list, CVE details, breaking changes, estimated effort
- **[GUIDED STOP]** Report available for user to share with team

**Phase 6 — Planning (20 min)**
- Planning Architect creates execution plan:
  - Step 1: Update Azure.Core in svc-api (most impacted)
  - Step 2: Fix breaking changes in svc-api
  - Step 3: Run svc-api tests
  - Step 4: Update portal-app (similar pattern)
  - Step 5: Update billing-api (minimal impact)
  - Step 6: Cross-repo integration verification
- **[GUIDED STOP]** Plan presented with per-step risk assessment
- User approves with one adjustment

**Phase 7 — Execution (120 min)**
- Implementation Engineer works through the plan step by step
- Creates git worktrees per repo for isolation
- Commits after each step passes build
- **[AUTO STOP]** Build failure in portal-app after Azure.Core update
- User helps resolve an ambiguous API migration
- Engineer continues after fix

**Phase 8 — Verification (30 min)**
- QA Specialist runs full test suites across all 3 repos
- Verifies each acceptance criterion
- Runs integration test pipeline (Pipeline 812) for cross-repo validation
- All tests pass

**Phase 9 — PR/Delivery (15 min)**
- Reporter creates 3 PRs (one per repo) with linked descriptions
- Each PR references US#170514 and lists package changes
- Pre-commit hooks pass on all 3

**Phase 10 — Retrospective (10 min)**
- Retrospective Analyst notes:
  - Azure.Core migration pattern documented for future use
  - Build failure in portal-app was due to missed interface change — add to audit checklist
  - Parallel scope analysis saved ~30 min

**Result:** Full 10-phase workflow. 3 PRs created, lessons captured.

---

## Example 4: Resume Scenario — Picking up where we left off

**Scenario:** Session ended mid-execution yesterday. User wants to continue.

```
User: "Resume story 170514"
```

### What happens

**Detection:**
- Orchestrator finds `user_story-170514-update-dependency-packages/`
- Reads `workflow_state.md`:
  ```
  Current Phase: 7 - Execution
  Status: IN_PROGRESS
  Last Activity: Step 3 of 6 completed (svc-api tests passing)
  ```
- Queries Memory MCP for `sdlc:US#170514:*` — confirms same state

**User prompt:**
```
Found in-progress workflow for US#170514:
  Phase: 7 - Execution (step 3 of 6 complete)
  Last activity: svc-api tests passing, portal-app update pending

Options:
  1. Continue from step 4 (portal-app update)
  2. Re-run step 3 (verify svc-api still passing)
  3. Restart from Phase 6 (re-plan)
```

**User selects option 1.**

**Spawn Team Lead** with resume context:
- Work item ID, mode (from previous session)
- Current phase and step
- Completed phase outputs (reads from phase folders)
- Previous decisions (from Memory MCP)

Team Lead picks up from step 4 of the execution plan and continues through remaining phases.
