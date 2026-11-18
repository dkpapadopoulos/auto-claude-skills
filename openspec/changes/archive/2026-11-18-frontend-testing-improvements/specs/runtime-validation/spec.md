# Spec Delta: runtime-validation

## ADDED Requirements

### Requirement: Report-only visual-regression overlay

The `runtime-validation` skill SHALL provide a visual-regression overlay in its Browser Path that
uses Playwright's built-in screenshot comparison (no new dependency), is self-gated on Playwright
availability, and is **report-only** — excluded from the fix-rescan loop and never hard-blocking
REVIEW, consistent with the existing Lighthouse perf overlay.

#### Scenario: First run seeds a baseline instead of failing

- **GIVEN** a browser scenario with no existing baseline screenshot
- **WHEN** the visual-regression overlay runs
- **THEN** it SHALL capture the current screenshot as the baseline under
  `tests/artifacts/validation/visual-baselines/<scenario>/<viewport>.png`
- **AND** report the result as `BASELINE_MISSING/SEEDED`, listing it in Coverage Gaps rather than
  as PASS or FAIL

#### Scenario: Subsequent run diffs against the baseline

- **GIVEN** an existing baseline for a scenario
- **WHEN** the visual-regression overlay runs and the rendered page differs
- **THEN** it SHALL report `CHANGED` in a dedicated report-only section with the diff artifact path
- **AND** the change SHALL NOT enter the fix-rescan loop or hard-block REVIEW

#### Scenario: Baselines are gitignored, not committed

- **GIVEN** the visual-regression artifact paths
- **WHEN** the repository ignore rules are evaluated
- **THEN** baselines, actuals, and diffs under `tests/artifacts/validation/` SHALL be gitignored
- **AND** the skill SHALL direct users to project-native committed snapshots for durable
  cross-commit regression

### Requirement: Visual-regression overlay is documented with an honesty note

The skill documentation SHALL state that the overlay performs session-scoped diffing (detecting
change within a review session), not cross-commit field regression, mirroring the "lab, not field"
honesty convention of the Lighthouse perf overlay.

#### Scenario: Report carries the session-scope caveat

- **GIVEN** the visual-regression report section in `skills/runtime-validation/SKILL.md`
- **WHEN** the section is inspected
- **THEN** it SHALL include a note that diffing is session-scoped and that durable regression is
  delegated to the consumer's committed snapshot suite
