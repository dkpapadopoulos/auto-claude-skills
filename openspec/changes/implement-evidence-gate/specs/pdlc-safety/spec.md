# Delta: pdlc-safety — IMPLEMENT-evidence gate, precondition, test-delta

## ADDED Requirements

### Requirement: IMPLEMENT-evidence leg on the outbound push/merge gate

The push/merge gate (`openspec-guard.sh`) MUST require IMPLEMENT-phase evidence for a push or merge whose diff touches material source, when an implementation-slot skill is in the active composition chain. The implementation slot comprises `executing-plans`, `subagent-driven-development`, and `agent-team-execution`, treated as one canonical slot. Evidence is satisfied by any of: an append-only invocation record, a branch-ledger record, a cross-location bridge record, OR an explicit `phase_attest executing-plans` attestation — attestation being accepted here specifically BECAUSE IMPLEMENT is not a gating milestone (unlike `requesting-code-review` / `verification-before-completion`, which MUST NOT accept attestation). Material source is any diff path that is not docs-only (docs = `docs/**`, `openspec/**`, `*.md`). The leg MUST ship warn-first: an advisory plus a telemetry line, with NO `permissionDecision:deny`. It MAY flip to deny in the plugin's own source repo only after the **forward shadow corpus** (`~/.claude/.push-implement-shadow.jsonl`, written by `hooks/lib/implement-shadow.sh`) satisfies the pre-registered decision rule in the Pre-registration section of `openspec/changes/implement-shadow-event/design.md` — which defines what counts as a false block, the decision rule, and the sample floor. Records of differing `predicate_version` MUST NOT be pooled. This requirement MUST NOT be read as naming `scripts/phase-gate-backtest.sh`: that script replays the **skill-sequencing** gate (`skill-gate.sh`, PreToolUse `^Skill$`), not this push-gate leg, so it cannot produce the evidence this requirement demands. The walker-writable `.completed` MUST NOT by itself satisfy the leg. The gate MUST fail open on any error.

#### Scenario: material-source push with IMPLEMENT in chain and no evidence warns

- **GIVEN** an active chain containing `executing-plans`, a push whose diff edits `hooks/foo.sh`, and no IMPLEMENT invocation/ledger/bridge/attestation evidence
- **WHEN** the model runs `git push`
- **THEN** the gate MUST emit an advisory naming the missing IMPLEMENT evidence and the `phase_attest executing-plans` remedy
- **AND** in warn-first mode it MUST NOT deny the push

#### Scenario: attestation satisfies the IMPLEMENT leg

- **GIVEN** the same push, preceded by `phase_attest executing-plans "<reason>"`
- **WHEN** the gate evaluates the IMPLEMENT leg
- **THEN** the leg MUST be satisfied
- **AND** no IMPLEMENT advisory is emitted

#### Scenario: docs-only push does not trigger the leg

- **GIVEN** an active chain containing `executing-plans` and a push whose diff touches only `docs/**`, `openspec/**`, or `*.md`
- **WHEN** the model runs `git push`
- **THEN** the IMPLEMENT leg MUST NOT fire

#### Scenario: attestation never satisfies REVIEW or VERIFY

- **GIVEN** an attestation `phase_attest requesting-code-review "<reason>"`
- **WHEN** the push gate evaluates the REVIEW leg
- **THEN** the attestation MUST NOT satisfy it (REVIEW/VERIFY require real invocation or ledger evidence)

### Requirement: executing-plans CURRENT-step precondition

The `executing-plans` composition entry in `config/default-triggers.json` and `config/fallback-registry.json` MUST carry a `precondition` string instructing the model to invoke an implementation-slot skill BEFORE editing code, and to record a deliberate skip via `phase_attest executing-plans "<reason>"`. The two config files MUST be edited together (canonical source + regenerated fallback). The precondition MUST be validated by a control-vs-treatment behavioral A/B eval showing treatment materially raises the rate of implementation-slot invocation before the first source edit, with no safety regression, before it is adopted.

#### Scenario: precondition present and renders on the IMPLEMENT step

- **GIVEN** the `executing-plans` entry in `config/default-triggers.json`
- **WHEN** the registry is built and the IMPLEMENT step is the current phase
- **THEN** the entry MUST contain a non-empty `precondition`
- **AND** the rendered CURRENT-step block MUST include the precondition text

#### Scenario: config pair stays consistent

- **GIVEN** a `precondition` added to `executing-plans` in `config/default-triggers.json`
- **WHEN** `config/fallback-registry.json` is regenerated
- **THEN** both files MUST carry the identical `precondition`

### Requirement: deterministic test-delta verdict dimension

`verify-and-record.sh` MUST record a `test_delta` field in the verification verdict with value `covered`, `missing`, or `n/a`: `covered` when a material source change in the verified range is accompanied by a test-file change; `missing` when material source changed with no test-file change; `n/a` when no material source changed. Test files are identified by the declared gate's test globs (default `tests/*.sh`). The field MUST be recorded honestly by the script (the model MUST NOT author it) and MUST be readable via a `verdict.sh` accessor. In v1 the field is advisory: recorded and surfaced in the verify report, NOT wired to any deny.

#### Scenario: source change without a test change records missing

- **GIVEN** a verified range that edits `scripts/foo.sh` but no `tests/*.sh`
- **WHEN** `verify-and-record.sh` writes the verdict
- **THEN** `test_delta` MUST be `missing`

#### Scenario: source change with a paired test change records covered

- **GIVEN** a verified range that edits `scripts/foo.sh` and `tests/test-foo.sh`
- **WHEN** the verdict is written
- **THEN** `test_delta` MUST be `covered`

#### Scenario: docs-only change records n/a

- **GIVEN** a verified range touching only `docs/**` / `*.md`
- **WHEN** the verdict is written
- **THEN** `test_delta` MUST be `n/a`
