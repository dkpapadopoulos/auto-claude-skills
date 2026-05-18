## ADDED Requirements

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
