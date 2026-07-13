# Spec Delta: skill-routing — Design Guard GIVEN/WHEN/THEN Body Check

## ADDED Requirements

### Requirement: Acceptance Scenarios body check in the PLAN-phase design guard

The DESIGN COMPLETENESS check in `hooks/skill-activation-hook.sh` SHALL, when the Acceptance Scenarios heading is present in the design file, count GIVEN/WHEN/THEN triplets within that section (case-sensitive uppercase tokens, section scoped from the heading to the next h2/h3) and mark the Acceptance Scenarios line `[OK]` only when `min(GIVEN, WHEN, THEN) >= 2`. The check SHALL remain advisory-only (never denies) and SHALL fail open to heading-presence semantics on any extraction error.

#### Scenario: Contract satisfied

- GIVEN a design file whose Acceptance Scenarios section contains at least 2 GIVEN/WHEN/THEN scenarios
- WHEN the PLAN-phase design guard runs
- THEN the Acceptance Scenarios line renders `[OK]`

#### Scenario: Empty or thin heading

- GIVEN a design file with an Acceptance Scenarios heading but fewer than 2 uppercase GIVEN/WHEN/THEN triplets in its section body
- WHEN the guard runs
- THEN the line renders `[X]` with a "heading present but <2 GIVEN/WHEN/THEN scenarios" message, and the hook exit remains advisory (no deny)

#### Scenario: Tokens outside the section do not count

- GIVEN a design file where GIVEN/WHEN/THEN tokens appear only outside the Acceptance Scenarios section
- WHEN the guard runs
- THEN the section count is 0 and the line renders the thin-heading `[X]` message

#### Scenario: Extraction failure fails open

- GIVEN the section extraction errors or returns a non-numeric count
- WHEN the guard runs
- THEN the Acceptance Scenarios line degrades to heading-presence semantics and the hook completes normally
