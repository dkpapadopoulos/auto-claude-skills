# Spec: prose-quality

## ADDED Requirements

### Requirement: Activation on authored persuasive prose

The routing engine SHALL select the `authorial-judgment` domain skill when a
prompt requests authoring or de-generic-ifying persuasive prose (essay, blog
post, op-ed, article, newsletter, talk, or a "make this not sound like AI /
less generic" rewrite).

#### Scenario: Persuasive-prose prompt activates the skill
- **GIVEN** a prompt "write a blog post arguing that X"
- **WHEN** the activation hook scores skills
- **THEN** `authorial-judgment` SHALL be among the selected domain skills

#### Scenario: De-genericify rewrite activates the skill
- **GIVEN** a prompt "rewrite this so it doesn't sound like AI"
- **WHEN** the activation hook scores skills
- **THEN** `authorial-judgment` SHALL be among the selected domain skills

### Requirement: Suppression on reference, procedural, and code prompts

The routing engine SHALL NOT select `authorial-judgment` for reference,
procedural, or code writing (README, API docs, spec, changelog, release notes,
commit message, test, config), because the lens's core moves are counterproductive
for writing that must be complete, linear, and certain.

#### Scenario: Reference-doc prompt does not activate the skill
- **GIVEN** a prompt "write the README for this module"
- **WHEN** the activation hook scores skills
- **THEN** `authorial-judgment` SHALL NOT be selected

#### Scenario: Code/procedural prompt does not activate the skill
- **GIVEN** a prompt "write the changelog entry" or "write a test for the parser"
- **WHEN** the activation hook scores skills
- **THEN** `authorial-judgment` SHALL NOT be selected

### Requirement: Real-texture gate in applied guidance

When the skill is applied to a draft, its guidance SHALL derive human texture only
from real supplied details, real evidentiary uncertainty, or real editorial
judgment, and SHALL keep prose clean when none of those exist rather than
fabricating cognition, memory, persona, or flaws.

#### Scenario: No real texture available
- **GIVEN** a draft with no author-supplied detail, no evidentiary uncertainty,
  and no editorial judgment to express
- **WHEN** the authorial-judgment pass runs
- **THEN** the guidance SHALL leave the prose clean and SHALL NOT invent fake
  lived experience, uncertainty, memory, or persona
