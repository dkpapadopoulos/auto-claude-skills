# design-foundations

## ADDED Requirements

### Requirement: A missing-state reason MUST be visible beside the value

The shipped styleguide SHALL prescribe, as the treatment for a missing value, a
reason stated in words in the visible render. It SHALL state that the reason
belongs in the same unit as the value it explains, and that a `title` attribute,
a footnote or a legend does not treat the state. The styleguide MUST NOT
prescribe a hidden channel as the treatment. The reference page SHALL demonstrate
the same rule: no element it marks as missing SHALL carry its reason in a `title`
attribute, and every table row holding a missing value SHALL carry words in that
row.

#### Scenario: The styleguide prescribes a visible reason

- **GIVEN** the shipped `assets/design-seed/styleguide.md`
- **WHEN** the Missing row of its states table is read
- **THEN** the treatment MUST say the reason is visible
- **AND** it MUST NOT name a title attribute, a tooltip or hover as the treatment

#### Scenario: The styleguide states where a treatment has to appear

- **GIVEN** the shipped `assets/design-seed/styleguide.md`
- **WHEN** it is searched for the placement rule
- **THEN** it MUST state that a state is only treated where the reader meets the
  value

#### Scenario: The reference page hides no reason in an attribute

- **GIVEN** `assets/design-seed/reference.html`
- **WHEN** every element carrying the class `missing` is inspected
- **THEN** at least one such element MUST exist
- **AND** none MUST carry a `title` attribute
- **AND** the page's prose MUST NOT describe a reason shown on hover

#### Scenario: A row with a missing value says why in that row

- **GIVEN** `assets/design-seed/reference.html`
- **WHEN** each table row containing a missing value is inspected
- **THEN** the row MUST contain words, in a status element or in the missing cell
  itself

### Requirement: Every statement of the preset version MUST agree

Every file in the shipped seed that states the preset version SHALL state the
same number, and that number SHALL equal the `version` field of `tokens.json`.
The seed whose guidance prescribes a visible missing-state reason SHALL be
version 2.

#### Scenario: One drifted site is reported

- **GIVEN** a copy of the seed in which one file states a different version
- **WHEN** the version statements across the seed are compared
- **THEN** the comparison MUST report more than one distinct version

#### Scenario: The amended guidance is not labelled version 1

- **GIVEN** the shipped `assets/design-seed/`
- **WHEN** its version statements are read
- **THEN** at least six sites MUST state a version
- **AND** every one MUST state version 2
