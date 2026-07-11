## ADDED Requirements

### Requirement: Global Fail-Closed Push Gate

The push gate MUST fire for every agent-attempted `git push`, independent of any
active composition chain, and MUST deny the push unless the branch carries **both**
a durable `requesting-code-review` record **and** a passing
`verification-before-completion` signal (a branch-ledger milestone, a session-local
`.completed` fallback, or a SHA-bound clean verification verdict covering HEAD).

The gate MUST be fail-open on infrastructure error: it runs only when the branch-ledger
library loaded AND `jq` is available, because every evidence leg is jq-dependent;
absent either, no push is denied. Only a check that runs and finds no record MUST deny.

The bypass `ACSM_SKIP_PUSH_GATE=1` MUST be honored only as an environment variable in
the hook's own process (human-set at Claude Code launch). The gate MUST NOT scan the
push command string for the bypass token, because the agent composes that string and
a command-string scan would be an agent-forgeable bypass.

#### Scenario: Non-driven session push with no records is denied
- **WHEN** an agent runs `git push` on a branch with no composition state, no ledger
  review record, and no verify signal
- **THEN** the gate MUST deny the push and name the missing `requesting-code-review`
  and/or `verification-before-completion` gate

#### Scenario: Review present but verify missing is denied
- **WHEN** an agent runs `git push` on a branch whose ledger records
  `requesting-code-review` but has no passing verify signal
- **THEN** the gate MUST deny the push and name the missing
  `verification-before-completion` gate

#### Scenario: Inline bypass token is not honored
- **WHEN** an agent runs `ACSM_SKIP_PUSH_GATE=1 git push` (the token inline in the
  command string) on a branch missing a required record
- **THEN** the gate MUST still deny the push (the inline token MUST NOT bypass it)

#### Scenario: Human-set env var bypasses the gate
- **WHEN** `ACSM_SKIP_PUSH_GATE=1` is exported in the hook's process environment
- **THEN** the gate MUST skip all push-gate denials

#### Scenario: Missing jq falls open
- **WHEN** an agent runs `git push` on a branch that would be denied with `jq` present,
  but `jq` is not on PATH
- **THEN** the gate MUST NOT deny the push (fail-open, "jq optional at runtime")
