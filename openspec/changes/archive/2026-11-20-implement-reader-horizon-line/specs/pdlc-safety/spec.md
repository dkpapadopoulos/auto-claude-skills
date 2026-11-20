## ADDED Requirements

### Requirement: The IMPLEMENT reader prints no horizon date the registration does not commit

When `scripts/shadow-adjudicate.sh --status` reports insufficient data, its horizon row MUST state the horizon as `openspec/changes/implement-shadow-event/design.md` currently registers it. While that registration commits no date, the row MUST say the horizon is unknown pending re-estimate and MUST NOT print a date as a horizon.

#### Scenario: Below the floor with no registered horizon date

- **GIVEN** three labelled would-block episodes in one repository
- **WHEN** the reader runs `--status`
- **THEN** the horizon row reads unknown, pending re-estimate
- **AND** the output does not contain the withdrawn date 2026-09-08
