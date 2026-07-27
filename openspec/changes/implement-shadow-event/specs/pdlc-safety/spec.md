# Spec delta: pdlc-safety — IMPLEMENT-leg shadow event

## ADDED Requirements

### Requirement: Adjudicable shadow record for IMPLEMENT would-block events

The IMPLEMENT-evidence leg of the outbound gate MUST, when it reaches its warn
branch, append exactly one JSON object to
`~/.claude/.push-implement-shadow.jsonl`.

The record MUST carry `schema_version`, a `record_id` unique across records, a
UTC ISO-8601 `ts`, a `predicate_version`, `action` (`push` or `gh-merge`),
`would_block: true`, and the facts that produced the warn (`impl_in_chain`,
`material_source`, `impl_evidence_kind`), plus `session_token` and
`transcript_path` as the adjudication pointer.

The record MUST NOT contain raw command text. Records from differing
`predicate_version` values MUST NOT be pooled when computing any rate.

Writing MUST be best-effort: any failure (unwritable path, missing `jq`,
construction error) MUST leave the gate decision unchanged. The shadow log is
diagnostic and MUST NOT be added to `_GATE_ENFORCE_LIBS`. The leg MUST remain
advisory — this requirement MUST NOT introduce a `permissionDecision`.

#### Scenario: material-source push with no IMPLEMENT evidence emits a shadow record

- **GIVEN** an active chain containing `executing-plans`, a push whose diff edits
  `hooks/foo.sh`, and no IMPLEMENT invocation/ledger/bridge/attestation evidence
- **WHEN** the model runs `git push`
- **THEN** exactly one JSON object MUST be appended to the shadow log with
  `gate: "push-implement"`, `would_block: true`, `action: "push"`, and a
  `record_id` not present in any earlier record
- **AND** the guard MUST NOT emit a `permissionDecision`

#### Scenario: the same predicate on a PR merge is also recorded

- **GIVEN** the same chain, evidence, and material-source conditions
- **WHEN** the model runs `gh pr merge 7 --squash`
- **THEN** a shadow record MUST be appended with `action: "gh-merge"`
- **AND** the leg MUST remain advisory for that command

#### Scenario: satisfied IMPLEMENT evidence emits nothing

- **GIVEN** an active chain containing `executing-plans` WITH invocation evidence
  on the current branch
- **WHEN** the model runs `git push` on a material-source diff
- **THEN** no shadow record MUST be written

#### Scenario: an unwritable shadow log never affects the decision

- **GIVEN** the conditions that would produce a shadow record, and a shadow log
  path that cannot be written
- **WHEN** the model runs `git push`
- **THEN** the guard's stdout MUST be byte-identical to the same run with a
  writable path
- **AND** the guard MUST exit 0
