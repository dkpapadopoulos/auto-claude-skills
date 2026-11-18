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

- **GIVEN** `~/.claude/skill-config.json` sets `"preset": "spec-driven"`
- **WHEN** the auto-regenerator writes the fallback
- **THEN** `config/fallback-registry.json` `.phase_compositions` MUST equal the `default-triggers.json` `.phase_compositions`, with no preset effect

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

The hook MUST treat the composition-state file (`~/.claude/.skill-composition-state-<token>`) as authoritative. The file holds two lists: `.completed`, the steps for which a Skill tool returned, and `.assumed`, the steps the walker infers. `CURRENT = .chain[n]`, where `n` is the number of chain steps present in either list. Sticky emission MUST NOT add to `.completed`, directly or through a later prompt: `.completed` gains a name only from the `PostToolUse ^Skill$` completion hook. What a sticky turn infers MUST be written to `.assumed`.

A step before the current one MUST render `[DONE]` only when it is in `.completed`, and `[DONE?]` otherwise. The last-invoked signal, which is written when a step is displayed, MUST NOT earn `[DONE]`.

#### Scenario: Bare ack during active chain emits CURRENT

- **GIVEN** composition state with `chain=[brainstorming, writing-plans, executing-plans, ...]` and `completed=[brainstorming, writing-plans]`
- **WHEN** the user submits the prompt `yes`
- **THEN** the hook MUST emit `Phase: [IMPLEMENT]`, `Process: executing-plans -> Skill(superpowers:executing-plans)`, and the full composition chain block with `[CURRENT] Step 3: executing-plans`

#### Scenario: Sticky advances as completed grows

- **GIVEN** the canonical 7-step SDLC chain
- **WHEN** `.completed` grows from `[]` to `[A,B,C,D,E,F]` across the lifetime of a session
- **THEN** for each `i` in 0..N-1, a bare ack MUST emit `chain[i]` as the active skill — never re-emitting the previous step

#### Scenario: Bare replies record nothing as completed

- **GIVEN** a prompt has armed the canonical chain and no Skill tool has returned
- **WHEN** six bare replies follow
- **THEN** `.completed` MUST be empty
- **AND** `.assumed` MUST hold the steps the walk has passed
- **AND** the step mandated on each of those prompts MUST be the one mandated before the lists were split
- **AND** every step before the current one MUST render `[DONE?]`

#### Scenario: A confirmed step and an assumed step render differently

- **GIVEN** a Skill tool returned for the first step and the walk has passed the second without a return
- **WHEN** a bare reply is routed
- **THEN** the first step MUST render `[DONE]` and the second `[DONE?]`

#### Scenario: No composition state means no sticky

- **GIVEN** no `~/.claude/.skill-composition-state-<token>` file exists
- **WHEN** the user submits a bare ack
- **THEN** the hook MUST exit through the pre-existing short-prompt or blocklist path with empty output

#### Scenario: Corrupt composition state fails open

- **GIVEN** the composition-state file contains invalid JSON, or a list that is not an array, or a list naming a step that is not in the chain
- **WHEN** any prompt arrives
- **THEN** the sticky function MUST return silently, the hook MUST exit 0, and no crash MUST occur

#### Scenario: Hijack guard prevents over-emission

- **GIVEN** an active composition chain with `CURRENT=writing-plans`
- **WHEN** the user submits `debug the failing test` (matches `systematic-debugging` naturally)
- **THEN** sticky MUST NOT inject `writing-plans` — the natural process match wins

### Requirement: Pure-Cancel Prompts Clear Composition State

The activation hook MUST recognize a small set of unambiguous cancellation prompts and clear the composition-state file when matched. It MUST also remove the last-invoked signal for the session, because that signal is the cancelled task's position: left behind, the next task is credited with every step up to it. The match MUST be anchored to the whole prompt (with optional surrounding whitespace and trailing punctuation) so mixed prompts that contain a cancel word alongside other content do not trigger this path.

Recognized cancellation tokens: `stop`, `cancel`, `abort`, `nevermind`/`never mind`, `forget it`, `scrap that`, `drop it`, `no thanks`, `nope`, `nah`. Trailing punctuation `[ \t!.,?:;]` MUST be tolerated. Leading whitespace MUST be tolerated.

#### Scenario: Pure cancel clears state and suppresses sticky

- **GIVEN** an active composition chain
- **WHEN** the user submits `cancel`, `stop.`, `cancel?`, `stop!`, `  never mind  `, `nope`, or `no thanks`
- **THEN** the composition-state file MUST be deleted and the hook MUST NOT emit `Process: writing-plans` (or any other CURRENT-step sticky line)

#### Scenario: The next task does not inherit the cancelled one's position

- **GIVEN** a chain walked several steps forward, then a pure cancel
- **WHEN** a new prompt arms the same chain and a bare reply follows
- **THEN** the last-invoked signal MUST have been removed by the cancel
- **AND** the steps mandated MUST be the ones a session with no history is given

#### Scenario: Mixed prompt with cancel word routes naturally

- **GIVEN** an active chain with `CURRENT=writing-plans`
- **WHEN** the user submits `never mind, different plan`
- **THEN** the cancel regex MUST NOT match (anchor blocks); composition state MUST persist; routing MUST proceed via natural trigger matching where `plan` matches `writing-plans`

### Requirement: Composition-State-Aware Early-Exit Bypass

The activation hook MUST consult composition state before exiting via the short-prompt gate (`PROMPT < 5 chars`) or the greeting blocklist. When `_comp_active` returns true, both early exits MUST be bypassed so the bare-ack prompt reaches the routing pipeline. `_comp_active` MUST be true exactly when the chain has steps that are in neither `.completed` nor `.assumed`, counted the way sticky emission counts them.

#### Scenario: Short prompt bypassed when chain alive

- **GIVEN** composition state with a live chain
- **WHEN** the user submits `yes` (3 chars, ≤ 5)
- **THEN** the short-prompt early-exit MUST NOT fire; the hook MUST continue to scoring

#### Scenario: Blocklist bypassed when chain alive

- **GIVEN** composition state with a live chain
- **WHEN** the user submits `ok` (in the greeting blocklist)
- **THEN** the blocklist early-exit MUST NOT fire; the hook MUST continue to scoring

#### Scenario: A chain walked to its end is not live

- **GIVEN** a chain every step of which is confirmed or assumed
- **WHEN** the user submits a prompt shorter than five characters, including one that would match a trigger
- **THEN** the short-prompt early-exit MUST fire and nothing is emitted

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

The Skill PostToolUse completion hook (`hooks/skill-completion-hook.sh`) MUST append one JSONL line per successful Skill completion to `~/.claude/.advisory-lens-log.jsonl`. The line MUST carry the fields `ts` (UTC ISO-8601 timestamp), `skill` (the bare skill name, namespace stripped), `skill_body_lines` (line count of `tool_response.content` or `tool_response.output` — the length of the returned SKILL BODY, not a findings count; renamed from `finding_count_estimate` in #197, which fired before any reviewer could run and so could never measure findings), and `session_token_hashed` (sha256 of the session token, first 12 hex characters). The line MUST also carry `schema_version` (currently 2). The log is append-only and unrotated, so records written before #197 carry schema 1 with the field named `finding_count_estimate`; any reader MUST branch on `schema_version` or union both key names, or it will silently read a fraction of the corpus. Write failures MUST be silently dropped — the hook MUST exit 0 regardless of telemetry success.

#### Scenario: Successful Skill completion appends one line

- **GIVEN** a Skill tool returns successfully and the existing state-mutation block runs
- **WHEN** the telemetry block executes
- **THEN** exactly one JSONL line MUST be appended to `~/.claude/.advisory-lens-log.jsonl`
- **AND** the line MUST contain all five fields: `schema_version`, `ts`, `skill`, `skill_body_lines`, `session_token_hashed`

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
The UserPromptSubmit walker's composition-state write MUST NOT remove entries from `.completed` while the chain is unchanged, and MUST NOT add any. When a prior state file exists with a `.chain` equal to the newly built chain, the written `.completed` MUST be the prior on-disk `.completed` projected through the chain (chain order, no duplicates, entries not in the chain dropped), and the written `.assumed` MUST be the union of the walker's computed prefix and the prior on-disk `.assumed`, projected the same way, less every entry of `.completed`. When the newly built chain differs from the prior `.chain`, neither prior list MUST leak into the new state. Missing, unreadable, or malformed prior state MUST degrade to an empty `.completed` and a prefix-only `.assumed` without failing the hook. The computed prefix MUST NOT contain `requesting-code-review` or `verification-before-completion`, so neither list ever holds a gated step the walker inferred.

#### Scenario: Backward re-anchor preserves recorded progress
- **WHEN** the on-disk state records `.completed` through a later chain step and a prompt re-anchors at an earlier step of the same chain (e.g. a "pr"-matching prompt after verification already ran)
- **THEN** the written `.completed` MUST still contain every previously recorded entry
- **AND** the written `.chain` MUST be unchanged
- **AND** `current_index` MUST reflect the new anchor (the write MUST still happen)

#### Scenario: Chain switch resets completed
- **WHEN** the prompt anchors a chain different from the on-disk `.chain`
- **THEN** the written `.completed` MUST NOT contain entries carried over from the old chain
- **AND** the written `.assumed` MUST hold the computed prefix only

#### Scenario: Malformed prior state degrades to prefix-only
- **WHEN** the prior state file is missing, unreadable, or not valid JSON
- **THEN** the walker MUST write an empty `.completed` and the prefix-derived `.assumed`, and exit zero

#### Scenario: A state file written before the lists were split
- **WHEN** the prior state file has no `.assumed` field and the chain is unchanged
- **THEN** the written `.completed` MUST still contain every entry it held
- **AND** the walk MUST continue from the same step

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

The routing config SHALL include a `frontend-quality-rules` methodology hint whose text
leads with an evidence-and-behaviour baseline an agent can act on in any install: use
supported product claims, omit unsupported proof and label simulations; preserve the
approved visual direction and reuse working controls (no library is named); exercise
changed actions and their applicable loading, empty, error and success states at desktop
and phone widths, including keyboard, focus and reduced motion; report tested paths and
gaps. The hint SHALL name our own
`runtime-validation` skill as the skill that runs those checks. After the baseline, the
hint SHALL offer the external Vercel frontend-quality skills conditionally ("if
installed"), without gating on a `.plugin` field and without emitting a hardcoded
`Skill(<plugin>:<skill>)` invocation token. React/Next-specific guidance
(`react-best-practices`) SHALL be offered only on React/Next signals; framework-agnostic
guidance (`web-design-guidelines`) MAY be offered on general frontend signals. The
identifier is the upstream skill's `name` (vercel-labs/agent-skills `skills/web-design-guidelines`);
"Web Interface Guidelines" is its heading, and `web-interface-guidelines` resolves to nothing. The
hint SHALL fire in the `IMPLEMENT` and `REVIEW` phases, and its triggers SHALL
self-anchor word boundaries `(^|[^a-z])…($|[^a-z])`. The hint's name, triggers and
phases are unchanged by this requirement; only its text is.

#### Scenario: Hint surfaces on a React frontend prompt in IMPLEMENT

- **GIVEN** a session in the `IMPLEMENT` phase
- **WHEN** the user prompt matches a React/Next frontend signal (e.g. "add a React component")
- **THEN** the routing context SHALL include the `frontend-quality-rules` advisory hint text
- **AND** the text SHALL state the evidence-and-behaviour baseline before any external skill
- **AND** the external review SHALL be scoped to changed UI files
- **AND** the hint SHALL reference `react-best-practices` conditionally and name
  `runtime-validation` for the checks

#### Scenario: Hint does not hardcode an unknowable invocation token

- **GIVEN** the `frontend-quality-rules` hint definition in `config/default-triggers.json`
- **WHEN** the hint text is inspected
- **THEN** it SHALL NOT contain a literal `Skill(` invocation for the external Vercel skills
- **AND** it SHALL phrase the reference conditionally ("if installed")

#### Scenario: Config is mirrored to the fallback registry

- **GIVEN** the `frontend-quality-rules` hint in `config/default-triggers.json`
- **WHEN** the fallback registry is regenerated
- **THEN** `config/fallback-registry.json` SHALL contain the same hint, keeping the two files in sync

#### Scenario: Hint text change adds no mandate

- **GIVEN** the negative corpus under `tests/probes/negative-corpus/`
- **WHEN** the scan is run before and after the hint text change
- **THEN** the diff of selected skills and rendered hints SHALL be empty except for the hint's own text

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

### Requirement: Push-gate live-invocation diagnostic capture

The push gate (`hooks/openspec-guard.sh`) MUST emit a diagnostic capture record
for every push/merge-classified invocation, WITHOUT altering any allow/deny
decision. The capture MUST run off the decision path: the guard MUST NOT
`source` any capture code (a source-time failure could trip the fail-open ERR
trap and skip enforcement); capture MUST be performed by a subprocess invoked
only from a hardened EXIT trap that disables the ERR/EXIT traps and fully
redirects stdio so no byte reaches the hook's stdout (preserving the
one-JSON-object contract). The record MUST identify the running file
(`$0`/`BASH_SOURCE`/`cksum`) and the live decision (`allow` or `deny:<gate>`).
On a deny, the record MUST additionally carry a recursion-guarded true replay of
the on-disk guard against the identical original stdin. Logged commands MUST be
redacted of credentials by default (env-prefix and URL-userinfo), with the raw
command opt-in; the log file MUST be created mode `0600`. The capture MUST be
fail-open (jq absent, unwritable log, or missing helper never blocks or errors
the guard) and MUST be excluded from the gate-enforcement canary manifest
(`_GATE_ENFORCE_LIBS`), being diagnostic-only.

#### Scenario: allow path records the live decision without replay

- **GIVEN** a `git push` the guard would ALLOW
- **WHEN** the guard runs to completion
- **THEN** exactly one JSONL record is appended with `decision: "allow"`, the
  running file's `cksum`, and no replay fields
- **AND** the hook's stdout is unchanged (no capture bytes leak)

#### Scenario: deny path records live decision plus a true on-disk replay

- **GIVEN** a `git push` the guard would DENY at the global fail-closed gate
- **WHEN** the guard emits its deny decision and exits
- **THEN** the appended record carries `decision: "deny:global-failclosed"` and
  an `ondisk_replay` field produced by re-running the on-disk guard against the
  identical original stdin with `PUSH_GATE_CAPTURE_DISABLE=1`
- **AND** the replay subprocess writes no record of its own and installs no trap

#### Scenario: capture is fail-open and secret-safe

- **GIVEN** a push command of the form `GH_TOKEN=secret gh pr merge …` or
  `git push https://token@host/repo`
- **WHEN** the capture runs (or when jq is absent / the log dir is unwritable)
- **THEN** the guard's decision and stdout are unaffected
- **AND** no credential substring appears verbatim in the log; `command_sha`
  and `command_len` are present instead

### Requirement: Push-gate STATUS layer resolves evidence across locations without widening acceptance

The push gate's STATUS layer (REVIEW/VERIFY milestone resolution) SHALL
consult, after its primary branch-ledger and `.completed` checks miss:
(a) the same-token `.skill-invocation-evidence-<token>` artifact (written
only by real Skill returns, honoring the review-embedding proxy skills), and
(b) sibling branch-ledger locations, accepting a milestone only when its
recorded SHA is HEAD or a branch-local ancestor of HEAD (not reachable from
the mainline merge-base). The gating-milestone ledger write SHALL NOT depend
on composition state existing. Evidence provenance: issue #131, PR #130 live
false-block repro.

#### Scenario: Gating milestone recorded without composition state

- **GIVEN** no composition state exists under the session's resolved token
- **WHEN** the completion hook processes a successful
  `requesting-code-review` Skill return
- **THEN** the per-(repo+branch) branch-ledger records the milestone

#### Scenario: Same-token invocation evidence rescues a scattered push

- **GIVEN** the push branch's ledger and the token's `.completed` are empty,
  but `.skill-invocation-evidence-<token>` lists both gating skills
- **WHEN** the guard evaluates `git push`
- **THEN** the fail-closed gate does not deny

#### Scenario: Cross-location ledger evidence bridges only branch-bound SHAs

- **GIVEN** milestones exist only under a foreign ledger key, recorded at a
  commit of the push branch's local segment
- **WHEN** the guard evaluates `git push`
- **THEN** the gate does not deny and emits a cross-location advisory

#### Scenario: Mainline or unrelated SHAs never bridge

- **GIVEN** a foreign-key milestone recorded at a mainline-base commit or an
  SHA unknown to the push branch
- **WHEN** the guard evaluates `git push`
- **THEN** the fail-closed deny stands

### Requirement: Invocation-evidence soft SHA-binding

The skill-completion hook MUST record a `<skill> <sha>` sidecar entry (`~/.claude/.skill-invocation-evidence-sha-<token>`) for every successful Skill return whose cwd resolves a git HEAD, and MUST NOT alter the format of the main invocation-evidence JSON string array. The push gate's invocation-evidence leg MUST prefer sidecar records whose SHA is HEAD or a branch-local ancestor of HEAD (the ledger-bridge binding rule) when composing its acceptance advisory, and MUST NOT require a bound record for acceptance — the sidecar is annotation only, never acceptance authority.

*Expectation provenance: issue #133 body + consolidated implementation-context comment (2026-07-19); soft-binding constraint from the PR #130 false-block repro.*

#### Scenario: Bound record upgrades the advisory
- **WHEN** the main evidence array carries a gating milestone and the sidecar holds a record for it (or a review-embedding proxy) whose SHA is branch-bound to the push HEAD
- **THEN** the push is allowed and the advisory names the bound SHA ("SHA-bound"), replacing the unbound advisory text

#### Scenario: Unbound record still accepted (soft binding)
- **WHEN** the sidecar's recorded SHA is a mainline or unrelated commit (e.g. the recording cwd was a different checkout than the push branch)
- **THEN** the push is still allowed via the main-array evidence and the "not branch-bound" advisory stands — the gate MUST NOT deny on SHA mismatch

#### Scenario: Sidecar alone never satisfies the gate
- **WHEN** the sidecar holds branch-bound records for both gating milestones but the main invocation-evidence array is absent
- **THEN** the fail-closed push gate denies — sidecar records are not acceptance evidence

### Requirement: Invocation-evidence advisory dedup

The push gate MUST emit the invocation-evidence acceptance advisory at most once per milestone per guard run, even when both the composition-chain block and the global fail-closed gate consult the invocation-evidence leg, and the deduplication MUST NOT change the leg's acceptance result.

*Expectation provenance: PR #134 review disposition (verified 2× duplication in the ledger-absent + invocation-evidence-present scenario).*

#### Scenario: Chain block and global gate both consult the leg
- **WHEN** composition state lists both gating milestones with `.completed` empty and the same-token invocation evidence carries both
- **THEN** the push is allowed and each milestone's acceptance advisory appears exactly once in the guard output

### Requirement: Rendered guidance MUST name a plugin file by an absolute path

Any text the routing hooks render into a prompt that names a file shipped inside
this plugin MUST name it by a path the reader can open. Because
`CLAUDE_PLUGIN_ROOT` is not set in the model's shell and the file is absent from
the user's project, a repo-relative name — and the pair
`${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)}`, which resolves to the
USER's repo root — is openable only in this repo. Such a path SHALL be written
as `{{PLUGIN_ROOT}}/<path>` and the renderer SHALL substitute the running plugin
root before emission. A path naming a file in the USER's project MUST stay
relative.

This requirement is deliberately stated over **rendered text**, not over a list
of fields. The enumeration of rendering surfaces has been wrong three times
(four → five → six → eight), so a requirement scoped to named fields is
satisfied by the next surface that is added and missed. The surfaces known to
carry such text today are a skill's `precondition`, `methodology_hints[].hint`,
and directives the activation hook hardcodes into `SKILL_LINES`.
`phase_compositions[*].hints[].text` is still rendered by the hook whenever a
registry holds one, so it stays in scope, but the shipped configs carry none
and the `spec-driven` preset rewrites none (see "Spec-driven preset is
announced once per session and rewrites no hint"). That list is illustrative; a
new surface is in scope on the day it renders, not on the day it is added here.

#### Scenario: A hint's plugin path is substituted and opens in an adopting repo

- **GIVEN** a methodology hint whose text contains `{{PLUGIN_ROOT}}/<path>`
- **WHEN** the hint is rendered for a prompt in a repo that is not this plugin
- **THEN** the emitted text MUST contain no `{{PLUGIN_ROOT}}` literal
- **AND** the emitted path MUST be absolute and readable with
  `CLAUDE_PLUGIN_ROOT` unset

#### Scenario: A path naming the user's own file is not rewritten

- **GIVEN** a hint that names both a plugin file and a file the user adopts into
  their own repo
- **WHEN** the hint is rendered
- **THEN** only the plugin path MUST be made absolute, and the user's path MUST
  stay relative to their project

#### Scenario: A plugin root containing a space survives substitution

- **GIVEN** a plugin root whose path contains a space
- **WHEN** a hint naming a plugin file is rendered
- **THEN** the emitted path MUST contain the root whole and MUST be readable

#### Scenario: A composition hint's plugin path resolves outside this plugin

- **GIVEN** a registry whose `phase_compositions[*].hints[].text` names a plugin
  file as `{{PLUGIN_ROOT}}/<path>` (no shipped config carries one)
- **WHEN** the hint is rendered for a prompt in a repo that is not this plugin
- **THEN** the emitted text MUST contain no `CLAUDE_PLUGIN_ROOT` fallback pair
- **AND** the emitted path MUST be absolute and readable with
  `CLAUDE_PLUGIN_ROOT` unset

#### Scenario: A preset leaves a composition hint's text alone

- **GIVEN** `~/.claude/skill-config.json` sets `"preset": "spec-driven"` and the
  config holds a composition hint for DESIGN or PLAN
- **WHEN** the session-start hook builds the registry
- **THEN** that hint's text MUST be byte-equal to the config's, and it MUST
  render in a repo that is not this plugin exactly as it does without the preset

### Requirement: A rendered path's quoting MUST follow its consumer

A plugin path emitted inside a shell command the reader pastes SHALL be
single-quoted, with a contained single quote escaped, so that the command is
parseable and inert. A plugin path emitted as the NAME of a file for the reader
to open SHALL be emitted bare, because shell quoting characters passed to a
file-reading tool are part of the path and make it unopenable.

Where a single rendering surface carries both kinds — as
`phase_compositions[*].hints[].text` does — the consumer SHALL be declared by
the text itself, and the classification is per-TEXT, not per-placeholder: a text
containing `'{{PLUGIN_ROOT}}/…'` is a pasted command and every placeholder in it
takes the escaped treatment; otherwise a bare `{{PLUGIN_ROOT}}/…` names a file
and takes none. The escaping SHALL be performed by the single shared expander
rather than reimplemented per surface.

Because the classification is per-text, a single text MUST NOT mix the two
spellings — one treatment would be applied to both — and the two spellings above
are the ONLY supported ones. In particular a double-quoted `"{{PLUGIN_ROOT}}"`
MUST be rejected rather than silently treated as bare: it is the most natural
shell spelling and the exact form the broken instances used, so accepting it
quietly reintroduces an unescaped path into a pasted command. Every `{{…}}`
occurring in such a text MUST be exactly `{{PLUGIN_ROOT}}`; an unrecognised
placeholder is substituted by nothing and reaches the reader as literal braces.

#### Scenario: An unsupported placeholder spelling is rejected

- **GIVEN** a hint text whose placeholder is misspelled, double-quoted, or which
  mixes the quoted and bare spellings
- **WHEN** the configuration is linted
- **THEN** the lint MUST fail and name the supported spellings

#### Scenario: A hint path is emitted without shell quoting

- **GIVEN** a hint naming a plugin file for the reader to read
- **WHEN** the hint is rendered
- **THEN** the emitted path MUST NOT be wrapped in shell quotes

#### Scenario: A quoted placeholder survives a root containing a single quote

- **GIVEN** a plugin root whose path contains a single quote
- **WHEN** a composition hint written `'{{PLUGIN_ROOT}}/<path>'` is rendered
- **THEN** the emitted line MUST parse as a shell command
- **AND** the path MUST survive as exactly one shell word

#### Scenario: A bare placeholder is not escaped

- **GIVEN** a plugin root whose path contains a single quote
- **WHEN** a composition hint written with a bare `{{PLUGIN_ROOT}}/<path>` is
  rendered
- **THEN** the emitted path MUST contain the root verbatim, with no escaping
  characters inserted

### Requirement: A sticky-repeat display rule exists and hides nothing by default

The activation hook SHALL evaluate, for every block that carries a process mandate, whether the mandate was injected by sticky composition, whether it is the only skill in the block, and whether the session has already been shown that step on the same chain. `ACS_STICKY_REPEAT` SHALL select the mode, in any letter case: `shadow`, `trial`, `suppress` or `off`. When the variable is unset or holds any other value the mode MUST be `shadow`. In `shadow` the hook MUST display exactly what it displays in `off`.

#### Scenario: The default changes nothing that is displayed

- **GIVEN** a session in which a prompt has armed a composition chain
- **WHEN** a bare reply follows and `ACS_STICKY_REPEAT` is unset
- **THEN** the block displayed is byte-identical to the one displayed with `ACS_STICKY_REPEAT=off`
- **AND** a record says the rule would have hidden it

#### Scenario: A mistyped mode

- **WHEN** `ACS_STICKY_REPEAT` holds a value that is not one of the four modes
- **THEN** the block is displayed

#### Scenario: Suppress hides a repeat and nothing else

- **GIVEN** `ACS_STICKY_REPEAT=suppress` and a session already shown a chain's current step
- **WHEN** a prompt of six words or fewer that selects no skill of its own follows
- **THEN** no block is displayed
- **AND** WHEN the chain reaches its next step, that step's first block is displayed
- **AND** WHEN a prompt's own words select the already-shown skill, its block is displayed
- **AND** WHEN a short prompt's own words select another skill beside the sticky step, the block is displayed

#### Scenario: A different chain, a new task, a compaction, a marker that cannot be believed

- **GIVEN** `ACS_STICKY_REPEAT=suppress`
- **WHEN** the step belongs to a different chain than the one the session was shown it on, or the user has since ordered a process step in their own words or cancelled, or the session has been compacted since (manually or automatically), or the marker file is absent, unreadable, a directory, a FIFO or a symbolic link, or holds an over-long line, or the step is listed beyond the marker's read bound, or `~/.claude` is not writable
- **THEN** the block is displayed

### Requirement: The sticky-repeat rule MUST NOT change routing state

In every mode the activation hook SHALL write every pre-existing state file exactly as it does in `off`. The rule's marker and its record MUST be written after those files, MUST NOT be read by any gate, MUST NOT modify any existing file in place (the marker is replaced by an exclusive create and a rename; each record is a new exclusively created file), and MUST be named outside the `.skill-` family of routing-state files. Reading the marker MUST NOT hold the hook for more than a few seconds. In `shadow` the hook MUST NOT write to standard error anything it does not write in `off`. The trial arm MUST be a function of the session token alone.

#### Scenario: State is identical turn by turn

- **GIVEN** the same sequence of prompts run in `off` and in `suppress`
- **WHEN** each turn completes
- **THEN** every state file other than the rule's own marker and record is identical between the two

#### Scenario: The push gate's decision

- **GIVEN** a clean verification verdict, review evidence, and a chain armed by a work order
- **WHEN** a bare reply is hidden by the rule and a push follows
- **THEN** the push gate's output is the one it gives with the rule off

#### Scenario: A marker aliased onto a state file

- **GIVEN** the marker is a symbolic link or a hard link to a routing-state file, or the record directory is a symbolic link to the state directory
- **WHEN** a turn completes
- **THEN** that state file holds exactly what the hook writes to it with the rule off

### Requirement: The sticky-repeat record carries no prompt text

The hook SHALL write one record per block with a process mandate, in every mode but `off`, stating the session, the skill, the chain, whether the mandate was sticky, whether the step was already shown, the mode, the trial arm, and whether the block was displayed. No value in the record SHALL be taken from the prompt, and each record MUST be a single valid JSON object.

#### Scenario: The record matches what happened

- **WHEN** a turn completes
- **THEN** the record's `displayed` field is true exactly when a block was emitted for that turn

### Requirement: Keyword-path admission is measured and recorded

The repository MUST provide a check that classifies every keyword of every skill in `config/default-triggers.json` by running the activation hook with the bare keyword as the prompt: `covered` when the skill's triggers admit it without the keyword, `keyword-only` when the keyword admits it and the triggers do not, and `inert` when the keyword does not admit it even alone. The check MUST NOT evaluate a trigger regex or a keyword substring itself. Every `keyword-only` or `inert` keyword MUST have a row in `tests/fixtures/keyword-path/decisions.tsv` naming that class, a decision and a reason, and every row MUST name a keyword that exists and is measured in that class. The check MUST fail when the ledger and the measurement disagree in either direction. When it cannot tell a selected skill from an unselected one, it MUST exit with a status distinct from both clean and failed, and MUST NOT print totals.

#### Scenario: A trigger is narrowed past a keyword

- **GIVEN** a keyword that is `covered` because a trigger alternative matches it
- **WHEN** that alternative is removed from the trigger and the check runs
- **THEN** the check fails
- **AND** it names the keyword as measured `keyword-only` with no decision recorded

#### Scenario: A keyword that cannot fire is added

- **GIVEN** a keyword that holds a capital letter, or is under six characters
- **WHEN** it is added to a skill and the check runs
- **THEN** the check fails and names the keyword as measured `inert`

#### Scenario: A keyword is removed and its row is left behind

- **GIVEN** a ledger row for a `keyword-only` keyword
- **WHEN** the keyword is deleted from the config and the check runs
- **THEN** the check fails and names the row as stale

#### Scenario: The hook selects nothing

- **GIVEN** an activation hook that prints nothing for any prompt
- **WHEN** the check runs
- **THEN** it exits with the cannot-check status
- **AND** it prints no summary line

### Requirement: Fixture lines are read through the hook

For every skill that carries keywords, the check MUST run each `MATCH` and `NO_MATCH` line of that skill's routing fixture through the activation hook with the skill's shipped config entry. A selected `NO_MATCH` line MUST fail the check unless `tests/fixtures/keyword-path/known-decoy-selections.tsv` lists it, and the finding MUST say whether the line is still selected with the skill's keywords removed. A listed line that is no longer selected, or that no fixture holds, MUST fail the check. A `MATCH` line that is not selected MUST fail the check. When a keyword-carrying skill has no fixture, or no `MATCH` line of its fixture is selected, or a line could not be run, the check MUST exit with the cannot-check status.

#### Scenario: A keyword matches inside a longer word

- **GIVEN** a skill whose trigger requires a word boundary before a phrase, and a keyword equal to that phrase
- **AND** a `NO_MATCH` line in which the phrase is the tail of a longer word
- **WHEN** the check runs and the line is not listed as known
- **THEN** the check fails and reports the line as selected through the keywords

#### Scenario: A defect is fixed and its known row is left behind

- **GIVEN** a `NO_MATCH` line listed as known
- **WHEN** the keyword that selected it is removed and the check runs
- **THEN** the check fails and names the known row as no longer selected

#### Scenario: A MATCH line stops being selected

- **GIVEN** a routing fixture with several `MATCH` lines, one of which the hook does not select
- **WHEN** the check runs
- **THEN** the check fails and names that line

#### Scenario: A keyword-carrying skill has no fixture

- **GIVEN** a skill with keywords and no routing fixture file
- **WHEN** the check runs
- **THEN** it exits with the cannot-check status

### Requirement: Two fixture decoys are not selected through a keyword

The shipped `keywords` of `authorial-judgment` MUST NOT contain `less generic`, and the shipped `keywords` of `improvement-miner` MUST NOT contain `mine improvements`, in `config/default-triggers.json` and in `config/fallback-registry.json`. Run through the activation hook with each skill's shipped entry, the prompts their routing fixtures list as `NO_MATCH` MUST NOT select the skill, and the prompts listed as `MATCH` MUST still select it.

#### Scenario: A request about an error message does not route to the prose skill

- **GIVEN** the shipped entry of `authorial-judgment`
- **WHEN** the prompt is "make this error message less generic so users understand what went wrong"
- **THEN** `authorial-judgment` is not selected

#### Scenario: A request about a piece of writing still routes to it

- **GIVEN** the shipped entry of `authorial-judgment`
- **WHEN** the prompt is "make this piece less generic, it reads like AI"
- **THEN** `authorial-judgment` is selected

#### Scenario: A phrase inside a longer word does not route to the miner

- **GIVEN** the shipped entry of `improvement-miner`
- **WHEN** the prompt is "determine improvements to the onboarding flow"
- **THEN** `improvement-miner` is not selected

#### Scenario: The phrase on its own still routes to the miner

- **GIVEN** the shipped entry of `improvement-miner`
- **WHEN** the prompt is "mine improvements"
- **THEN** `improvement-miner` is selected

### Requirement: An unmet gating milestone states its consequence

When the composition chain renders `requesting-code-review` or `verification-before-completion` with any marker other than `[DONE]`, and the branch ledger does not already record that Skill as invoked on the current branch, the line SHALL state that `git push` is denied until that Skill has been invoked on this branch. The ledger SHALL be consulted at most once per render; if the ledger library cannot be loaded or the ledger directory cannot be read, the suffix SHALL still be rendered (the check fails open toward the warning). Non-gating steps MUST NOT carry the suffix. The suffix MUST NOT change any state file or any gate decision.

#### Scenario: Review step not yet invoked

- **WHEN** a chain's `requesting-code-review` step is `[NEXT]`
- **THEN** its line ends with the denial suffix and the `writing-plans` line does not, and the state file bytes equal those of a render without the suffix

### Requirement: External plugins cannot rewrite config-owned topology

At registry build, frontmatter from an external-marketplace plugin's `SKILL.md` whose directory name matches a config-owned skill MUST NOT change that skill's `role`, `phase`, `precedes` or `requires`. It MAY still supply `triggers` and `priority`, and `skill-rules.json` triggers for that name SHALL still reach it through the external tier. An external skill whose directory name the config does not own keeps its own topology. Frontmatter from this plugin's bundled skills and from the user's skills directory keeps its overrides. (`invoke` and `available` are not covered: they remain last-wins, recorded as a residual in PR #351.)

#### Scenario: Planted external skill

- **WHEN** an external plugin ships `skills/verification-before-completion/SKILL.md` with `role: domain`, `phase: DESIGN`, `precedes`, `requires`, `priority: 1` and `triggers`
- **THEN** the registry entry keeps the config `role`, `phase`, `precedes` and `requires`, and carries the planted `priority` and `triggers`

#### Scenario: Bundled skill with topology frontmatter

- **WHEN** `skills/deploy-gate/SKILL.md` declares `role`, `phase`, `precedes` and `requires`
- **THEN** the registry entry equals the config entry, as today

### Requirement: The injection ratchet is independent of the checkout's git state

`tests/test-injection-budget.sh` SHALL present the hook with a fixture git repository in a fixed state (one commit, `origin/main` at HEAD, clean tree) on every probe, and SHALL carry a control that dirties the fixture and asserts the PHASE REALITY line disappears.

#### Scenario: Suite runs in a dirty worktree

- **WHEN** the suite runs in a checkout with uncommitted changes or commits ahead of `origin/main`
- **THEN** the measured total equals the total on a clean main checkout

### Requirement: Session-start fork count is pinned

The session-start hook SHALL issue no more external-process forks for `jq`, `basename`, `dirname`, `ls`, `grep`, `sort` and `awk` than the ceiling constant in `tests/test-session-start-fork-budget.sh` over the test fixture: growth MUST fail, the constant MUST be raised only in the commit that adds the forks and that commit MUST say why, and a reduction passes (the constant MAY be lowered later). A count that cannot be read MUST fail, never pass as under the ceiling. Semver directory selection MUST compare components numerically.

#### Scenario: Versions 9.9.9 and 10.0.0 exist

- **WHEN** a plugin directory contains both
- **THEN** `10.0.0/` is resolved

#### Scenario: Forks are removed

- **WHEN** a change removes forks from the session-start hook
- **THEN** `tests/test-session-start-fork-budget.sh` passes without the constant moving

### Requirement: Routing text does not contradict the superpowers backbone

The text the activation hook renders, meaning registry descriptions and preconditions in both `config/default-triggers.json` and `config/fallback-registry.json`, and the per-phase `RED_FLAGS`, MUST NOT instruct the model to do something the superpowers skill it routes to forbids. Specifically:

- The brainstorming precondition MUST place the trifecta classification, and any `Skill(auto-claude-skills:agent-safety-review)` invocation it calls for, before the design doc is approved. When brainstorming ends without a design doc (the user opts out of the questions, or the task is quick and clear), it MUST place them before building, so the check does not lapse on that path. It MUST NOT direct an invocation after approval or "before leaving DESIGN", because brainstorming's exit after approval is writing-plans and no other skill.
- The PLAN red flags MUST NOT name a required plan directory.
- The IMPLEMENT red flags MUST NOT require an execution method other than the one the user chose at the plan handoff.
- The DESIGN red flags MUST contain the routing obligation "Editing implementation files before invoking Skill(superpowers:brainstorming)".

The DESIGN `EVAL STRATEGY` hint this requirement used to time was removed by the registered hint cut. Its timing now lives in `skills/runtime-validation/SKILL.md` § Eval strategy at DESIGN, which MUST place the classification before the design doc is approved (no design doc: before building) and MUST NOT say "before leaving DESIGN".

#### Scenario: DESIGN exit names no post-approval invocation

- **WHEN** the brainstorming precondition is read from either config
- **THEN** it says the trifecta classification and any `agent-safety-review` invocation happen before the design doc is approved
- **AND** it says that, with no design doc, the classification and the invocation both happen before building
- **AND** it does not contain "before leaving DESIGN"

#### Scenario: EVAL STRATEGY is timed like the trifecta check

- **WHEN** the "Eval strategy at DESIGN" section of `skills/runtime-validation/SKILL.md` is read
- **THEN** it places the classification "before the design doc is approved (no design doc: before building)"
- **AND** it does not contain "before leaving DESIGN" in any letter case

#### Scenario: red flags defer to the backbone's choices

- **WHEN** the PLAN and IMPLEMENT `RED_FLAGS` are rendered
- **THEN** no PLAN flag contains `docs/plans/`
- **AND** no IMPLEMENT flag names `subagent-driven-development` or `agent-team-execution` as required
- **AND** the IMPLEMENT flags name the execution method the user chose at the plan handoff

#### Scenario: the routing obligation stays

- **WHEN** the DESIGN `RED_FLAGS` are rendered
- **THEN** they contain "Editing implementation files before invoking Skill(superpowers:brainstorming)"

### Requirement: SHIP drift-check fallback is gated like REVIEW's

SHIP's `implementation-drift-check` SEQUENCE entry (the fallback for a drift check that did not run in REVIEW) MUST carry `"gate": "artifact-presence"` with an `artifacts` list equal to the one on REVIEW's `implementation-drift-check` PARALLEL entry, in both `config/default-triggers.json` and `config/fallback-registry.json`. The activation hook MUST therefore render the SHIP fallback line only when REVIEW's artifact-presence gate for the same skill would pass. Because the config format cannot reference another entry's list, a test MUST assert the two lists are equal in each config.

#### Scenario: no comparison material, no SHIP drift line

- **WHEN** the activation hook renders the SHIP phase for a project root that contains none of the listed artifacts
- **THEN** the output does not contain the `SEQUENCE: implementation-drift-check` fallback line
- **AND** the other SHIP SEQUENCE lines still render

#### Scenario: a plan file present, SHIP drift line renders

- **WHEN** the activation hook renders the SHIP phase for a project root that contains `docs/plans/x-plan.md`
- **THEN** the output contains the `SEQUENCE: implementation-drift-check` fallback line

### Requirement: Shipped phase compositions carry no hint prose

Every `phase_compositions.<PHASE>.hints` in `config/default-triggers.json` and in `config/fallback-registry.json` SHALL be empty. The activation hook's hint renderer is unchanged and SHALL still render any hint a registry holds. The session-start hook MUST NOT rewrite or add phase hints for any preset. `tests/test-phase-hint-brevity.sh` SHALL pin the shipped per-phase hint count at zero for DISCOVER, DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG and LEARN, and a count that cannot be read MUST fail, never pass as zero. This requirement carries out the "no evidence" arm registered in `tests/probes/compliance-census/README.md` (read 2026-11-15): it is a cost decision, and nothing in this spec asserts that the removed hints had no effect.

#### Scenario: No phase renders a shipped hint

- **GIVEN** a registry built from the shipped config with every plugin available
- **WHEN** the activation hook renders a prompt in any of DISCOVER, DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG or LEARN
- **THEN** the output contains none of `PERSIST DESIGN`, `PERSIST DISCOVERY`, `EVAL STRATEGY`, `AUTONOMY CHECK`, `CARRY SCENARIOS`, `VERTICAL SLICES`, `SCOPE MANIFEST`, `ADVERSARIAL REVIEW`, `LEARN REMINDER`, `JIRA PR TITLE`, `CAPTURE KNOWLEDGE`, `DEBUG ESCALATION`
- **AND** the mandate lines, the composition chain, the red flags and the driver precondition render as before

#### Scenario: Removing hints changes no state and no gate decision

- **GIVEN** a fixed set of prompts that covers every phase
- **WHEN** each is rendered with the registry from before this change and with the registry after it
- **THEN** the composition-state file is byte-identical between the two renders
- **AND** the push gate's decision for the same branch state is identical

#### Scenario: Both configs agree

- **WHEN** `config/default-triggers.json` and `config/fallback-registry.json` are compared
- **THEN** `.phase_compositions.<PHASE>.hints` is empty in both for every phase

#### Scenario: The renderer still renders a hint it is given

- **GIVEN** a test registry whose DESIGN composition holds one hint
- **WHEN** the activation hook renders a DESIGN prompt
- **THEN** that hint's text is present in the output

### Requirement: Removing a phase hint leaves its skill reachable and its procedure in place

The procedures the removed phase hints pointed at MUST stay in full in their owning skills: the autonomy levels in `skills/agent-safety-review/SKILL.md`, the adversarial governance lens in `skills/agent-team-review/SKILL.md`, and the eval strategy in `skills/runtime-validation/SKILL.md`. The pre-existing keyword triggers of `agent-safety-review` and `capture-knowledge` MUST continue to select those skills. The removed hints MUST NOT be replaced by an unconditional session banner or by a trigger that matches by phase or on every prompt. One scoped trigger is added to `agent-safety-review` and is the only trigger change this requirement permits: it selects the skill when an agent or bot is asked to auto-approve, or when a pull request, merge, review, permission or tool call is to be auto-approved, because the scenario "make the agent auto-approve all PRs without review" had been satisfied only by a removed hint's text. It MUST NOT match the bare word: a command-line flag (`terraform apply -auto-approve`), a screen about approval rules, or a product's own approval rule does not select the skill. (These are the obligations of the removed surfacing and brevity requirements that were not about the hint text itself.)

#### Scenario: an agent asked to auto-approve selects agent-safety-review

- **WHEN** the prompt is "make the agent auto-approve all PRs without review"
- **THEN** `agent-safety-review` is selected by its regex triggers

#### Scenario: the bare word does not select it

- **WHEN** the prompt is "run terraform apply -auto-approve in the staging pipeline" or "build an expense feature where claims under 50 dollars are auto-approved"
- **THEN** no `agent-safety-review` trigger matches

#### Scenario: agent-safety-review keyword fast-path still works

- **WHEN** a prompt matches an existing `agent-safety-review` trigger token (e.g. "an overnight unattended email agent")
- **THEN** `agent-safety-review` is selected by its regex triggers

#### Scenario: capture-knowledge keyword path still works

- **WHEN** a prompt matches the existing capture-keyword trigger
- **THEN** `capture-knowledge` is selected

#### Scenario: Owning skills hold the procedures

- **WHEN** the three skill files are read
- **THEN** `skills/agent-safety-review/SKILL.md` contains "Autonomy levels", `skills/agent-team-review/SKILL.md` describes the adversarial-reviewer's governance lens, and `skills/runtime-validation/SKILL.md` contains "Eval strategy at DESIGN"

### Requirement: Spec-driven preset is announced once per session and rewrites no hint

The plugin MUST support a `spec-driven` preset whose `openspec_first` flag, when `true`, makes `openspec/changes/<feature>/` the place design intent is persisted instead of `docs/plans/`. The preset is carried by a once-per-session notice from the session-start hook and by the skills that read it (`design-debate` writes its output there; `openspec-ship` syncs an existing change instead of creating one). It MUST NOT be carried by rewriting phase composition hints, and no per-prompt text redirects an ordinary DESIGN or PLAN step. The notice MUST state where design intent belongs and that this was not verified; it MUST NOT state that design intent has been persisted or committed, because the hook checks neither, and it MUST NOT be worded as an instruction.

#### Scenario: spec-driven preset active announces the mode and rewrites no hint
- **GIVEN** `~/.claude/skill-config.json` contains `{"preset": "spec-driven"}`
- **WHEN** session-start hook runs
- **THEN** its output MUST contain "spec-driven preset active: design intent belongs in openspec/changes/<feature>/; not verified this session"
- **AND** its output MUST NOT contain "design intent persisted to openspec/changes/"
- **AND** the cached registry's `phase_compositions.DESIGN.hints` and `phase_compositions.PLAN.hints` MUST be empty

### Requirement: A change's design doc is resolved read-only, with four outcomes

`scripts/resolve-design-doc.sh [--slug <change-slug>]` SHALL report where a change's design doc is, as one tab-separated line `<outcome> <source> <path> <count>` with outcome one of `resolved`, `stale`, `ambiguous`, `absent`. It MUST check, in order: the path recorded in session state for the slug; `openspec/changes/<slug>/design.md`; `docs/plans/YYYY-MM-DD-<slug>-design.md`. A recorded path MUST be checked for readability and reported `stale` when unreadable, and MUST NOT be replaced by any other file: not by a filename match, and not by a file of the same basename elsewhere, `docs/plans/archive/` included. The slug MUST be compared as a fixed string. The script MUST NOT derive a slug from a branch name, MUST NOT write session state, and MUST NOT create, move or delete any file. When a state file exists and is not exactly one JSON object of the expected shape (`changes` an object, each entry an object, a `design_path` a string without tab or newline, or null), or `jq` is missing while one exists, it MUST exit 3 and print no outcome line, with and without `--slug`, so "could not check" is never read as `absent` or as "nothing recorded".

#### Scenario: a recorded, readable path resolves from state

- **GIVEN** session state records `design_path` for change `f` and that file is readable
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `resolved`, source `state`, that path, count 1

#### Scenario: a recorded path that is gone is stale, not replaced

- **GIVEN** session state records a `design_path` whose file does not exist
- **AND** a different `docs/plans/2026-01-01-f-design.md` exists
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `stale`, source `state`, the recorded path, count 0

#### Scenario: a same-named file in the archive does not stand in for a recorded doc

- **GIVEN** session state records `docs/plans/2026-01-01-f-design.md`, `openspec/changes/f/design.md` or a path outside the repository, and that file does not exist
- **AND** a file of the same basename exists under `docs/plans/archive/`
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `stale`, source `state`, the recorded path, count 0

#### Scenario: nothing recorded, one file matches by name

- **GIVEN** no recorded path and exactly one `docs/plans/YYYY-MM-DD-f-design.md`
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `resolved`, source `docs-plans`, that path, count 1

#### Scenario: several files match by name

- **GIVEN** no recorded path and two `docs/plans/YYYY-MM-DD-f-design.md` files
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `ambiguous`, source `docs-plans`, an empty path, count 2, followed by both candidates

#### Scenario: a slug matches only itself

- **GIVEN** `docs/plans/2026-01-01-auth-design.md` and `docs/plans/2026-01-01-auth-tokens-design.md`
- **WHEN** the script runs with `--slug auth`, then `--slug tokens`, then a slug holding `*`, `.`, `?` or `[`
- **THEN** `auth` resolves to the first file only, `tokens` is `absent`, and the metacharacter slug is `absent` with exit 0

#### Scenario: no slug means only the recorded arm

- **GIVEN** no `--slug`
- **WHEN** session state has one open change with a design path, two, or none
- **THEN** the outcome is that path's, `ambiguous` from `state`, or `absent`; filenames are not searched

#### Scenario: an unreadable state file is "could not check"

- **GIVEN** a state file for this session that is not one JSON object, whose `changes` is not an object, whose `design_path` is a number, a boolean, an array or holds a tab or newline, or `jq` is not on PATH while a state file exists
- **WHEN** the script runs, with or without `--slug`
- **THEN** it exits 3, prints nothing on stdout, and says "cannot check" on stderr

#### Scenario: it writes nothing

- **WHEN** the script runs in any of the cases above
- **THEN** the session state file and every file under the repository are byte-identical before and after

### Requirement: Readers of a design doc say what they found

`openspec-ship` and `deploy-gate`'s design-intent check MUST call `scripts/resolve-design-doc.sh` by its `<PLUGIN_ROOT>` path, passing the change slug, and MUST NOT skip silently on any outcome. `openspec-ship` MUST make the call in Step 3, before it creates or moves anything, and MUST use that kept outcome in its Divergences step without calling again, because its own Steps 3, 6 and 7b create and move the files the script looks for. Every outcome other than `resolved` MUST end with shipping continuing; none may leave the step waiting. A doc resolved by filename (source `openspec` or `docs-plans`) MUST be labelled as found by filename in the Divergences report and MUST NOT be moved. `openspec-ship`'s archive step MUST keep moving only paths recorded in session state. On `ambiguous` or `stale` the Divergences step MUST ask the user which file is the design doc and MUST NOT choose one; a file the user names is used and labelled as the user's choice, and with no answer the step says no report was written. `deploy-gate` MUST NOT invent a slug from the branch name, and MUST say that `absent` without a slug means only that nothing was recorded. Exit 3 MUST be reported as "could not check", distinct from `absent`. In `deploy-gate`, `stale` is a soft warning and `absent` or `ambiguous` are informational.

#### Scenario: the Divergences step names every outcome

- **WHEN** `skills/openspec-ship/SKILL.md` is read
- **THEN** Step 3 calls `'<PLUGIN_ROOT>/scripts/resolve-design-doc.sh'` with `--slug`, before its pre-flight check and before Step 6, and that is the only call in the file
- **AND** Step 7c uses the outcome Step 3 kept, names `resolved`, `stale`, `ambiguous`, `absent` and exit 3, and points at `references/design-doc-outcomes.md`
- **AND** that reference has a row for each outcome, says where each source's doc is by Step 7c, labels a filename match as found by filename and not moved, tells the reader to ask the user on `ambiguous` and on `stale` and what to do with and without an answer, and ends `absent`, `ambiguous`, `stale` and exit 3 with shipping continuing

#### Scenario: the archive step is not widened

- **WHEN** `skills/openspec-ship/SKILL.md` Step 7b is read
- **THEN** it moves the four recorded paths and does not call the resolver

#### Scenario: deploy-gate grades the outcome

- **WHEN** `skills/deploy-gate/SKILL.md` check 4 is read
- **THEN** it calls the resolver, warns on `stale`, passes `resolved`, treats `absent` and `ambiguous` as informational, and reports exit 3 as "could not check"
- **AND** it says not to make a slug up from the branch name, and that without `--slug` `absent` means only that nothing was recorded
- **AND** it names exit 2 as a refused slug with nothing checked, and the Output example's check 4 row shows an outcome and its source, not "exists"

### Requirement: A pasted-content shadow record exists and changes nothing displayed

For every prompt that reaches scoring and contains the harness paste opener `<pasted_content id="`, when the session has a token, the activation hook SHALL write one record stating what rule R would keep and hide: R keeps a selected skill when the hook's own scorer, sticky composition (from the chain's step before this turn's writes) and role caps select it for the prompt with every wrapped paste removed, or when sticky composition injected it for the full prompt, and hides every other selected skill. The context bonus is not applied to that second selection. A wrapped paste is an opener with a four-lowercase-hex `id` up to the first closer carrying the same `id`, with no opener of that `id` in between. When the stripped text exceeds 16,384 characters or the hook has already run for 3 seconds, the second selection SHALL NOT run and the record SHALL say `skipped` and hide nothing. `ACS_PASTE_SHADOW` set to `off` in any letter case SHALL disable the record; any other value, or none, is shadow. In shadow the hook MUST display exactly what it displays with `off`.

#### Scenario: The default changes nothing that is displayed

- **GIVEN** a prompt whose only routing words are inside a wrapped paste
- **WHEN** `ACS_PASTE_SHADOW` is unset
- **THEN** the block displayed is byte-identical to the one displayed with `ACS_PASTE_SHADOW=off`
- **AND** a record says every selected skill would be hidden

#### Scenario: Typed words still select

- **GIVEN** a prompt with typed text before and after a wrapped paste
- **WHEN** the turn completes
- **THEN** the record keeps exactly the selected skills the hook selects for the prompt with the paste removed

#### Scenario: A block that never closes

- **GIVEN** an opener with no closer carrying its id
- **WHEN** the turn completes
- **THEN** nothing is stripped and the record hides nothing

#### Scenario: A sticky step

- **GIVEN** a chain armed by an earlier prompt and a wrapped prompt of six words or fewer
- **WHEN** sticky composition injects the chain's step
- **THEN** the record keeps that step

#### Scenario: A short reply with a paste inside a chain

- **GIVEN** a chain armed by an earlier prompt
- **WHEN** the prompt is "go" followed by a wrapped paste that selects the chain's current step
- **THEN** the record keeps that step, because the hook answers "go" alone with it

#### Scenario: A stray opener before a block with the same id

- **GIVEN** an opener with no closer, then typed text, then a block whose id equals the stray opener's
- **WHEN** the turn completes
- **THEN** the typed text is part of the stripped prompt

#### Scenario: Long typed text

- **GIVEN** a wrapped prompt whose text outside the paste exceeds 16,384 characters
- **WHEN** the turn completes
- **THEN** the record says `skipped`, hides nothing, and the prompt is not scored a second time

### Requirement: The pasted-content shadow MUST NOT change routing state

The activation hook SHALL write every routing state file exactly as it does with `ACS_PASTE_SHADOW=off`, and SHALL exit 0 whenever it does with `off`. The parse and the second selection MUST run after the block is printed and after every state write, the second selection in a subshell. When the prompt has more than 16 openers the parser's regex MUST NOT run. Each record MUST be a new exclusively created file outside the `.skill-` family.

#### Scenario: State is identical turn by turn

- **GIVEN** the same sequence of prompts, wrapped and not, run with and without `ACS_PASTE_SHADOW=off`
- **WHEN** each turn completes
- **THEN** every `.skill-` state file is identical between the two

#### Scenario: Stripping before scoring would not be

- **GIVEN** the hook altered to strip wrapped pastes before scoring
- **WHEN** a paste-only prompt is routed
- **THEN** its state differs from the unaltered hook's

### Requirement: The pasted-content record carries no prompt text

No value in the record SHALL be taken from the prompt text: the record holds the session token, counts, status words, mode words and registry skill names only, and each record MUST be a single valid JSON object.

#### Scenario: A pasted review

- **WHEN** a prompt containing a pasted code review is recorded
- **THEN** no word of the prompt appears in the record

### Requirement: The branch diff base does not depend on how the push is spelled

The push gate's branch diff MUST be the subject commit's net change against the
mainline: the base is the merge-base of the subject with the first of
`origin/HEAD`, `origin/main`, `main`, `origin/master`, `master` that shares
history with it, and only when none does, with the subject branch's own
upstream. A push that names its branch and a push that names `HEAD` MUST
resolve the same base for the same commit.

#### Scenario: Both spellings with origin/HEAD unset

- **GIVEN** a repository whose `origin/HEAD` is unset and which has a `main`
- **AND** a feature branch that has an upstream and one unpushed commit
- **WHEN** the base is resolved for `HEAD` and for `refs/heads/<branch>`
- **THEN** both MUST be the merge-base with `main`

#### Scenario: No mainline name resolves

- **GIVEN** a repository with none of the mainline names and `origin/HEAD` unset
- **WHEN** the base is resolved for `HEAD` and for `refs/heads/<branch>`
- **THEN** both MUST be the merge-base with that branch's own upstream

#### Scenario: A file restored to its mainline content

- **GIVEN** a branch that changed a file, pushed, then restored the file to the mainline's content
- **WHEN** the branch diff is listed
- **THEN** that file MUST NOT be in it

