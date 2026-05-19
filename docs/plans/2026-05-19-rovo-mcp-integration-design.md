# Atlassian Rovo MCP Integration — Design

**Date:** 2026-05-19
**Status:** Approved — ready for implementation plan
**Approach:** B (Rovo-aware skill refresh + /setup walkthrough)

## Problem

The plugin's skills and docs were written against the "Atlassian MCP" branding and surface a narrow tool set (`searchJiraIssuesUsingJql`, `getJiraIssue`, `searchConfluenceUsingCql`, `getConfluencePage`, `createJiraIssue`, `addCommentToJiraIssue`). Atlassian has since rebranded the same server as the **Atlassian Rovo MCP Server**, added a cross-system `search(cloudId, query)` tool that returns Jira issues and Confluence pages in one call, published official client guidance (defaults in CLAUDE.md / AGENTS.md), and announced deprecation of the legacy `https://mcp.atlassian.com/v1/mcp` endpoint after **2026-06-30** in favour of `/v1/mcp/authv2`. The plugin's `product-discovery` and `outcome-review` skills do separate JQL + CQL queries when a single Rovo `search` would scope better, and `/setup` only mentions Atlassian in passing rather than walking users through connecting it.

## Research Findings

| Question | Answer | Source |
|---|---|---|
| Same server? | Yes. "Atlassian Rovo MCP Server" = current branding for the same server. | Atlassian Community article; `/atlassian/atlassian-mcp-server` Context7 docs |
| Endpoint | `https://mcp.atlassian.com/v1/mcp/authv2` (recommended); legacy `/v1/mcp` deprecated after 2026-06-30 | Atlassian Support: Getting started with the Atlassian Remote MCP Server |
| New Rovo tools we don't use | `search(cloudId, query)` — cross-system Jira+Confluence search; exposed in this session as `mcp__atlassian__search` | Context7 docs |
| Rovo Agents as MCP tools? | No. Rovo MCP is data tools only (Jira, Confluence, Compass) + cross-system search. | Atlassian Support docs |
| Auth | OAuth 2.1 with dynamic client registration (no Atlassian-side app creation); API token optional. | Atlassian Support docs |
| Other scope | Compass tools (services, dependencies) supported on same server. | Atlassian Support + GitHub README |
| Official client guidance | Put `cloudId`, default Jira project key, default Confluence spaceId, and `maxResults: 10` in CLAUDE.md/AGENTS.md to skip discovery calls. | GitHub README |

## Capabilities Affected

| Area | Files |
|---|---|
| Skills (Tier 1 rewrite) | `skills/product-discovery/SKILL.md`, `skills/outcome-review/SKILL.md` |
| Routing config | `config/default-triggers.json`, `config/fallback-registry.json` |
| Setup walkthrough | `commands/setup.md` — new section "Atlassian Rovo MCP" |
| Docs / banner | `README.md`, `hooks/session-start-hook.sh` (comment block only), `CHANGELOG.md` |

## Out-of-Scope

- No bundled marketplace plugin install (Rovo is claude.ai-managed, not marketplace)
- No `CONTEXT_CAPS` detection of Atlassian/Rovo in session-start (deferred; revival trigger: a skill that branches on its presence)
- No Compass-specific skill or workflow (server exposes it; no current use case)
- No Rovo Agents wrapper (not exposed as MCP tools)
- `/setup` does **not** write to project CLAUDE.md autonomously — it offers a copy-paste defaults block
- No rewriting of users' existing `/mcp` configs
- No hook routing logic changes

## Approach

Tactical edits — no new files, no new architecture.

### 1. `product-discovery` Tier 1 rewrite

Replace the current "Query Jira / Query Confluence" pair with a three-step flow:

1. **Scope** — `mcp__atlassian__search(cloudId, query)` returns mixed Jira issues + Confluence pages
2. **Deep-read top hits** — `getJiraIssue` / `getConfluencePage`
3. **Targeted refine** — `searchJiraIssuesUsingJql` / `searchConfluenceUsingCql` only if scoping missed relevant work

Add a one-line note: *"If `cloudId` and defaults are in CLAUDE.md, skip `getAccessibleAtlassianResources`."* Use `maxResults: 10` / `limit: 10` per Atlassian guidance.

### 2. `outcome-review` Tier 1 rewrite

Same `search`-first pattern when looking up the original Jira ticket from feature name. Keeps the existing `createJiraIssue` / `addCommentToJiraIssue` flow for follow-up creation (unchanged).

### 3. Routing config updates

- Add `search` to the `atlassian` capability tool list in `config/fallback-registry.json`.
- Update `atlassian-jira` and `atlassian-confluence` trigger hint copy in both `config/default-triggers.json` and `config/fallback-registry.json` to lead with: *"If Atlassian Rovo MCP is connected, prefer `search` for cross-system discovery before targeted JQL/CQL."*
- Update the `atlassian` capability `description` field to reference Rovo branding and Compass scope.

### 4. New `/setup` step

Insert as a new section in `commands/setup.md` (numbered after the Context Stack step). Pseudocode:

```
detect: claude mcp list 2>/dev/null | grep -iE 'atlassian|rovo'

case absent:
  ask: "Would you like to connect Atlassian Rovo MCP? It provides Jira/Confluence/Compass access via OAuth."
  if yes: instruct user to run /mcp and add server at https://mcp.atlassian.com/v1/mcp/authv2

case present at legacy /v1/mcp URL:
  note: "Atlassian is deprecating /v1/mcp after 2026-06-30. The recommended URL is /v1/mcp/authv2."
  offer URL upgrade (do not force)

case present:
  offer copy-paste defaults block for project CLAUDE.md:
    ## Atlassian Rovo MCP
    When connected:
    - cloudId = "https://<site>.atlassian.net"
    - Default Jira project key = "<KEY>"
    - Default Confluence spaceId = "<ID>"
    - Use `maxResults: 10` / `limit: 10` for JQL and CQL search
    - Prefer `search(cloudId, query)` for cross-system discovery first
```

User-prompt-gated at each branch; no autonomous file writes.

### 5. Terminology refresh

"Atlassian MCP" → "Atlassian Rovo MCP" across `README.md`, `commands/setup.md`, `hooks/session-start-hook.sh` comment block, and skill copy in `product-discovery` and `outcome-review`. Single inline `(formerly Atlassian MCP)` on first README mention for continuity.

### 6. CHANGELOG

Add to `[Unreleased]` accumulator per repo convention.

## Acceptance Scenarios

**GIVEN** a user with no Atlassian/Rovo MCP connected
**WHEN** they run `/setup`
**THEN** /setup detects absence via `claude mcp list`, asks if they want to connect, points them to `/mcp` with the `/v1/mcp/authv2` URL, and offers the defaults block on success.

**GIVEN** a user with Atlassian MCP already connected at the legacy `/v1/mcp` URL
**WHEN** they run `/setup`
**THEN** /setup detects the connection, notes the 2026-06-30 deprecation, and offers the URL upgrade as opt-in.

**GIVEN** `product-discovery` is invoked for an ambiguous topic ("what's our auth roadmap?")
**WHEN** Rovo MCP is available
**THEN** the skill calls `mcp__atlassian__search` first, refines with `getJiraIssue`/`getConfluencePage`, and only falls back to JQL/CQL for misses.

**GIVEN** any user-facing documentation in this repo
**WHEN** read after this change
**THEN** all Atlassian references use "Atlassian Rovo MCP" (one inline continuity hint on first README mention).

## Testing

- `bash tests/run-tests.sh` — existing suites should pass
- If trigger hint text is asserted in `tests/test-routing.sh` fixtures, update fixtures alongside the hint copy
- Manual: simulate `/setup` flow with and without an `atlassian` entry in `claude mcp list`
- Verify session-start banner is byte-identical (no new `CONTEXT_CAPS` key)

## Risk / Rollback

- Change set is documentation- and config-shaped. No hook routing logic touched.
- Single `git revert` of the PR rolls back cleanly.
- No persistent user-system state changes (no writes to user CLAUDE.md, no MCP config edits).

## Decision

Approved by user 2026-05-19 — proceed to implementation plan via `superpowers:writing-plans`.
