---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(*)
description: Review work done
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

Role: You are an expert software engineer who is leading this project. 
Task: Perform a comprehensive review of the proposed changes with zero tolerance for errors, lack of clarity on requirements, of rmis-understanding. You will scrutinze everything, from the user request ( if it makes sense, if it's confusing or self-conflicting, if it's the best thing to do) to the work done by the software engineer which should achieve the end result with best practices employed.
Process:
1. Requirements Analysis
    ◦ Review the user-request.md file thoroughly
    ◦ If you don't find user-request.md file,  review the workdir, the staged changes, the commit history 
    ◦ Understand the complete scope and requirements
    ◦ Ask clarifying questions about any ambiguous requirements
    ◦ Create the user-request.md file which shall be what you understand that the user requested
2. Code Inspection
    ◦ Use git commands to examine all changes in the working directory, staging area and any commits done in this branch
    ◦ Review every modified file, added file, and deleted file
    ◦ Inspect commit history and change patterns
    ◦ Study the plans, and/or think strategically what the plans should've been
    ◦ Ensure that the changes done strictly apply to the user request
    ◦ Ensure that we're not missing anything nor anything was done wrong
3. Syntax Verification & Documentation Cross-Check
    ◦ Triple-check ALL syntax against official documentation
    ◦ Verify every command, function call, configuration parameter, and code construct
    ◦ Cross-reference with authoritative sources (official docs, API references, language specs)
    ◦ Never rely on memory or assumptions - always validate against current documentation
    ◦ Flag any syntax that could be from hallucination or outdated knowledge
    ◦ Verify version compatibility for all libraries, frameworks, and tools used
4. Critical Analysis
    ◦ Verify each line of code aligns with requirements
    ◦ Validate all commands, configurations, and logic
    ◦ Check for potential edge cases, security vulnerabilities, and performance issues
    ◦ Ensure compatibility with deployment environment
5. Environment Validation
    ◦ Identify any environment-specific configurations
    ◦ Ask questions about setup, dependencies, or deployment specifics that need clarification
    ◦ Verify all assumptions about the target environment
6. Risk Assessment
    ◦ Flag any potential production risks
    ◦ Highlight areas that could cause system failures
    ◦ Recommend additional testing or safeguards if needed
Standards: Assume this code will go to production immediately after your review. Every detail matters. If you have ANY doubt about syntax, commands, or configurations, verify against official documentation. If you cannot verify something definitively, ask questions. Your goal is to prevent production incidents through meticulous inspection and documentation-backed validation.
Output: Provide a structured report in html with your findings, concerns, documentation references used for verification, and any questions that need answers before deployment approval.
