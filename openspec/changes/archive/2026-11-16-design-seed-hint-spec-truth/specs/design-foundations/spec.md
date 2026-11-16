# design-foundations delta: where the design-seed hint is

## MODIFIED Requirements

### Requirement: Design method reachable without a design-project connector

The plugin SHALL document a design method whose primary lane requires no
external design-system connector, and SHALL surface it through a methodology
hint (`methodology_hints` entry `design-seed` in `config/default-triggers.json`)
rather than a trigger-matched skill. The hint MUST NOT be carried as a phase
composition hint: `phase_compositions.<PHASE>.hints` are empty by the
`skill-routing` capability's requirement. The hint renders only when a skill is
selected, the prompt matches the hint's trigger, and the phase is DESIGN or
IMPLEMENT; this requirement does not promise it on any other prompt.

#### Scenario: DESIGN hint renders without adding a routed skill

- **GIVEN** the routing registry built from `config/default-triggers.json`
- **WHEN** a DESIGN-phase prompt that selects a skill and matches the `design-seed` hint's trigger is scored
- **THEN** the design-seed hint MUST be rendered from `methodology_hints`
- **AND** `phase_compositions.DESIGN.hints` MUST NOT contain it
- **AND** the registry MUST contain no skill entry named `design-seed`
