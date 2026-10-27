# prose-quality: suppression rationale and explicit requests

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
  precision about uncertainty, and say which moves were withheld and why

## ADDED Requirements

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
  say which edits were considered and declined

#### Scenario: Correct plain close is kept
- **GIVEN** a post whose last paragraph gives an instruction and its consequence
- **WHEN** the pass runs
- **THEN** the instruction and its consequence SHALL remain in the returned text

#### Scenario: A requested change is made
- **GIVEN** the same good draft and an explicit request to add the objection to one claim
- **WHEN** the pass runs
- **THEN** the objection SHALL be added using only material in the draft, and every other
  fact SHALL stay as written

### Requirement: Cover-letter conditional

When the draft is a cover letter or application (addressed to a hiring manager, recruiter
or committee, about the writer's fit), move 2 SHALL address only a concern the posting
states, using facts already in the letter; a gap the applicant mentions outside the
letter SHALL go in the note to the applicant rather than into the letter; and the close
SHALL ask for the conversation without qualifying the fit.

#### Scenario: Gap supplied outside the letter stays out
- **GIVEN** a cover letter and a note from the applicant that the posting lists a tool they
  have not used
- **WHEN** the pass runs
- **THEN** the returned letter SHALL NOT mention the gap, the note to the applicant SHALL,
  and the close SHALL NOT hedge the fit

#### Scenario: Gap the applicant already wrote is kept
- **GIVEN** a cover letter whose own text names the gap
- **WHEN** the pass runs
- **THEN** that sentence SHALL remain, reworded only to point at evidence already in the letter
