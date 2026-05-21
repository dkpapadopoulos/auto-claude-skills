## ADDED Requirements

### Requirement: Fallback Registry Sync Gate

The test suite MUST include a regression that fails when `config/fallback-registry.json` diverges from a deterministic regeneration of `config/default-triggers.json`. The regeneration MUST use the same jq pipeline session-start uses to write the fallback (single source of truth for the fallback shape).

#### Scenario: Default-triggers edit forgets fallback regeneration

- **GIVEN** a contributor edits `config/default-triggers.json` to add or modify a trigger block
- **AND** does NOT regenerate `config/fallback-registry.json`
- **WHEN** `bash tests/test-registry.sh` runs the sync gate test
- **THEN** the test MUST fail with a unified diff showing the drift
- **AND** the failure message MUST reference how to regenerate

#### Scenario: jq is unavailable

- **GIVEN** the test environment has no `jq` binary on PATH
- **WHEN** the sync gate test runs
- **THEN** the test MUST skip (emit `SKIP`) and MUST NOT fail the test run

### Requirement: Per-Skill Iteration Cap With Role-Allowlist Invariant

Trigger blocks in `config/default-triggers.json` MAY declare an optional `max_iterations: N` field. The activation hook (`hooks/skill-activation-hook.sh::_score_skills`) MUST honor this cap by skipping a matched skill when its prior-completion count in the session's composition state is ≥ N. The cap MUST be honored ONLY for skills with `role: domain` or `role: required`. Skills with `role: process` or `role: workflow` MUST NEVER be capped, regardless of any `max_iterations` value in their trigger block. This role-allowlist invariant MUST be hardcoded in the activation hook (not config-driven) so that override files cannot silently widen it.

#### Scenario: Domain skill at cap is skipped

- **GIVEN** a skill with `role: domain` and `max_iterations: 1`
- **AND** the session composition state lists the skill once in `.completed`
- **WHEN** a subsequent prompt matches the skill's trigger
- **THEN** the activation hook MUST skip the skill (no entry in `RESULTS`)
- **AND** under `SKILL_EXPLAIN=1` MUST emit `[max-iter] skipping <skill> (<count> of <cap>)` to stderr

#### Scenario: Required skill at cap is skipped

- **GIVEN** a skill with `role: required` and `max_iterations: 1` (such as `agent-team-review`)
- **AND** the session composition state lists the skill once in `.completed`
- **WHEN** a subsequent prompt matches the skill's trigger
- **THEN** the activation hook MUST skip the skill

#### Scenario: Process skill bypasses cap regardless of config

- **GIVEN** a skill with `role: process` and `max_iterations: 1` (deliberate misconfiguration)
- **AND** the session composition state lists the skill once in `.completed`
- **WHEN** a subsequent prompt matches the skill's trigger
- **THEN** the activation hook MUST NOT skip the skill (role-allowlist invariant)
- **AND** the skill MUST appear normally in `RESULTS`

#### Scenario: Workflow skill bypasses cap regardless of config

- **GIVEN** a skill with `role: workflow` (such as `verification-before-completion`, `openspec-ship`, or `finishing-a-development-branch`) and `max_iterations: 1`
- **WHEN** a subsequent prompt matches the skill's trigger after prior completion
- **THEN** the activation hook MUST NOT skip the skill

#### Scenario: Sessionless invocation never caps

- **GIVEN** the activation hook runs without `_SESSION_TOKEN` set (test or dry run)
- **WHEN** any skill with `max_iterations` is matched
- **THEN** the cap check MUST be bypassed (no composition state to consult)

#### Scenario: Missing composition state file fails open

- **GIVEN** `_SESSION_TOKEN` is set but the composition state file does not exist
- **WHEN** a domain or required skill with `max_iterations` is matched
- **THEN** the cap check MUST be bypassed (no count available)
- **AND** the skill MUST be allowed to fire

#### Scenario: Push gate is independent of iteration cap

- **GIVEN** the iteration cap has skipped one or more advisory lenses on the current branch
- **WHEN** the contributor attempts `git push`
- **THEN** the push gate (`hooks/openspec-guard.sh`) MUST evaluate composition state independently
- **AND** the cap-skip event MUST NOT cause the push gate to allow an incomplete SHIP composition

### Requirement: Passive Advisory-Lens Telemetry

The Skill PostToolUse completion hook (`hooks/skill-completion-hook.sh`) MUST append one JSONL line per successful Skill completion to `~/.claude/.advisory-lens-log.jsonl`. The line MUST carry the fields `ts` (UTC ISO-8601 timestamp), `skill` (the bare skill name, namespace stripped), `finding_count_estimate` (line count of `tool_response.content` or `tool_response.output` as a coarse proxy, numeric), and `session_token_hashed` (sha256 of the session token, first 12 hex characters). Write failures MUST be silently dropped — the hook MUST exit 0 regardless of telemetry success.

#### Scenario: Successful Skill completion appends one line

- **GIVEN** a Skill tool returns successfully and the existing state-mutation block runs
- **WHEN** the telemetry block executes
- **THEN** exactly one JSONL line MUST be appended to `~/.claude/.advisory-lens-log.jsonl`
- **AND** the line MUST contain all four fields: `ts`, `skill`, `finding_count_estimate`, `session_token_hashed`

#### Scenario: Telemetry write failure does not propagate

- **GIVEN** `~/.claude/.advisory-lens-log.jsonl` is unwritable (e.g., disk full, permission denied)
- **WHEN** the telemetry block runs
- **THEN** the hook MUST exit 0
- **AND** the existing state-mutation work MUST NOT be undone

#### Scenario: Missing shasum and sha256sum binaries

- **GIVEN** neither `shasum` nor `sha256sum` is on PATH
- **WHEN** the telemetry block runs
- **THEN** the line MUST still be written
- **AND** `session_token_hashed` MUST be an empty string (not omitted)

#### Scenario: No labeling required

- **GIVEN** any Skill completion event
- **THEN** the telemetry line MUST NOT require any human label or counterfactual assertion (passive shape only)
