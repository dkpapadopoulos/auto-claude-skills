# Design: Atlassian Rovo MCP Integration

## Architecture

Pure documentation + routing-config change. No new hook logic. Two layers touched:

**Skill layer (`skills/<name>/SKILL.md`).** `product-discovery` and `outcome-review` are tiered skills with a Tier 1 (MCP-available) and Tier 2 (manual) flow. The Tier 1 sections of both now lead with a single Rovo `search(cloudId, query)` call before falling back to targeted `searchJiraIssuesUsingJql` / `searchConfluenceUsingCql` queries. The control flow in the skill is unchanged — the same tool calls happen, but the *first* tool is the Rovo cross-system one. Skills are LLM-readable markdown; no code generation.

**Routing layer (`config/{default-triggers,fallback-registry}.json`).** The plugin maintains a small declarative routing config: trigger regexes with `hint` strings emitted into the SessionStart and UserPromptSubmit hooks, and a capability registry naming each MCP server's exposed tools and a description. Two pieces changed:
1. The `atlassian` capability's `mcp_tools` list adds `search` as its first element; the capability `description` is rewritten to name Atlassian Rovo MCP, the `/v1/mcp/authv2` endpoint, the 2026-06-30 legacy deprecation, and Compass scope.
2. The `atlassian-jira` and `atlassian-confluence` trigger `hint` strings lead with the directive "if Atlassian Rovo MCP is connected, prefer `search(cloudId, query)` for cross-system discovery before targeted JQL/CQL queries".

**Source-of-truth coupling.** `config/default-triggers.json` is canonical; the session-start hook regenerates `config/fallback-registry.json` from it (excluding user-config and auto-discovered plugins) so that the no-jq fallback path has a structurally valid registry. Any change to a capability or trigger MUST be applied to both files; updating only fallback-registry causes subsequent hook invocations to revert the working tree. This was caught during implementation (initial pass missed `default-triggers.json` for the capability block; fix in commit `cc3a0c7`).

**Walkthrough layer (`commands/setup.md`).** A new numbered step (Step 7 "Atlassian Rovo MCP") was inserted between the existing Context Stack step and the Incident analysis step. The new step is Bash-detection-driven: `claude mcp list 2>/dev/null | grep -iE 'atlassian|rovo'` branches the flow into three cases (not connected / legacy URL / connected). The step is user-prompt-gated at each branch — it never writes to project CLAUDE.md autonomously; it offers a copy-paste defaults block instead. Inserting a step required renumbering subsequent sections and updating the Execution footer reference list (`steps 5, 6, 7, and 9`).

## Dependencies

No new external dependencies. The Atlassian Rovo MCP server is a claude.ai-managed integration users connect via Claude Code's built-in `/mcp` command — the plugin does not bundle or install it. `claude mcp list` (used by the new `/setup` step) is part of the Claude Code CLI and is already a prerequisite for other `/setup` steps.

## Decisions & Trade-offs

**Decision: Tier 1 prefers `search` first; JQL/CQL only on miss.**
Rejected: keep JQL/CQL as the default and treat `search` as opt-in. Rationale: Atlassian's official `skills/search-company-knowledge/SKILL.md` in the `atlassian-mcp-server` repository identifies `search` as the *primary* tool for information retrieval, with the targeted JQL/CQL tools as follow-ups. Aligning the plugin's Tier 1 flow with Atlassian's own guidance produces fewer tool calls per discovery session (one Rovo call vs two targeted calls when the user doesn't know which system holds the answer) and better recall across split Jira+Confluence content.

**Decision: `/setup` walkthrough as a passive offer, not an autonomous write.**
Rejected: have `/setup` auto-detect cloudId from `getAccessibleAtlassianResources` and write a defaults block to project CLAUDE.md without asking. Rationale: writing to a project's CLAUDE.md is a high-blast-radius action that can collide with the user's own conventions or existing Atlassian guidance in that file. Per `feedback_match_scope_to_fix_size` and the project's "prove observability before abstraction" stance, the walkthrough offers the block as copy-paste text and lets the user paste it into the right place.

**Decision: Terminology refresh with one continuity hint, not a hard cutover.**
Rejected: rewrite every "Atlassian MCP" reference cleanly without any continuity marker. Rationale: existing users have project CLAUDE.md and personal memory referring to "Atlassian MCP". A single inline `(formerly Atlassian MCP)` on the first README mention preserves searchability and signals that the name change is Atlassian's, not a different product. Historical CHANGELOG entries are intentionally left alone — they record factual release content from the time they were written.

**Decision: No bundled marketplace plugin install.**
Rejected: bundle the Atlassian Rovo MCP server config into the plugin's `/setup` step so users get it without running `/mcp` separately. Rationale: Atlassian distributes it as a claude.ai-managed integration with dynamic OAuth client registration. There is no marketplace plugin to install; bundling would mean inlining server config the plugin doesn't own. `/setup` instead points users at Claude Code's native `/mcp` flow.

**Decision: No `CONTEXT_CAPS` flag for Atlassian/Rovo presence.**
Rejected: add an `atlassian_connected` capability flag (parallel to `serena_connected` / `forgetful_connected`) that downstream skills can branch on. Rationale: no current skill branches on this flag — both `product-discovery` and `outcome-review` already do tier detection in-skill via tool-availability check. Adding a capability flag with no consumer is speculative scaffolding (`feedback_prove_observability_before_abstraction`). Revival trigger: a skill that needs to branch on Atlassian Rovo connectedness without invoking a tool.

**Decision: Compass mentioned, no Compass-specific skill or workflow.**
Rejected: add a discovery flow or routing trigger for Compass service-catalog queries. Rationale: no logged user need. Mentioning Compass in the capability description and `/setup` walkthrough costs one line and signals the connection's wider scope; building a Compass workflow without a use case is speculative.

## Implementation Notes (synced at ship time)

Rebased before push: the worktree was initially branched from `origin/main` at `cb967ba`, and `main` advanced by three commits during the development session (design doc, plan doc, and an unrelated `docs/CLAUDE.md` "Doc locations" addition). Final reviewer flagged this as a critical issue; rebased cleanly with no conflicts before completing the SHIP phase.
