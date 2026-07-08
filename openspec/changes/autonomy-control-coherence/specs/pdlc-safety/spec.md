# pdlc-safety (delta)

## ADDED Requirements

### Requirement: Autonomy↔Control Coherence Guidance at DESIGN

DESIGN-phase safety guidance MUST help the user apply the principle that agent
autonomy must be matched by proportional control/oversight. When a design is an
agentic/AI solution whose intended autonomy is `execute-reversible` or higher AND
proportional oversight is not designed in, the plugin MUST surface guidance to
add that oversight before leaving DESIGN. The guidance MUST be model-assessed
from the actual design (not keyword-triggered), MUST be advisory (never a gate or
veto), and MUST remain silent when proportional oversight is present. It MUST NOT
alter the existing `agent-safety-review` trifecta risk classification.

#### Scenario: High autonomy without oversight surfaces design-time guidance
- **GIVEN** a DESIGN-phase design for an agent that autonomously commits/acts on
  a recurring, unattended schedule with no per-run human checkpoint
- **WHEN** the DESIGN autonomy check is applied
- **THEN** the plugin MUST identify the autonomy level as
  `execute-irreversible · unattended`, MUST identify oversight as weak, and MUST
  surface guidance to add proportional oversight (per-run approval, HITL,
  manifest+dry-run review, or a bounded/reversible blast radius) before PLAN

#### Scenario: Proportional oversight present stays silent (over-fire guard)
- **GIVEN** a DESIGN-phase design for a bulk codemod run through `batch-scripting`
  with a reviewed manifest, a dry-run diff, and explicit user approval before
  execution
- **WHEN** the DESIGN autonomy check is applied
- **THEN** the plugin MUST NOT surface an autonomy advisory (oversight is strong
  — the human approval + dry-run supply the control leg), and MUST NOT block or
  gate the design

#### Scenario: agent-safety-review backstop fires at low trifecta count
- **GIVEN** a design that reaches `agent-safety-review` with autonomy level
  `execute-reversible` or higher, weak oversight, and only 0-1 trifecta fields
  present (e.g. local-only autonomous refactor on non-sensitive code, no external
  input)
- **WHEN** the safety review is produced
- **THEN** Step 2b MUST emit a proportional autonomy advisory in the output
  **even though** the trifecta classification is `Standard risk`, and the Step 4
  output MUST include an `Autonomy: <rung> · Oversight: <strong|weak>` line

#### Scenario: Trifecta classification is unchanged (additive-only invariant)
- **GIVEN** a design with exactly 2 of the 3 trifecta fields present
- **WHEN** `agent-safety-review` classifies it
- **THEN** the trifecta classification MUST still be `Elevated risk` exactly as
  before this change — Step 2b MUST NOT raise, lower, or otherwise modify the
  trifecta risk level; it only adds an independent autonomy advisory
