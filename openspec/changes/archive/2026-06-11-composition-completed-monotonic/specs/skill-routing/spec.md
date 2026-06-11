## ADDED Requirements

### Requirement: Composition completed-array monotonicity
The UserPromptSubmit walker's composition-state write MUST NOT remove entries from `.completed` while the chain is unchanged. When a prior state file exists with a `.chain` equal to the newly built chain, the written `.completed` MUST be the union of the walker's computed prefix and the prior on-disk `.completed`, projected through the chain (chain order, no duplicates, entries not in the chain dropped). When the newly built chain differs from the prior `.chain`, the prior `.completed` MUST NOT leak into the new state. Missing, unreadable, or malformed prior state MUST degrade to the prefix-only write without failing the hook.

#### Scenario: Backward re-anchor preserves recorded progress
- **WHEN** the on-disk state records `.completed` through a later chain step and a prompt re-anchors at an earlier step of the same chain (e.g. a "pr"-matching prompt after verification already ran)
- **THEN** the written `.completed` MUST still contain every previously recorded entry
- **AND** the written `.chain` MUST be unchanged
- **AND** `current_index` MUST reflect the new anchor (the write MUST still happen)

#### Scenario: Chain switch resets completed
- **WHEN** the prompt anchors a chain different from the on-disk `.chain`
- **THEN** the written `.completed` MUST NOT contain entries carried over from the old chain

#### Scenario: Malformed prior state degrades to prefix-only
- **WHEN** the prior state file is missing, unreadable, or not valid JSON
- **THEN** the walker MUST write the prefix-derived `.completed` and exit zero
