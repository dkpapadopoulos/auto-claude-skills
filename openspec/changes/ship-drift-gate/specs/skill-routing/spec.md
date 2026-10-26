## ADDED Requirements

### Requirement: SHIP drift-check fallback is gated like REVIEW's

SHIP's `implementation-drift-check` SEQUENCE entry (the fallback for a drift check that did not run in REVIEW) MUST carry `"gate": "artifact-presence"` with an `artifacts` list equal to the one on REVIEW's `implementation-drift-check` PARALLEL entry, in both `config/default-triggers.json` and `config/fallback-registry.json`. The activation hook MUST therefore render the SHIP fallback line only when REVIEW's artifact-presence gate for the same skill would pass. Because the config format cannot reference another entry's list, a test MUST assert the two lists are equal in each config.

#### Scenario: no comparison material, no SHIP drift line

- **WHEN** the activation hook renders the SHIP phase for a project root that contains none of the listed artifacts
- **THEN** the output does not contain the `SEQUENCE: implementation-drift-check` fallback line
- **AND** the other SHIP SEQUENCE lines still render

#### Scenario: a plan file present, SHIP drift line renders

- **WHEN** the activation hook renders the SHIP phase for a project root that contains `docs/plans/x-plan.md`
- **THEN** the output contains the `SEQUENCE: implementation-drift-check` fallback line
