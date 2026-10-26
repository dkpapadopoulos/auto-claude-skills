## ADDED Requirements

### Requirement: Owned skills fit the post-compaction re-attach budget

Every owned `skills/<name>/SKILL.md` MUST be at most 19,500 bytes, so the whole file survives Claude Code's post-compaction re-attachment (first 5,000 tokens per skill). Detail beyond that MUST live in `skills/<name>/references/` files that the core names together with the condition under which to Read them. A skill not yet split, or one whose rules alone exceed the budget, MAY exceed the budget only while listed as pending with a recorded ceiling equal to its current size; the ceiling MAY rise only in a commit whose message states the reason, and a pending skill whose size changes without its ceiling changing in the same commit MUST fail the guard.

#### Scenario: An over-budget skill fails the guard
- **GIVEN** an owned SKILL.md of 19,501 bytes that is not on the pending list
- **WHEN** the skill-size test runs
- **THEN** it fails naming that file and its size

#### Scenario: A pending skill may not grow
- **GIVEN** a pending skill with a recorded ceiling of 47,871 bytes
- **WHEN** its SKILL.md grows to 47,900 bytes
- **THEN** the skill-size test fails

#### Scenario: A raise is recorded, never silent
- **GIVEN** a pending skill whose SKILL.md grows from 83,053 to 85,250 bytes because its gates are restated inside the re-attach window
- **WHEN** the same commit raises its recorded ceiling to 85,250 and its message states the reason
- **THEN** the skill-size test passes, and the raise is visible in the diff and the commit message
