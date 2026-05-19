## ADDED Requirements

### Requirement: Atlassian capability advertises Rovo cross-system search

The routing capability registry SHALL list the Rovo cross-system `search` tool as a member of the `atlassian` capability's `mcp_tools` array, ordered before the targeted Jira and Confluence query tools. The capability description SHALL identify the integration as "Atlassian Rovo MCP", name the recommended endpoint `https://mcp.atlassian.com/v1/mcp/authv2`, note the legacy `/v1/mcp` deprecation date (2026-06-30), and acknowledge Compass scope. The `mcp_tools` array MUST be identical in `config/default-triggers.json` and `config/fallback-registry.json` so the session-start hook's regeneration pass (from `default-triggers.json` to `fallback-registry.json`) does not produce a working-tree diff.

#### Scenario: Rovo `search` listed first in atlassian mcp_tools

- **GIVEN** the canonical routing fallback registry
- **WHEN** the JSON path `.plugins[] | select(.name == "atlassian") | .provides.mcp_tools` is evaluated against `config/default-triggers.json`
- **THEN** the first element of the resulting array is `"search"`
- **AND** the array contains `"searchJiraIssuesUsingJql"`, `"searchConfluenceUsingCql"`, `"getJiraIssue"`, `"getConfluencePage"`, `"createJiraIssue"`, and `"addCommentToJiraIssue"`

#### Scenario: Capability description names Atlassian Rovo MCP and the recommended endpoint

- **GIVEN** the canonical routing fallback registry
- **WHEN** the JSON path `.plugins[] | select(.name == "atlassian") | .description` is read
- **THEN** the value contains the literal substring `Atlassian Rovo MCP`
- **AND** the value contains the literal substring `https://mcp.atlassian.com/v1/mcp/authv2`
- **AND** the value contains the literal substring `2026-06-30`
- **AND** the value contains the literal substring `Compass`

#### Scenario: default-triggers and fallback-registry stay in sync under regeneration

- **GIVEN** a clean working tree and the session-start hook source
- **WHEN** the session-start hook executes with `CLAUDE_PLUGIN_ROOT` set to the project root and `_SKILL_TEST_MODE` unset
- **THEN** `git status --short config/fallback-registry.json` produces no output (the regenerated content matches the committed file)

### Requirement: Atlassian routing hints prefer Rovo cross-system search

The `atlassian-jira` and `atlassian-confluence` trigger objects in both `config/default-triggers.json` and `config/fallback-registry.json` SHALL emit `hint` strings that lead with `ATLASSIAN ROVO:` and direct the model to prefer `search(cloudId, query)` for cross-system discovery before targeted JQL / CQL queries. The hints SHALL mention `maxResults: 10` (for Jira) and `limit: 10` (for Confluence) per Atlassian's official client-configuration guidance.

#### Scenario: Jira hint leads with Rovo `search` directive

- **GIVEN** the canonical routing fallback registry
- **WHEN** the `hint` value on the `atlassian-jira` trigger is read
- **THEN** the value starts with the literal prefix `ATLASSIAN ROVO:`
- **AND** the value contains the literal substring `search(cloudId, query)`
- **AND** the value contains the literal substring `maxResults: 10`

#### Scenario: Confluence hint leads with Rovo `search` directive

- **GIVEN** the canonical routing fallback registry
- **WHEN** the `hint` value on the `atlassian-confluence` trigger is read
- **THEN** the value starts with the literal prefix `ATLASSIAN ROVO:`
- **AND** the value contains the literal substring `search(cloudId, query)`
- **AND** the value contains the literal substring `limit: 10`

#### Scenario: Test fixture matches canonical hint copy

- **GIVEN** the inline `atlassian-jira` fixture in `tests/test-routing.sh`
- **WHEN** the `hint` field of that fixture is read
- **THEN** the value equals the canonical `atlassian-jira` hint copy from `config/fallback-registry.json`

### Requirement: Tier 1 skill flows prefer Rovo cross-system search

The `product-discovery` and `outcome-review` skill files SHALL describe a Tier 1 flow that calls the Rovo cross-system `search` tool first when the Atlassian Rovo MCP is available, then deep-reads top hits with `getJiraIssue` or `getConfluencePage`, and only falls back to targeted `searchJiraIssuesUsingJql` / `searchConfluenceUsingCql` queries when the cross-system scope misses relevant work. Both skill files SHALL refer to the integration as "Atlassian Rovo MCP" in user-facing prose.

#### Scenario: product-discovery names Rovo `search` as the first call

- **GIVEN** `skills/product-discovery/SKILL.md`
- **WHEN** the Step 2 "Tier 1 (Atlassian Rovo MCP available)" subsection is read
- **THEN** the first numbered tool call is `search(cloudId, query)`
- **AND** subsequent steps reference `getJiraIssue`, `getConfluencePage`, `searchJiraIssuesUsingJql`, and `searchConfluenceUsingCql` in that fallback order

#### Scenario: outcome-review uses Rovo `search` to find original ticket

- **GIVEN** `skills/outcome-review/SKILL.md`
- **WHEN** the Step 6 "If 'Create follow-up tickets' (and Atlassian Rovo MCP available)" subsection is read
- **THEN** the first numbered step calls `search(cloudId, "<feature name>")`
- **AND** `searchJiraIssuesUsingJql` is documented as the fallback only when `search` returns no matches

### Requirement: /setup walks the user through Atlassian Rovo MCP

The `/setup` slash-command body (`commands/setup.md`) SHALL include a numbered section that detects an existing Atlassian Rovo MCP connection via `claude mcp list 2>/dev/null | grep -iE 'atlassian|rovo'` and branches into three cases: not connected (offer to connect via `/mcp` at `https://mcp.atlassian.com/v1/mcp/authv2`), connected at the legacy `/v1/mcp` URL (offer URL upgrade with the 2026-06-30 deprecation note), and connected at any URL (offer a copy-paste defaults block for project CLAUDE.md). The walkthrough MUST NOT write to project CLAUDE.md autonomously and MUST gate every branch on explicit user consent.

#### Scenario: Setup section detects existing connection via `claude mcp list`

- **GIVEN** `commands/setup.md`
- **WHEN** the "Atlassian Rovo MCP" section is read
- **THEN** the section contains the literal command `claude mcp list 2>/dev/null | grep -iE 'atlassian|rovo'`

#### Scenario: Setup section names the recommended endpoint and the deprecation date

- **GIVEN** `commands/setup.md`
- **WHEN** the "Atlassian Rovo MCP" section is read
- **THEN** the section contains the literal substring `https://mcp.atlassian.com/v1/mcp/authv2`
- **AND** the section contains the literal substring `2026-06-30`

#### Scenario: Defaults block is offered as copy-paste, not written autonomously

- **GIVEN** `commands/setup.md`
- **WHEN** the "Atlassian Rovo MCP" section's Case C branch is read
- **THEN** the section contains the literal directive `Do NOT write to project CLAUDE.md autonomously — present as copy-paste only.`
- **AND** the defaults block includes lines for `cloudId`, `Default Jira project key`, `Default Confluence spaceId`, `maxResults: 10`, `limit: 10`, and the `search(cloudId, query)` preference

#### Scenario: Step numbering is consistent after insertion

- **GIVEN** `commands/setup.md`
- **WHEN** every `### N. <heading>` line is enumerated in source order
- **THEN** the leading integers form the unbroken sequence 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 with no duplicates

### Requirement: DISCOVER and LEARN RED_FLAGS reference Atlassian Rovo MCP without shell-substitution traps

The `RED_FLAGS` strings emitted by `hooks/skill-activation-hook.sh` for the `DISCOVER` and `LEARN` phases SHALL name the integration as "Atlassian Rovo MCP" and SHALL NOT contain any character that triggers Bash command substitution when the variable is assigned inside double quotes (no literal backticks; no unescaped `$(...)`; no unescaped `$<name>` outside of an intended substitution).

#### Scenario: DISCOVER RED_FLAGS names Atlassian Rovo MCP and renders the word "search" at runtime

- **GIVEN** the `hooks/skill-activation-hook.sh` source
- **WHEN** the `DISCOVER` case branch of the `RED_FLAGS` assignment is read
- **THEN** the string contains the substring `Atlassian Rovo MCP is connected`
- **AND** the string contains the substring `'search'` (single-quoted, literal)
- **AND** the string does NOT contain literal backticks around tool names

#### Scenario: LEARN RED_FLAGS names Atlassian Rovo MCP

- **GIVEN** the `hooks/skill-activation-hook.sh` source
- **WHEN** the `LEARN` case branch of the `RED_FLAGS` assignment is read
- **THEN** the string contains the substring `via Atlassian Rovo MCP without user approval`
