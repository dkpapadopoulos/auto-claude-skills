# Spec delta: pdlc-safety — observed dispatch telemetry

## MODIFIED Requirements

### Requirement: Review verdict dispatch telemetry MUST record its own provenance

The review verdict artifact MUST record `dispatch_evidence` with one of exactly
three values: `observed`, `asserted`, or `imported`.

`observed` MUST be used only when a reviewer subagent return was actually
recorded for this branch. `imported` MUST be used only when the values were
derived from a resolvable pull request. `asserted` MUST be used in every other
case, including when the caller passed `--dispatch-attempted` or
`--dispatch-succeeded` explicitly.

The artifact MUST NOT report `observed` for a value it did not measure. Absence
of an observation MUST record as "not observed" and MUST NOT be rendered as an
observed negative.

`schema_version` MUST be incremented to 2. `predicate_version` MUST NOT change:
this adds a descriptive field and alters no fire condition, so existing records
remain poolable and the pre-registered observation horizon is not restarted.

`dispatch_attempted`, `dispatch_succeeded`, and `dispatch_evidence` MUST remain
telemetry. None of them, alone or collapsed, MUST act as a deny predicate.

#### Scenario: an observed dispatch is recorded as observed

- **GIVEN** a reviewer subagent returned non-error on this branch
- **WHEN** a review verdict is recorded without dispatch flags
- **THEN** `dispatch_attempted` and `dispatch_succeeded` are `true`
- **AND** `dispatch_evidence` is `observed`

#### Scenario: an assertion is not laundered into a measurement

- **GIVEN** no reviewer subagent return was recorded for this branch
- **WHEN** a review verdict is recorded WITH `--dispatch-attempted --dispatch-succeeded`
- **THEN** `dispatch_evidence` is `asserted`
- **AND** `dispatch_evidence` is NOT `observed`

#### Scenario: the telemetry cannot block a push

- **GIVEN** a verdict artifact with any combination of dispatch values
- **WHEN** the outbound push gate evaluates the branch
- **THEN** no `permissionDecision` is derived from any dispatch field

## ADDED Requirements

### Requirement: A returning reviewer subagent is observed and recorded

A `PostToolUse` hook MUST record an observed reviewer-subagent return into the
per-(repo+branch) branch ledger.

The matcher MUST cover both `Task` and `Agent` tool names, because the subagent
tool is named `Agent` on current Claude Code and `Task` on older builds.

A return whose `tool_response` reports an error MUST NOT be recorded. The error
field MUST be read through a type guard so that a non-object `tool_response`
degrades to "not errored" rather than raising and silently disabling the
recorder for every payload.

Reviewer identification MUST use a `subagent_type` allowlist, with a
`general-purpose` dispatch recorded only when its description matches a
review-intent pattern at word boundaries. Substring matching MUST NOT be used:
it credits the noun in implementation task names.

The hook MUST write nothing to stdout, MUST exit 0 on every path, and MUST NOT
be added to `_GATE_ENFORCE_LIBS`.

The hook's write and the recording script's read MUST resolve the branch-ledger
key identically. The key is a hash of the raw path string, so a non-canonical
path on either side yields a different directory and the read silently misses.

#### Scenario: a reviewer return is observed

- **GIVEN** a `PostToolUse` payload with tool name `Agent`, an allowlisted
  reviewer `subagent_type`, and no error
- **WHEN** the hook runs
- **THEN** an observed reviewer return is recorded for the current repo and branch

#### Scenario: a non-object payload does not disable the recorder

- **GIVEN** a payload whose `tool_response` is an array rather than an object
- **WHEN** the hook runs
- **THEN** the return is recorded
- **AND** the hook exits 0 having written nothing to stdout

#### Scenario: an implementation agent is not recorded as a reviewer

- **GIVEN** a payload with `subagent_type` `general-purpose` and a description
  describing implementation work
- **WHEN** the hook runs
- **THEN** no reviewer return is recorded
