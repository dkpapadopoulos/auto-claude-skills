# Atlassian Rovo MCP Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the plugin's Atlassian integration to use Rovo cross-system `search` first, walk users through connecting Atlassian Rovo MCP via `/setup`, and update terminology + endpoint guidance throughout.

**Architecture:** Doc + config edits across 2 skills, 2 routing configs, 1 command, 1 test fixture, README, hook comment blocks, and CHANGELOG. No hook routing logic changes; no new files; no `CONTEXT_CAPS` additions. Reversible via single `git revert`.

**Tech Stack:** Bash 3.2 hooks, JSON routing config (jq-validated), Markdown skill/command files.

**Design doc:** `docs/plans/2026-05-19-rovo-mcp-integration-design.md`

---

## File Structure

| File | Purpose | Action |
|---|---|---|
| `skills/product-discovery/SKILL.md` | DISCOVER skill | Tier 1 rewrite — search-first |
| `skills/outcome-review/SKILL.md` | LEARN skill | Tier 1 rewrite — search-first; refresh follow-up section terminology |
| `config/fallback-registry.json` | Routing fallback | Add `search` to atlassian tools; update hints + description |
| `config/default-triggers.json` | Routing triggers | Update `atlassian-jira` + `atlassian-confluence` hint copy |
| `tests/test-routing.sh` | Routing test fixtures | Update inline hint text for `atlassian-jira` |
| `commands/setup.md` | /setup walkthrough | Insert new "Atlassian Rovo MCP" step (numbered after Context Stack) |
| `README.md` | Public docs | Terminology refresh, Compass mention, endpoint note |
| `hooks/session-start-hook.sh` | MCP plugins comment block | Update Atlassian comment lines (no logic change) |
| `hooks/skill-activation-hook.sh` | RED_FLAGS text | Update DISCOVER + LEARN red-flag wording |
| `CHANGELOG.md` | Release notes | `[Unreleased]` accumulator entries |

---

## Task 1: Update product-discovery skill — search-first Tier 1

**Files:**
- Modify: `skills/product-discovery/SKILL.md` (lines 10-43 region)

- [ ] **Step 1: Replace Step 1 + Step 2 sections to lead with Rovo search**

In `skills/product-discovery/SKILL.md`, replace lines 10-43 (the "Step 1: Detect Available Tools" and "Step 2: Gather Context" sections through the end of the Tier 2 Manual block) with:

````markdown
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
````

- [ ] **Step 2: Verify the file still parses as Markdown**

Run: `bash -n /dev/null; grep -c '^## Step' skills/product-discovery/SKILL.md`
Expected: at least `6` (Steps 1-6 still present; the renumber-stable change only edits Step 1 and Step 2 content).

- [ ] **Step 3: Commit**

```bash
git add skills/product-discovery/SKILL.md
git commit -m "feat: product-discovery prefers Rovo cross-system search first"
```

---

## Task 2: Update outcome-review skill — search-first + terminology

**Files:**
- Modify: `skills/outcome-review/SKILL.md` (lines 103-114 region)

- [ ] **Step 1: Replace Step 6 follow-up actions section**

In `skills/outcome-review/SKILL.md`, replace lines 103-114 (the "## Step 6: Follow-Up Actions" section through the end of the "Atlassian MCP unavailable" block) with:

````markdown
## Step 6: Follow-Up Actions

**If "Create follow-up tickets" (and Atlassian Rovo MCP available):**

1. If the baseline lacks `jira_ticket` or the feature's parent ticket is unknown, find it first: call `search(cloudId, "<feature name>")` — the Rovo cross-system search returns the original ticket alongside any linked Confluence docs in one call. Fall back to `searchJiraIssuesUsingJql` only if `search` returns no matches.
2. Draft the ticket(s) — title, description, acceptance criteria, priority.
3. Present each draft to the user for approval.
4. Only after explicit approval: `createJiraIssue` to create the ticket.
5. `addCommentToJiraIssue` on the original ticket with the outcome summary.

**If Atlassian Rovo MCP unavailable:**
> "I don't have Atlassian Rovo MCP access. Here are the recommended follow-up tickets — please create them manually:
> [formatted ticket descriptions]"
````

- [ ] **Step 2: Verify the file still parses**

Run: `grep -c '^## Step' skills/outcome-review/SKILL.md`
Expected: `7` (Steps 1-7 intact).

- [ ] **Step 3: Commit**

```bash
git add skills/outcome-review/SKILL.md
git commit -m "feat: outcome-review uses Rovo search to find original ticket"
```

---

## Task 3: Update routing config — atlassian capability + hints

**Files:**
- Modify: `config/fallback-registry.json` (lines 901-925, 1372-1395)
- Modify: `config/default-triggers.json` (lines 721-744)

- [ ] **Step 1: Update `atlassian` capability in `config/fallback-registry.json`**

Replace lines 901-925 (the `atlassian` capability object) with:

```json
    {
      "name": "atlassian",
      "source": "claude-ai-managed",
      "provides": {
        "commands": [],
        "skills": [],
        "agents": [],
        "hooks": [],
        "mcp_tools": [
          "search",
          "searchJiraIssuesUsingJql",
          "getJiraIssue",
          "getConfluencePage",
          "searchConfluenceUsingCql",
          "createJiraIssue",
          "addCommentToJiraIssue"
        ]
      },
      "phase_fit": [
        "DISCOVER",
        "DESIGN",
        "PLAN",
        "REVIEW",
        "LEARN"
      ],
      "description": "Atlassian Rovo MCP (Jira, Confluence, Compass) via claude.ai managed integration. Connect via /mcp at https://mcp.atlassian.com/v1/mcp/authv2 (legacy /v1/mcp deprecated after 2026-06-30). Exposes Rovo cross-system search plus targeted Jira/Confluence tools.",
      "available": false
    },
```

- [ ] **Step 2: Update `atlassian-jira` and `atlassian-confluence` hints in `config/fallback-registry.json`**

Replace the `hint` value on the `atlassian-jira` trigger (around line 1378) from:
```
"hint": "ATLASSIAN: If Jira MCP tools are available, pull acceptance criteria and linked context for relevant tickets. Reference any Jira context already discussed in this session.",
```
to:
```
"hint": "ATLASSIAN ROVO: If Atlassian Rovo MCP is connected, prefer `search(cloudId, query)` for cross-system discovery before targeted JQL. Pull acceptance criteria and linked context. Use `maxResults: 10`.",
```

Replace the `hint` value on the `atlassian-confluence` trigger (around line 1391) from:
```
"hint": "ATLASSIAN: If Confluence MCP tools are available, search for relevant design docs and references. Keep searches narrow by title or space.",
```
to:
```
"hint": "ATLASSIAN ROVO: If Atlassian Rovo MCP is connected, prefer `search(cloudId, query)` to scope across Jira+Confluence first; refine with CQL by title or space using `limit: 10`.",
```

- [ ] **Step 3: Mirror hint updates in `config/default-triggers.json`**

Apply the same two `hint` value replacements at the corresponding `atlassian-jira` (line 727) and `atlassian-confluence` (line 740) entries in `config/default-triggers.json`.

- [ ] **Step 4: Validate both JSON files**

Run:
```bash
jq '.' config/fallback-registry.json > /dev/null && echo "fallback-registry OK"
jq '.' config/default-triggers.json > /dev/null && echo "default-triggers OK"
```
Expected: both lines print OK.

- [ ] **Step 5: Run registry tests**

Run: `bash tests/test-registry.sh`
Expected: all assertions pass (the curated-plugin count of 11 includes `atlassian` — capability count is unchanged).

- [ ] **Step 6: Commit**

```bash
git add config/fallback-registry.json config/default-triggers.json
git commit -m "feat: routing config recognizes Rovo search and prefers it in hints"
```

---

## Task 4: Update routing test fixture for atlassian-jira hint

**Files:**
- Modify: `tests/test-routing.sh` (line 348)

- [ ] **Step 1: Update inline hint in test fixture**

In `tests/test-routing.sh`, replace line 348:
```
      "hint": "ATLASSIAN: If Atlassian MCP tools are available, use Jira (searchJiraIssuesUsingJql, getJiraIssue) to pull acceptance criteria.",
```
with:
```
      "hint": "ATLASSIAN ROVO: If Atlassian Rovo MCP is connected, prefer `search(cloudId, query)` for cross-system discovery before targeted JQL. Pull acceptance criteria and linked context. Use `maxResults: 10`.",
```

- [ ] **Step 2: Run routing tests**

Run: `bash tests/test-routing.sh`
Expected: all assertions pass.

- [ ] **Step 3: Commit**

```bash
git add tests/test-routing.sh
git commit -m "test: align atlassian-jira routing fixture with Rovo hint copy"
```

---

## Task 5: Add `/setup` walkthrough step for Atlassian Rovo MCP

**Files:**
- Modify: `commands/setup.md` (insert new section after current Context Stack step, before Optional Hooks if present, or at logical end of MCP-related steps)

- [ ] **Step 1: Locate insertion point**

Run:
```bash
grep -n "^### " commands/setup.md
```
Identify the heading that comes AFTER the Context Stack section (Step 6). The Rovo step will be inserted as the next-numbered step (renumber subsequent sections in Step 2 of this task).

- [ ] **Step 2: Insert new section**

Insert the following new section directly after the Context Stack section (Step 6 in current `commands/setup.md`), as the next sequentially-numbered step. **Renumber all subsequent sections by +1**:

````markdown
### 7. Atlassian Rovo MCP (Jira / Confluence / Compass)

The Atlassian Rovo MCP is a claude.ai-managed integration — no marketplace install. It exposes Jira, Confluence, and Compass via one connection, plus a `search` tool that queries Jira + Confluence simultaneously. `product-discovery` and `outcome-review` skills use it when connected.

**Detection:**

```bash
claude mcp list 2>/dev/null | grep -iE 'atlassian|rovo'
```

**Case A — Not connected (no output):**

Ask the user: "Would you like to connect Atlassian Rovo MCP? It provides Jira, Confluence, and Compass access via OAuth, plus a Rovo cross-system `search` tool that lets `product-discovery` find context in one call instead of two."

If yes, instruct them:
> 1. Run `/mcp` in Claude Code.
> 2. Add a new server with URL `https://mcp.atlassian.com/v1/mcp/authv2`.
> 3. Complete the OAuth flow in your browser.
> 4. Re-run `/setup` and we'll continue from here.

If the user declines, note that `product-discovery` and `outcome-review` skills will fall back to Tier 2 (manual context).

**Case B — Connected at legacy `/v1/mcp` URL:**

Detect with:
```bash
claude mcp list 2>/dev/null | grep -E 'atlassian|rovo' | grep -E 'v1/mcp($|[^/])'
```

If matched, inform the user:
> "Atlassian is deprecating the `/v1/mcp` endpoint after 2026-06-30. The recommended URL is `https://mcp.atlassian.com/v1/mcp/authv2`. Would you like to update your `/mcp` config now? (Re-run `/mcp`, remove the existing entry, add the new URL.)"

If the user declines, leave it — it still works until the deprecation date.

**Case C — Connected (any version):**

Offer the defaults block for project CLAUDE.md:

> "Atlassian's official guidance is to declare cloudId and default project/space in your project CLAUDE.md to skip discovery calls and bound search-result sizes. Would you like me to show you the block to paste in?"

If yes, present:

````markdown
## Atlassian Rovo MCP

When connected:
- cloudId = "https://<your-site>.atlassian.net"
- Default Jira project key = "<KEY>"
- Default Confluence spaceId = "<ID>"
- Use `maxResults: 10` / `limit: 10` for ALL Jira JQL and Confluence CQL searches
- Prefer `search(cloudId, query)` for cross-system discovery; refine with JQL/CQL only on miss
````

Do NOT write to project CLAUDE.md autonomously — present as copy-paste only.
````

- [ ] **Step 3: Renumber subsequent sections**

After the insertion in Step 2, every `### N. <heading>` that previously had `N > 6` should be incremented by 1. Verify with:
```bash
grep -nE "^### [0-9]+\." commands/setup.md
```
Confirm the sequence is unbroken (1, 2, 3, …, no gaps and no duplicates).

- [ ] **Step 4: Commit**

```bash
git add commands/setup.md
git commit -m "feat(setup): add Atlassian Rovo MCP walkthrough step"
```

---

## Task 6: Terminology refresh — README, hooks, RED_FLAGS

**Files:**
- Modify: `README.md` (line 152, and any other Atlassian mentions)
- Modify: `hooks/session-start-hook.sh` (lines 1038-1040 comment block)
- Modify: `hooks/skill-activation-hook.sh` (lines 1334, 1374 — RED_FLAGS strings)

- [ ] **Step 1: Update `README.md` line 152**

Replace the current line 152:
```
**Atlassian managed integration** — Jira and Confluence connect via `/mcp` as a claude.ai managed MCP, not through `/setup`.
```
with:
```
**Atlassian Rovo MCP** (formerly Atlassian MCP) — Jira, Confluence, and Compass connect via `/mcp` as a claude.ai managed integration at `https://mcp.atlassian.com/v1/mcp/authv2`. `/setup` includes a walkthrough that detects existing connections, warns on the legacy `/v1/mcp` endpoint (deprecated after 2026-06-30), and offers a copy-paste defaults block. Skills prefer the Rovo cross-system `search` tool for unified Jira+Confluence discovery.
```

- [ ] **Step 2: Update `hooks/session-start-hook.sh` comment block (lines 1038-1040)**

Replace:
```bash
# MCP plugins (SDLC data sources — live docs, GitHub, Atlassian)
# Note: Atlassian may be available as a claude.ai managed integration
# (mcp__claude_ai_Atlassian__) without a marketplace install.
```
with:
```bash
# MCP plugins (SDLC data sources — live docs, GitHub, Atlassian Rovo)
# Note: Atlassian Rovo MCP (Jira/Confluence/Compass) is a claude.ai managed
# integration at https://mcp.atlassian.com/v1/mcp/authv2. Tools appear under
# the mcp__atlassian__ prefix (server name set by the user's /mcp config).
```

- [ ] **Step 3: Update RED_FLAGS in `hooks/skill-activation-hook.sh`**

Replace line 1334:
```
- Skipping Jira/Confluence context pull when Atlassian MCP is available
```
with:
```
- Skipping Jira/Confluence context pull when Atlassian Rovo MCP is connected (prefer `search` for cross-system scoping)
```

Replace line 1374:
```
- Creating Jira follow-up tickets without user approval
```
with:
```
- Creating Jira follow-up tickets via Atlassian Rovo MCP without user approval
```

- [ ] **Step 4: Syntax-check both hooks**

Run:
```bash
bash -n hooks/session-start-hook.sh && echo "session-start OK"
bash -n hooks/skill-activation-hook.sh && echo "activation OK"
```
Expected: both print OK.

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: all assertions pass. If any test asserts on the old Atlassian wording (none expected from the grep audit, but verify), surface the failure and update the fixture.

- [ ] **Step 6: Commit**

```bash
git add README.md hooks/session-start-hook.sh hooks/skill-activation-hook.sh
git commit -m "docs: refresh terminology to Atlassian Rovo MCP throughout"
```

---

## Task 7: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md` (add to `[Unreleased]` section)

- [ ] **Step 1: Append entries under `[Unreleased]` → `### Changed`**

Insert the following bullet at the top of the `### Changed` list under `## [Unreleased]`:

```markdown
- Atlassian integration refreshed to Atlassian Rovo MCP. `product-discovery` and `outcome-review` Tier 1 flows now prefer the Rovo cross-system `search(cloudId, query)` tool to scope Jira+Confluence in one call before falling back to targeted `searchJiraIssuesUsingJql` / `searchConfluenceUsingCql` queries. Routing config (`config/default-triggers.json`, `config/fallback-registry.json`) updates the `atlassian` capability tool list to include `search`, refreshes hint copy on `atlassian-jira` and `atlassian-confluence` triggers, and updates the capability description to note the recommended endpoint `https://mcp.atlassian.com/v1/mcp/authv2` (legacy `/v1/mcp` deprecated after 2026-06-30) and Compass scope. `commands/setup.md` gains a new "Atlassian Rovo MCP" walkthrough step that detects an existing `/mcp` connection, warns on legacy URLs, and offers a copy-paste defaults block (cloudId, project key, spaceId, `maxResults: 10`) per Atlassian's official client guidance. README, hook comment blocks, and DISCOVER/LEARN RED_FLAGS reword "Atlassian MCP" → "Atlassian Rovo MCP" with one continuity hint on first README mention. No hook routing logic changed; no `CONTEXT_CAPS` additions; users without the connection see no behavioral change. Capability: `skill-routing`.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog entry for Atlassian Rovo MCP integration refresh"
```

---

## Task 8: Final verification

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: all suites pass.

- [ ] **Step 2: Verify routing emits new hint text on relevant prompts**

Run:
```bash
SKILL_EXPLAIN=1 echo '{"prompt":"pull jira ticket ABC-123 acceptance criteria"}' | \
  bash hooks/skill-activation-hook.sh 2>&1 | \
  grep -E "ATLASSIAN ROVO|search\(cloudId" || echo "MISS — hint not surfaced"
```
Expected: the new hint text appears (or the activation hook surfaces "ATLASSIAN ROVO" somewhere in the output). If the activation hook's invocation contract requires a different stdin shape, follow the in-file convention used by existing manual tests in the repo.

- [ ] **Step 3: Confirm no stale "Atlassian MCP" without "Rovo" remains in user-facing copy**

Run:
```bash
grep -rn "Atlassian MCP" --include="*.md" --include="*.sh" --include="*.json" \
  hooks/ skills/ commands/ config/ README.md CHANGELOG.md 2>/dev/null \
  | grep -v "Atlassian Rovo MCP" \
  | grep -v "docs/plans/" \
  | grep -v "(formerly Atlassian MCP)" \
  || echo "All references use new terminology"
```
Expected: prints "All references use new terminology" (the one allowed exception is the inline `(formerly Atlassian MCP)` continuity hint in README).

- [ ] **Step 4: Commit any cleanups discovered in Steps 2-3**

If Step 2 or Step 3 surfaces a missed reference, fix it and commit:

```bash
git add <files>
git commit -m "docs: clean up stale Atlassian MCP reference"
```

---

## Self-Review Checklist

- **Spec coverage:** Tasks 1-7 cover all sections in the design doc (product-discovery rewrite ✓, outcome-review rewrite ✓, routing config ✓, /setup walkthrough ✓, terminology refresh ✓, CHANGELOG ✓). Task 8 covers the testing requirement.
- **Placeholders:** All template tokens (`<your-site>`, `<KEY>`, `<ID>`) are intentional user-facing placeholders in the copy-paste defaults block, not plan gaps.
- **Type consistency:** Tool name `search` (Rovo cross-system) is used identically in Tasks 1, 2, 3 hint copy, README, and CHANGELOG. `maxResults: 10` / `limit: 10` numerics are consistent. Endpoint URL `https://mcp.atlassian.com/v1/mcp/authv2` is identical across all references. Capability tag `skill-routing` matches the canonical capability used elsewhere in the CHANGELOG.

---

## Risk / Rollback

- All changes are documentation- and config-shaped. No hook routing logic touched. No new files. No deletions of existing functionality.
- Rollback: `git revert` of the merged PR returns all files to pre-change state.
- No persistent user-system state changes (no writes to user CLAUDE.md, no MCP config edits).
- /setup additions are user-prompt-gated at each branch.
