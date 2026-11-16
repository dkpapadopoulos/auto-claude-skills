# pdlc-safety delta: registered hint cut

## ADDED Requirements

### Requirement: Eval-strategy procedure lives in runtime-validation

`skills/runtime-validation/SKILL.md` MUST carry the eval-strategy procedure under a heading "Eval strategy at DESIGN": the model classifies how a feature is verified, asking the user when unclear; probabilistic, LLM or agent behaviour plans an eval set with adversarial and safety subsets, the safety subset authored failing before implementation; deterministic work uses test-driven development plus the acceptance scenarios. Safety dimensions MUST be treated as hard pass/fail gates, never averaged into a quality blend. The section MUST place the classification before the design doc is approved, or before building when there is no design doc, and MUST NOT say "before leaving DESIGN" (the timing the removed hint carried, and the same rule the brainstorming precondition follows). (This keeps the content obligations of the removed "eval-strategy classification at DESIGN" requirement; only the always-on DESIGN hint is gone.)

#### Scenario: The procedure is present in the owning skill

- **WHEN** `skills/runtime-validation/SKILL.md` is read
- **THEN** it contains the heading "Eval strategy at DESIGN"
- **AND** it states that safety dimensions are hard pass/fail gates and are never averaged

#### Scenario: The timing is the design doc's approval, not "leaving DESIGN"

- **WHEN** the "Eval strategy at DESIGN" section is read
- **THEN** it contains "before the design doc is approved (no design doc: before building)"
- **AND** it does not contain "before leaving DESIGN" in any letter case

## REMOVED Requirements

### Requirement: eval-strategy classification at DESIGN

**Reason**: Registered hint cut (`tests/probes/compliance-census/README.md`, read 2026-11-15). The requirement mandates an always-on DESIGN hint; all shipped phase hints are removed. This is a cost decision, not a finding that the hint had no effect. Measured 2026-11-15: the hint rendered in 188 sessions since 2026-10-12 and the skill it names, `runtime-validation`, was invoked in none.

**Migration**: The eval-strategy procedure stays in `skills/runtime-validation/SKILL.md` ("Eval strategy at DESIGN"), including the rule that safety dimensions are hard pass/fail gates. Nothing renders it at DESIGN; it is reached by `runtime-validation`'s triggers or by name.
