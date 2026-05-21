## Purpose

Skill routing correctness contract. Regression tests for collision resolution, canonical/legacy session-state field aliasing for backward compatibility, and tiered Intent Truth retrieval — ensuring the right artifact wins at the right time across overlapping trigger patterns.
## Requirements
### Requirement: Routing Collision Regression Tests
The routing test suite MUST include interaction tests that verify correct skill selection when overlapping trigger patterns match the same prompt.

#### Scenario: Code review collision resolution
- **WHEN** a prompt contains "review" without team/multi-perspective qualifiers
- **THEN** `requesting-code-review` (priority 25) MUST be selected over `agent-team-review` (priority 20)

#### Scenario: Worktree routing with phase gating
- **WHEN** a prompt triggers brainstorming (DESIGN phase) and also matches `worktree`
- **THEN** `using-git-worktrees` (required role, IMPLEMENT phase) MUST NOT appear in activation context

#### Scenario: Debug vs incident disambiguation
- **WHEN** a prompt mentions infrastructure symptoms (crashloop, OOM, latency spike, SLO burn rate)
- **THEN** `incident-analysis` MUST be selected regardless of `systematic-debugging` also matching

#### Scenario: Negative routing
- **WHEN** a prompt is a greeting or generic question
- **THEN** no domain or process skills SHOULD activate

### Requirement: Session State Canonical Fields
The `openspec_state_upsert_change` function MUST write both canonical field names (`design_path`, `plan_path`, `spec_path`) and legacy aliases (`sp_plan_path`, `sp_spec_path`).

#### Scenario: Backward-compatible reads
- **WHEN** a provenance writer reads a state file written by the new code
- **THEN** both `plan_path` and `sp_plan_path` MUST return the same value

#### Scenario: Legacy state file reads
- **WHEN** a provenance writer reads a state file written by old code (only `sp_plan_path`)
- **THEN** the canonical `plan_path` field MUST fall back to `sp_plan_path` via jq `//` operator

### Requirement: Intent Truth 5-Tier Retrieval
Intent Truth retrieval MUST check sources in this order: OpenSpec active changes, `docs/plans/` live artifacts, `openspec/specs/` canonical, `docs/plans/archive/` archived, `docs/superpowers/specs/` legacy.

#### Scenario: Live intent takes precedence
- **WHEN** both `docs/plans/*-design.md` and `openspec/specs/<cap>/spec.md` exist
- **THEN** `docs/plans/` MUST be read first (Source 2 before Source 3)

### Requirement: Preset-Gated OpenSpec-First Mode
The plugin MUST support a `spec-driven` preset that redirects DESIGN and PLAN artifact creation from `docs/plans/` to `openspec/changes/<feature>/` when the preset's `openspec_first` flag is `true`.

#### Scenario: spec-driven preset active redirects DESIGN hints
- **GIVEN** `~/.claude/skill-config.json` contains `{"preset": "spec-driven"}`
- **WHEN** session-start hook runs
- **THEN** the cached registry's `phase_compositions.DESIGN.hints[].text` MUST contain `openspec/changes/`

### Requirement: openspec-ship Idempotent Pre-flight
`openspec-ship` MUST detect whether `openspec/changes/<feature-name>/` already exists before creating it. If present, validate and sync; if absent, create retrospectively.

#### Scenario: Existing change folder synced not overwritten
- **GIVEN** `openspec/changes/feature-x/` already exists from an upfront DESIGN-phase write
- **WHEN** `openspec-ship` runs in SHIP phase for `feature-x`
- **THEN** the existing proposal.md and design.md MUST NOT be overwritten; only the specs/ folder is updated to reflect as-built

#### Scenario: Missing change folder created retrospectively
- **GIVEN** no `openspec/changes/feature-x/` exists
- **WHEN** `openspec-ship` runs in SHIP phase for `feature-x`
- **THEN** the change folder MUST be created with retrospective proposal.md, design.md, and specs/

### Requirement: New-Capability Warning
When introducing a previously-unknown capability, skills MUST emit a visible `⚠️ NEW CAPABILITY:` warning for user taxonomy review.

#### Scenario: First use of a capability name
- **GIVEN** `openspec/specs/<cap>/` does not exist
- **WHEN** openspec-ship or design-debate introduces that capability
- **THEN** the skill output MUST contain a `⚠️ NEW CAPABILITY` warning line referencing the capability name

### Requirement: Dual-Mode design-debate Output
`design-debate` MUST check the session preset and write its synthesis to `openspec/changes/<topic>/` in spec-driven mode or `docs/plans/YYYY-MM-DD-<topic>-design.md` in solo mode.

#### Scenario: spec-driven mode write location
- **GIVEN** `~/.claude/skill-config.json` has `{"preset": "spec-driven"}`
- **WHEN** design-debate synthesizes its output
- **THEN** the synthesis MUST be written under `openspec/changes/<topic>/` (committed path)

#### Scenario: solo mode write location
- **GIVEN** no `spec-driven` preset is set
- **WHEN** design-debate synthesizes its output
- **THEN** the synthesis MUST be written to `docs/plans/YYYY-MM-DD-<topic>-design.md` (gitignored path)

### Requirement: PLAN-phase DESIGN COMPLETENESS emission
The skill-activation hook MUST emit an accurate, file-grounded `DESIGN COMPLETENESS` block in the PLAN-phase activation context when the session has a token, an OpenSpec state file with an active change, and a non-null `design_path` for that change. The block MUST name three canonical sections of the design artifact: `## Capabilities Affected`, `## Out-of-Scope`, and `## Acceptance Scenarios`.

#### Scenario: All three sections present
- **WHEN** the design file at `design_path` contains all three canonical section headers as prefix matches (`^## <Header>`)
- **THEN** the activation output MUST contain the string `DESIGN COMPLETENESS: all sections present` on a single line
- **AND** the activation output MUST NOT contain the word "missing"

#### Scenario: Missing section names the gap
- **WHEN** the design file is missing one or more of the canonical section headers
- **THEN** the activation output MUST include a `DESIGN COMPLETENESS` header
- **AND** the activation output MUST explicitly name each missing section by header with a `(missing — ...)` annotation
- **AND** the activation output MUST instruct the LLM to complete the missing section(s) before invoking `Skill(superpowers:writing-plans)`
- **AND** the activation output MUST NOT annotate any present section with `(missing`

#### Scenario: Design file unreadable
- **WHEN** the state file's `design_path` refers to a file that does not exist on disk
- **THEN** the activation output MUST include a `DESIGN COMPLETENESS` header
- **AND** the output MUST include the word `unreadable` and echo the path
- **AND** the hook MUST still emit a valid JSON context block (no crash)

#### Scenario: No active change with design_path
- **WHEN** the state file is absent, or is present with an empty `changes` object, or has no active change with a non-null `design_path`
- **THEN** the activation output MUST NOT contain the string `DESIGN COMPLETENESS`

### Requirement: DESIGN COMPLETENESS fail-open contract
The PLAN-phase DESIGN COMPLETENESS block MUST fail-open on every sub-check: missing session token, missing state file, malformed state JSON, missing `design_path` key, missing file on disk, and grep errors MUST all degrade silently. The block MUST NOT cause the hook to exit non-zero or emit malformed JSON.

#### Scenario: Malformed state JSON
- **WHEN** the state file exists but is not valid JSON
- **THEN** the activation hook MUST still emit its normal output
- **AND** the activation output MUST NOT contain the string `DESIGN COMPLETENESS`

#### Scenario: Non-PLAN phase
- **WHEN** `PRIMARY_PHASE` is not `PLAN`
- **THEN** the DESIGN COMPLETENESS block MUST NOT fire regardless of state file contents

### Requirement: DESIGN COMPLETENESS SKILL_EXPLAIN breadcrumb
When `SKILL_EXPLAIN=1` is set, the PLAN-phase DESIGN COMPLETENESS block MUST emit an observability breadcrumb to stderr naming the three presence flags and the design path. When multiple open changes have `design_path` set, the block MUST additionally emit a `WARN N open changes` breadcrumb to make the arbitrary first-wins selection visible.

#### Scenario: Presence-flag breadcrumb
- **WHEN** `SKILL_EXPLAIN=1` and the block runs against a readable design file
- **THEN** stderr MUST contain a line of the form `[skill-hook]   [design-guard] caps=<0|1> oos=<0|1> acc=<0|1> path=<design_path>`

#### Scenario: Unreadable-file breadcrumb
- **WHEN** `SKILL_EXPLAIN=1` and the `design_path` points at a missing file
- **THEN** stderr MUST contain `[skill-hook]   [design-guard] unreadable: <design_path>`

#### Scenario: Multi-change ambiguity breadcrumb
- **WHEN** `SKILL_EXPLAIN=1` and two or more non-archived changes have `design_path` set
- **THEN** stderr MUST contain a `WARN <N> open changes with design_path; picked first` line before the presence-flag breadcrumb

### Requirement: Skill-tool completion advances composition state
A `PostToolUse` hook matching `^Skill$` MUST advance `~/.claude/.skill-composition-state-<token>`'s `.completed` array when a chain-member `Skill` tool call returns successfully. The hook MUST extract the skill name from `tool_input.name` (falling back to `tool_input.skill`), strip the plugin prefix by removing the longest leading `<anything>:` segment, and append the bare name to `.completed` only if it appears in `.chain` and not yet in `.completed`. On advancement, the hook MUST also bump `.current` to the next chain member that follows the just-completed skill, or leave `.current` unchanged if the completed skill is the last chain member.

#### Scenario: Chain-member Skill returns successfully
- **WHEN** the `Skill` tool returns with `tool_response.is_error == false` for a plugin-prefixed name whose bare form is in `.chain` and not in `.completed`
- **THEN** the hook MUST append the bare name to `.completed` preserving existing array order
- **AND** `.current` MUST advance to the next chain member not yet completed

#### Scenario: Last chain member preserves current
- **WHEN** the just-completed skill is the final entry in `.chain`
- **THEN** `.current` MUST remain unchanged (the existing value is preserved because no next chain member exists)

#### Scenario: tool_input.skill fallback
- **WHEN** the tool-use payload has `tool_input.skill` set instead of `tool_input.name`
- **THEN** the hook MUST read the skill name from `tool_input.skill` and advance state identically

### Requirement: Skill-completion hook fail-open contract
The `PostToolUse` `^Skill$` hook MUST exit 0 on every error path and MUST NOT mutate the state file on any failure. Specifically: missing stdin, missing `jq`, missing session token, missing state file, malformed state JSON, errored `tool_response`, empty skill name, unknown skill name, non-chain-member, already-completed skill, and `mv` failure MUST all degrade to silent exit 0 with no state change.

#### Scenario: Non-chain skill is a no-op
- **WHEN** the bare skill name is not present in `.chain`
- **THEN** the state file MUST remain byte-identical to its pre-call contents

#### Scenario: Errored tool response is a no-op
- **WHEN** `tool_response.is_error == true`
- **THEN** the state file MUST remain byte-identical to its pre-call contents

#### Scenario: Malformed state JSON is a no-op
- **WHEN** the state file exists but fails `jq empty` validation
- **THEN** the hook MUST exit 0 without overwriting or deleting the state file

#### Scenario: Idempotent re-invocation
- **WHEN** the hook is invoked twice in a row with the same skill name whose bare form is already in `.completed`
- **THEN** `.completed` MUST NOT grow; its length MUST equal its `unique` length

### Requirement: Skill-completion hook emits SKILL_EXPLAIN breadcrumb
When `SKILL_EXPLAIN=1` is set in the environment and the hook advances state, it MUST emit a single-line breadcrumb to stderr naming the skill that was marked completed. The breadcrumb MUST NOT fire on any no-op path.

#### Scenario: Breadcrumb on successful advance
- **WHEN** `SKILL_EXPLAIN=1` and the hook appends a chain-member skill to `.completed`
- **THEN** stderr MUST contain a line of the form `[skill-hook]   [completion] <skill-name> → completed`

#### Scenario: Breadcrumb suppressed on no-op
- **WHEN** `SKILL_EXPLAIN=1` but the skill name is not in `.chain` (or already in `.completed`, or the tool returned with an error)
- **THEN** the hook MUST NOT emit a `[completion]` breadcrumb

### Requirement: LSP Capability Detection

Session-start MUST set `.context_capabilities.lsp = true` if AND ONLY IF BOTH conditions hold at session-start time:

1. At least one installed plugin under `~/.claude/plugins/cache/<marketplace>/<plugin-name>/[<version>/].claude-plugin/plugin.json` declares a non-empty `lspServers` object with at least one `<server-name>.command` string.
2. At least one declared `lspServers.<name>.command` resolves via POSIX `command -v` on the session's PATH at hook execution time.

The user MAY additionally force `lsp = true` by placing `{"context_capabilities": {"lsp": true}}` in `~/.claude/skill-config.json`; the override is governed by the general User-Config Capability Override requirement below. The resulting flag MUST appear as `.context_capabilities.lsp` in the cache registry and in the session-start `Context Stack:` output line.

When a plugin is detected with `lspServers` declared but none of its `command` values resolve on PATH (a "partial install"), session-start MUST emit a diagnostic line naming the plugin and the missing command(s), so the user knows which binary to install. The diagnostic MUST NOT claim `lsp=true` when the capability is actually `false`.

#### Scenario: LSP plugin installed with backing binary resolvable

- **GIVEN** an installed plugin (e.g. `typescript-lsp`) whose `plugin.json` declares `lspServers.typescript.command = "typescript-language-server"`
- **AND** `typescript-language-server` resolves via `command -v` on the session PATH
- **WHEN** session-start runs
- **THEN** `.context_capabilities.lsp` MUST equal `true` in `~/.claude/.skill-registry-cache.json`
- **AND** the session-start `additionalContext` output MUST contain a line beginning with `LSP:` that references `mcp__ide__getDiagnostics`

#### Scenario: LSP plugin installed but backing binary missing

- **GIVEN** an installed plugin (e.g. `typescript-lsp`) whose `plugin.json` declares a language-server command
- **AND** that command does NOT resolve via `command -v` on the session PATH
- **WHEN** session-start runs
- **THEN** `.context_capabilities.lsp` MUST equal `false`
- **AND** the session-start `additionalContext` output MUST NOT contain the guidance line referencing `mcp__ide__getDiagnostics`
- **AND** the session-start `additionalContext` output MUST contain a `LSP (partial install)` line naming both the plugin and the missing command

#### Scenario: no LSP plugin installed

- **GIVEN** no installed plugin declares `lspServers`
- **WHEN** session-start runs
- **THEN** `.context_capabilities.lsp` MUST equal `false`
- **AND** the session-start `additionalContext` output MUST NOT contain the string `mcp__ide__getDiagnostics`
- **AND** the session-start `additionalContext` output MUST NOT contain a `LSP (partial install)` diagnostic (zero-noise contract)

### Requirement: User-Config Capability Override

Session-start MUST honor `~/.claude/skill-config.json` entries of shape `{"context_capabilities": {"<flag>": true}}` for every canonical capability key, upgrading the detected flag from `false` to `true`. The override MUST NOT downgrade `true` to `false` under any circumstances. The override MUST silently drop any entry whose key is not in the canonical capability set, preventing injection of non-capability keys into `context_capabilities`.

#### Scenario: legitimate override honored

- **GIVEN** `~/.claude/skill-config.json` contains `{"context_capabilities": {"lsp": true}}`
- **AND** no LSP plugin is detected (or the declared language-server binary is not on PATH)
- **WHEN** session-start runs
- **THEN** `.context_capabilities.lsp` MUST equal `true` in the cache — the override upgrades `false → true`

#### Scenario: downgrade rejected

- **GIVEN** a capability is detected as `true` via plugin presence (e.g., `context7`)
- **AND** `~/.claude/skill-config.json` contains `{"context_capabilities": {"context7": false}}`
- **WHEN** session-start runs
- **THEN** `.context_capabilities.context7` MUST equal `true` — the override MUST NOT downgrade

#### Scenario: arbitrary key rejected

- **GIVEN** `~/.claude/skill-config.json` contains `{"context_capabilities": {"foo_injected": true, "malicious_safety_gate": true, "lsp": true}}`
- **WHEN** session-start runs
- **THEN** `.context_capabilities` MUST contain exactly the 8 canonical keys (`context7`, `context_hub_cli`, `context_hub_available`, `serena`, `forgetful_memory`, `openspec`, `posthog`, `lsp`)
- **AND** `.context_capabilities.lsp` MUST equal `true`
- **AND** `.context_capabilities.foo_injected` and `.context_capabilities.malicious_safety_gate` MUST NOT exist

### Requirement: Canonical Fallback Registry Shape

The committed `config/fallback-registry.json` served on the no-jq path MUST contain exclusively structural shape derived from `config/default-triggers.json`. It MUST NOT contain any machine-specific state, user configuration, or preset effects. Specifically: every `.plugins[].available` and every `.skills[].available` MUST be `false`; `.plugins[]` MUST be limited to curated entries from `default-triggers.json`; `.skills[]` MUST be limited to curated entries; `.context_capabilities` MUST contain exactly the canonical capability key set with every value `false`; and `.phase_compositions` MUST match `default-triggers.json` pre-preset content.

#### Scenario: zero-trust availability

- **WHEN** the session-start auto-regenerator writes `config/fallback-registry.json`
- **THEN** `[.plugins[] | select(.available == true)] | length` MUST equal `0`
- **AND** `[.skills[] | select(.available == true)] | length` MUST equal `0`
- **AND** `[.context_capabilities | to_entries[] | select(.value == true)]` MUST be empty

#### Scenario: preset activation does not leak

- **GIVEN** `~/.claude/skill-config.json` sets `"preset": "spec-driven"` (rewrites `phase_compositions.DESIGN.hints`)
- **WHEN** the auto-regenerator writes the fallback
- **THEN** `config/fallback-registry.json` `.phase_compositions.DESIGN.hints` MUST match the `default-triggers.json` default text, not the spec-driven preset rewrite

#### Scenario: user-config override keys do not leak

- **GIVEN** `~/.claude/skill-config.json` sets `{"context_capabilities": {"foo_injected": true}}`
- **WHEN** the auto-regenerator writes the fallback
- **THEN** `config/fallback-registry.json` `.context_capabilities` MUST NOT contain the key `foo_injected`

#### Scenario: auto-discovered plugins do not leak

- **GIVEN** `~/.claude/plugins/cache/<marketplace>/<external-plugin>/` exists with a valid plugin.json
- **WHEN** the auto-regenerator writes the fallback
- **THEN** `config/fallback-registry.json` `.plugins` MUST NOT contain an entry for `<external-plugin>`

### Requirement: LSP Tier Guidance in unified-context-stack

The `unified-context-stack` tier documentation MUST present LSP diagnostics as the first-choice tool for compile/type errors when `lsp=true`, Serena as the tool for symbol navigation and structural edits when `serena=true`, and Grep/Read/Edit as the fallback when neither capability is present or when the content is non-code (log strings, YAML values, config text).

#### Scenario: internal-truth tier ordering

- **WHEN** a Claude session reads `skills/unified-context-stack/tiers/internal-truth.md`
- **THEN** the file MUST define three tiers in order: Tier 0 (LSP diagnostics), Tier 1 (Serena symbol navigation), Tier 2 (standard tools)

#### Scenario: testing-and-debug phase guidance

- **WHEN** a Claude session reads `skills/unified-context-stack/phases/testing-and-debug.md` section 3 (Internal Truth)
- **THEN** the first bullet MUST direct Claude to `mcp__ide__getDiagnostics` when `lsp=true`
- **AND** the Serena and Grep bullets MUST appear after as `serena=true` and `serena=false and lsp=false` branches respectively

#### Scenario: code-review phase guidance

- **WHEN** a Claude session reads `skills/unified-context-stack/phases/code-review.md` section 2 (Internal Truth / Dependency Safety)
- **THEN** the first bullet MUST direct Claude to `mcp__ide__getDiagnostics` when `lsp=true` and the reviewer claims a type/compile error

### Requirement: LSP Nudge on Error-Hunt Grep

The plugin MUST emit a `hookSpecificOutput.additionalContext` hint pointing at `mcp__ide__getDiagnostics` when Claude invokes the `Grep` tool with a pattern matching a language-agnostic error-hunt regex AND the registry cache has `context_capabilities.lsp = true`. The hint is advisory: the PreToolUse hook MUST NOT deny the Grep call. The hook MUST exit 0 under every circumstance, including when its guards skip the emit path.

#### Scenario: error-hunt pattern fires the nudge

- **GIVEN** the registry cache at `~/.claude/.skill-registry-cache.json` has `.context_capabilities.lsp` equal to `true`
- **AND** Claude invokes `Grep` with a pattern containing any of: `TypeError`, `SyntaxError`, `ReferenceError`, `ImportError`, `ModuleNotFoundError`, `AttributeError`, `NameError`, `NullPointerException`, `ClassCastException`, `Cannot find module|name`, `is not assignable`, `implicit any`, `Property .* does not exist`, `does not exist on type`, `Expected ... got|but got`, `no matching`, `undefined symbol`, `cannot resolve`, `unresolved reference|import`, `use of undeclared`, `undefined reference to`, `not exported from`, `is not defined`, `has no attribute` (case-insensitive)
- **WHEN** the `lsp-nudge.sh` PreToolUse hook runs
- **THEN** the hook MUST emit a valid JSON payload with shape `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "<hint>"}}` on stdout
- **AND** the `additionalContext` string MUST reference `mcp__ide__getDiagnostics`
- **AND** the hook MUST exit 0

#### Scenario: plain-symbol pattern is silent

- **GIVEN** the registry cache has `.context_capabilities.lsp` equal to `true`
- **AND** Claude invokes `Grep` with a pattern that does not match the error-hunt regex (e.g., `authenticate`, `UserProfile`, `fetch_user`)
- **WHEN** the `lsp-nudge.sh` PreToolUse hook runs
- **THEN** the hook MUST NOT emit any `mcp__ide__getDiagnostics` hint
- **AND** the hook MUST exit 0

#### Scenario: lsp=false suppresses the nudge regardless of pattern

- **GIVEN** the registry cache has `.context_capabilities.lsp` equal to `false`
- **AND** Claude invokes `Grep` with an error-hunt pattern
- **WHEN** the `lsp-nudge.sh` PreToolUse hook runs
- **THEN** the hook MUST NOT emit any `mcp__ide__getDiagnostics` hint
- **AND** the hook MUST exit 0

#### Scenario: missing registry cache is fail-open

- **GIVEN** the registry cache at `~/.claude/.skill-registry-cache.json` does not exist
- **WHEN** the `lsp-nudge.sh` PreToolUse hook runs for any `Grep` invocation
- **THEN** the hook MUST NOT emit any `mcp__ide__getDiagnostics` hint
- **AND** the hook MUST exit 0

### Requirement: Coexistence With Serena Nudge on Grep

The plugin MUST register both `hooks/serena-nudge.sh` and `hooks/lsp-nudge.sh` as `PreToolUse` matchers for the `Grep` tool. Both hooks MUST run on every `Grep` invocation; each MUST emit its hint independently when its guards pass, without suppressing or interfering with the other.

#### Scenario: both matchers configured

- **WHEN** `hooks/hooks.json` is loaded
- **THEN** the `PreToolUse` array MUST contain two entries with `matcher: "Grep"` whose `hooks[0].command` resolve to `serena-nudge.sh` and `lsp-nudge.sh` respectively

#### Scenario: only LSP guards match

- **GIVEN** both hooks are registered and the cache has `lsp=true` and `serena=false`
- **AND** Claude invokes `Grep` with an error-hunt pattern (e.g., `TypeError: ...`)
- **WHEN** the runtime fires both PreToolUse hooks
- **THEN** the LSP nudge MUST emit its hint
- **AND** the Serena nudge MUST exit 0 without emitting

#### Scenario: only Serena guards match

- **GIVEN** both hooks are registered and the cache has `serena=true` and `lsp=false`
- **AND** Claude invokes `Grep` with a symbol-shape pattern (e.g., `authenticate`)
- **WHEN** the runtime fires both PreToolUse hooks
- **THEN** the Serena nudge MUST emit its hint
- **AND** the LSP nudge MUST exit 0 without emitting

### Requirement: Per-Skill Regex Trigger Fixtures

The repository MUST provide a deterministic test harness that verifies regex triggers in `config/default-triggers.json` against per-skill fixture files. The harness MUST lowercase prompts before matching (to mirror `hooks/skill-activation-hook.sh` pre-processing) and MUST use bash `[[ =~ ]]` extended regex (the same engine as the activation hook). The harness MUST be auto-discovered by the default `tests/run-tests.sh` so that fixture regressions break the default test suite at zero LLM cost.

#### Scenario: Fixture directives drive assertions
- **WHEN** `tests/fixtures/routing/<skill>.txt` contains a line `MATCH: <prompt>` and the skill has entries in `config/default-triggers.json`
- **THEN** at least one trigger regex MUST match the lowercased prompt, or the test MUST fail with a line-numbered failure message citing the skill and the unmatched prompt.

#### Scenario: Negative directives enforce specificity
- **WHEN** the fixture contains a line `NO_MATCH: <prompt>`
- **THEN** no trigger regex for that skill SHALL match the lowercased prompt, or the test MUST fail and cite the offending regex verbatim.

#### Scenario: Comments and blank lines ignored
- **WHEN** a fixture line is empty or begins with `#` (optionally preceded by whitespace)
- **THEN** the line MUST be skipped without affecting pass/fail counts.

#### Scenario: Missing trigger entry fails closed
- **WHEN** a fixture file exists for a skill that has no matching entry in `config/default-triggers.json`
- **THEN** the test MUST fail explicitly rather than silently pass.

#### Scenario: Bash 3.2 compatibility
- **WHEN** `tests/test-regex-fixtures.sh` runs on macOS `/bin/bash` (3.2.57)
- **THEN** it MUST execute without invoking bash-4-only features (associative arrays, `mapfile`/`readarray`, `${var,,}`, `<<<` here-strings in load-bearing positions).

### Requirement: Description Trigger Accuracy CI Gate

The repository MUST provide a non-blocking PR workflow that scores each changed skill's SKILL.md frontmatter `description` against an optional per-skill eval pack (`skills/<name>/evals/evals.json`). The workflow MUST be opt-in via either a `run-eval` PR label or an `@claude run eval` PR comment. The workflow SHALL NOT fail the PR check; it SHALL only post advisory markdown results as a PR comment.

#### Scenario: Happy path evaluation
- **WHEN** a maintainer applies the `run-eval` label to a PR that edits `skills/<name>/SKILL.md` and `skills/<name>/evals/evals.json` exists
- **THEN** the workflow MUST post a markdown table per changed skill containing per-case PASS/FAIL, trigger accuracy (recall on positives), specificity (correct skips on negatives), and overall percentage.

#### Scenario: Missing eval pack graceful skip
- **WHEN** a PR edits `skills/<name>/SKILL.md` and `evals/evals.json` does NOT exist for that skill
- **THEN** the workflow MUST post a "skipped — add evals" section naming the skill and referencing `docs/eval-pack-schema.md`, rather than erroring.

#### Scenario: Accuracy threshold flag
- **WHEN** a skill's overall accuracy score is below 80%
- **THEN** the workflow MUST flag the result with an explicit warning line that quotes the current description verbatim and recommends a rewrite.

#### Scenario: Prior bot comment reaper
- **WHEN** a new evaluation run completes successfully
- **THEN** prior `github-actions[bot]` comments whose body matches "Skill Eval Results" MUST be deleted before the new table is posted.

#### Scenario: Reaper disabled on eval failure
- **WHEN** the eval step fails or is skipped (including the fork-PR abort path)
- **THEN** the reaper step MUST NOT run, so that prior legitimate eval warnings on the PR survive unchanged.

#### Scenario: Fork-PR head refused
- **WHEN** the workflow is triggered for a PR whose `head.repo.full_name` differs from the base repository
- **THEN** the workflow MUST emit a `::notice::` and abort before `actions/checkout@v4` runs, so that adversarial fork-PR content is never checked out while secrets are in scope.

#### Scenario: Permission gate excludes read-only and triage users
- **WHEN** the triggering user's permission (from `/repos/<repo>/collaborators/<user>/permission`) is not one of `admin`, `write`, or `maintain`
- **THEN** the workflow MUST abort before checkout with a `::notice::` citing the actual permission level.

### Requirement: Eval Pack Schema Convention

Per-skill `evals/evals.json` files MUST be JSON arrays where each element is an object with at minimum a string `id`, a string `query`, and a boolean `should_trigger`. The optional field `note` MAY be included as a string used for reviewer context in the CI output. The schema MUST be documented at `docs/eval-pack-schema.md` with authoring guidelines covering case counts, positive/negative balance, and the 80% accuracy threshold.

#### Scenario: Required fields present
- **WHEN** an eval pack is consumed by the Description Trigger Accuracy CI Gate
- **THEN** each case object MUST contain `id`, `query`, and `should_trigger`, or the gate MUST report the malformed case in its output rather than silently ignoring it.

#### Scenario: Author guidelines reflect intent
- **WHEN** a contributor reads `docs/eval-pack-schema.md`
- **THEN** the document MUST describe: (a) recommended case count per skill (5–10), (b) the requirement that at least one-third of cases target explicit out-of-scope boundaries as `should_trigger: false`, (c) the 80% overall accuracy threshold, and (d) the `CLAUDE_CODE_OAUTH_TOKEN` repo secret required to run the CI gate.

### Requirement: Sticky Composition Emission on Bare Acks

The activation hook MUST sticky-emit the CURRENT chain step when composition state is active and the user's prompt is short (≤ 6 words by whitespace count), so the SDLC chain context remains visible across bare acknowledgment prompts that would otherwise produce no routing output.

The hook MUST treat the composition-state file (`~/.claude/.skill-composition-state-<token>`) as authoritative: `CURRENT = .chain[length(.completed)]`. Sticky emission is display-only and MUST NOT mutate `.completed`; chain advancement remains the responsibility of the `PostToolUse ^Skill$` completion hook.

#### Scenario: Bare ack during active chain emits CURRENT

- **GIVEN** composition state with `chain=[brainstorming, writing-plans, executing-plans, ...]` and `completed=[brainstorming, writing-plans]`
- **WHEN** the user submits the prompt `yes`
- **THEN** the hook MUST emit `Phase: [IMPLEMENT]`, `Process: executing-plans -> Skill(superpowers:executing-plans)`, and the full composition chain block with `[CURRENT] Step 3: executing-plans`

#### Scenario: Sticky advances as completed grows

- **GIVEN** the canonical 7-step SDLC chain
- **WHEN** `.completed` grows from `[]` to `[A,B,C,D,E,F]` across the lifetime of a session
- **THEN** for each `i` in 0..N-1, a bare ack MUST emit `chain[i]` as the active skill — never re-emitting the previous step

#### Scenario: No composition state means no sticky

- **GIVEN** no `~/.claude/.skill-composition-state-<token>` file exists
- **WHEN** the user submits a bare ack
- **THEN** the hook MUST exit through the pre-existing short-prompt or blocklist path with empty output

#### Scenario: Corrupt composition state fails open

- **GIVEN** the composition-state file contains invalid JSON
- **WHEN** any prompt arrives
- **THEN** the sticky function MUST return silently, the hook MUST exit 0, and no crash MUST occur

#### Scenario: Hijack guard prevents over-emission

- **GIVEN** an active composition chain with `CURRENT=writing-plans`
- **WHEN** the user submits `debug the failing test` (matches `systematic-debugging` naturally)
- **THEN** sticky MUST NOT inject `writing-plans` — the natural process match wins

### Requirement: Pure-Cancel Prompts Clear Composition State

The activation hook MUST recognize a small set of unambiguous cancellation prompts and clear the composition-state file when matched. The match MUST be anchored to the whole prompt (with optional surrounding whitespace and trailing punctuation) so mixed prompts that contain a cancel word alongside other content do not trigger this path.

Recognized cancellation tokens: `stop`, `cancel`, `abort`, `nevermind`/`never mind`, `forget it`, `scrap that`, `drop it`, `no thanks`, `nope`, `nah`. Trailing punctuation `[ \t!.,?:;]` MUST be tolerated. Leading whitespace MUST be tolerated.

#### Scenario: Pure cancel clears state and suppresses sticky

- **GIVEN** an active composition chain
- **WHEN** the user submits `cancel`, `stop.`, `cancel?`, `stop!`, `  never mind  `, `nope`, or `no thanks`
- **THEN** the composition-state file MUST be deleted and the hook MUST NOT emit `Process: writing-plans` (or any other CURRENT-step sticky line)

#### Scenario: Mixed prompt with cancel word routes naturally

- **GIVEN** an active chain with `CURRENT=writing-plans`
- **WHEN** the user submits `never mind, different plan`
- **THEN** the cancel regex MUST NOT match (anchor blocks); composition state MUST persist; routing MUST proceed via natural trigger matching where `plan` matches `writing-plans`

### Requirement: Composition-State-Aware Early-Exit Bypass

The activation hook MUST consult composition state before exiting via the short-prompt gate (`PROMPT < 5 chars`) or the greeting blocklist. When `_comp_active` returns true (chain length > completed length), both early exits MUST be bypassed so the bare-ack prompt reaches the routing pipeline.

#### Scenario: Short prompt bypassed when chain alive

- **GIVEN** composition state with a live chain
- **WHEN** the user submits `yes` (3 chars, ≤ 5)
- **THEN** the short-prompt early-exit MUST NOT fire; the hook MUST continue to scoring

#### Scenario: Blocklist bypassed when chain alive

- **GIVEN** composition state with a live chain
- **WHEN** the user submits `ok` (in the greeting blocklist)
- **THEN** the blocklist early-exit MUST NOT fire; the hook MUST continue to scoring

### Requirement: Serena Grep Matcher Regex Coverage

The `serena-nudge.sh` hook MUST classify Grep patterns of the following shapes as symbol lookups and emit `additionalContext` recommending Serena MCP tools: word-boundary identifiers (`\bIdent\b`, `^Ident$`), dotted or qualified member access (`Foo\.bar`, `Foo::bar`), and embedded definition-prefix patterns (`^class +Foo\b`, `def +process_\w+`). The hook MUST NOT emit additionalContext when the pattern contains heavy alternation (3 or more alternatives), lookaround constructs, or character classes containing whitespace.

#### Scenario: Word-boundary symbol fires the nudge

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Grep` with pattern `\bUserService\b`
- **THEN** the PreToolUse hook MUST emit `additionalContext` recommending `find_symbol` or `get_symbols_overview`

#### Scenario: Dotted member access fires the nudge

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Grep` with pattern `Foo::bar` or `User\.profile`
- **THEN** the hook MUST emit `additionalContext` recommending Serena symbol tools

#### Scenario: Definition prefix fires regardless of regex wrapping

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Grep` with pattern `^class +Foo\b`
- **THEN** the hook MUST emit `additionalContext` recommending Serena symbol tools

#### Scenario: Free text and broad character classes do not fire

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Grep` with pattern `Connection refused` or `[A-Za-z 0-9_-]+ failed`
- **THEN** the hook MUST NOT emit any `additionalContext`

### Requirement: Serena Telemetry Append-Only Log

When the Grep nudge fires, the hook MUST append a tab-separated record to `~/.claude/.serena-nudge-telemetry` containing six fields: unix timestamp, session token, turn id, kind (`nudge`), pattern class (in field 5), and matcher source name (`grep_extension`, in field 6). The schema places the class in field 5 consistently across all kinds (`nudge`, `observe`, `followup`) so the follow-through correlator and the rolling-window report can join on a single field and produce per-class follow-through buckets. Telemetry writes MUST be opt-out via the `SERENA_TELEMETRY=0` environment variable. A failed write MUST NOT cause the hook to exit non-zero.

#### Scenario: Telemetry is appended on fire

- **GIVEN** `SERENA_TELEMETRY` is unset and the Grep matcher fires on pattern `\bUserService\b`
- **WHEN** the hook completes
- **THEN** `~/.claude/.serena-nudge-telemetry` MUST contain a line with `nudge`, `word_boundary` in field 5, and `grep_extension` in field 6

#### Scenario: Telemetry is suppressed by env flag

- **GIVEN** `SERENA_TELEMETRY=0` and the Grep matcher fires
- **WHEN** the hook completes
- **THEN** no telemetry line MUST be written

### Requirement: Silent Missed-Opportunity Observers

The `serena-observer.sh` hook MUST run on `Read`, `Glob`, and `Edit` PreToolUse events when `serena=true` and silently log candidate missed-opportunity observations to the same telemetry file used by the active matcher. The hook MUST NOT emit any `additionalContext` for any input. The observer MUST classify:

- `read_large_source`: Read of a source-code file (one of `.ts|.tsx|.js|.jsx|.py|.go|.rs|.java|.kt|.scala|.rb|.cs|.cpp|.cc|.c|.h|.hpp|.swift|.m|.mm`) with no `offset` or `limit` field and more than 500 lines.
- `glob_definition_hunt`: Glob pattern containing a CamelCase token between `*` wildcards, excluding patterns matching `*.md*|*.json*|*.yaml*|*.yml*|*.lock*|*.test.*|*.spec.*`.
- `edit_symbol_token`: Edit on a source file where both `old_string` and `new_string` are single-line bare identifiers and differ.

#### Scenario: Read on >500-line source file logs observation

- **GIVEN** `serena=true` and a 600-line `.ts` file
- **WHEN** Claude calls `Read` on the file with no `offset`/`limit`
- **THEN** the observer MUST append an `observe` line with class `read_large_source` to telemetry
- **AND** the observer MUST NOT emit `additionalContext`

#### Scenario: Glob on broad inventory does not log

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Glob` with pattern `**/*.md` or `**/*.test.ts`
- **THEN** no observation MUST be logged

#### Scenario: Edit single-symbol diff in source logs observation

- **GIVEN** `serena=true` and a `.ts` file
- **WHEN** Claude calls `Edit` with `old_string=UserService` and `new_string=AccountService`
- **THEN** the observer MUST log an `observe` line with class `edit_symbol_token`

### Requirement: Follow-Through Correlator

The `serena-followthrough.sh` hook MUST run on PostToolUse for tools matching `^mcp__serena__` and append a `followup` record for each unmarked nudge or observation in the same session that occurred within 3 turns. Correlation MUST be idempotent: a `(turn, matcher)` pair already followed up MUST NOT generate a duplicate record. The correlator MUST NOT emit followups for errored Serena tool results.

#### Scenario: Serena call within 3 turns of nudge correlates

- **GIVEN** a `nudge` record at turn 5 in session token T
- **WHEN** `mcp__serena__find_symbol` returns successfully at turn 6 in session T
- **THEN** a `followup` line MUST be appended carrying the original matcher and the Serena tool name

#### Scenario: No double-correlation on repeat Serena calls

- **GIVEN** a `nudge` already correlated to a `followup` record
- **WHEN** another Serena tool call occurs in the same window
- **THEN** no additional `followup` line MUST be appended for the same `(turn, matcher)` pair

#### Scenario: Cross-session noise does not evict our window

- **GIVEN** a `nudge` for session T followed by 250 telemetry lines from concurrent sessions
- **WHEN** Serena tool returns for session T within 3 turns
- **THEN** the followup MUST still be appended (token-filter happens before line cap)

### Requirement: Subagent Guidance Propagation

The SessionStart Serena banner MUST instruct the parent context to propagate Serena guidance into Task spawn prompts. The instruction MUST be included only when `serena=true` and MUST name the propagated guidance string verbatim. The banner MUST NOT mention `mcp__serena__get_diagnostics_for_file`; the two-pole rule (LSP for diagnostics, Serena for navigation) is preserved.

#### Scenario: Banner instructs propagation when serena is enabled

- **GIVEN** `serena=true` in the session capabilities
- **WHEN** the SessionStart hook runs
- **THEN** the emitted `additionalContext` MUST mention `Task tool` and the literal string `Serena available`

#### Scenario: Banner does not surface third-pole diagnostics

- **WHEN** the SessionStart hook runs with `serena=true` and `lsp=true`
- **THEN** the emitted banner MUST mention `mcp__ide__getDiagnostics` for diagnostics
- **AND** the banner MUST NOT mention `get_diagnostics_for_file`

### Requirement: Telemetry Rolling-Window Report

The `scripts/serena-telemetry-report.sh` script MUST summarise per-class follow-through percentages over a rolling window (default 14 days). The report MUST include `firings`, `followups`, and `pct` columns for every observed class. Firings MUST be deduplicated by `(token, turn, class)` so multiple firings of the same class within a single turn count once — matching the follow-through correlator's `(turn, matcher)` idempotent dedup so the denominator is comparable to the numerator. When telemetry is empty or missing, the script MUST emit a recognisable empty-state message rather than fail.

#### Scenario: Per-class percentages are computed correctly

- **GIVEN** 10 `nudge` records (each in a distinct turn) and 5 `followup` records for class `word_boundary` within the window
- **WHEN** the report runs with `days=14`
- **THEN** the output MUST contain `word_boundary` with `50%` follow-through

#### Scenario: Per-turn firing dedup matches followthrough idempotency

- **GIVEN** two `nudge` records for class `word_boundary` in the same `(token, turn)` and one `followup`
- **WHEN** the report runs
- **THEN** `firings` for `word_boundary` MUST be `1`, not `2`, and `pct` MUST be `100%`

#### Scenario: Empty telemetry produces empty-state output

- **GIVEN** `~/.claude/.serena-nudge-telemetry` does not exist or is empty
- **WHEN** the report runs
- **THEN** the output MUST contain `no telemetry`

### Requirement: Glob Sequence-Aware Analysis

The `scripts/serena-glob-sequence-check.sh` script MUST classify each `glob_definition_hunt` observation in the rolling window as one of: `Serena followup` (a Serena MCP call within 3 turns of the same session), `Intervening Grep` (a Grep `nudge` within 3 turns without a Serena follow-up), or `revival signal` (neither). The script MUST emit per-bucket counts. When telemetry is empty or missing, the script MUST emit a recognisable empty-state message rather than fail.

#### Scenario: Glob followed by Serena counts as followup

- **GIVEN** an `observe glob_definition_hunt` at turn 10 in session `T` and a `followup glob_definition_hunt` at turn 11 in `T`
- **WHEN** the script runs
- **THEN** the followup bucket MUST count 1 and the revival bucket MUST count 0 for this observation

#### Scenario: Glob followed by Grep without Serena counts as intervening

- **GIVEN** an `observe glob_definition_hunt` at turn 20 in session `T` and a `nudge` at turn 22 in `T` with no follow-up
- **WHEN** the script runs
- **THEN** the intervening Grep bucket MUST count 1

#### Scenario: Glob with no follow-up activity counts as revival signal

- **GIVEN** an `observe glob_definition_hunt` at turn 30 in session `T` and no `nudge` or `followup` for it within 3 turns
- **WHEN** the script runs
- **THEN** the revival signal bucket MUST count 1

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

### Requirement: Fallback Registry Sync Gate

The test suite MUST include a regression that fails when `config/fallback-registry.json` diverges from a deterministic regeneration of `config/default-triggers.json`. The regeneration MUST use the same jq pipeline session-start uses to write the fallback (single source of truth for the fallback shape).

#### Scenario: Default-triggers edit forgets fallback regeneration

- **GIVEN** a contributor edits `config/default-triggers.json` to add or modify a trigger block
- **AND** does NOT regenerate `config/fallback-registry.json`
- **WHEN** `bash tests/test-registry.sh` runs the sync gate test
- **THEN** the test MUST fail with a unified diff showing the drift
- **AND** the failure message MUST reference how to regenerate

#### Scenario: jq is unavailable

- **GIVEN** the test environment has no `jq` binary on PATH
- **WHEN** the sync gate test runs
- **THEN** the test MUST skip (emit `SKIP`) and MUST NOT fail the test run

### Requirement: Per-Skill Iteration Cap With Role-Allowlist Invariant

Trigger blocks in `config/default-triggers.json` MAY declare an optional `max_iterations: N` field. The activation hook (`hooks/skill-activation-hook.sh::_score_skills`) MUST honor this cap by skipping a matched skill when its prior-completion count in the session's composition state is ≥ N. The cap MUST be honored ONLY for skills with `role: domain` or `role: required`. Skills with `role: process` or `role: workflow` MUST NEVER be capped, regardless of any `max_iterations` value in their trigger block. This role-allowlist invariant MUST be hardcoded in the activation hook (not config-driven) so that override files cannot silently widen it.

#### Scenario: Domain skill at cap is skipped

- **GIVEN** a skill with `role: domain` and `max_iterations: 1`
- **AND** the session composition state lists the skill once in `.completed`
- **WHEN** a subsequent prompt matches the skill's trigger
- **THEN** the activation hook MUST skip the skill (no entry in `RESULTS`)
- **AND** under `SKILL_EXPLAIN=1` MUST emit `[max-iter] skipping <skill> (<count> of <cap>)` to stderr

#### Scenario: Required skill at cap is skipped

- **GIVEN** a skill with `role: required` and `max_iterations: 1` (such as `agent-team-review`)
- **AND** the session composition state lists the skill once in `.completed`
- **WHEN** a subsequent prompt matches the skill's trigger
- **THEN** the activation hook MUST skip the skill

#### Scenario: Process skill bypasses cap regardless of config

- **GIVEN** a skill with `role: process` and `max_iterations: 1` (deliberate misconfiguration)
- **AND** the session composition state lists the skill once in `.completed`
- **WHEN** a subsequent prompt matches the skill's trigger
- **THEN** the activation hook MUST NOT skip the skill (role-allowlist invariant)
- **AND** the skill MUST appear normally in `RESULTS`

#### Scenario: Workflow skill bypasses cap regardless of config

- **GIVEN** a skill with `role: workflow` (such as `verification-before-completion`, `openspec-ship`, or `finishing-a-development-branch`) and `max_iterations: 1`
- **WHEN** a subsequent prompt matches the skill's trigger after prior completion
- **THEN** the activation hook MUST NOT skip the skill

#### Scenario: Sessionless invocation never caps

- **GIVEN** the activation hook runs without `_SESSION_TOKEN` set (test or dry run)
- **WHEN** any skill with `max_iterations` is matched
- **THEN** the cap check MUST be bypassed (no composition state to consult)

#### Scenario: Missing composition state file fails open

- **GIVEN** `_SESSION_TOKEN` is set but the composition state file does not exist
- **WHEN** a domain or required skill with `max_iterations` is matched
- **THEN** the cap check MUST be bypassed (no count available)
- **AND** the skill MUST be allowed to fire

#### Scenario: Push gate is independent of iteration cap

- **GIVEN** the iteration cap has skipped one or more advisory lenses on the current branch
- **WHEN** the contributor attempts `git push`
- **THEN** the push gate (`hooks/openspec-guard.sh`) MUST evaluate composition state independently
- **AND** the cap-skip event MUST NOT cause the push gate to allow an incomplete SHIP composition

### Requirement: Passive Advisory-Lens Telemetry

The Skill PostToolUse completion hook (`hooks/skill-completion-hook.sh`) MUST append one JSONL line per successful Skill completion to `~/.claude/.advisory-lens-log.jsonl`. The line MUST carry the fields `ts` (UTC ISO-8601 timestamp), `skill` (the bare skill name, namespace stripped), `finding_count_estimate` (line count of `tool_response.content` or `tool_response.output` as a coarse proxy, numeric), and `session_token_hashed` (sha256 of the session token, first 12 hex characters). Write failures MUST be silently dropped — the hook MUST exit 0 regardless of telemetry success.

#### Scenario: Successful Skill completion appends one line

- **GIVEN** a Skill tool returns successfully and the existing state-mutation block runs
- **WHEN** the telemetry block executes
- **THEN** exactly one JSONL line MUST be appended to `~/.claude/.advisory-lens-log.jsonl`
- **AND** the line MUST contain all four fields: `ts`, `skill`, `finding_count_estimate`, `session_token_hashed`

#### Scenario: Telemetry write failure does not propagate

- **GIVEN** `~/.claude/.advisory-lens-log.jsonl` is unwritable (e.g., disk full, permission denied)
- **WHEN** the telemetry block runs
- **THEN** the hook MUST exit 0
- **AND** the existing state-mutation work MUST NOT be undone

#### Scenario: Missing shasum and sha256sum binaries

- **GIVEN** neither `shasum` nor `sha256sum` is on PATH
- **WHEN** the telemetry block runs
- **THEN** the line MUST still be written
- **AND** `session_token_hashed` MUST be an empty string (not omitted)

#### Scenario: No labeling required

- **GIVEN** any Skill completion event
- **THEN** the telemetry line MUST NOT require any human label or counterfactual assertion (passive shape only)

