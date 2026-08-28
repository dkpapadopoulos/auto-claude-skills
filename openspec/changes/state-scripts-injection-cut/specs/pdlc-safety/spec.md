# Spec Delta: pdlc-safety — script-owned session-state persistence

Session-state writes MUST resolve the session token in exactly one place (a
called script), never by an incantation retyped across injection/config/skill
surfaces. Dead state writes that no reader consumes MUST NOT exist.

## Acceptance Scenarios

### Scenario 1: The model authors no token logic

- GIVEN a DESIGN-phase persist step (intent, change upsert, or discovery path)
- WHEN the guidance instructs the model to persist that state
- THEN it MUST call `scripts/persist-state.sh <op> <args>` and MUST NOT contain the token-resolution incantation (`resolve_own_session_token || cat ~/.claude/.skill-session-token`); the token is resolved inside the script

### Scenario 2: The script resolves the token payload-first

- GIVEN `persist-state.sh set-intent "<text>"` invoked from a model Bash turn
- WHEN it resolves the token
- THEN it MUST use `resolve_own_session_token` (honoring `SKILL_SESSION_TOKEN` when set), falling back to the singleton only when the lib is absent, and MUST write the same `~/.claude/.skill-openspec-state-<token>` content the prior inline incantation produced (verifiable via `openspec_state_read`)

### Scenario 3: No dead state writes

- GIVEN the `runtime-validation` and `implementation-drift-check` skills
- WHEN their SKILL.md is scanned
- THEN neither MUST write a `.skill-*-ran-<token>` marker (no reader exists) nor claim it is "checked by the SHIP phase gate"

### Scenario 4: Coverage does not regress

- GIVEN the retirement of `test-openspec-state-token-symmetry.sh`
- WHEN the test suite runs
- THEN a `persist-state.sh` unit test MUST cover token resolution and each op, AND a call-site assertion MUST fail if any writer surface reintroduces the incantation or stops calling the script
