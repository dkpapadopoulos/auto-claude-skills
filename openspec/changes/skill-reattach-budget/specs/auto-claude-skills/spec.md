## ADDED Requirements

### Requirement: Owned skills fit the post-compaction re-attach budget

Every owned `skills/<name>/SKILL.md` MUST be at most 19,500 bytes, so the whole file survives Claude Code's post-compaction re-attachment (first 5,000 tokens per skill). Detail beyond that MUST live in `skills/<name>/references/` files that the core names together with the condition under which to Read them. A skill not yet split MAY exceed the budget only while listed as pending with a recorded ceiling that never rises.

#### Scenario: An over-budget skill fails the guard
- **GIVEN** an owned SKILL.md of 19,501 bytes that is not on the pending list
- **WHEN** the skill-size test runs
- **THEN** it fails naming that file and its size

#### Scenario: A pending skill may not grow
- **GIVEN** a pending skill with a recorded ceiling of 47,871 bytes
- **WHEN** its SKILL.md grows to 47,900 bytes
- **THEN** the skill-size test fails
