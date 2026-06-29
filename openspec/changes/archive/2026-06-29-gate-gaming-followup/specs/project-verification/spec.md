# project-verification — Gate-Gaming Detector Limits (delta)

## ADDED Requirements

### Requirement: Gate-Gaming Detector Limits Are Stated

The skill SHALL state the limits of the gate-gaming detector so trust is calibrated: a `clean`
result MUST NOT be presented as proof that no gate-gaming occurred. The guidance SHALL name the
structural blind spots the line-diff check cannot see (at minimum: stubbing the subject-under-test,
control-flow guards that skip assertions, block-comment- or docstring-muted assertions, and
uncommon per-language skip dialects) and SHALL note that the check can false-alarm on benign moves
and renames. The detector MUST remain advisory (it MUST NOT hard-block).

#### Scenario: A clean detector result is not reported as a guarantee

- **GIVEN** the gate-gaming check returns `clean`
- **WHEN** the skill reports verification results
- **THEN** the guidance MUST NOT claim "no gate-gaming"
- **AND** it MUST direct that a human reviewer still owns assertion integrity

#### Scenario: Structural blind spots are documented

- **WHEN** the skill describes the gate-gaming detector
- **THEN** it MUST list the gaming forms the line-diff check cannot detect
- **AND** it MUST NOT claim coverage of subject-stubbing or control-flow gaming
