# skill-routing — Delta: lethal-trifecta DESIGN/REVIEW model-asks directive

## ADDED Requirements

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
