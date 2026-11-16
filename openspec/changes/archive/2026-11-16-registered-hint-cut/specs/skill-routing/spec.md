# skill-routing delta: registered hint cut

## ADDED Requirements

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

The plugin MUST support a `spec-driven` preset whose `openspec_first` flag, when `true`, makes `openspec/changes/<feature>/` the place design intent is persisted instead of `docs/plans/`. The preset is carried by a once-per-session notice from the session-start hook and by the skills that read it (`design-debate` writes its output there; `openspec-ship` syncs an existing change instead of creating one). It MUST NOT be carried by rewriting phase composition hints, and no per-prompt text redirects an ordinary DESIGN or PLAN step.

#### Scenario: spec-driven preset active announces the mode and rewrites no hint
- **GIVEN** `~/.claude/skill-config.json` contains `{"preset": "spec-driven"}`
- **WHEN** session-start hook runs
- **THEN** its output MUST contain "spec-driven mode active: design intent persisted to openspec/changes/ (committed)"
- **AND** the cached registry's `phase_compositions.DESIGN.hints` and `phase_compositions.PLAN.hints` MUST be empty

## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Preset-Gated OpenSpec-First Mode

**Reason**: Registered hint cut. Its only scenario requires the cached registry's DESIGN hint text to contain `openspec/changes/`, which was the spec-driven preset's rewrite of phase hints; the hints and the rewrite are removed.

**Migration**: Replaced by "Spec-driven preset is announced once per session and rewrites no hint" in this delta. The preset still exists and `design-debate` and `openspec-ship` still read it.

### Requirement: Vertical-slice decomposition hint in PLAN-phase composition

**Reason**: Registered hint cut. The VERTICAL SLICES hint is one of the 23 shipped phase hints removed; the requirement also describes a spec-driven rewrite of `CARRY SCENARIOS` that no longer exists.

**Migration**: None in the routing block. Nothing prompts vertical slicing at PLAN; `superpowers:writing-plans` owns plan decomposition.

### Requirement: Jira PR-title advisory hint at SHIP

**Reason**: Registered hint cut. The JIRA PR TITLE hint is a shipped SHIP-phase hint.

**Migration**: None. The trigger-matched "Jira branch-naming advisory hint" (a `methodology_hints` entry) is outside the cut and stays.

### Requirement: Phase-scoped lethal-trifecta surfacing

**Reason**: Registered hint cut, and issue #356. The DESIGN `TRIFECTA CHECK` hint this requirement mandates was already dropped from the config before `933f2398`; the REVIEW `ADVERSARIAL REVIEW` hint it also mandates is removed here.

**Migration**: The DESIGN-phase trifecta classification is delivered by the brainstorming precondition, which "Routing text does not contradict the superpowers backbone" requires. `agent-safety-review`'s keyword triggers are unchanged. REVIEW no longer routes a trifecta-completing change to `agent-safety-review` through a hint; that route now depends on `agent-team-review` or a trigger match.

### Requirement: Phase-scoped capture-knowledge surfacing

**Reason**: Registered hint cut. The CAPTURE KNOWLEDGE hint at LEARN, SHIP and DEBUG is removed. Measured 2026-11-15: rendered in 52 sessions since 2026-10-12, `capture-knowledge` invoked in none.

**Migration**: `capture-knowledge` remains reachable by its capture-keyword trigger and by name. Writes to `.claude/knowledge/` stay human-gated.

### Requirement: Phase hints name the owning skill and stay short

**Reason**: There are no shipped phase hints to bound. Its "Hint content changes" scenario (state and gate decision byte-identical) is kept as "Removing hints changes no state and no gate decision" in the added requirement.

**Migration**: `tests/test-phase-hint-brevity.sh` pins zero instead of per-phase ceilings.
