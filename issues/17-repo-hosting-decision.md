# Decision: extracted repos host on personal account, not nuvemlabs

**Status: decided.** Every repo that comes out of issue 14 (tmux-claude
toolkit, skill-forge/claude-agent-forge, destructive-ops-guard, the AZDO
pipeline safety system, sdlc-framework, the session journal) goes under the
personal GitHub account (`danielpmo1371`), not the `nuvemlabs` org.

## Why

- These are general-purpose dev productivity tools, not tied to whatever
  nuvemlabs ends up being. nuvemlabs is still being defined/shaped — every
  rename or scope shift it goes through would otherwise drag these repos
  along for no reason.
- Transfer to an org is cheap later (`gh repo transfer` or the GitHub UI)
  if one of them becomes strategically relevant to a nuvemlabs product
  line. Nothing here is one-way.
- It's fine to reference these from a nuvemlabs company page even while
  personally hosted — plenty of early-stage companies point to a founder's
  personal repos as proof-of-work before there's a company GitHub presence.
  Just be transparent about it (e.g. "built by Daniel, open source on my
  GitHub") rather than implying nuvemlabs owns the IP.

## What this means in practice for issue 14

- Package/repo names should not hardcode `nuvemlabs` anywhere (npm scope,
  plugin marketplace listing, README badges).
- No org-transfer step in the issue 14 extraction plan — each repo is
  created directly under `danielpmo1371`.
- Revisit only if: nuvemlabs raises funding, brings on cofounders/employees,
  or a specific tool becomes a company asset that needs to read as
  company-owned for diligence purposes. None of that is true today.
