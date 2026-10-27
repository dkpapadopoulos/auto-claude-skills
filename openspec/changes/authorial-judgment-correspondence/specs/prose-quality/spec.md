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
