## ADDED Requirements

### Requirement: A sticky-repeat display rule exists and hides nothing by default

The activation hook SHALL evaluate, for every block that carries a process mandate, whether the mandate was injected by sticky composition, whether it is the only skill in the block, and whether the session has already been shown that step on the same chain. `ACS_STICKY_REPEAT` SHALL select the mode, in any letter case: `shadow`, `trial`, `suppress` or `off`. When the variable is unset or holds any other value the mode MUST be `shadow`. In `shadow` the hook MUST display exactly what it displays in `off`.

#### Scenario: The default changes nothing that is displayed

- **GIVEN** a session in which a prompt has armed a composition chain
- **WHEN** a bare reply follows and `ACS_STICKY_REPEAT` is unset
- **THEN** the block displayed is byte-identical to the one displayed with `ACS_STICKY_REPEAT=off`
- **AND** a record says the rule would have hidden it

#### Scenario: A mistyped mode

- **WHEN** `ACS_STICKY_REPEAT` holds a value that is not one of the four modes
- **THEN** the block is displayed

#### Scenario: Suppress hides a repeat and nothing else

- **GIVEN** `ACS_STICKY_REPEAT=suppress` and a session already shown a chain's current step
- **WHEN** a prompt of six words or fewer that selects no skill of its own follows
- **THEN** no block is displayed
- **AND** WHEN the chain reaches its next step, that step's first block is displayed
- **AND** WHEN a prompt's own words select the already-shown skill, its block is displayed
- **AND** WHEN a short prompt's own words select another skill beside the sticky step, the block is displayed

#### Scenario: A different chain, a new task, a compaction, a marker that cannot be believed

- **GIVEN** `ACS_STICKY_REPEAT=suppress`
- **WHEN** the step belongs to a different chain than the one the session was shown it on, or the user has since ordered a process step in their own words or cancelled, or the session has been compacted since (manually or automatically), or the marker file is absent, unreadable, a directory, a FIFO or a symbolic link, or holds an over-long line, or the step is listed beyond the marker's read bound, or `~/.claude` is not writable
- **THEN** the block is displayed

### Requirement: The sticky-repeat rule MUST NOT change routing state

In every mode the activation hook SHALL write every pre-existing state file exactly as it does in `off`. The rule's marker and its record MUST be written after those files, MUST NOT be read by any gate, MUST NOT modify any existing file in place (the marker is replaced by an exclusive create and a rename; each record is a new exclusively created file), and MUST be named outside the `.skill-` family of routing-state files. Reading the marker MUST NOT hold the hook for more than a few seconds. In `shadow` the hook MUST NOT write to standard error anything it does not write in `off`. The trial arm MUST be a function of the session token alone.

#### Scenario: State is identical turn by turn

- **GIVEN** the same sequence of prompts run in `off` and in `suppress`
- **WHEN** each turn completes
- **THEN** every state file other than the rule's own marker and record is identical between the two

#### Scenario: The push gate's decision

- **GIVEN** a clean verification verdict, review evidence, and a chain armed by a work order
- **WHEN** a bare reply is hidden by the rule and a push follows
- **THEN** the push gate's output is the one it gives with the rule off

#### Scenario: A marker aliased onto a state file

- **GIVEN** the marker is a symbolic link or a hard link to a routing-state file, or the record directory is a symbolic link to the state directory
- **WHEN** a turn completes
- **THEN** that state file holds exactly what the hook writes to it with the rule off

### Requirement: The sticky-repeat record carries no prompt text

The hook SHALL write one record per block with a process mandate, in every mode but `off`, stating the session, the skill, the chain, whether the mandate was sticky, whether the step was already shown, the mode, the trial arm, and whether the block was displayed. No value in the record SHALL be taken from the prompt, and each record MUST be a single valid JSON object.

#### Scenario: The record matches what happened

- **WHEN** a turn completes
- **THEN** the record's `displayed` field is true exactly when a block was emitted for that turn
