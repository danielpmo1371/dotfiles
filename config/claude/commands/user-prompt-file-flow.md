Agent Execution Instructions
Primary Directive
You are to analyze the requirements in user-prompt.md and ensure complete understanding before proceeding with implementation. This systematic approach prevents misaligned deliverables and wasted effort.
Phase 1: Requirements Analysis
1.1 Read and Analyze
Thoroughly review user-prompt.md and extract:
• Primary objectives
• Specific deliverables requested
• Technical constraints
• Success criteria
• Implicit assumptions
1.2 Create Requirements Understanding Document
Generate user-request.md with the following structure:

markdown

# Requirements Understanding Document

## Executive Summary
[Brief 2-3 sentence summary of the core request]

## Interpreted Objectives
1. [Primary objective as understood]
2. [Secondary objectives]
3. [Implicit goals identified]

## Deliverables Breakdown
- [ ] Deliverable 1: [Description]
- [ ] Deliverable 2: [Description]
- [ ] ...

## Technical Analysis

### Assumptions Made
- [List assumptions about technology stack, environment, etc.]

### Potential Challenges
- [Technical challenge 1 and impact]
- [Technical challenge 2 and impact]

## Clarification Needed

### Critical Questions
1. **[Question]**: [Why this matters for the solution]
2. **[Question]**: [Impact if misunderstood]

### Ambiguities Identified
- [Ambiguous requirement]: [Possible interpretations]

### Potential Issues
- **Inconsistency**: [Describe any conflicting requirements]
- **Missing Information**: [What key details are absent]
- **Scope Concerns**: [Areas that might be out of scope]

## Risk Assessment
- **High Risk**: [Elements that could cause project failure]
- **Medium Risk**: [Elements that could impact quality/timeline]
- **Low Risk**: [Minor concerns]

## Recommendation
[ ] Proceed with implementation - all requirements are clear
[ ] Request clarification - critical information missing
[ ] Suggest requirement refinements - improvements identified

## Proposed Approach (if proceeding)
[High-level implementation strategy]
Phase 2: Decision Point
2.1 Evaluation Criteria
Assess whether to proceed based on:
Proceed if ALL are true:
• Core objectives are unambiguous
• Deliverables are clearly defined
• Technical approach is feasible
• No high-risk ambiguities exist
• Success criteria are measurable
Request Clarification if ANY are true:
• Critical technical details are missing
• Conflicting requirements exist
• Scope is undefined or unrealistic
• Dependencies are unclear
• Success metrics are vague
2.2 Action Based on Decision
If Proceeding:
1. Create implementation-plan.md with:
    ◦ Detailed task breakdown
    ◦ Technical approach for each deliverable
    ◦ Timeline estimates
    ◦ Testing strategy
2. Begin systematic implementation following the plan
If Clarification Needed:
1. Present the user-request.md to the user
2. Highlight specific sections needing attention
3. Provide this message format:



I've analyzed your requirements and created a detailed understanding document in `user-request.md`.

**Key Clarifications Needed:**
1. [Most critical question]
2. [Second priority question]

**Recommended Refinements:**
- [Specific improvement to requirements]

Please review the analysis and provide additional context for the highlighted areas. This will ensure the deliverables precisely match your expectations.
Phase 3: Quality Checks
Before proceeding with any implementation:
1. Verify all file paths and resources mentioned exist
2. Confirm technical stack compatibility
3. Validate that proposed solutions align with stated constraints
4. Ensure deliverables match the requested format/structure
Error Handling
If user-prompt.md is:
• Missing: Request the user provide the requirements file
• Empty: Ask for requirements to be added to the file
• Corrupted/Unreadable: Request a new version
• In unexpected format: Attempt to parse and note format issues in analysis
Communication Guidelines
• Be specific about what's unclear rather than vague
• Provide examples when asking for clarification
• Suggest alternatives when identifying issues
• Maintain professional tone while being direct about concerns
• Focus on achieving the user's underlying goals
