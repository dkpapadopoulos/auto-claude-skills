# Spec Delta: runtime-validation — Expectation Provenance

## ADDED Requirements

### Requirement: Expectation provenance for validation scenarios

`skills/runtime-validation/SKILL.md` SHALL require, in the scenario-derivation step (Step 2), that every validation scenario's expected outcome traces to one of the three source tiers — `eval-pack`, `intent-truth`, or `generic-smoke`. The implementation under validation MAY inform which paths to exercise and supplies actual observations, but MUST NOT define what counts as correct. A scenario whose expectation cannot be traced to a source tier MUST NOT be reported as PASS.

#### Scenario: Expectation derivable only from the implementation

- GIVEN a change whose only statement of expected behavior is the implementation itself
- WHEN the agent derives validation scenarios per Step 2
- THEN the scenario MUST be downgraded to `generic-smoke` or recorded as a Coverage Gap flagged for human definition of expected behavior, not reported as a spec-backed PASS

#### Scenario: Report row with out-of-enum Source

- GIVEN a validation report row whose Source value is not `eval-pack`, `intent-truth`, or `generic-smoke`
- WHEN the report is assembled per Step 4
- THEN the row is invalid and MUST be re-derived from a valid source tier or dropped

#### Scenario: Content test asserts the directive

- GIVEN `tests/test-validation-skill-content.sh` runs against `skills/runtime-validation/SKILL.md`
- WHEN the provenance assertions execute
- THEN they MUST fail if the Expectation Provenance rule (source-tier enum + "MUST NOT define what counts as correct") is absent from the skill
