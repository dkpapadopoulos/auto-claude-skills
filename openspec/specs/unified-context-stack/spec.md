# Unified Context Stack

## Purpose

Tiered context retrieval across External, Internal, Historical, and Intent Truth. Phase-specific guidance chooses the highest available source per tier and degrades gracefully — falling through to Grep, CLAUDE.md, or web search — when a tier's tool is unavailable.
## Requirements
### Requirement: Design phase context retrieval
The unified-context-stack SHALL provide a phase document for the DESIGN phase that guides Intent Truth and Historical Truth retrieval before approaches are proposed during brainstorming.

#### Scenario: Existing spec found during brainstorming
Given a feature with an existing OpenSpec canonical spec at `openspec/specs/<capability>/spec.md`
When the DESIGN phase activates
Then the phase doc instructs the model to read the canonical spec and account for existing requirements in proposed approaches

#### Scenario: Past decisions found during brainstorming
Given Forgetful Memory is available (`forgetful_memory=true`)
When the DESIGN phase activates
Then the phase doc instructs the model to query Forgetful for past architectural decisions and known constraints

#### Scenario: No context tools available
Given neither Forgetful Memory nor OpenSpec artifacts exist
When the DESIGN phase activates
Then the phase doc instructs the model to read CLAUDE.md, docs/architecture.md, and .cursorrules as fallback

### Requirement: Narrowed DESIGN-phase activation hint
The activation hook's DESIGN phase composition MUST emit hint text specific to Intent Truth and Historical Truth, not generic 4-tier text.

#### Scenario: Activation hook emits DESIGN hint
Given the unified-context-stack plugin is available
When a DESIGN-phase prompt is processed
Then the PARALLEL hint references "Intent Truth, Historical Truth" specifically
And the purpose describes checking existing specs and past decisions

### Requirement: Tier 0 diagnostics fallback chain
The unified-context-stack tier doc (`tiers/internal-truth.md`) MUST present Tier 0 diagnostics as a strict 3-level fallback: `0a` (IDE LSP), then `0b` (Serena diagnostics when `lsp=false` and `serena=true`), then `0c` (skip when neither is available).

#### Scenario: IDE LSP plugin available
Given the session capability flag `lsp=true`
When the model consults Tier 0 in `tiers/internal-truth.md`
Then the doc directs the model to use `mcp__ide__getDiagnostics`

#### Scenario: Serena available but no IDE LSP plugin
Given the session capability flags `lsp=false` and `serena=true`
When the model consults Tier 0 in `tiers/internal-truth.md`
Then the doc directs the model to use `mcp__serena__get_diagnostics_for_file` (file-scoped) or `mcp__serena__get_diagnostics_for_symbol` (symbol-scoped, marked as Serena's optional tool gated on `included_optional_tools`)
And the doc notes Serena v1.3.0+ as the minimum version

#### Scenario: Neither LSP nor Serena available
Given the session capability flags `lsp=false` and `serena=false`
When the model consults Tier 0 in `tiers/internal-truth.md`
Then the doc directs the model to skip Tier 0 and verify by running build/test commands

### Requirement: Tier 1 v1.3.0 retrieval tool surface
The unified-context-stack tier doc (`tiers/internal-truth.md`) MUST name `find_declaration` and `find_implementations` in the Tier 1 Serena navigation list, alongside `find_symbol` and `find_referencing_symbols`.

#### Scenario: Tier 1 lists v1.3.0 tools
Given the Tier 1 section of `tiers/internal-truth.md` is read
Then the bullet list MUST include `find_declaration` with a "preferred over `find_symbol` when you know the symbol exists" qualifier
And MUST include `find_implementations` for enumerating concrete implementations of an interface or abstract method
And MUST tag both as `(Serena v1.3.0+)`

#### Scenario: Question-mapping table covers v1.3.0 tools
Given the question-mapping table of `tiers/internal-truth.md` is read
Then the table MUST contain a row mapping "Where is this function defined?" to Tier 1 (Serena `find_declaration`, falling back to `find_symbol`)
And MUST contain a row mapping "Who implements this interface?" to Tier 1 (Serena `find_implementations`)

### Requirement: Per-phase v1.3.0 tool guidance
Each phase doc in `skills/unified-context-stack/phases/` MUST name the v1.3.0 retrieval tools that are relevant to that phase's questions when `serena=true`.

#### Scenario: All four phases name find_declaration
Given the `serena=true` guidance in any of `phases/triage-and-plan.md`, `phases/implementation.md`, `phases/testing-and-debug.md`, or `phases/code-review.md` is read
Then the phase MUST mention `find_declaration`

#### Scenario: Planning and debugging phases name find_implementations
Given the `serena=true` guidance in `phases/triage-and-plan.md` or `phases/testing-and-debug.md` is read
Then the phase MUST mention `find_implementations` for interface-dispatch questions

#### Scenario: Diagnostics fallback surfaces in debug and review phases
Given the Internal Truth section of `phases/testing-and-debug.md` or `phases/code-review.md` is read
Then the phase MUST name `mcp__serena__get_diagnostics_for_file` as a fallback when `lsp=false and serena=true`
And `phases/code-review.md` MUST name both `get_diagnostics_for_file` and `get_diagnostics_for_symbol` (symbol-scoped, optional) for consistency with the tier doc and the testing-and-debug phase

### Requirement: Session-start banner reflects v1.3.0 tool surface without subagent propagation
The Serena banner emitted by `hooks/session-start-hook.sh` when `serena=true` MUST name the v1.3.0 retrieval tools and MUST NOT instruct the parent agent to propagate Serena guidance into Task subagent prompts.

#### Scenario: Banner lists v1.3.0 retrieval tools
Given the session-start hook runs with `serena=true`
When the Serena banner is emitted
Then the banner MUST mention `mcp__serena__` tools including `find_declaration` and `find_implementations`

#### Scenario: Banner does not propagate to subagents
Given the session-start hook runs with `serena=true`
When the Serena banner is emitted
Then the banner MUST NOT contain "Task tool" instructions for prompt injection
And MUST NOT contain the propagation phrase "Serena available"

#### Scenario: Diagnostics tools stay out of the banner
Given the session-start hook runs with `serena=true`
When the Serena banner is emitted
Then the banner MUST NOT mention `get_diagnostics_for_file` or `get_diagnostics_for_symbol`
And diagnostics guidance MUST be reached via the unified-context-stack phase docs instead

### Requirement: Regression coverage for v1.3.0 tool name references
The test suite MUST include grep-based assertions that the v1.3.0 tool name references stay present in the skill docs across the tier doc and the four phase docs.

#### Scenario: Per-phase find_declaration coverage
Given `tests/test-serena-v1-3-0-skill-references.sh` runs
Then it MUST assert `find_declaration` appears in each of `phases/triage-and-plan.md`, `phases/implementation.md`, `phases/testing-and-debug.md`, and `phases/code-review.md`

#### Scenario: Tier doc covers all three v1.3.0 tools
Given `tests/test-serena-v1-3-0-skill-references.sh` runs
Then it MUST assert `find_declaration`, `find_implementations`, and `get_diagnostics_for_file` appear in `tiers/internal-truth.md`

#### Scenario: Diagnostics fallback assertions in debug and review phases
Given `tests/test-serena-v1-3-0-skill-references.sh` runs
Then it MUST assert `get_diagnostics_for_file` appears in both `phases/testing-and-debug.md` and `phases/code-review.md`

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

