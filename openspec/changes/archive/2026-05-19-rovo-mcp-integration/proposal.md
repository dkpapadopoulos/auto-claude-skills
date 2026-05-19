## Why

The plugin's skills and routing config were written against the legacy "Atlassian MCP" branding and surface a narrow tool set (`searchJiraIssuesUsingJql`, `getJiraIssue`, `searchConfluenceUsingCql`, `getConfluencePage`, `createJiraIssue`, `addCommentToJiraIssue`). Atlassian has since rebranded the same server as the **Atlassian Rovo MCP Server**, added a cross-system `search(cloudId, query)` tool that returns Jira issues + Confluence pages in one call, published official client guidance (defaults in CLAUDE.md / AGENTS.md), and announced deprecation of the legacy `https://mcp.atlassian.com/v1/mcp` endpoint after **2026-06-30** in favour of `/v1/mcp/authv2`. `product-discovery` and `outcome-review` did separate JQL + CQL queries when a single Rovo `search` would scope better, and `/setup` only mentioned Atlassian in passing rather than walking users through connecting it.

## What Changes

1. **Tier 1 skill flows prefer Rovo `search` first.** Both `skills/product-discovery/SKILL.md` and `skills/outcome-review/SKILL.md` lead Tier 1 with `mcp__atlassian__search(cloudId, query)` to scope across Jira + Confluence in one call, then deep-read top hits with `getJiraIssue` / `getConfluencePage`, and only fall back to targeted `searchJiraIssuesUsingJql` / `searchConfluenceUsingCql` when the cross-system scope missed relevant work. `maxResults: 10` / `limit: 10` guidance added per Atlassian's official client docs.
2. **Routing config recognises `search` and prefers it in hints.** `config/default-triggers.json` and `config/fallback-registry.json` add `search` as the first element of the `atlassian` capability's `mcp_tools` list, rewrite the capability description to name Atlassian Rovo MCP / the recommended `/v1/mcp/authv2` endpoint / the 2026-06-30 legacy deprecation / Compass scope, and update the `atlassian-jira` and `atlassian-confluence` trigger hint copy to lead with `prefer search(cloudId, query) for cross-system discovery before targeted JQL/CQL`.
3. **`/setup` Atlassian Rovo MCP walkthrough.** `commands/setup.md` gains a new Step 7 that detects an existing `/mcp` connection via `claude mcp list`, branches for not-connected / legacy-URL / connected cases, points users at the `/v1/mcp/authv2` endpoint, warns on the legacy URL deprecation, and offers a copy-paste defaults block (cloudId, project key, spaceId, `maxResults: 10`) for project CLAUDE.md without writing autonomously. Subsequent steps renumbered.
4. **Terminology refresh.** README.md (with one `(formerly Atlassian MCP)` continuity hint), the `hooks/session-start-hook.sh` MCP-plugins comment block, and the DISCOVER / LEARN RED_FLAGS strings in `hooks/skill-activation-hook.sh` all reword "Atlassian MCP" → "Atlassian Rovo MCP".
5. **Test fixture aligned.** `tests/test-routing.sh` inline `atlassian-jira` hint fixture (line 348) updated to match the new canonical copy.

Two defects caught during implementation and fixed:
- **Source of truth mismatch.** The session-start hook regenerates `config/fallback-registry.json` from `config/default-triggers.json`. An initial pass only updated the fallback-registry capability block, so subsequent hook runs reverted the working tree. Fix mirrored the capability change into `default-triggers.json` (commit `cc3a0c7`).
- **Shell substitution trap in RED_FLAGS.** A `DISCOVER` RED_FLAGS line used literal backticks around `search` inside a double-quoted Bash assignment, which triggered command substitution at runtime (the rendered banner emitted `search: command not found` to stderr and dropped the word entirely). `bash -n` does not catch this. Fix switched to single quotes around `'search'` (commit `d1f68a8`).

## Capabilities

### Modified Capabilities
- `skill-routing`: extends the routing engine with Rovo-aware Atlassian capability metadata (`search` in `mcp_tools`, Rovo branding + endpoint URL + Compass scope in description, Rovo-first hint copy on `atlassian-jira` and `atlassian-confluence` triggers, and search-first Tier 1 flows in the two Atlassian-consuming skills).

## Impact

- `skills/product-discovery/SKILL.md` — Step 1 and Step 2 rewritten; Steps 3–6 unchanged
- `skills/outcome-review/SKILL.md` — Step 6 rewritten; Steps 1–5 and Step 7 unchanged
- `config/default-triggers.json` — `atlassian` capability + two trigger hints updated
- `config/fallback-registry.json` — `atlassian` capability + two trigger hints updated
- `commands/setup.md` — new Step 7 inserted; old Step 7 → Step 8, old Step 8 → Step 9; Execution footer (`steps 5, 6, 7, and 9`) updated to reflect renumbering
- `hooks/session-start-hook.sh` — MCP-plugins comment block updated (no logic change)
- `hooks/skill-activation-hook.sh` — DISCOVER and LEARN RED_FLAGS strings updated; backtick→single-quote fix in DISCOVER line
- `tests/test-routing.sh` — `atlassian-jira` inline fixture hint aligned with new copy
- `README.md` — Atlassian section reworded with Rovo branding + endpoint + walkthrough mention
- `CHANGELOG.md` — `[Unreleased]` accumulator entry under `### Changed`

No hook routing logic changes. No new files outside this change folder and `docs/plans/`. No `CONTEXT_CAPS` additions. Users without the Atlassian Rovo MCP connected see no behavioural change.
