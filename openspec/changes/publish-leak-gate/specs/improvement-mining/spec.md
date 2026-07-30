# Spec delta: improvement-mining — cite memory evidence by path:line

## ADDED Requirements

### Requirement: Published proposals MUST cite memory evidence by path and line

A memory-derived candidate MUST be published citing `memory/<file>.md:<line>`
together with an observed-at date, and the published body MUST NOT contain the
cited line verbatim.

Evidence that is not private — eval-report issue bodies, `gate-status` output,
commit shas, issue numbers — MAY continue to be quoted verbatim.

The in-session report presented at the human gate MUST continue to carry the
verbatim quote: it is not a publication surface, and the quote is what makes the
approve/reject decision reviewable.

The skill's human-approval gate MUST NOT be weakened by this requirement, and the
miner's read access to the memory corpus MUST remain unrestricted.

The skill documentation MUST state that the existing `--body-file` requirement is
a command-injection control and is not a confidentiality control.

#### Scenario: a memory-derived proposal is published with a citation

- **GIVEN** a candidate whose supporting evidence is a line in a memory file
- **WHEN** the user approves it and the skill creates the issue
- **THEN** the published body MUST carry `memory/<file>.md:<line>` and an
  observed-at date, and MUST NOT contain the line verbatim

#### Scenario: the in-session report retains the verbatim quote

- **GIVEN** the same candidate
- **WHEN** the skill presents its ranked report for approval
- **THEN** the report MUST show the verbatim quote with its provenance

#### Scenario: non-private evidence is unaffected

- **GIVEN** a candidate whose evidence is a bot-authored eval-report issue body
- **WHEN** the proposal is published
- **THEN** the body MAY quote that evidence verbatim
