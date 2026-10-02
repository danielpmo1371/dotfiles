# Scheduled Follow-ups — Templates

Contents: [Prompt template](#prompt-template) · [Memory record](#memory-record) · [User report](#user-report) · [Worked example](#worked-example)

## Prompt template

Fill the `[bracketed]` parts; keep every other line. Pick ONE mode block and delete the other. Derived from the prompts in `~/.local/state/claude-tasks/prompts/`.

```markdown
Scheduled follow-up (set up [YYYY-MM-DD]): [one-line goal, e.g. "24-hour health check after the Jellyfin 12.1 upgrade on CT 180"]. You are in [~/repos/<repo>].

<!-- mode: READ-ONLY -->
READ-ONLY. Change nothing on any host or in any repo except appending the result to the Log of the "[section title]" section in workflow_state.md (commit only that file; don't stage the user's other uncommitted files).

<!-- mode: PLAN-ONLY -->
PLANNING ONLY. Read-only commands; the only write is a new section in workflow_state.md (commit only that file; don't stage the user's other uncommitted files).

Context: read the "[section title]" section of workflow_state.md first ([what it holds: hosts, backups, rollback, the decision already made]). [Any facts the future session cannot rediscover: commit ids, timestamps, baseline numbers.]

Guardrails (mandatory):
- No-Delete: never delete, move or overwrite anything outside a git work tree; clean-ups become commands for the user to run.
- Never print secret values (API keys, tokens, passwords); refer to them by name.
- If anything needs changing, do NOT change it: write a short plan in workflow_state.md with Status NEEDS_PLAN_APPROVAL.
- Don't edit ~/.local/state/claude-tasks/SCHEDULED.md; task status is maintained only by `claude-task`.
- Test through the real user-facing path (no --resolve, no auth/TLS bypass); report failures as failures.

Steps:
1. [Access: how to reach the hosts, e.g. `ssh -o BatchMode=yes root@pve`, then `pct exec <id> -- ...`.]
2. [What to check / inventory, with the exact commands where they matter.]
3. [Decision rule with a threshold, e.g. "under ~20 MB/day is fine, leave it; above that, write a plan".]
4. Append a concise dated result to that section's Log and set its Status to [DONE / ISSUES FOUND / NEEDS_PLAN_APPROVAL].
5. Finish with ttalk "<20-word summary>".
```

Checklist before scheduling — the prompt must have:

- [ ] a context pointer to a named `workflow_state.md` section (or the facts inline if there is none)
- [ ] exactly one mode: READ-ONLY or PLAN-ONLY
- [ ] the five guardrail lines
- [ ] where the result is logged and which Status to set
- [ ] a final `ttalk "<20-word summary>"` step
- [ ] no secret values anywhere

## Memory record

Duty 1. Content (plain text, one fact per line):

```
Scheduled follow-up <name>: fires <YYYY-MM-DD HH:MM> NZ in tmux session <session>, dir <dir>.
Purpose: <purpose>.
Prompt: ~/.local/state/claude-tasks/prompts/<fire-date>-<name>.md
Created <YYYY-MM-DD> by the session working on "<workflow_state.md section>".
Cancel: claude-task cancel <name>
```

Primary — `mcp__memory__memory_store`:

```json
{
  "content": "<content above>",
  "metadata": { "tags": "scheduled-followup,<repo-name>", "type": "action_item" }
}
```

Fallback — REST, only if the MCP tool errors or is unavailable. The key is read from the environment inside the command and never echoed; only the HTTP status is printed:

```bash
endpoint=$(jq -r '.memoryService.http.endpoint' ~/.claude/hooks/config.json)
jq -n --arg c "$content" --arg repo "<repo-name>" \
  '{content: $c, tags: ["scheduled-followup", $repo], memory_type: "action_item"}' |
  curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$endpoint/api/memories" \
    -H 'Content-Type: application/json' \
    -H @<(printf 'X-API-Key: %s\n' "$MEMORY_MCP_API_KEY") \
    --data @-
```

`2xx` = stored. Anything else (or `$MEMORY_MCP_API_KEY` empty — check with `secrets-doctor MEMORY_MCP_API_KEY`, never by echoing it) = failed. Either way, tell the user the MCP tool failed and what happened with the fallback.

## User report

Duty 3. One block per task in the reply:

```
Scheduled follow-up `<name>` — <purpose>
- Fires: <Day YYYY-MM-DD HH:MM> NZ (tmux session `<session>`, dir <dir>)
- Mode: READ-ONLY | PLAN-ONLY; result goes to workflow_state.md "<section>"
- Verified: `claude-task list` row present; dry-run delivered the prompt
- Memory: stored via MCP | via REST fallback (MCP failed: <error>) | NOT stored (<error>)
- Cancel: `claude-task cancel <name>`
```

## Worked example

End of a session that upgraded Jellyfin on 2026-09-27 at 20:05. `claude-task list` shows nothing else on 2026-09-28.

1. Name `jellyfin-24h`; time `"2026-09-28 20:30"` (next evening, ~24h after).
2. Prompt drafted in the scratchpad from the template, READ-ONLY mode, context pointer to "Jellyfin 10.11.5 → 12.1 upgrade (CT 180)", checks: version, restarts, `[ERR]` counts, NVENC transcode, Seerr sync, public URL via real DNS.
3. Schedule and verify:
   ```bash
   claude-task schedule jellyfin-24h "2026-09-28 20:30" ~/repos/proxmox-homelab <scratchpad>/jellyfin-24h.md \
     --purpose "Read-only 24h health check after Jellyfin 12.1 upgrade"
   claude-task list
   claude-task dry-run jellyfin-24h
   ```
4. `mcp__memory__memory_store` with tags `scheduled-followup,proxmox-homelab`.
5. Reply with the user report block, ending `Cancel: claude-task cancel jellyfin-24h`.

A second follow-up the same evening (e.g. a log-size check) goes at 20:40, not 20:30.
