## ADDED Requirements

### Requirement: Routing text does not contradict the superpowers backbone

The text the activation hook renders, meaning registry descriptions and preconditions in both `config/default-triggers.json` and `config/fallback-registry.json`, and the per-phase `RED_FLAGS`, MUST NOT instruct the model to do something the superpowers skill it routes to forbids. Specifically:

- The brainstorming precondition MUST place the trifecta classification, and any `Skill(auto-claude-skills:agent-safety-review)` invocation it calls for, before the design doc is approved. It MUST NOT direct an invocation after approval or "before leaving DESIGN", because brainstorming's exit after approval is writing-plans and no other skill.
- The PLAN red flags MUST NOT name a required plan directory.
- The IMPLEMENT red flags MUST NOT require an execution method other than the one the user chose at the plan handoff.
- The DESIGN red flags MUST contain the routing obligation "Editing implementation files before invoking Skill(superpowers:brainstorming)".

#### Scenario: DESIGN exit names no post-approval invocation

- **WHEN** the brainstorming precondition is read from either config
- **THEN** it says the trifecta classification and any `agent-safety-review` invocation happen before the design doc is approved
- **AND** it does not contain "before leaving DESIGN"

#### Scenario: red flags defer to the backbone's choices

- **WHEN** the PLAN and IMPLEMENT `RED_FLAGS` are rendered
- **THEN** no PLAN flag contains `docs/plans/`
- **AND** no IMPLEMENT flag names `subagent-driven-development` or `agent-team-execution` as required
- **AND** the IMPLEMENT flags name the execution method the user chose at the plan handoff

#### Scenario: the routing obligation stays

- **WHEN** the DESIGN `RED_FLAGS` are rendered
- **THEN** they contain "Editing implementation files before invoking Skill(superpowers:brainstorming)"
