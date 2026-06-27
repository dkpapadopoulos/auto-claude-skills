## Purpose

Domain skills that enforce safety disciplines in DESIGN. Scaffolding for new skills, prototype variation for design decisions, and lethal-trifecta review for agent designs — co-selected alongside the superpowers process drivers without displacing them.
## Requirements
### Requirement: starter-template domain skill
The plugin MUST provide a `starter-template` domain skill in DESIGN phase that emits repo-native seed files when creating new skills, commands, plugins, hooks, or modules.

#### Scenario: New skill creation
- **WHEN** the user prompts with "create a new skill" or matching trigger patterns
- **THEN** starter-template MUST co-select alongside brainstorming as a domain skill
- **AND** brainstorming MUST remain the process driver

#### Scenario: Process skill restriction
- **WHEN** the user requests a process skill for a superpowers-owned phase (DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG)
- **THEN** the skill MUST emit a warning about the superpowers phase driver contract

### Requirement: prototype-lab domain skill
The plugin MUST provide a `prototype-lab` domain skill in DESIGN phase that produces exactly 3 thin comparable variants with a comparison artifact and mandatory Human Validation Plan.

#### Scenario: Multi-variant design
- **WHEN** the user prompts with "prototype" or "compare options" or matching trigger patterns
- **THEN** prototype-lab MUST co-select alongside brainstorming as a domain skill
- **AND** brainstorming MUST remain the process driver
- **AND** prototype-lab MUST NOT appear as a process skill

#### Scenario: Human Validation Plan
- **WHEN** prototype-lab produces a comparison artifact
- **THEN** the artifact MUST include a Human Validation Plan section
- **AND** AI-simulated user testing MUST NOT replace the Human Validation Plan

### Requirement: agent-safety-review domain skill
The plugin MUST provide an `agent-safety-review` domain skill in DESIGN phase that evaluates designs for the lethal trifecta pattern.

#### Scenario: Lethal trifecta detection
- **WHEN** a design involves private_data AND untrusted_input AND outbound_action
- **THEN** agent-safety-review MUST classify the design as high risk
- **AND** MUST recommend blast-radius mitigation (cutting at least one leg)
- **AND** MUST NOT claim that improved detection scores solve the problem

#### Scenario: Autonomy trigger matching
- **WHEN** the user prompts with autonomy-related language (autonomous loop, overnight, YOLO, skip permissions, etc.)
- **THEN** agent-safety-review MUST fire as a domain skill

### Requirement: Driver invariant protection
Wave 1 additions MUST NOT alter the superpowers driver invariants.

#### Scenario: Driver invariants unchanged
- **WHEN** any Wave 1 skill fires
- **THEN** the phase_compositions drivers MUST remain: DESIGN=brainstorming, PLAN=writing-plans, IMPLEMENT=executing-plans, REVIEW=requesting-code-review, SHIP=verification-before-completion, DEBUG=systematic-debugging

### Requirement: Scenario-eval test suite
The plugin MUST include a suite-level behavioral evaluation that validates routing judgment.

#### Scenario: Scenario coverage
- **WHEN** `bash tests/test-scenario-evals.sh` is run
- **THEN** it MUST test PDLC scenarios (prototype-lab, starter-template co-selection), safety scenarios (lethal trifecta, overnight, YOLO), guardrail scenarios (SHIP phase routing, composition chain), and driver-invariant scenarios (new skills never as process drivers)

### Requirement: eval-strategy classification at DESIGN
The DESIGN phase composition MUST emit an always-on advisory hint instructing the model to classify how the feature is verified — asking the user when unclear — and branch the guidance: probabilistic/AI/LLM/agent behavior plans an eval set (smoke + adversarial/safety subsets, pinned judge model+version, never-delete cases, pre-registered safety-stop) with the safety subset authored failing (red) before implementation; deterministic work uses test-driven-development plus the mandated acceptance scenarios. The hint MUST be advisory and fail-open, and MUST be mirrored into the fallback registry. Safety dimensions MUST be treated as hard pass/fail gates, never averaged into a quality blend.

#### Scenario: AI/LLM feature classification
- **WHEN** a builder is in DESIGN for a feature whose outputs cannot be exact-matched (LLM/agent/probabilistic)
- **THEN** the EVAL STRATEGY hint MUST direct planning an eval set with adversarial/safety subsets and a safety subset authored red before implementation
- **AND** it MUST NOT rely on an automatic AI-feature detector — the model classifies, asking the user when unclear

#### Scenario: Deterministic feature classification
- **WHEN** the feature is deterministic
- **THEN** the EVAL STRATEGY hint MUST direct standard test-driven-development plus the acceptance scenarios already required by the DESIGN→PLAN contract
- **AND** it MUST NOT impose eval-set ceremony (judges, adversarial subsets) on deterministic work

#### Scenario: Advisory and fail-open
- **WHEN** the hint is emitted
- **THEN** it MUST be advisory only and MUST NOT block or alter routing scores
- **AND** it MUST be present in both `config/default-triggers.json` and `config/fallback-registry.json`

### Requirement: safety eval cases red before code
The `agent-safety-review` skill MUST require that, for AI/LLM or agent features, the safety eval cases (injection, escalation, refusal, safety-routing-suppression) are authored and failing (red) before the behavior is implemented, composing with `test-driven-development`. Detection added after the behavior exists MUST NOT be treated as a substitute.

#### Scenario: Red-before-code for an agent feature
- **WHEN** agent-safety-review evaluates an AI/LLM or agent design
- **THEN** it MUST state that safety eval cases are authored and failing before the behavior is implemented
- **AND** it MUST reference composition with test-driven-development

### Requirement: safety-relevant runtime paths exercised and eval scenarios append-only
The `runtime-validation` skill MUST require that changes touching authentication/authorization, data deletion, money/payments, or destructive or externally-visible side effects exercise and report those paths (pass/fail with evidence) rather than deferring them to manual checks. Eval-pack safety scenarios MUST be append-only: a scenario MUST NOT be deleted to make the bar pass; an obsolete scenario MUST be marked deprecated with a dated rationale.

#### Scenario: Safety-relevant path must be exercised
- **WHEN** a change alters a safety-relevant path (auth, data deletion, money, destructive side effects)
- **THEN** runtime-validation MUST require that path be exercised and reported with evidence
- **AND** a green happy-path result MUST NOT be treated as clearing an unexercised safety-relevant path

#### Scenario: Eval scenarios are append-only
- **WHEN** an eval-pack safety scenario becomes inconvenient or obsolete
- **THEN** it MUST NOT be deleted to make the bar pass
- **AND** it MUST be marked deprecated with a dated rationale instead

