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

### Requirement: Serena First-Time MCP Auto-Registration

The session-start hook (`hooks/session-start-hook.sh`) MUST source `hooks/lib/serena-autoregister.sh` and invoke `serena_maybe_autoregister` immediately before the existing `context_capabilities` augmentation block. The library function MUST be fail-open (return 0 in every branch) and MUST be idempotent via a marker file at `${HOME}/.claude/.auto-claude-skills-serena-registered`. When all eligibility checks pass, the function MUST execute exactly:

```
claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false
```

The `--open-web-dashboard false` flag MUST be present in the registered command so Serena does NOT open a browser tab on each Claude Code session start. The plugin MUST NOT modify the user's global `~/.serena/serena_config.yml` — all dashboard-suppression behavior MUST be expressed at the per-MCP-server scope via the CLI flag.

#### Scenario: Fresh user with Serena installed and no MCP registration

- **GIVEN** `command -v serena` returns a path
- **AND** `command -v claude` returns a path
- **AND** `claude mcp list` does NOT contain a line beginning `serena: `
- **AND** `${HOME}/.claude/.auto-claude-skills-serena-registered` does NOT exist
- **WHEN** the user starts a Claude Code session in any project (outside `_SKILL_TEST_MODE=1`, OR with `_SKILL_TEST_AUTOREG=1` set)
- **THEN** `hooks/lib/serena-autoregister.sh::serena_maybe_autoregister` MUST run `claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false`
- **AND** the marker file MUST be written with a `<ISO timestamp>\t<PID>\tregistered` TSV line
- **AND** no browser tab MUST open for the Serena dashboard
- **AND** `~/.serena/serena_config.yml` MUST NOT be modified

#### Scenario: Marker file already exists

- **GIVEN** `${HOME}/.claude/.auto-claude-skills-serena-registered` exists (from a prior session)
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST return 0 immediately without invoking `claude mcp list` or `claude mcp add`

#### Scenario: Serena already registered in claude mcp list

- **GIVEN** `claude mcp list` contains a line matching `^serena: `
- **AND** the marker file does NOT exist
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST NOT invoke `claude mcp add` (idempotent — registration already present)
- **AND** the marker file MUST be written with status `already-registered`

#### Scenario: Serena binary not on PATH

- **GIVEN** `command -v serena` fails
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST return 0 immediately without invoking `claude mcp list` or `claude mcp add`
- **AND** the marker file MUST NOT be written

#### Scenario: Claude CLI not on PATH

- **GIVEN** `command -v serena` succeeds
- **AND** `command -v claude` fails
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST return 0 immediately without invoking any further commands
- **AND** the marker file MUST NOT be written

#### Scenario: claude mcp add exits non-zero

- **GIVEN** all eligibility checks pass
- **WHEN** `claude mcp add ...` exits with a non-zero status
- **THEN** the marker file MUST be written with status `register-failed` (to prevent every-session retries of a deterministically broken command)
- **AND** `${HOME}/.claude/.auto-claude-skills-serena-register-error` MUST be written with the captured stderr and exit code
- **AND** the function MUST still return 0 (fail-open invariant)

#### Scenario: SKILL_EXPLAIN breadcrumbs

- **GIVEN** `SKILL_EXPLAIN=1` is set in the environment
- **WHEN** `serena_maybe_autoregister` takes any code path other than the early marker-exists return
- **THEN** the function MUST emit exactly one line to stderr matching `^\[serena-autoregister\] (registered|already-registered|register-failed)` followed by a status message

#### Scenario: Test-mode default isolation

- **GIVEN** the session-start hook is invoked with `_SKILL_TEST_MODE=1` set
- **AND** `_SKILL_TEST_AUTOREG` is NOT set (or set to `0`)
- **WHEN** the hook reaches the auto-register wiring block
- **THEN** `serena_maybe_autoregister` MUST NOT be invoked
- **AND** no `claude mcp add` MUST execute
- **AND** no marker file MUST be written

#### Scenario: Test-mode opt-in via _SKILL_TEST_AUTOREG

- **GIVEN** `_SKILL_TEST_MODE=1` and `_SKILL_TEST_AUTOREG=1` are both set
- **WHEN** the hook reaches the auto-register wiring block
- **THEN** `serena_maybe_autoregister` MUST be invoked (per the standard eligibility checks)

### Requirement: Serena Auto-Register Library Bash Compatibility

`hooks/lib/serena-autoregister.sh` MUST be compatible with Bash 3.2 (macOS default `/bin/bash`). It MUST NOT use associative arrays, `[[` -only constructs without `[`-equivalents, or any features introduced in Bash 4+. It MUST NOT depend on `jq` — the library's parsing of `claude mcp list` output MUST use only `grep -F` / `grep -q` patterns.

#### Scenario: jq is unavailable

- **GIVEN** the host environment has no `jq` binary on PATH
- **WHEN** `serena_maybe_autoregister` is invoked
- **THEN** the function MUST proceed through all branches without invoking `jq`
- **AND** MUST return 0

### Requirement: Tolerant design-section heading recognition
The PLAN-phase DESIGN COMPLETENESS check MUST recognize each canonical design section by a tolerant heading match rather than an exact prefix match. A section MUST count as present when the design file contains a line beginning with two or three `#` characters followed by a space whose text contains the section's key words — case-insensitively, with each inter-word join accepting either a space or a hyphen, and with arbitrary prefix or suffix text on the heading line. Headings at h4 or deeper, body-text mentions of the section name, and headings indented with leading whitespace MUST NOT count as present.

#### Scenario: Real-world heading variants recognized
- **WHEN** the design file's three sections use variant headings such as `### Capabilities affected`, `## Out of Scope & Non-Goals`, and `## 🚫 Acceptance Scenarios`
- **THEN** the activation output MUST contain `DESIGN COMPLETENESS: all sections present`
- **AND** the activation output MUST NOT annotate any section with `(missing`

#### Scenario: Variant dimensions hold for every section pattern
- **WHEN** the variant dimensions are rotated across sections (e.g. `## 🚫 Capabilities Affected & Constraints`, `### out of scope`, `## Acceptance-Scenarios`)
- **THEN** the activation output MUST contain `DESIGN COMPLETENESS: all sections present`

#### Scenario: Non-heading mentions do not count
- **WHEN** a section name appears only as an h4 heading (`#### Out-of-Scope`) or in body text while the other two sections use canonical h2 headings
- **THEN** the activation output MUST annotate that section with `(missing`
- **AND** the activation output MUST NOT annotate the two present sections with `(missing`

### Requirement: Composition completed-array monotonicity
The UserPromptSubmit walker's composition-state write MUST NOT remove entries from `.completed` while the chain is unchanged. When a prior state file exists with a `.chain` equal to the newly built chain, the written `.completed` MUST be the union of the walker's computed prefix and the prior on-disk `.completed`, projected through the chain (chain order, no duplicates, entries not in the chain dropped). When the newly built chain differs from the prior `.chain`, the prior `.completed` MUST NOT leak into the new state. Missing, unreadable, or malformed prior state MUST degrade to the prefix-only write without failing the hook.

#### Scenario: Backward re-anchor preserves recorded progress
- **WHEN** the on-disk state records `.completed` through a later chain step and a prompt re-anchors at an earlier step of the same chain (e.g. a "pr"-matching prompt after verification already ran)
- **THEN** the written `.completed` MUST still contain every previously recorded entry
- **AND** the written `.chain` MUST be unchanged
- **AND** `current_index` MUST reflect the new anchor (the write MUST still happen)

#### Scenario: Chain switch resets completed
- **WHEN** the prompt anchors a chain different from the on-disk `.chain`
- **THEN** the written `.completed` MUST NOT contain entries carried over from the old chain

#### Scenario: Malformed prior state degrades to prefix-only
- **WHEN** the prior state file is missing, unreadable, or not valid JSON
- **THEN** the walker MUST write the prefix-derived `.completed` and exit zero

### Requirement: Workflow-Free Skill Descriptions
skill-scaffold MUST direct that skill descriptions (SKILL.md frontmatter and routing entry `description` fields) state what the skill is for and when to use it, and MUST NOT summarize the skill's workflow steps. A description containing process steps risks the agent following the summary instead of reading the full skill.

#### Scenario: Scaffold guidance includes the description rule
- **GIVEN** an agent uses skill-scaffold to seed a new skill
- **WHEN** it reads the SKILL.md skeleton and routing entry steps
- **THEN** both include the rule that descriptions state purpose and when-to-use, never workflow steps

### Requirement: Payload-First Session Token Resolution

Hooks that receive a stdin JSON payload MUST resolve the session token from
their own payload's `transcript_path` (as
`session-<basename of transcript_path without .jsonl>`) rather than reading
the shared singleton `~/.claude/.skill-session-token`. The singleton MUST be
used only as a fallback when the payload lacks `transcript_path` or jq is
unavailable, and remains the resolution source for consumers that have no
stdin payload. Resolution failures MUST fail open (empty token → the hook
skips its token-dependent behavior; it never blocks the user). The token
format MUST be defined in exactly one place (`hooks/lib/session-token.sh`)
and shared by the writer and all readers.

#### Scenario: Concurrent session overwrote the singleton

- **WHEN** session A's composition state (keyed to A's transcript-derived token) has an incomplete chain, the singleton contains session B's token, and `openspec-guard.sh` receives a `git push` PreToolUse payload carrying A's `transcript_path`
- **THEN** the gate evaluates A's composition state and denies the push; B's state is never consulted

#### Scenario: Gate allows when own chain is complete despite foreign singleton

- **WHEN** session A's chain is fully completed, the singleton contains session B's token whose chain is incomplete, and the guard receives a `git push` payload carrying A's `transcript_path`
- **THEN** the push is allowed

#### Scenario: Payload lacks transcript_path

- **WHEN** a converted hook receives a payload without `transcript_path`
- **THEN** it resolves the token by reading the singleton, preserving prior behavior

#### Scenario: Completion recorder keys to its own conversation

- **WHEN** the singleton contains a foreign token and `skill-completion-hook.sh` receives a successful chain-member Skill PostToolUse payload carrying this conversation's `transcript_path`
- **THEN** `.completed` advances in this conversation's state file, not the foreign one

#### Scenario: Activation hook re-stamps the singleton

- **WHEN** `skill-activation-hook.sh` resolves a payload-derived token that differs from the singleton's content
- **THEN** after routing, the singleton contains the resolved token, so no-payload SKILL.md consumers invoked later in the same turn read this conversation's token

### Requirement: Adversarial trigger-regex fixture coverage for collision-prone skills

Each collision-prone trigger-bearing skill (`incident-analysis`, `brainstorming`, `requesting-code-review`, `supply-chain-investigation`, `verification-before-completion`, `outcome-review`) MUST have a fixture file at `tests/fixtures/routing/<skill>.txt` containing at least 4 `MATCH:` and at least 2 `NO_MATCH:` directives. (The debate's original shortlist named `security-scanner` and `finishing-a-development-branch`; both are composition-routed with no trigger regexes, so regex fixtures are meaningless for them — they were substituted by their collision counterparts `verification-before-completion` and `outcome-review`.) Every `NO_MATCH:` prompt MUST be a near-miss: it contains at least one token adjacent to the skill's trigger alternation that the regex is required to reject. Fixtures MUST be validated by the existing `tests/test-regex-fixtures.sh` harness against the live `config/default-triggers.json`; the harness MUST NOT be duplicated. Skills without trigger regexes MUST NOT have fixture files.

#### Scenario: Near-miss prompt does not fire an adjacent skill

- GIVEN the `supply-chain-investigation` fixture file contains `NO_MATCH: upgrade the lodash dependency to the latest version`
- WHEN `tests/test-regex-fixtures.sh` runs
- THEN no `supply-chain-investigation` trigger regex matches the prompt
- AND the suite fails loudly if a future trigger edit makes it match

#### Scenario: Trigger drift in default-triggers.json is caught before merge

- GIVEN a fixture file with passing `MATCH:` directives for a skill
- WHEN a trigger regex for that skill is edited in `config/default-triggers.json` such that a `MATCH:` prompt no longer matches
- THEN `bash tests/run-tests.sh` reports the fixture failure (the harness is glob-discovered; no wiring step exists or is required)

### Requirement: Word-boundary anchoring for substring-prone trigger words

Bare short-word trigger alternatives that match inside common English words MUST carry word-boundary anchors. Leading-only anchoring (`(^|[^a-z])word`) is the default — it blocks prefix contamination while preserving suffix inflections; both-side anchoring is used only where the word is itself a prefix of a contaminating word (`mass` → "massive"). The anchored set, discovered via fixture authoring and a systematic sibling scan: `review` (requesting-code-review, agent-team-review, pr-review hint — blocks "preview"), `ship`/`tag`/`merge`/`release`/`ready.to`/`complete`/`finish` (verification-before-completion — blocks "relationship", "staging"/"untagged", "emerged"/"emergency", "prerelease", "already too", "incomplete", "unfinished"), `hang` (systematic-debugging — blocks "change"/"changelog"/"exchange"), `nits?` (receiving-code-review — blocks "unit"/"initialize"/"monitoring"/"definition"), `as.?built` (openspec-ship — blocks "was built"/"has built"), `set.?up` (brainstorming — blocks "asset upload"/"offset update"), `mass` both-side (batch-scripting — blocks "massive"), `continue` (executing-plans — blocks "discontinued"), `release` (deploy-gate — blocks "prerelease"), `merge` (github-mcp hint — blocks "emergency"). All anchored triggers MUST be identical in `config/default-triggers.json` and `config/fallback-registry.json` (fallback-drift gate). Every anchored skill trigger MUST be pinned by fixture regressions in `tests/fixtures/routing/` (the two hint anchors are structurally untestable by the harness, which reads `.skills[]` only). Genuine uses MUST keep matching (verified inflections include "re-review", "we shipped", "tagged", "merged", "completed", "finished", "hangs", "nitpicks", "as-built", "setup", "continue", "released").

#### Scenario: Embedded substring does not fire a process or workflow skill

- GIVEN the prompt "preview the deployment in staging"
- WHEN trigger scoring runs
- THEN `requesting-code-review` does not trigger
- AND given the prompt "the relationship between hooks and registry is unclear", `verification-before-completion` does not trigger

#### Scenario: Leading-boundary anchors preserve genuine matches

- GIVEN the prompts "please re-review the fix", "we shipped the fix", and "tag the release and publish the plugin"
- WHEN trigger scoring runs
- THEN `requesting-code-review` triggers on the first AND `verification-before-completion` triggers on the second and third

### Requirement: Informational measurable-bar advisory in PLAN-phase design-guard

When the PLAN-phase design-guard reads a readable design document, it MUST additionally grep the document body for numeric-threshold patterns (digits with unit or percent, `p50|p90|p95|p99`, `threshold`, or comparison operators). When no pattern is found, the guard MUST append exactly one informational `[i]` line suggesting a measurable bar. The line MUST NOT affect the design-completeness verdict, MUST NOT render as `[X]`, and MUST NOT block any transition. All failure modes (unreadable file, grep error, missing state) MUST fail open. `SKILL_EXPLAIN=1` SHOULD emit a `[design-guard] bar=<0|1>` breadcrumb to stderr.

#### Scenario: Design doc without numeric bar gets the [i] line only

- GIVEN an active change whose `design_path` points to a readable design doc containing all three required headings but no numeric-threshold pattern
- WHEN the activation hook runs in PLAN phase
- THEN the DESIGN COMPLETENESS output reports all sections present AND includes one `[i]` measurable-bar line
- AND the hook exits 0 with no blocking action

#### Scenario: Organically numeric design doc stays quiet

- GIVEN a design doc containing `p95 < 200ms` or `>= 80%` in its body
- WHEN the activation hook runs in PLAN phase
- THEN no `[i]` measurable-bar line appears in the output

#### Scenario: Grep failure cannot block the hook

- GIVEN the numeric-bar grep errors for any reason
- WHEN the activation hook runs in PLAN phase
- THEN the completeness verdict is unchanged, the worst-case effect is the advisory `[i]` line appearing, AND the hook exits 0

### Requirement: Vertical-slice decomposition hint in PLAN-phase composition

The PLAN-phase composition MUST emit an advisory hint steering work decomposition toward thin end-to-end vertical slices (each task touching all layers and independently testable) over file-disjoint horizontal layers, and SHOULD direct that tasks sized for `agent-team-execution` be sliced by behavior rather than by file. The hint MUST be present and byte-identical in both `config/default-triggers.json` and `config/fallback-registry.json` (fallback-drift gate). The hint MUST be advisory only: it MUST NOT alter the design-completeness verdict, role caps, composition state, or any push/transition gate. The hint MUST be independent of the spec-driven session-start rewrite — its text MUST NOT contain the `CARRY SCENARIOS` token that keys that transform — so it survives unchanged in both default and spec-driven presets.

#### Scenario: PLAN-phase prompt receives the vertical-slice hint

- GIVEN a session whose primary phase resolves to PLAN
- WHEN the activation hook emits PLAN-phase composition hints
- THEN a hint steering toward thin end-to-end vertical slices over file-disjoint horizontal layers is present in the output

#### Scenario: Hint stays in sync across both registries

- GIVEN the PLAN composition hints in `config/default-triggers.json`
- WHEN compared against `config/fallback-registry.json`
- THEN the vertical-slice hint text is present and identical in both files

#### Scenario: Spec-driven rewrite leaves the hint untouched

- GIVEN the repo preset is `spec-driven`
- WHEN session-start rewrites the PLAN hint whose text matches `CARRY SCENARIOS`
- THEN the vertical-slice hint is not matched by that transform and passes through unchanged

### Requirement: Hint-path triggers must self-anchor against substring mis-fires

Triggers evaluated on the hint path (`hooks/skill-activation-hook.sh` raw `[[ "$P" =~ $htrigger ]]`) are NOT covered by the scorer's word-boundary post-filter and therefore MUST anchor their own alternations. Anchoring MUST use POSIX-ERE bracket-class boundaries `(^|[^a-z])…([^a-z]|$)` and MUST NOT use `\b`, `\d`, `(?:…)`, or other PCRE constructs, which silently fail to match under Bash 3.2. The `frontend-playwright` trigger specifically MUST NOT fire on backend prompts whose words merely contain a frontend fragment as a substring.

#### Scenario: Backend prompt does not trigger the Playwright mandate
- **GIVEN** a pure-backend prompt such as "tabulate the metrics", "update onboarding docs", or "paginate the results"
- **WHEN** the activation hook evaluates the `frontend-playwright` trigger under `/bin/bash` (3.2)
- **THEN** the trigger MUST NOT match
- **AND** no Playwright/frontend validation mandate MUST be emitted

#### Scenario: Genuine frontend prompt still triggers
- **GIVEN** a frontend prompt such as "the button component", "fix the navbar", or "make the layout responsive"
- **WHEN** the activation hook evaluates the `frontend-playwright` trigger under `/bin/bash` (3.2)
- **THEN** the trigger MUST match
- **AND** the Playwright/frontend hint MUST be emitted

#### Scenario: Anchored regex compiles under Bash 3.2
- **GIVEN** the anchored `frontend-playwright` trigger expression
- **WHEN** the regex-compilation test in `tests/test-routing.sh` runs under `/bin/bash`
- **THEN** the expression MUST compile (exit code not 2) and MUST be present identically in both `config/default-triggers.json` and `config/fallback-registry.json`

### Requirement: SHIP-phase no-work advisory

When the activation hook derives `PRIMARY_PHASE == SHIP`, it MUST emit an advisory `PHASE REALITY:` line if the repository shows no committed work — specifically when `git rev-list --count origin/main..HEAD` is `0` AND `git status --porcelain` is empty. The advisory MUST be informational (`[i]`), MUST NOT block, and MUST be appended to the activation context (the same channel as the design-guard advisory). The check MUST be gated to SHIP only (it MUST NOT run at REVIEW or any other phase). The check MUST fail open: if the commit count is non-numeric (detached HEAD, no `origin/main`, fresh clone, or any git error) OR the working tree is dirty OR commits exist ahead of `origin/main`, the hook MUST emit no advisory line and MUST NOT error.

#### Scenario: SHIP claimed with no committed work
- **GIVEN** a git repository on a branch with 0 commits ahead of `origin/main` and a clean working tree
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the activation output MUST contain a `PHASE REALITY:` advisory noting no committed work exists
- **AND** the hook MUST NOT block or deny anything

#### Scenario: Silent when committed work exists
- **GIVEN** a git repository with at least one commit ahead of `origin/main` OR a non-empty `git status --porcelain`
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the no-work advisory MUST NOT be emitted

#### Scenario: Fail-open when origin/main is unresolvable
- **GIVEN** a detached HEAD, a repository with no `origin/main` ref, or any git error resolving the commit count
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the no-work advisory MUST NOT be emitted and the hook MUST exit normally (routing proceeds unaffected)

### Requirement: SHIP-phase REVIEW-skip advisory

When the activation hook derives `PRIMARY_PHASE == SHIP` and a composition state file exists for the session whose `.chain` contains `requesting-code-review` but whose `.completed` does not, the hook MUST emit an advisory `PHASE REALITY:` line noting that REVIEW has not completed before SHIP. The advisory MUST be informational (`[i]`) and MUST NOT block. The rule MUST be self-scoping: it MUST check `.chain` membership so that chains which never included `requesting-code-review` do not fire. The check MUST fail open: a missing state file, malformed JSON, missing jq, or stale/foreign composition state MUST result in no advisory line. Because composition state is only written for multi-skill chains, this rule is SILENT when no chain exists — that case is covered by the no-work advisory, and the implementation MUST document this so it is not mistaken for a bug.

#### Scenario: SHIP claimed but chain skipped REVIEW
- **GIVEN** a composition state file whose `.chain` includes `requesting-code-review` and whose `.completed` does not include it
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the activation output MUST contain a `PHASE REALITY:` advisory noting REVIEW has not completed
- **AND** the hook MUST NOT block

#### Scenario: Silent with no active chain
- **GIVEN** no composition state file exists for the session (single-skill or no-skill prompt)
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the REVIEW-skip advisory MUST NOT be emitted (the no-work advisory may still fire independently)

#### Scenario: Silent at non-SHIP phases
- **GIVEN** any `PRIMARY_PHASE` other than SHIP (e.g. REVIEW, IMPLEMENT, DESIGN)
- **WHEN** the activation hook runs
- **THEN** neither phase-reality advisory MUST be emitted and no git or composition-state checks for this feature MUST run

### Requirement: Atlassian MCP availability detection

The session-start hook MUST set the `atlassian` plugin's `.available` flag to `true` when an `atlassian` MCP server is present in either the user-scoped `mcpServers` or the current-project-scoped `projects[<workspace>].mcpServers` of `~/.claude.json`. The detection MUST NOT add `atlassian` to the context-capability set (`_CANONICAL_CAP_KEYS`) — it is a plugin-availability flag, not a context capability. The detection MUST fail open: a missing `~/.claude.json`, missing jq, or any jq error MUST leave `atlassian.available` unchanged (false) and MUST NOT abort the hook.

#### Scenario: Atlassian MCP server present
- **GIVEN** a `~/.claude.json` whose `mcpServers` (or current-project `mcpServers`) contains an `atlassian` key
- **WHEN** the session-start hook builds the registry
- **THEN** the registry cache `.plugins[]` entry named `atlassian` MUST have `available == true`

#### Scenario: No Atlassian MCP server
- **GIVEN** a `~/.claude.json` with no `atlassian` entry in any `mcpServers` scope
- **WHEN** the session-start hook builds the registry
- **THEN** the `atlassian` plugin's `available` MUST remain `false`

#### Scenario: Fail-open on unreadable config
- **GIVEN** a missing or unreadable `~/.claude.json`, or jq unavailable
- **WHEN** the session-start hook builds the registry
- **THEN** the `atlassian` plugin's `available` MUST remain `false` and the hook MUST complete normally

### Requirement: Jira branch-naming advisory hint

When the `atlassian` plugin is available AND the lowercased prompt contains a Jira-ID-shaped token matching `(^|[^a-z0-9])[a-z][a-z0-9]+-[0-9]+($|[^a-z0-9])`, the activation hook MUST emit an advisory hint instructing that the working branch be named `<type>/<JIRA-ID>` using the ticket's exact uppercase ID. The hint MUST be advisory (it MUST NOT block) and MUST be suppressed entirely when the `atlassian` plugin is unavailable. The trigger MUST self-anchor (it MUST NOT rely on `\b`, which is unavailable under Bash 3.2 ERE), because methodology-hint triggers bypass the scorer word-boundary post-filter.

#### Scenario: Jira ID mentioned with Atlassian available
- **GIVEN** the `atlassian` plugin is available
- **WHEN** a prompt contains a Jira-ID-shaped token (e.g. `PROJ-123`)
- **THEN** the activation output MUST contain the branch-naming advisory

#### Scenario: Suppressed without Atlassian
- **GIVEN** the `atlassian` plugin is unavailable
- **WHEN** a prompt contains a Jira-ID-shaped token
- **THEN** the branch-naming advisory MUST NOT be emitted

### Requirement: Jira PR-title advisory hint at SHIP

When the `atlassian` plugin is available AND `PRIMARY_PHASE == SHIP`, the activation hook MUST emit an advisory hint instructing that the Jira ID be derived from the branch name and the PR be titled `<JIRA-ID>: <exact ticket subject>`, with the subject fetched via the Atlassian MCP, and that the step be skipped (no fabricated ID) when no Jira ID is present. The hint MUST be advisory (it MUST NOT block) and MUST be suppressed when the `atlassian` plugin is unavailable.

#### Scenario: SHIP phase with Atlassian available
- **GIVEN** the `atlassian` plugin is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the activation output MUST contain the PR-title advisory (text including `JIRA PR TITLE`)

#### Scenario: Suppressed without Atlassian at SHIP
- **GIVEN** the `atlassian` plugin is unavailable
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP`
- **THEN** the PR-title advisory MUST NOT be emitted

### Requirement: Phase-scoped lethal-trifecta surfacing

The activation hook MUST surface `agent-safety-review` as a model-assessed candidate at
the `DESIGN` phase independently of the user typing an autonomy/agent keyword, because
the lethal trifecta (private_data × untrusted_input × outbound_action) is a semantic
property of a design's data flow that the skill's lexical triggers cannot reliably match.

The surfacing MUST be implemented through the existing `phase_compositions[PHASE].hints`
mechanism (a single advisory line), NOT as an unconditional session banner and NOT by
widening `agent-safety-review`'s regex triggers. The DESIGN hint MUST instruct the model
to classify each trifecta field as Present/Absent/Unknown from the proposed data flow and
to invoke `Skill(auto-claude-skills:agent-safety-review)` only if **2 or more fields are
Present, or Unknowns could make the count reach 2 or more** — matching the skill's own
Step 2 risk table (2-of-3 = Elevated, 3 = Lethal; 0-1 = Standard, no action). The hint
MUST scope invocation to **after brainstorming has a candidate design and before
transitioning to PLAN**, so it does not conflict with the brainstorming-first gate.

The REVIEW `ADVERSARIAL REVIEW` hint MUST additionally route to
`agent-safety-review` when the **resulting** change has ≥2 trifecta fields, or when the
diff adds a missing leg to an existing ≥2-field flow — not only when a change weakens an
existing safety gate.

The hint text MUST contain the literal `Skill(auto-claude-skills:agent-safety-review)`
invocation so the model can act on it. `config/fallback-registry.json` MUST stay in sync
with `config/default-triggers.json` for these hints (enforced by the existing Fallback
Registry Sync Gate). The pre-existing `agent-safety-review` keyword triggers MUST
continue to work unchanged. The hints are advisory and MUST fail open (they never block
the hook and never auto-invoke a skill or auto-write any artifact).

#### Scenario: DESIGN phase surfaces the trifecta directive without keywords

- **GIVEN** a registry whose `DESIGN` driver (`brainstorming`) is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == DESIGN` with no autonomy/agent keyword (e.g. "build something that reads customer support emails and posts replies to Slack")
- **THEN** the activation context MUST contain a `TRIFECTA CHECK` hint carrying the literal `Skill(auto-claude-skills:agent-safety-review)`

#### Scenario: Trifecta directive present even on a generic build prompt

- **GIVEN** a registry whose `DESIGN` driver is available
- **WHEN** any prompt routes to `PRIMARY_PHASE == DESIGN` (e.g. "let's add a new feature")
- **THEN** the activation context MUST contain the `TRIFECTA CHECK` hint (always-on; the model decides whether to act on it)

#### Scenario: Directive absent outside its gate phases

- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP` (e.g. "ship the release and wrap up")
- **THEN** the activation context MUST NOT contain the `TRIFECTA CHECK` hint

#### Scenario: REVIEW adversarial hint covers trifecta introduction

- **GIVEN** a registry whose `REVIEW` phase composition is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == REVIEW` (e.g. "review my changes before merge")
- **THEN** the activation context's `ADVERSARIAL REVIEW` hint MUST reference `Skill(auto-claude-skills:agent-safety-review)` for resulting ≥2-field trifecta flows

#### Scenario: agent-safety-review keyword fast-path still works

- **WHEN** a prompt matches an existing `agent-safety-review` trigger token (e.g. "an overnight unattended email agent")
- **THEN** `agent-safety-review` MUST still be selected by its regex triggers as before, independently of the DESIGN hint

### Requirement: Phase-scoped capture-knowledge surfacing

The activation hook MUST surface `capture-knowledge` as a model-assessed candidate at
the SDLC phases where durable team learnings emerge — `LEARN`, `SHIP`, and `DEBUG` —
independently of the user typing a capture keyword. The surfacing MUST be implemented
through the existing `phase_compositions[PHASE].hints` mechanism (a single advisory
line per phase), NOT as an unconditional session banner and NOT by widening the skill's
regex triggers. Each hint MUST carry an explicit relevance gate that instructs the model
to invoke `Skill(auto-claude-skills:capture-knowledge)` only if a durable, non-obvious,
team-relevant learning emerged and to skip otherwise (routine or repo-derivable facts).
The existing human approval at write time MUST remain the safety gate; this requirement
adds a *when-to-consider* signal only and MUST NOT introduce any autonomous write. The
hint text MUST contain the literal `Skill(auto-claude-skills:capture-knowledge)`
invocation so the model can act on it. `config/fallback-registry.json` MUST stay in sync
with `config/default-triggers.json` for these hints (enforced by the existing Fallback
Registry Sync Gate). The pre-existing capture-keyword trigger MUST continue to work.

#### Scenario: LEARN phase surfaces capture-knowledge without keywords

- **GIVEN** a registry whose `LEARN` driver (`outcome-review`) is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == LEARN` with no capture/save/remember keyword (e.g. "how did the auth feature perform after launch")
- **THEN** the activation context MUST contain `Skill(auto-claude-skills:capture-knowledge)` carried by a relevance-gated `CAPTURE KNOWLEDGE` hint

#### Scenario: SHIP phase surfaces capture-knowledge without keywords

- **GIVEN** a registry whose `SHIP` driver (`verification-before-completion`) is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP` with no capture keyword (e.g. "wrap up the auth module and ship the release")
- **THEN** the activation context MUST contain `Skill(auto-claude-skills:capture-knowledge)`

#### Scenario: DEBUG phase surfaces capture-knowledge without keywords

- **GIVEN** a registry whose `DEBUG` driver (`systematic-debugging`) is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == DEBUG` with no capture keyword (e.g. "debug the broken auth login error")
- **THEN** the activation context MUST contain `Skill(auto-claude-skills:capture-knowledge)` via a post-resolution `CAPTURE KNOWLEDGE` hint

#### Scenario: Not an unconditional banner

- **GIVEN** any phase other than LEARN, SHIP, or DEBUG (e.g. DESIGN, PLAN, IMPLEMENT, REVIEW)
- **WHEN** a prompt routes to that phase with no capture keyword
- **THEN** the `CAPTURE KNOWLEDGE` phase hint MUST NOT be emitted (surfacing is phase-scoped, not global)

### Requirement: Push-gate readiness survives composition chain re-anchors

The push gate SHALL determine whether a gating milestone (`requesting-code-review`,
`verification-before-completion`) is satisfied from **either** a durable per-(repo+branch) milestone
ledger **or** the transient composition `.completed`. A genuinely-completed milestone MUST remain
satisfied across a composition chain re-anchor (a later prompt detecting a different phase) within
the same repo+branch. The gate SHALL deny a push only when a gating milestone is present in the
active chain and **neither** source records it. The `.completed` state and its writers MUST be
left unchanged by this mechanism.

#### Scenario: Chain re-anchor does not re-block a reviewed+verified branch

- **GIVEN** `requesting-code-review` and `verification-before-completion` completed on the current branch (recorded in the ledger)
- **AND** a subsequent prompt re-anchors the composition chain so `.completed` no longer lists them
- **WHEN** the user pushes
- **THEN** the push gate MUST NOT deny on the missing gating milestones (the ledger satisfies them)

#### Scenario: A new branch must re-earn the milestones

- **GIVEN** the milestones are recorded for branch `feature/a`
- **AND** the working tree is now on a different branch `feature/b` with no ledger entries
- **WHEN** a composition chain on `feature/b` contains the gating milestones and the user pushes
- **THEN** the push gate MUST deny until the milestones are completed on `feature/b`

#### Scenario: In-flight session without a ledger falls back to `.completed`

- **GIVEN** no milestone ledger exists for the current repo+branch (e.g. a session predating this feature)
- **AND** `.completed` lists the gating milestones
- **WHEN** the user pushes
- **THEN** the push gate MUST accept (the `.completed` path is preserved, no regression)

### Requirement: Branch ledger is repo-scoped and isolated

The milestone ledger SHALL be keyed by a **repo+branch** identity (not branch name alone), and a
detached HEAD SHALL form its own boundary. A same-named branch in a different repository or worktree
MUST NOT inherit another repo's recorded milestones. If the repo+branch identity cannot be
determined, the gate SHALL fall back to the `.completed`-only check rather than failing open.

#### Scenario: Same branch name in a different repo does not inherit milestones

- **GIVEN** milestones recorded for branch `main` in repo X
- **WHEN** the gate evaluates a push for branch `main` in a different repo Y
- **THEN** repo Y's gate MUST NOT treat repo X's milestones as satisfying repo Y's gate

### Requirement: HEAD advancement past a recorded milestone emits a soft warning

The gate MUST emit an advisory staleness warning, and MUST NOT deny on that basis, when it is
satisfied via the ledger but the recorded HEAD sha differs from the current HEAD. The warning MUST
name both the recorded sha and the current sha.

#### Scenario: New commits after review warn but do not block

- **GIVEN** `requesting-code-review` was recorded at sha `A` on the current branch
- **AND** the current HEAD is `B` (commits added since)
- **WHEN** the user pushes
- **THEN** the gate MUST emit a staleness warning referencing `A` and `B`
- **AND** the gate MUST NOT deny the push solely because HEAD advanced

### Requirement: Verdict artifact SHA freshness

The owned verification verdict artifact `~/.claude/.skill-project-verified-<token>` MUST record a `sha` field equal to `git rev-parse HEAD` at the time `project-verification` writes it, and the push gate MUST honor a verdict only when that `sha` covers the pushed HEAD (equals HEAD, or is an ancestor of HEAD on the current branch). A verdict whose `sha` is absent or does not cover HEAD MUST be treated as if no verdict were present, falling back to the status-layer behavior.

#### Scenario: Verdict covers the pushed HEAD
- **GIVEN** `~/.claude/.skill-project-verified-<token>` records `sha` equal to the current HEAD
- **WHEN** the push gate evaluates the verdict
- **THEN** the verdict MUST be honored (its clean/failed status governs)

#### Scenario: Stale or cross-branch verdict is ignored, never denies
- **GIVEN** a verdict artifact whose `sha` is absent, or names a commit that is not HEAD and not an ancestor of HEAD on the current branch
- **WHEN** the push gate evaluates the verdict
- **THEN** the verdict MUST NOT cause a denial
- **AND** the gate MUST fall back to the existing status-layer (`.completed` OR branch-ledger) behavior

### Requirement: Verify-verdict hardening

The push gate MUST deny `git push` when a verification verdict **at HEAD** (its `sha` equals HEAD) reports a test failure — `failed[]` non-empty — even if the status layer records `verification-before-completion` as completed. Only positive test-failure evidence at the exact pushed commit denies: a `could_not_verify[]` entry and a `suspect` gate-gaming status remain advisory and MUST NOT hard-block, and a failing verdict that is merely an ancestor of HEAD (a later commit may be fixed) MUST NOT deny. When no such verdict is present, the gate MUST preserve its status-only behavior and MUST NOT introduce a new denial.

#### Scenario: Failing verification at HEAD blocks the push despite recorded status
- **GIVEN** the status layer records `verification-before-completion` as completed
- **AND** a verdict whose `sha` equals HEAD reports `failed` containing `tests`
- **WHEN** `git push` is attempted
- **THEN** the gate MUST deny and name the failing gate (`tests`)

#### Scenario: Ancestor failing verdict does not block a later HEAD
- **GIVEN** a failing verdict whose `sha` is an ancestor of HEAD (HEAD advanced past it)
- **WHEN** `git push` is attempted
- **THEN** the gate MUST NOT deny on verdict grounds (the failure is authoritative only for the commit it was measured at)

#### Scenario: Absent verdict preserves status behavior
- **GIVEN** no verdict artifact exists for the session
- **AND** the status layer records `verification-before-completion` as completed
- **WHEN** `git push` is attempted
- **THEN** the gate MUST NOT deny on verdict grounds

### Requirement: Routing-governance push gate

In a skill-routing plugin repository (detected by the presence of `config/default-triggers.json`), when the pushed diff touches routing paths (`skills/`, `config/`, or `hooks/`), the push gate MUST require a clean verdict that covers the pushed routing changes: either a clean verdict at HEAD, or a clean verdict at an ancestor whose routing files are unchanged since. The gate MUST deny with a `project-verification` remedy when no clean verdict covers HEAD, or when a clean verdict is an ancestor but routing files changed after it (an unverified routing delta). A clean ancestor verdict with no routing change since MUST warn (advisory) rather than deny. This gate MUST fire independent of an active composition chain. Repositories without `config/default-triggers.json` MUST NOT be subject to this gate.

#### Scenario: Routing change without a clean verdict is denied
- **GIVEN** the repository contains `config/default-triggers.json`
- **AND** the pushed diff modifies a file under `hooks/`
- **AND** no clean verdict covering the branch exists
- **WHEN** `git push` is attempted
- **THEN** the gate MUST deny and instruct the user to run `Skill(auto-claude-skills:project-verification)`

#### Scenario: Routing change with a clean covering verdict is allowed
- **GIVEN** the repository contains `config/default-triggers.json`
- **AND** the pushed diff modifies a file under `config/`
- **AND** a clean verdict covering HEAD exists
- **WHEN** `git push` is attempted
- **THEN** the gate MUST allow the push

#### Scenario: Routing changed after an ancestor verdict is denied
- **GIVEN** the repository contains `config/default-triggers.json`
- **AND** a clean verdict exists whose `sha` is an ancestor of HEAD
- **AND** a routing file (`skills/`, `config/`, or `hooks/`) changed in a commit after that `sha`
- **WHEN** `git push` is attempted
- **THEN** the gate MUST deny (the routing delta is unverified) and instruct the user to run `Skill(auto-claude-skills:project-verification)`

#### Scenario: Non-routing repository is unaffected
- **GIVEN** the repository does not contain `config/default-triggers.json`
- **AND** the pushed diff modifies a file under `skills/`
- **WHEN** `git push` is attempted
- **THEN** the routing-governance gate MUST NOT deny the push

### Requirement: Review milestone remains status-only

The push gate MUST NOT derive a pass/fail verdict for `requesting-code-review` from the skill's return text or any model-attested signal. The review milestone MUST remain governed by the status layer only.

#### Scenario: Review is not verdict-gated
- **GIVEN** `requesting-code-review` has returned and is recorded in the status layer
- **WHEN** the push gate evaluates review readiness
- **THEN** the gate MUST rely on the status layer alone and MUST NOT parse review output for a verdict

### Requirement: Advisory routing to external frontend-quality skills

The routing config SHALL include a `frontend-quality-rules` methodology hint that advises using the
external Vercel frontend-quality skills when they are installed, without gating on a `.plugin`
field and without emitting a hardcoded `Skill(<plugin>:<skill>)` invocation token. The hint SHALL
name our own `frontend-design` and `runtime-validation` skills as the fallback. React/Next-specific
guidance (`react-best-practices`) SHALL be offered only on React/Next signals; framework-agnostic
guidance (`web-interface-guidelines`) MAY be offered on general frontend signals. The hint SHALL
fire in the `IMPLEMENT` and `REVIEW` phases, and its triggers SHALL self-anchor word boundaries
`(^|[^a-z])…($|[^a-z])`.

#### Scenario: Hint surfaces on a React frontend prompt in IMPLEMENT

- **GIVEN** a session in the `IMPLEMENT` phase
- **WHEN** the user prompt matches a React/Next frontend signal (e.g. "add a React component")
- **THEN** the routing context SHALL include the `frontend-quality-rules` advisory hint text
- **AND** the hint SHALL reference `react-best-practices` and name `frontend-design` /
  `runtime-validation` as the fallback

#### Scenario: Hint does not hardcode an unknowable invocation token

- **GIVEN** the `frontend-quality-rules` hint definition in `config/default-triggers.json`
- **WHEN** the hint text is inspected
- **THEN** it SHALL NOT contain a literal `Skill(` invocation for the external Vercel skills
- **AND** it SHALL phrase the reference conditionally ("if installed")

#### Scenario: Config is mirrored to the fallback registry

- **GIVEN** the `frontend-quality-rules` hint added to `config/default-triggers.json`
- **WHEN** the fallback registry is regenerated
- **THEN** `config/fallback-registry.json` SHALL contain the same hint, keeping the two files in sync

### Requirement: frontend-playwright hint fires in REVIEW

The `frontend-playwright` methodology hint SHALL include `REVIEW` in its `phases` so that its
"During REVIEW, use runtime-validation" guidance can fire in the REVIEW phase.

#### Scenario: frontend-playwright surfaces in REVIEW

- **GIVEN** a session in the `REVIEW` phase
- **WHEN** the user prompt matches a frontend signal (e.g. "review the login form")
- **THEN** the routing context SHALL include the `frontend-playwright` hint text

### Requirement: runtime-validation routes on visual-regression terms

The `runtime-validation` skill triggers SHALL match `visual regression`, `layout regression`, and
`screenshot` terms, without matching unrelated substrings (e.g. `tabulate`, `onboarding`).

#### Scenario: Visual-regression prompt routes to runtime-validation

- **GIVEN** a session in the `REVIEW` phase
- **WHEN** the user prompt contains "visual regression" or "screenshot" in a validation context
- **THEN** `runtime-validation` SHALL be surfaced in the routing context

#### Scenario: Negative terms do not false-trigger

- **GIVEN** the `runtime-validation` trigger regex
- **WHEN** matched against `tabulate the results` or `user onboarding flow`
- **THEN** the visual-regression terms SHALL NOT match those substrings

### Requirement: Evidence-gated local-override hint at session start

The session-start hook SHALL append a single advisory banner line pointing to the local override mechanism (`~/.claude/skill-config.json`, the zero-match log, and `SKILL_EXPLAIN=1`) when and only when the previous session recorded at least 5 zero-match prompts, at least 8 total prompts, and a zero-match rate of at least 30%. The hint MUST be suppressed when a cooldown marker younger than 7 days exists, or when the user's `skill-config.json` already contains per-skill overrides. Emitting the hint SHALL touch the cooldown marker. Every failure mode (unreadable or non-numeric counters, jq absent or erroring, marker operations failing) MUST suppress the hint without affecting the rest of the banner (fail-open).

#### Scenario: High miss rate fires the hint once

- GIVEN the previous session recorded 5 zero-matches across 10 prompts
- AND no cooldown marker exists and `skill-config.json` has no per-skill overrides
- WHEN the session-start hook runs
- THEN the banner SHALL contain one routing-hint line naming 5, 10, and the rate
- AND the cooldown marker SHALL exist afterwards

#### Scenario: Chatty session does not fire

- GIVEN the previous session recorded 5 zero-matches across 50 prompts (10%)
- WHEN the session-start hook runs
- THEN the banner SHALL NOT contain a routing-hint line

#### Scenario: Existing overrides suppress the hint

- GIVEN qualifying friction evidence AND `skill-config.json` containing at least one per-skill override
- WHEN the session-start hook runs
- THEN the banner SHALL NOT contain a routing-hint line

#### Scenario: Fresh cooldown suppresses the hint

- GIVEN qualifying friction evidence AND a cooldown marker touched less than 7 days ago
- WHEN the session-start hook runs
- THEN the banner SHALL NOT contain a routing-hint line
- AND the marker's mtime SHALL be unchanged

### Requirement: Global Fail-Closed Push Gate

The push gate MUST fire for every agent-attempted `git push`, independent of any
active composition chain, and MUST deny the push unless the branch carries **both**
a durable `requesting-code-review` record **and** a passing
`verification-before-completion` signal (a branch-ledger milestone, a session-local
`.completed` fallback, or a SHA-bound clean verification verdict covering HEAD).

The gate MUST be fail-open on infrastructure error: it runs only when the branch-ledger
library loaded AND `jq` is available, because every evidence leg is jq-dependent;
absent either, no push is denied. Only a check that runs and finds no record MUST deny.

The bypass `ACSM_SKIP_PUSH_GATE=1` MUST be honored only as an environment variable in
the hook's own process (human-set at Claude Code launch). The gate MUST NOT scan the
push command string for the bypass token, because the agent composes that string and
a command-string scan would be an agent-forgeable bypass.

#### Scenario: Non-driven session push with no records is denied
- **WHEN** an agent runs `git push` on a branch with no composition state, no ledger
  review record, and no verify signal
- **THEN** the gate MUST deny the push and name the missing `requesting-code-review`
  and/or `verification-before-completion` gate

#### Scenario: Review present but verify missing is denied
- **WHEN** an agent runs `git push` on a branch whose ledger records
  `requesting-code-review` but has no passing verify signal
- **THEN** the gate MUST deny the push and name the missing
  `verification-before-completion` gate

#### Scenario: Inline bypass token is not honored
- **WHEN** an agent runs `ACSM_SKIP_PUSH_GATE=1 git push` (the token inline in the
  command string) on a branch missing a required record
- **THEN** the gate MUST still deny the push (the inline token MUST NOT bypass it)

#### Scenario: Human-set env var bypasses the gate
- **WHEN** `ACSM_SKIP_PUSH_GATE=1` is exported in the hook's process environment
- **THEN** the gate MUST skip all push-gate denials

#### Scenario: Missing jq falls open
- **WHEN** an agent runs `git push` on a branch that would be denied with `jq` present,
  but `jq` is not on PATH
- **THEN** the gate MUST NOT deny the push (fail-open, "jq optional at runtime")

### Requirement: Acceptance Scenarios body check in the PLAN-phase design guard

The DESIGN COMPLETENESS check in `hooks/skill-activation-hook.sh` SHALL, when the Acceptance Scenarios heading is present in the design file, count GIVEN/WHEN/THEN triplets within that section (case-sensitive uppercase tokens, section scoped from the heading to the next h2/h3) and mark the Acceptance Scenarios line `[OK]` only when `min(GIVEN, WHEN, THEN) >= 2`. The check SHALL remain advisory-only (never denies) and SHALL fail open to heading-presence semantics on any extraction error.

#### Scenario: Contract satisfied

- GIVEN a design file whose Acceptance Scenarios section contains at least 2 GIVEN/WHEN/THEN scenarios
- WHEN the PLAN-phase design guard runs
- THEN the Acceptance Scenarios line renders `[OK]`

#### Scenario: Empty or thin heading

- GIVEN a design file with an Acceptance Scenarios heading but fewer than 2 uppercase GIVEN/WHEN/THEN triplets in its section body
- WHEN the guard runs
- THEN the line renders `[X]` with a "heading present but <2 GIVEN/WHEN/THEN scenarios" message, and the hook exit remains advisory (no deny)

#### Scenario: Tokens outside the section do not count

- GIVEN a design file where GIVEN/WHEN/THEN tokens appear only outside the Acceptance Scenarios section
- WHEN the guard runs
- THEN the section count is 0 and the line renders the thin-heading `[X]` message

#### Scenario: Extraction failure fails open

- GIVEN the section extraction errors or returns a non-numeric count
- WHEN the guard runs
- THEN the Acceptance Scenarios line degrades to heading-presence semantics and the hook completes normally

### Requirement: Spec-driven acceptance scenarios satisfy the design guard via sibling spec files

When the design-file acceptance-scenarios check fails, the DESIGN COMPLETENESS check in `hooks/skill-activation-hook.sh` SHALL count uppercase WHEN/THEN tokens across sibling `<design_dir>/specs/*/spec.md` files and SHALL mark the Acceptance Scenarios line `[OK]` (with a distinct "in sibling specs/" annotation) when the aggregated `min(WHEN, THEN) >= 2`. GIVEN MUST NOT be required in spec files (the OpenSpec scenario template makes it optional). The fallback SHALL be strictly additive — it only flips `[X]` to `[OK]`; any error degrades to the design-file verdict — and the guard SHALL remain advisory-only.

#### Scenario: Spec-driven change satisfies via sibling specs

- GIVEN a design file whose acceptance section is missing or thin, with a sibling `specs/<cap>/spec.md` containing at least 2 WHEN/THEN scenario pairs
- WHEN the PLAN-phase design guard runs
- THEN the Acceptance Scenarios line renders `[OK]` with the sibling-specs annotation

#### Scenario: GIVEN-less template scenarios count

- GIVEN sibling spec files whose scenarios use only bold `- **WHEN**` / `- **THEN**` lines with no GIVEN
- WHEN the guard runs
- THEN the aggregated count treats them as valid scenarios and the line renders `[OK]`

#### Scenario: Thin sibling specs do not flip the verdict

- GIVEN a design file failing the acceptance check and sibling spec files carrying fewer than 2 WHEN/THEN pairs
- WHEN the guard runs
- THEN the line keeps the existing design-file `[X]` message (missing or thin, unchanged)

#### Scenario: Default-mode designs are unaffected

- GIVEN a design file with no sibling `specs/` directory (e.g. `docs/plans/*-design.md`)
- WHEN the guard runs
- THEN the fallback is skipped silently and rendering is byte-identical to the pre-fallback behavior

