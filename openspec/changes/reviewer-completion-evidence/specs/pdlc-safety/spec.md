# Spec delta: pdlc-safety — observed reviewer completion

## ADDED Requirements

### Requirement: A reviewer subagent's COMPLETION MUST be recorded distinctly from its dispatch

The plugin MUST record a `reviewer-returned` milestone into the per-(repo+branch)
branch ledger when a reviewer subagent runs to completion, and this milestone
MUST be distinct from the existing `reviewer-ran` dispatch milestone. A dispatch
that never completes MUST NOT produce `reviewer-returned`. A subagent that
emitted no final message MUST be treated as not having returned.

The recorder MUST be diagnostic-only: it MUST emit nothing on stdout, MUST NOT
set a `permissionDecision`, and MUST exit 0 on every failure path. It MUST NOT
be added to `_GATE_ENFORCE_LIBS`.

No gate decision in this change MAY read `reviewer-returned`.

#### Scenario: a reviewer subagent completes

- **GIVEN** a subagent classified as a reviewer at dispatch on this branch
- **WHEN** its completion is observed with a non-empty final message
- **THEN** `reviewer-returned` is recorded in the branch ledger
- **AND** the hook writes nothing to stdout and exits 0

#### Scenario: an ordinary subagent completes

- **GIVEN** a subagent that was not classified as a reviewer at dispatch
- **WHEN** its completion is observed
- **THEN** no milestone is recorded
- **AND** the hook writes nothing to stdout and exits 0

### Requirement: The dispatch/completion join MUST NOT depend on hook firing order

Reviewer classification MUST be performed at dispatch, against the short
dispatch `description` and `subagent_type`. The word-boundary description
predicate MUST NOT be applied to the subagent's task prompt: it was fitted on
the short label, and its `*[Rr]eview[!a-zA-Z]*` arm matches the word anywhere
followed by a non-letter, so against multi-paragraph prompt text it degenerates
into the substring variant measured at 4/7 false positives.

Because neither hook is guaranteed to run first — measured, the dispatch hook
fires before completion for a backgrounded subagent and AFTER it for a
foreground one — each side MUST publish its own half before reading the other,
and EITHER side MUST be able to record the milestone. A design in which only one
side can record MUST NOT be used.

A lookup MISS MUST record nothing. A missing, unreadable, or unparseable pairing
file MUST be treated as a miss and MUST NOT be treated as an error.

#### Scenario: the completion is observed before the dispatch is recorded

- **GIVEN** a reviewer subagent whose completion event fires first
- **WHEN** the dispatch event is subsequently observed for the same agent
- **THEN** `reviewer-returned` is recorded

#### Scenario: the dispatch is recorded before the completion is observed

- **GIVEN** a reviewer subagent whose dispatch event fires first
- **WHEN** its completion is subsequently observed
- **THEN** `reviewer-returned` is recorded

### Requirement: A completion credit MUST be bound to the branch it was dispatched on

The branch ledger key MUST be recorded at dispatch and compared at completion. A
credit MUST NOT be recorded when the two differ, because the ledger key is
derived from the working directory at call time and a backgrounded reviewer can
complete after the session has moved to another branch — writing a credit into
the ledger of a branch the reviewer never examined.

A refused credit MUST leave a diagnostic trace, so that "no reviewer ran" and "a
reviewer ran and the join was refused" are distinguishable.

#### Scenario: a reviewer completes after the session changed branches

- **GIVEN** a reviewer subagent dispatched while one branch was checked out
- **WHEN** its completion is observed with a different branch ledger key
- **THEN** no milestone is recorded on either branch
- **AND** a diagnostic record of the refusal is written
