# Capability: pdlc-closed-loop

## ADDED Requirements

### Requirement: deploy-gate fails closed on absent or broken CI

The `deploy-gate` CI check MUST distinguish three states — green, red, and **absent-or-broken** — and MUST treat absent-or-broken as a FAILURE, not a pass. Specifically, an empty `gh pr checks` result combined with an empty `gh run list` conclusion (no CI runs reported), or a CI run that concluded with zero completed steps, MUST cause the CI check to fail closed. The gate MUST NOT interpret "no checks reported" as "nothing blocking → ship". This is the design's only model-independent hard signal and MUST key on the external CI conclusion rather than on any artifact the gated agent can write.

#### Scenario: Zero CI checks fails the gate
- **GIVEN** a branch/PR for which `gh pr checks` reports no checks and `gh run list` reports no conclusion
- **WHEN** the deploy-gate CI check runs
- **THEN** the check MUST report FAIL with an explicit "absent ≠ green" message
- **AND** deploy-gate MUST NOT proceed to `openspec-ship`

#### Scenario: Zero-step CI job fails the gate
- **GIVEN** a CI run that concluded almost immediately having executed zero steps (e.g. a billing-blocked runner)
- **WHEN** the deploy-gate CI check runs
- **THEN** the check MUST report FAIL rather than reading the run as a pass

### Requirement: deploy-gate accepts a fresh local verification as the verification of record

When hosted CI is absent, the deploy-gate CI check MUST be able to accept a fresh `~/.claude/.skill-project-verified-<token>` evidence artifact with no entries in `failed` as the local verification of record, recording that verification occurred on substrate `local`. This acceptance is for surfacing local-vs-hosted provenance to the human; it MUST NOT be presented as a non-bypassable enforcement gate, since the artifact is model-writable.

#### Scenario: Local verification evidence surfaces when CI is absent
- **GIVEN** no hosted CI is configured AND a fresh `~/.claude/.skill-project-verified-<token>` exists with an empty `failed` list
- **WHEN** the deploy-gate CI check runs
- **THEN** the gate MUST report the verification as performed on substrate `local` with provenance noted
- **AND** the gate MUST still surface that hosted CI was absent rather than claiming hosted-CI green
