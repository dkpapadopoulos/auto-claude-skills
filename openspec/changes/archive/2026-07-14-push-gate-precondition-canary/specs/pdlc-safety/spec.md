# pdlc-safety (delta)

## ADDED Requirements

### Requirement: Push-gate degradation is surfaced at session start

Session start MUST emit a `PUSH-GATE CANARY` warning naming the affected
component whenever a load-bearing push-gate component — the guard hook or a
gate library it sources (`branch-ledger.sh`, `verdict.sh`, `git-command.sh`,
`session-token.sh`) — is missing or fails a syntax parse, and the jq-less
session-start fallback message MUST state that the push gate cannot
establish evidence and falls open. A healthy environment MUST emit no canary
output. The canary MUST be fail-open: an error inside the check itself MUST
NOT break session start, and the canary MUST only report — it MUST NOT
modify or repair any enforcement file.

#### Scenario: Healthy environment stays silent

- **GIVEN** a plugin root whose guard and gate libraries all exist and parse
- **WHEN** the session-start hook runs
- **THEN** its output MUST NOT contain `PUSH-GATE CANARY`

#### Scenario: Broken gate library is named

- **GIVEN** a plugin root where `hooks/lib/branch-ledger.sh` has a syntax
  error (or is deleted)
- **WHEN** the session-start hook runs
- **THEN** the output MUST contain a `PUSH-GATE CANARY` warning that names
  `branch-ledger.sh` and states the gate silently skips affected checks

#### Scenario: Missing jq names the gate consequence

- **GIVEN** a PATH without jq
- **WHEN** the session-start hook runs its jq-less fallback
- **THEN** the fallback message MUST state the push gate falls open until jq
  is installed
