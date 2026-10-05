## ADDED Requirements

### Requirement: Non-human input is not displayed a routing block

The activation hook SHALL NOT emit a routing block for input that reached `UserPromptSubmit` without being typed by the user, where that input is one of: a peer-session message delivered as a single `<agent-message from="…">` block (optionally wrapped in the harness's fixed intro line and one harness paragraph), or a background-task notification followed only by `<system-reminder>` blocks. Any input that is not exactly one of those shapes MUST be treated as the user's prompt.

#### Scenario: A subagent hand-back arrives

- **WHEN** the prompt is a subagent's final report wrapped in an `<agent-message>` block and the harness paragraph
- **THEN** the hook emits no `additionalContext`

#### Scenario: A user request follows the block

- **WHEN** an `<agent-message>` block is followed by text on a later line, or preceded by text, or the prompt contains two such blocks
- **THEN** the hook routes the prompt as the user's and emits its routing block as before

#### Scenario: The classifier cannot be compiled

- **WHEN** the hook's own jq definition, the shared notification definition, or both fail to compile
- **THEN** the hook retries without the failing definition and a user prompt is still routed

### Requirement: Display suppression MUST NOT change routing state

When the activation hook suppresses its routing block, it SHALL still score, select, walk the composition chain and write every state file exactly as it would have had the block been displayed. Suppression MUST be implemented at the final print and MUST NOT be implemented by exiting early or by removing a skill from scoring.

#### Scenario: A peer message that would arm a chain

- **WHEN** a peer message whose text matches a process skill's triggers arrives in a session with no composition state
- **THEN** the composition-state file is written with the same contents as for the same text routed normally, and nothing is displayed

#### Scenario: A push follows a suppressed input

- **WHEN** a session's only chain-arming input was suppressed, review and verification have not completed on that chain, and a `git push` is attempted
- **THEN** the push gate denies on its chain check, as it would have had the block been displayed

#### Scenario: An active session receives a suppressed input

- **WHEN** a session with composition state, a prompt counter and a last-invoked signal receives a non-human input
- **THEN** each of those files changes exactly as it would for the same input with suppression disabled

### Requirement: A hyphenated frontmatter key is a key boundary

Skill discovery SHALL treat a line that begins with a hyphenated key (for example `allowed-tools:`) as the start of a new key. List items under a hyphenated key MUST NOT be appended to the preceding key, and the hyphenated key's own value is not ingested.

#### Scenario: A list key is followed by a hyphenated key

- **WHEN** a SKILL.md frontmatter declares `triggers:` as a list and then `allowed-tools:` as a list
- **THEN** the registry's triggers for that skill contain only the items listed under `triggers:`

#### Scenario: A value contains a control character

- **WHEN** a frontmatter scalar or list item contains a tab or another control character
- **THEN** the character is replaced by a space and the batch's frontmatter map remains valid JSON
