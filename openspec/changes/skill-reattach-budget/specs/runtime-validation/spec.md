## MODIFIED Requirements

### Requirement: Visual-regression overlay is documented with an honesty note

The skill documentation SHALL state that the overlay performs session-scoped diffing (detecting
change within a review session), not cross-commit field regression, mirroring the "lab, not field"
honesty convention of the Lighthouse perf overlay.

#### Scenario: Report carries the session-scope caveat

- **GIVEN** the visual-regression report section in `skills/runtime-validation/references/report-template.md`
- **WHEN** the section is inspected
- **THEN** it SHALL include a note that diffing is session-scoped and that durable regression is
  delegated to the consumer's committed snapshot suite
