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
