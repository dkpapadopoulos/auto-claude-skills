## ADDED Requirements

### Requirement: Forgetful three-step API ordering in banner

The session-start banner SHALL name the Forgetful Memory MCP API in the explicit order `mcp__forgetful__discover_forgetful_tools` (no args, entry point) → `mcp__forgetful__execute_forgetful_tool` (per-call read/write) → `mcp__forgetful__how_to_use_forgetful_tool(tool_name)` (per-operation docs when needed) whenever `forgetful_memory=true`. The banner SHALL include the phase anchors `DESIGN/PLAN/IMPLEMENT/DEBUG/REVIEW` (read) and `SHIP` (write).

#### Scenario: Session starts with Forgetful MCP configured

- **GIVEN** `~/.claude.json` registers a `forgetful` MCP server
- **WHEN** the session-start hook fires
- **THEN** the emitted context contains a `Forgetful:` line naming `discover_forgetful_tools` first, then `execute_forgetful_tool`, then `how_to_use_forgetful_tool` in that order
- **AND** the line contains the phrase `DESIGN/PLAN/IMPLEMENT/DEBUG/REVIEW`
- **AND** the line contains the phrase `store after SHIP`

#### Scenario: Session starts without Forgetful MCP configured

- **GIVEN** `~/.claude.json` does not register a `forgetful` MCP server
- **WHEN** the session-start hook fires
- **THEN** no `Forgetful:` line is emitted in the session context

### Requirement: Forgetful connection probe capability flag

The plugin SHALL expose a `forgetful_connected` boolean context-capability key parallel to `serena_connected`. The flag MUST default to `false`. When the environment variable `FORGETFUL_CONNECTION_CHECK=1` is set AND the `claude` CLI is on `PATH`, the session-start hook SHALL parse `claude mcp list` output and set `forgetful_connected=true` only when the `forgetful:` entry contains the `✓ Connected` marker. The probe MUST fail open: any error (missing binary, jq failure, malformed output) leaves `forgetful_connected=false` and does not abort the hook.

#### Scenario: Probe disabled by default

- **GIVEN** `FORGETFUL_CONNECTION_CHECK` is unset
- **AND** `~/.claude.json` registers a `forgetful` MCP server
- **WHEN** the session-start hook fires
- **THEN** the cached `context_capabilities.forgetful_memory` is `true`
- **AND** the cached `context_capabilities.forgetful_connected` is `false`

#### Scenario: `forgetful_connected` present in canonical key list

- **GIVEN** the session-start hook source
- **WHEN** `_CANONICAL_CAP_KEYS` is parsed
- **THEN** the key `forgetful_connected` is present alongside `serena_connected`

#### Scenario: Probe fails open on missing `claude` binary

- **GIVEN** `FORGETFUL_CONNECTION_CHECK=1` is set
- **AND** the `claude` binary is not on `PATH`
- **WHEN** the session-start hook fires
- **THEN** the hook completes with exit code 0
- **AND** `context_capabilities.forgetful_connected` remains `false`

### Requirement: Memory backend boundary documented

The plugin SHALL document the boundary between Forgetful Memory MCP (cross-session architectural memory) and Claude Code auto-memory (per-project conversation memory) in both `skills/unified-context-stack/tiers/historical-truth.md` and `CLAUDE.md`. The documentation MUST state a no-dual-write policy: callers pick one backend per learning based on cross-project versus project-local scope.

#### Scenario: Boundary section present in tier doc

- **GIVEN** a developer reads `skills/unified-context-stack/tiers/historical-truth.md`
- **WHEN** they search for guidance on memory write target
- **THEN** they find a heading or section named "Memory backend boundary"
- **AND** the section names both Forgetful (cross-session) and Claude Code auto-memory (per-project) with their distinct scopes

#### Scenario: Boundary note present in CLAUDE.md Gotchas

- **GIVEN** a developer reads the Gotchas section of `CLAUDE.md`
- **WHEN** they search for memory-backend guidance
- **THEN** they find a bullet referencing both backends and the no-dual-write policy
