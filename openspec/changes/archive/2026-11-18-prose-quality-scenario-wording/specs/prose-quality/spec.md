## MODIFIED Requirements

### Requirement: Suppression on reference, procedural, and code prompts

The routing engine SHALL NOT select `authorial-judgment` for reference,
procedural, or code writing (README, API docs, spec, changelog, release notes,
commit message, test, config), because this persuasive-prose workflow is not
their default editing lens. The suppression governs inferred activation only: an
explicit request to apply the skill to such text SHALL receive a scope-aware
response (precision about uncertainty still applies; the genre-specific moves do
not), not a refusal and not the full persuasive-prose pass.

#### Scenario: Reference-doc prompt does not activate the skill
- **GIVEN** a prompt "write the README for this module"
- **WHEN** the activation hook scores skills
- **THEN** `authorial-judgment` SHALL NOT be selected

#### Scenario: Code/procedural prompt does not activate the skill
- **GIVEN** a prompt "write the changelog entry" or "write a test for the parser"
- **WHEN** the activation hook scores skills
- **THEN** `authorial-judgment` SHALL NOT be selected

#### Scenario: Explicit request on procedural text gets a scope-aware pass
- **GIVEN** a prompt "run these release notes through the authorial-judgment skill"
- **WHEN** the skill is applied
- **THEN** the guidance SHALL keep the notes complete, linear and literal, apply only
  precision about uncertainty

### Requirement: Minimum effective edit on a good draft

When the skill is applied to a draft whose facts, rhythm and close already do their
work, the guidance SHALL return it near-unchanged: every fact, number, date, name,
commitment and stated certainty SHALL stay as the author wrote it; a plain claim SHALL
stay plain unless the draft's own evidence contradicts it; a close that states a
consequence SHALL NOT be replaced by one that states none; an objection that needs
material the author has not supplied SHALL go in the note to the author, not in the
piece; and the response SHALL list the largest edits made, or say that none were.

#### Scenario: Good newsletter draft comes back unchanged
- **GIVEN** a draft with specific supplied facts (counts, a date, named tools) and a close
  that states a consequence of its own argument
- **WHEN** the authorial-judgment pass runs with no further request
- **THEN** the returned text SHALL keep every fact and the close, and the response SHALL
  list the largest edits made, or say that none were

#### Scenario: Correct plain close is kept
- **GIVEN** a post whose last paragraph gives an instruction and its consequence
- **WHEN** the pass runs
- **THEN** the instruction and its consequence SHALL remain in the returned text

#### Scenario: A requested change is made
- **GIVEN** the same good draft and an explicit request to add the objection to one claim
- **WHEN** the pass runs
- **THEN** the objection SHALL be added using only material in the draft, and every other
  fact SHALL stay as written
