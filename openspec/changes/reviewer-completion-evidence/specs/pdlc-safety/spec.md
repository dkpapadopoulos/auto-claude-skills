# Spec delta: pdlc-safety — observed reviewer completion

## ADDED Requirements

### Requirement: A reviewer subagent's COMPLETION MUST be recorded distinctly from its dispatch

The plugin MUST record a `reviewer-returned` milestone into the per-(repo+branch)
branch ledger when a reviewer subagent runs to completion, and this milestone
MUST be distinct from the existing `reviewer-ran` dispatch milestone. A dispatch
that never completes MUST NOT produce `reviewer-returned`.

The recorder MUST be diagnostic-only: it MUST emit nothing on stdout, MUST NOT
set a `permissionDecision`, and MUST exit 0 on every failure path. It MUST NOT
be added to `_GATE_ENFORCE_LIBS`.

No gate decision in this change MAY read `reviewer-returned`.

#### Scenario: a reviewer subagent completes

- **GIVEN** a subagent whose `agent_type` is in the reviewer allowlist
- **WHEN** the `SubagentStop` hook receives its completion payload
- **THEN** `reviewer-returned` is recorded in the branch ledger
- **AND** the hook writes nothing to stdout and exits 0

#### Scenario: a non-reviewer subagent completes

- **GIVEN** a subagent whose `agent_type` is `general-purpose` and whose
  `agent_id` was never recorded as a reviewer dispatch
- **WHEN** the `SubagentStop` hook receives its completion payload
- **THEN** no milestone is recorded
- **AND** the hook writes nothing to stdout and exits 0

### Requirement: Reviewer identification for `general-purpose` MUST use the dispatch-time pairing key, not the task prompt

For a subagent whose `agent_type` is `general-purpose`, reviewer-ness MUST be
resolved by looking up the `agent_id` recorded at dispatch time.

The word-boundary description predicate MUST NOT be applied to the subagent's
task prompt. That predicate was fitted on the short dispatch `description`; its
`*[Rr]eview[!a-zA-Z]*` arm matches any occurrence of the word followed by a
non-letter, so against multi-paragraph prompt text it degenerates into the
substring variant that measured 4/7 false positives.

A lookup MISS MUST record nothing. A missing, unreadable, or unparseable pairing
file MUST be treated as a miss and MUST NOT be treated as an error.

#### Scenario: a general-purpose reviewer paired at dispatch completes

- **GIVEN** `reviewer-evidence-hook.sh` judged a `general-purpose` dispatch to be
  a reviewer and recorded its `agent_id`
- **WHEN** that subagent's `SubagentStop` payload arrives with the same `agent_id`
- **THEN** `reviewer-returned` is recorded

#### Scenario: the pairing file is absent

- **GIVEN** no pairing file exists for this session
- **WHEN** a `general-purpose` subagent completes
- **THEN** no milestone is recorded
- **AND** the hook exits 0
