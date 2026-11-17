## ADDED Requirements

### Requirement: A pasted-content shadow record exists and changes nothing displayed

For every prompt that reaches scoring and contains the harness paste opener `<pasted_content id="`, when the session has a token, the activation hook SHALL write one record stating what rule R would keep and hide: R keeps a selected skill when the hook's own scorer, sticky composition (from the chain's step before this turn's writes) and role caps select it for the prompt with every wrapped paste removed, or when sticky composition injected it for the full prompt, and hides every other selected skill. The context bonus is not applied to that second selection. A wrapped paste is an opener with a four-lowercase-hex `id` up to the first closer carrying the same `id`, with no opener of that `id` in between. When the stripped text exceeds 16,384 characters or the hook has already run for 3 seconds, the second selection SHALL NOT run and the record SHALL say `skipped` and hide nothing. `ACS_PASTE_SHADOW` set to `off` in any letter case SHALL disable the record; any other value, or none, is shadow. In shadow the hook MUST display exactly what it displays with `off`.

#### Scenario: The default changes nothing that is displayed

- **GIVEN** a prompt whose only routing words are inside a wrapped paste
- **WHEN** `ACS_PASTE_SHADOW` is unset
- **THEN** the block displayed is byte-identical to the one displayed with `ACS_PASTE_SHADOW=off`
- **AND** a record says every selected skill would be hidden

#### Scenario: Typed words still select

- **GIVEN** a prompt with typed text before and after a wrapped paste
- **WHEN** the turn completes
- **THEN** the record keeps exactly the selected skills the hook selects for the prompt with the paste removed

#### Scenario: A block that never closes

- **GIVEN** an opener with no closer carrying its id
- **WHEN** the turn completes
- **THEN** nothing is stripped and the record hides nothing

#### Scenario: A sticky step

- **GIVEN** a chain armed by an earlier prompt and a wrapped prompt of six words or fewer
- **WHEN** sticky composition injects the chain's step
- **THEN** the record keeps that step

#### Scenario: A short reply with a paste inside a chain

- **GIVEN** a chain armed by an earlier prompt
- **WHEN** the prompt is "go" followed by a wrapped paste that selects the chain's current step
- **THEN** the record keeps that step, because the hook answers "go" alone with it

#### Scenario: A stray opener before a block with the same id

- **GIVEN** an opener with no closer, then typed text, then a block whose id equals the stray opener's
- **WHEN** the turn completes
- **THEN** the typed text is part of the stripped prompt

#### Scenario: Long typed text

- **GIVEN** a wrapped prompt whose text outside the paste exceeds 16,384 characters
- **WHEN** the turn completes
- **THEN** the record says `skipped`, hides nothing, and the prompt is not scored a second time

### Requirement: The pasted-content shadow MUST NOT change routing state

The activation hook SHALL write every routing state file exactly as it does with `ACS_PASTE_SHADOW=off`, and SHALL exit 0 whenever it does with `off`. The parse and the second selection MUST run after the block is printed and after every state write, the second selection in a subshell. When the prompt has more than 16 openers the parser's regex MUST NOT run. Each record MUST be a new exclusively created file outside the `.skill-` family.

#### Scenario: State is identical turn by turn

- **GIVEN** the same sequence of prompts, wrapped and not, run with and without `ACS_PASTE_SHADOW=off`
- **WHEN** each turn completes
- **THEN** every `.skill-` state file is identical between the two

#### Scenario: Stripping before scoring would not be

- **GIVEN** the hook altered to strip wrapped pastes before scoring
- **WHEN** a paste-only prompt is routed
- **THEN** its state differs from the unaltered hook's

### Requirement: The pasted-content record carries no prompt text

No value in the record SHALL be taken from the prompt text: the record holds the session token, counts, status words, mode words and registry skill names only, and each record MUST be a single valid JSON object.

#### Scenario: A pasted review

- **WHEN** a prompt containing a pasted code review is recorded
- **THEN** no word of the prompt appears in the record
