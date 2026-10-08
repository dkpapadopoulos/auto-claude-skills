## ADDED Requirements

### Requirement: Keyword-path admission is measured and recorded

The repository MUST provide a check that classifies every keyword of every skill in `config/default-triggers.json` by running the activation hook with the bare keyword as the prompt: `covered` when the skill's triggers admit it without the keyword, `keyword-only` when the keyword admits it and the triggers do not, and `inert` when the keyword does not admit it even alone. The check MUST NOT evaluate a trigger regex or a keyword substring itself. Every `keyword-only` or `inert` keyword MUST have a row in `tests/fixtures/keyword-path/decisions.tsv` naming that class, a decision and a reason, and every row MUST name a keyword that exists and is measured in that class. The check MUST fail when the ledger and the measurement disagree in either direction. When it cannot tell a selected skill from an unselected one, it MUST exit with a status distinct from both clean and failed, and MUST NOT print totals.

#### Scenario: A trigger is narrowed past a keyword

- **GIVEN** a keyword that is `covered` because a trigger alternative matches it
- **WHEN** that alternative is removed from the trigger and the check runs
- **THEN** the check fails
- **AND** it names the keyword as measured `keyword-only` with no decision recorded

#### Scenario: A keyword that cannot fire is added

- **GIVEN** a keyword that holds a capital letter, or is under six characters
- **WHEN** it is added to a skill and the check runs
- **THEN** the check fails and names the keyword as measured `inert`

#### Scenario: A keyword is removed and its row is left behind

- **GIVEN** a ledger row for a `keyword-only` keyword
- **WHEN** the keyword is deleted from the config and the check runs
- **THEN** the check fails and names the row as stale

#### Scenario: The hook selects nothing

- **GIVEN** an activation hook that prints nothing for any prompt
- **WHEN** the check runs
- **THEN** it exits with the cannot-check status
- **AND** it prints no summary line

### Requirement: Fixture lines are read through the hook

For every skill that carries keywords, the check MUST run each `MATCH` and `NO_MATCH` line of that skill's routing fixture through the activation hook with the skill's shipped config entry. A selected `NO_MATCH` line MUST fail the check unless `tests/fixtures/keyword-path/known-decoy-selections.tsv` lists it, and the finding MUST say whether the line is still selected with the skill's keywords removed. A listed line that is no longer selected, or that no fixture holds, MUST fail the check. A `MATCH` line that is not selected MUST fail the check. When a keyword-carrying skill has no fixture, or no `MATCH` line of its fixture is selected, or a line could not be run, the check MUST exit with the cannot-check status.

#### Scenario: A keyword matches inside a longer word

- **GIVEN** a skill whose trigger requires a word boundary before a phrase, and a keyword equal to that phrase
- **AND** a `NO_MATCH` line in which the phrase is the tail of a longer word
- **WHEN** the check runs and the line is not listed as known
- **THEN** the check fails and reports the line as selected through the keywords

#### Scenario: A defect is fixed and its known row is left behind

- **GIVEN** a `NO_MATCH` line listed as known
- **WHEN** the keyword that selected it is removed and the check runs
- **THEN** the check fails and names the known row as no longer selected

#### Scenario: A MATCH line stops being selected

- **GIVEN** a routing fixture with several `MATCH` lines, one of which the hook does not select
- **WHEN** the check runs
- **THEN** the check fails and names that line

#### Scenario: A keyword-carrying skill has no fixture

- **GIVEN** a skill with keywords and no routing fixture file
- **WHEN** the check runs
- **THEN** it exits with the cannot-check status
