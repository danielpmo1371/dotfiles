---
name: secrets-debugging
description: Diagnose why a secret, token, or credential is not reaching a tool, using the secrets-doctor CLI as the canonical method. Use when AZDO_PAT, PIPELINE_GUARD_*, API keys, or other env-var secrets are missing or empty, when MCP servers or pipeline hooks fail auth (401/unauthorized), or when keychain / secrets.sh / environment propagation is in question. Replaces ad-hoc security/grep pipelines.
---

# Secrets Debugging

## Role

Diagnose secret-propagation failures with `secrets-doctor` — the single canonical tool for this. Do NOT hand-assemble `security find-generic-password` / `grep` / `[ -n "$VAR" ]` pipelines; that is exactly what this skill replaces.

## The chain being diagnosed

```
macOS Keychain            config/shell/secrets.sh       shell environment
(nuvemlabs/secrets,   ──▶ (export KEY="$(secret    ──▶  (what tools and MCP
 service "dotfiles")        KEY)")                       servers actually see)
      STORE                     EXPORTS                       ENV
```

## Quick start

```bash
secrets-doctor                    # full health check: every key secrets.sh reads
secrets-doctor AZDO_PAT           # one key
secrets-doctor PIPELINE_GUARD     # prefix — expands to all matching keys
```

Lives at `$DOTFILES_DIR/util-scripts/secrets-doctor` (on PATH). Exit codes: 0 = chain intact, 1 = at least one break, 2 = setup error. `--help` for details.

## Interpreting the output

The failure pattern IS the diagnosis:

| STORE   | EXPORTS | ENV     | Diagnosis → Fix |
|---------|---------|---------|-----------------|
| MISSING | L*n*    | MISSING | Secret never stored → `secret_set KEY <value>` (ask the user to run it with the real value — never handle the value yourself) |
| ok      | MISSING | MISSING | Stored but not exported → add `export KEY="$(secret KEY 2>/dev/null)"` to `config/shell/secrets.sh` |
| ok      | L*n*    | MISSING | Chain fine, the current shell is stale → user restarts shell or re-sources `secrets.sh`; long-running processes (MCP servers, tmux panes) need a restart too |
| ok      | L*n*    | set     | Not a secrets problem — stop here and look elsewhere (wrong var name expected by the tool, scope/permissions of the token, network) |
| n/a     | L*n* (derived) | MISSING | Alias var (e.g. AZURE_DEVOPS_PAT re-exports AZDO_PAT) → diagnose the source key instead |

## Example

User reports: "the azure-devops MCP server gets 401s."

```bash
$ secrets-doctor AZDO_PAT AZURE_DEVOPS_PAT
KEY                STORE   EXPORTS         ENV
AZDO_PAT           ok      L27             MISSING
AZURE_DEVOPS_PAT   n/a     L28 (derived)   MISSING
$ echo $?
1
```

Reading: the store and export line are fine, so nothing to fix in the keychain or `secrets.sh` — the shell that spawned the MCP server predates the secret (row 3 of the table). The derived alias is MISSING only as a consequence of its source key. Fix: restart the session that launches the MCP server, then re-run `secrets-doctor AZDO_PAT` (expect exit 0) and retry the MCP call.

## Rules

1. **Never print, echo, log, or copy a secret's value.** `secrets-doctor` is names-only by design; keep every follow-up command names-only too. If a value must be entered or compared, the user does it.
2. **ENV reflects the invoking shell.** A green ENV in your Bash tool session does not vouch for a GUI app, daemon, or a different tmux pane — say which context was tested.
3. **Don't bypass a red link to fake a green result** (e.g. exporting the var inline just to make a tool run). Fix the broken link, then re-run `secrets-doctor` to prove it.
4. **New secrets need two links**: `secret_set KEY ...` (user) AND an export line in `config/shell/secrets.sh` (committed to dotfiles). One without the other is the top-two failure patterns above.
5. If `secrets-doctor` itself is missing (new machine), it comes from the dotfiles repo (`util-scripts/`); check PATH wiring in `config/shell/path.sh` before reinventing the checks.

## Verification

After any fix, re-run the same `secrets-doctor` invocation and confirm exit 0. Then re-run the originally failing tool. Both, in that order — a green doctor with a still-failing tool means the diagnosis was incomplete, not that the doctor is wrong.
