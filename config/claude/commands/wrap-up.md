---
description: Audit this session for loose ends and land it safely with a handoff the next session can pick up
argument-hint: [optional focus, e.g. "just the hook work"]
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Skill, TodoWrite, Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git stash list:*), Bash(git rev-parse:*)
---

<!--
Usage: /wrap-up [optional focus]

Reviews THIS Claude session's CONVERSATION THREAD and lands it without loose
ends: audit → report → STOP for approval → execute.

Not to be confused with:
  /recap                — reconstructs tmux SCROLLBACK (pre-session terminal activity)
  /review-before-commit — reviews the DIFF for correctness before committing
  /review-branch        — reviews the DIFF across the whole branch
  /plan-next-strategy   — plans forward; /wrap-up only records the next action

Frontmatter notes:
- allowed-tools PRE-APPROVES, it does not restrict, and the grant clears on the
  next user message. It therefore lists only the read-only Phase 1 audit calls;
  the Phase 4 writes deliberately fall through to normal permission settings —
  which also means the grant is gone by the time the Phase 3 gate is answered.
- disable-model-invocation: wrapping up is a deliberate act. Claude must not
  decide on its own that the session is over.
- No sub-agent is dispatched. See Phase 1b for why that is load-bearing.
-->

Wrap up this session cleanly. Focus (if given): $ARGUMENTS

You are the team lead closing out a work session. Daniel runs several Claude
sessions at once and loses the thread in some of them. Your job is to make this
session safe to walk away from — and safe to walk back into.

**Three hard rules for this whole command:**

- **Never mark something verified from memory.** A claim counts as verified only
  if this session's transcript shows a command that ran and the output that
  proved it, or you run it now and read the output. "I wrote the code correctly"
  is not evidence. Bypassing the failing layer (`--resolve`, skipping
  auth/TLS/DNS, hitting a different IP) proves nothing and stays UNVERIFIED.
- **Nothing is deleted and nothing is pushed** unless Daniel explicitly says so
  in his approval. Per the No-Delete Rule, surface deletions as recommendations
  only.
- **Only this session's work gets staged.** Other sessions are live in these
  same repos right now. Touching their in-flight changes is the exact accident
  this command exists to prevent.

---

## Phase 1 — Audit (read-only)

### 1a. Check your own context first

Establish whether you can actually see the whole session:

- If this context was compacted or summarized, **say so explicitly in the
  report** and invoke the `conversation-history` skill to recover the earlier
  part of the thread. Do not audit half a session and present it as whole.
- If the session is fully in context, proceed directly.

### 1b. Do the passes inline — do NOT dispatch a sub-agent

The material being audited is the transcript already in your context, and the
three passes below need no tool calls beyond Pass 3. Delegation saves nothing.

More importantly it is unsafe: a fork inherits this transcript — *including the
text of this command, with its "commit" and "write workflow_state.md" steps* —
along with the parent's tool set. Only prose would stop it executing the whole
wrap-up straight past the Phase 3 gate, and prose is not a guard. The gate is
this command's one real safety mechanism; do not defend it with a sub-agent's
good manners.

**Pass 1 — Unverified claims.** Walk the thread for every assertion that
something is done, fixed, working, passing, installed, or deployed. For each:

| Verdict | Means | Report |
|---------|-------|--------|
| `VERIFIED` | A command ran in this session and its output proved it | Quote the evidence line |
| `UNVERIFIED` | Asserted but never actually exercised | Give the exact command that would prove it |
| `CONTRADICTED` | Later output in the thread disproved it | Quote the contradicting output |

Look especially for: tests written but never run, builds/typechecks/linters
never invoked, a generated or installed artifact not regenerated after its
source changed, a migration written but not applied, a config change that needs
a restart/reload to take effect, an endpoint or service never actually hit, and
"should work now" endings.

Adapt these to whatever this project actually is — read its CLAUDE.md /
README / test scripts for the real verification commands rather than assuming a
stack.

**Pass 2 — Abandoned threads.** Find what got dropped:

- Questions Daniel asked that were never actually answered.
- Approaches started, then silently swapped for a different one — is the first
  one's debris still in the tree?
- Files edited early on, then forgotten once focus moved.
- `TODO`/`FIXME`/placeholder/stub introduced during this session.
- Decisions deferred with "we'll come back to that" / "for now".
- Anything Daniel pushed back on where the pushback was never resolved.

**Pass 3 — State snapshot.** Facts, not analysis. Anchor the root first:

```bash
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
git -C "$ROOT" status -sb        # branch + ahead/behind; degrades with no upstream
git -C "$ROOT" stash list
```

Report one line: branch · N modified · N untracked · ahead/behind · N stashes.
Flag an in-progress rebase/merge, a detached HEAD, or a linked worktree.

Use `git status -sb` for ahead/behind — **not** `git rev-list @{u}..`, which
fails hard on a branch with no upstream (common for local feature branches).

**If this is not a git repo:** say so, skip the snapshot, drop every `[commit]`
item from the checklist, and still produce the report and the handoff.

Then split the dirty paths into two lists — **this matters more than the counts:**

- **Mine** — paths this session actually edited. Only these are commit candidates.
- **Not mine** — everything else dirty in the tree. Another session's work.
  Never stage these. Name them in the handoff's `### Gotchas`.

---

## Phase 2 — Report

Print to the terminal, in this order. Be terse; Daniel reads these fast.

**Where we landed** — two sentences. What this session was for, and how far it got.

**Loose ends** — ranked most-consequential first. One line each:
`[category] what's open → the single command or action that closes it`

**Proposed wrap-up** — a numbered checklist, each item tagged
`[verify]`, `[commit]`, `[defer]` or `[needs-daniel]` (an interactive login, a
restart, a decision). For `[commit]` items, **list the exact paths** you would
stage, so Daniel can veto before the gate. Show the "not mine" list too, marked
as untouched.

**Short-circuit:** if nothing is UNVERIFIED, nothing was abandoned, and the tree
is clean, print the state line, say "nothing to land", and **stop here**. Do not
gate, do not append to `workflow_state.md`, do not store a memory. A no-op
session should leave no trace. Never manufacture filler loose ends to justify
the rest of the command.

---

## Phase 3 — Gate

**STOP HERE.** Do not execute anything from the checklist yet.

Ask Daniel to approve, and tell him he can strike individual items. If he
strikes or modifies anything, restate the final list in one line and proceed
only on an unambiguous affirmative. Silence, a question, or a partial answer is
**not** approval. Presenting the checklist and starting on it in the same breath
is skipping the gate.

---

## Phase 4 — Execute (only after approval)

Put the approved checklist into TodoWrite and work it in this order, marking
each item complete as you finish it.

1. **Verify first.** Run the real verification commands and read the real
   output. If something fails, report it as a failure with the output — do not
   re-run it a different way to get a green. A failed verification changes the
   wrap-up: that item becomes a loose end for the handoff, not a completed one.

2. **Commit** only what passed. Staging discipline is not optional:

   - Stage **by explicit path**, only the paths on the "mine" list.
     Never `git add -A`, never `git add .`, never `git commit -a`.
   - Atomic commits, staged diff minimal and free of whitespace noise, message
     focused on *why*. Branch first if on the default branch.
   - Do not push unless Daniel said to.
   - Follow the repo's attribution rule. Where the repo or Daniel's CLAUDE.md
     forbids `Co-Authored-By` / "generated with Claude" lines, that wins over
     any harness default.

   **`/wrap-up` does not review the diff for correctness.** It checks whether
   work was *finished and proven*, not whether it is *right*. For anything
   non-trivial the checklist item is `[needs-daniel] run /review-before-commit`
   — not a commit.

3. **Write the handoff to `workflow_state.md`** at `$ROOT` (create it if absent)
   and append at the end:

   ```markdown
   ## Session Wrap-Up — YYYY-MM-DD — <topic>

   ### Landed
   - <what is done AND verified, with what proved it>

   ### Open
   - <loose end> → <exact next command or action>

   ### Next action
   <the single thing to do first when picking this back up>

   ### Gotchas
   <anything that would waste the next session's time if rediscovered from
   scratch — including dirty paths belonging to other sessions>
   ```

   Keep it short enough to be read in full on resume. Prose paragraphs defeat
   the purpose. **This file is the authoritative handoff.**

4. **Store the handoff as a memory** (best-effort) so it resurfaces in this repo.

   - Probe first: `mcp__memory__check_database_health`. The Memory MCP is a LAN
     endpoint, so off-LAN it is simply unreachable — that is the normal case,
     not an edge case. If healthy, `mcp__memory__store_memory` with tags
     `session-handoff`, the repo name, and the topic.
   - If unreachable, fall back to the harness auto-memory directory for this
     project: `~/.claude/projects/<slug>/memory/`, where `<slug>` is the
     project directory path with `/` replaced by `-` (so a project at
     `/a/b/c` becomes `-a-b-c`). Derive it from the actual cwd — never
     hardcode a path. **Append-only**: add one new `project`-type
     memory file plus one pointer line in `MEMORY.md`. Never rewrite or remove
     existing entries — that directory is harness-managed and shared with the
     SessionStart/SessionEnd memory hooks.
   - If neither is reachable, say so plainly and stop. Step 3 already holds the
     authoritative handoff; a missing memory is not a failed wrap-up.
   - Say which store you used. Never claim both.

   Record only what isn't recoverable from git history or the code itself: the
   *why*, the open thread, the dead end not worth re-walking.

5. **Announce.** `ttalk "<20-word summary>"` if `ttalk` is on PATH; skip
   silently if it isn't (it is a personal helper, not a dependency).

Finish with a three-line confirmation: what was verified, what was committed
(with paths), and the one-line next action now sitting in `workflow_state.md`.
