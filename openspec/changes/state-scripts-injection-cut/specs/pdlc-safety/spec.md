## MODIFIED Requirements

### Requirement: Script-owned session-state persistence

Session-state writes MUST resolve the session token in exactly one place (a
called script), never by an incantation retyped across injection, config, or
skill surfaces. Dead state writes that no reader consumes MUST NOT exist. The
resolving script MUST resolve the token the same way the openspec-state reader
does — `resolve_own_session_token` then the singleton — and MUST NOT honor
`SKILL_SESSION_TOKEN`, which no openspec-state reader honors.

#### Scenario: The model authors no token logic
- **WHEN** a DESIGN-phase persist step (intent, change upsert, or discovery path) is instructed
- **THEN** the guidance MUST call `scripts/persist-state.sh <op> <args>`
- **AND** it MUST NOT contain the token-resolution incantation (`resolve_own_session_token || cat ~/.claude/.skill-session-token`)

#### Scenario: The script resolves the token payload-first
- **WHEN** `persist-state.sh set-intent "<text>"` is invoked from a model Bash turn
- **THEN** it MUST resolve the token via `resolve_own_session_token`, falling back to the singleton only when the lib is absent
- **AND** it MUST write the same `~/.claude/.skill-openspec-state-<token>` content the prior inline incantation produced
- **AND** a set `SKILL_SESSION_TOKEN` MUST NOT redirect the write

#### Scenario: No dead state writes
- **WHEN** the `runtime-validation` and `implementation-drift-check` skills are scanned
- **THEN** neither MUST write a `.skill-*-ran-<token>` marker
- **AND** neither MUST claim such a marker is "checked by the SHIP phase gate"

#### Scenario: Coverage does not regress
- **WHEN** `test-openspec-state-token-symmetry.sh` is retired
- **THEN** a `persist-state.sh` unit test MUST cover token resolution and each op
- **AND** a call-site assertion MUST fail if any converted surface reintroduces the incantation or stops calling the script
