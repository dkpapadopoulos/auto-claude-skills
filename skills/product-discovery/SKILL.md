---
name: product-discovery
description: Use when starting a new feature or initiative and you need problem context, prior art, and acceptance criteria before design — the DISCOVER phase entry point — pulling Jira/Confluence context and synthesizing a discovery brief to validate problem framing
---

# Product Discovery

Synthesize a discovery brief from Jira tickets, Confluence docs, and conversation context. Present the brief for user validation before transitioning to design.

## Step 1: Detect Available Tools

Check which MCP tools are available:

**Tier 1 — Atlassian Rovo MCP:**
If you have access to `search` (Rovo cross-system search), `searchJiraIssuesUsingJql`, `getJiraIssue`, `searchConfluenceUsingCql`, or `getConfluencePage` as MCP tools, use Tier 1. This is the same managed integration whether the user connected it as "Atlassian" or "Atlassian Rovo MCP" — they share endpoint `https://mcp.atlassian.com/v1/mcp/authv2` (legacy `/v1/mcp` deprecated after 2026-06-30).

**Tier 2 — Manual Context:**
If no Atlassian Rovo MCP tools are available, ask the user to provide context directly:
> "I don't have Atlassian Rovo MCP access. Please share any of the following:
> - Jira ticket IDs or URLs for the work you're considering
> - Problem statements or user pain points
> - Acceptance criteria or success metrics
> - Links to relevant Confluence docs or ADRs"

## Step 2: Gather Context

**Tier 1 (Atlassian Rovo MCP available):**

1. Ask the user what area, project, or problem they want to explore.
2. **Scope across both systems first** — call `search(cloudId, query)`. This Rovo cross-system call returns Jira issues + Confluence pages ranked in a single response. Use `cloudId` from project CLAUDE.md if present; otherwise call `getAccessibleAtlassianResources` once.
3. **Deep-read top hits** — for the most relevant returned items, call `getJiraIssue` (for `jira_issue` results) or `getConfluencePage` (for `confluence_page` results) to pull full content.
4. **Refine only on miss** — if the cross-system scope missed relevant work, fall back to targeted queries:
   - `searchJiraIssuesUsingJql` with project, status, priority, labels (`maxResults: 10`)
   - `searchConfluenceUsingCql` for design docs, ADRs, prior decisions (`limit: 10`)
5. Note any linked issues, parent epics, or blocked dependencies.

**Tier 2 (Manual):**

1. Ask the user to describe the problem space.
2. Ask for any existing ticket IDs, doc links, or context.
3. Synthesize from what the user provides.

## Step 3: Synthesize Discovery Brief

Present a structured brief covering:

### Discovery Brief

**Problem Statement:** What user pain point or business need are we addressing?

**Prior Art:** What has been tried before? What related work exists? (from Jira history, Confluence docs)

**Acceptance Criteria:** What does success look like? (from Jira tickets or user input)

**Constraints:** Known limitations — timeline, dependencies, technical constraints

**Hypotheses:**

### H1: [description]
We believe [intervention] will [outcome].
- **Metric:** [specific metric name or event, e.g., "checkout_completion_rate"]
- **Baseline:** [current value or "unknown" — can be refined during DESIGN/PLAN]
- **Target:** [directional — "increase", "decrease >20%", or specific threshold]
- **Window:** [validation timeframe — "2 weeks post-ship", "next sprint"]

Add H2, H3, etc. for additional hypotheses. All structured fields are nullable at discovery time.

**Open Questions:** What needs to be answered before design can begin?

## Step 4: User Validation

Present the brief and ask:
> "Does this discovery brief capture the problem accurately? Should I adjust anything before we move to design?"

Wait for user confirmation. If they request changes, revise and re-present.

## Step 5: Persist Discovery State

After the user approves the brief — this is mandatory. The LEARN-phase `outcome-review` skill reads a baseline written at SHIP time, which in turn depends on `discovery_path` and `hypotheses` being present in session state.

1. **Write the brief** to `docs/plans/YYYY-MM-DD-<slug>-discovery.md` using the Write tool. Derive `<slug>` as kebab-case from the primary feature name.

2. **Read the session token:**
   ```bash
   TOKEN="$(cat ~/.claude/.skill-session-token 2>/dev/null)"
   ```

3. **Source the state helpers** from the auto-claude-skills plugin root (typically `$CLAUDE_PLUGIN_ROOT/hooks/lib/openspec-state.sh`):
   ```bash
   . "$CLAUDE_PLUGIN_ROOT/hooks/lib/openspec-state.sh"
   ```

4. **Persist the discovery path:**
   ```bash
   openspec_state_set_discovery_path "$TOKEN" "<slug>" "docs/plans/YYYY-MM-DD-<slug>-discovery.md"
   ```

5. **Persist structured hypotheses** as a JSON array. Each H<N> from Step 3 becomes one object:
   ```bash
   HYPS='[{"id":"H1","description":"We believe ...","metric":"checkout_completion_rate","baseline":"0.12","target":"increase >20%","window":"2 weeks post-ship"}]'
   openspec_state_set_hypotheses "$TOKEN" "<slug>" "$HYPS"
   ```
   Use `null` for fields unknown at discovery time. Keep them as JSON literals — the helper validates the shape.

If any helper call fails (missing token, jq unavailable), note it in chat but continue to Step 6. The loop degrades gracefully; the session still produces a valid discovery artifact.

## Step 6: Transition to Design

Once discovery state is persisted:

> "Discovery complete. Invoke Skill(superpowers:brainstorming) to begin design."

This is a hard transition. Do not begin design work within the discovery skill.