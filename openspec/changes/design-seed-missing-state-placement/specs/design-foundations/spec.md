# design-foundations

## ADDED Requirements

### Requirement: A missing-state reason MUST be visible in the unit that holds the value

The shipped styleguide SHALL prescribe, as the treatment for a missing value, a
reason stated in words and visible in the same row, card or field as the value.
It SHALL state that the reason belongs in the smallest unit that holds the value
it explains, and that a `title` attribute, a footnote or a legend does not treat
the state. The treatment it prescribes MUST NOT name a hidden or distant channel.
The reference page SHALL demonstrate the same rule: no table row holding a
missing value SHALL carry a `title` attribute on any of its elements, and every
such row SHALL carry words in that row.

#### Scenario: The styleguide prescribes a visible reason

- **GIVEN** the shipped `assets/design-seed/styleguide.md`
- **WHEN** the Missing row of its states table is read
- **THEN** the treatment MUST say the reason is visible in the same row, card or
  field
- **AND** it MUST NOT name a title, a tooltip, hover, a note or footnote, or a
  legend
- **AND** it MUST NOT say the reason is invisible, not visible or never visible

#### Scenario: The styleguide states where a treatment has to appear

- **GIVEN** the shipped `assets/design-seed/styleguide.md`
- **WHEN** the paragraph opening "A state is only treated where the reader meets
  the value" is read
- **THEN** it MUST name the smallest unit that holds the value, and give the row
  of a table, the card and the field as examples
- **AND** it MUST name a `title` attribute, a footnote and a legend
- **AND** it MUST state that none of them treats the state

#### Scenario: The reference page hides no reason in an attribute

- **GIVEN** `assets/design-seed/reference.html`
- **WHEN** every table row containing an element with the class `missing` is
  inspected
- **THEN** at least one such element MUST exist
- **AND** no element in such a row MUST carry a `title` attribute, in either
  letter case and either quoting
- **AND** the file MUST NOT contain the words hover, tooltip or mouseover
  anywhere, its stylesheet included

#### Scenario: A row with a missing value says why in that row

- **GIVEN** `assets/design-seed/reference.html`
- **WHEN** each table row containing a missing value is inspected
- **THEN** the row MUST contain words, in a status element or in the missing cell
  itself
- **AND** the name of an HTML entity MUST NOT count as words

### Requirement: Every statement of the preset version MUST agree

Every file in the shipped seed that states the preset version SHALL state the
same number, and that number SHALL equal the `version` field of `tokens.json`.
The seed whose guidance prescribes a visible missing-state reason MUST NOT be
labelled version 1, which is the label the superseded guidance shipped under.

#### Scenario: One drifted site is reported

- **GIVEN** a copy of the seed in which one file states a different version
- **WHEN** the version statements across the seed are compared
- **THEN** the comparison MUST report more than one distinct version

#### Scenario: The amended guidance is not labelled version 1

- **GIVEN** the shipped `assets/design-seed/`
- **WHEN** its version statements are read
- **THEN** at least five sites MUST state a version
- **AND** every one MUST state the same version, which MUST NOT be 1

### Requirement: Regenerating tokens.json MUST keep the version the adopter holds

Adoption removes the adopter's copy of `ADOPT.md`, so a reader who regenerates
`tokens.json` follows the plugin's current instructions against an older copy of
the seed. Those instructions SHALL take the preset name and version from the
adopter's `design/adopted.json` and MUST NOT state a preset name or a version of
their own. The command SHALL exit non-zero and leave the existing `tokens.json`
unchanged when `adopted.json` is absent, when it does not hold exactly one
record carrying a preset name that is not blank and a version that is a whole
number above zero, and when it reads no tokens for one of the themes. It SHALL
accept a record that carries further keys.

#### Scenario: An earlier adopter is not restamped

- **GIVEN** a project that adopted version 1 of the seed
- **WHEN** the regenerate command in the current `ADOPT.md` is run in it, in
  either the hook shell or the model's shell
- **THEN** `design/tokens.json` MUST record version 1 and the preset name that
  project adopted
- **AND** its token maps MUST equal those in `design/tokens.css`, including a
  value the project has edited there

#### Scenario: A failed regeneration changes nothing

- **GIVEN** a project whose `design/adopted.json` or `design/tokens.css` is absent
- **WHEN** the regenerate command is run
- **THEN** it MUST exit non-zero
- **AND** `design/tokens.json` MUST be byte-identical to what it was before

#### Scenario: A record that exists and cannot be used is refused

- **GIVEN** a project whose `design/adopted.json` is empty, is not JSON, is not a
  single object, carries a blank or absent preset name, or carries a version that
  is absent, not a number, not whole, or not above zero
- **WHEN** the regenerate command is run
- **THEN** it MUST exit non-zero
- **AND** `design/tokens.json` MUST be byte-identical to what it was before

#### Scenario: A usable record with further keys is accepted

- **GIVEN** a project whose `design/adopted.json` holds a preset name, a whole
  version above zero, and keys of the project's own
- **WHEN** the regenerate command is run
- **THEN** it MUST exit zero
- **AND** `design/tokens.json` MUST record that preset name and that version

#### Scenario: One empty theme is refused

- **GIVEN** a project whose `design/tokens.css` has tokens for the light theme
  only, or for the dark theme only
- **WHEN** the regenerate command is run
- **THEN** it MUST exit non-zero
- **AND** `design/tokens.json` MUST be byte-identical to what it was before
