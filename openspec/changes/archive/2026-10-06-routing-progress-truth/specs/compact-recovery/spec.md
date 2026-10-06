## ADDED Requirements

### Requirement: Recovery text separates confirmed steps from assumed ones

The compaction-recovery text MUST list under "Completed:" only the steps in the composition state's `.completed`. When `.assumed` is a non-empty array it MUST list those steps on a separate line that says they were not invoked and are not evidence. A missing or non-array `.assumed` MUST be treated as empty.

#### Scenario: A session whose steps were only assumed

- **GIVEN** composition state in which one step is in `.completed` and another only in `.assumed`
- **WHEN** the recovery text is rendered
- **THEN** the "Completed:" line names the first step and not the second
- **AND** a separate line names the second step and states it was not invoked
