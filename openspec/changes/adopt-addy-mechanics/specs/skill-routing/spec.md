## ADDED Requirements

### Requirement: Intent-extraction pre-brainstorming directive

The activation hook SHALL provide a phase-gated directive that, when the DESIGN
phase is entered with an underspecified ask and no approved discovery brief, instructs
the model to run a one-question-at-a-time intent extraction before brainstorming and to
persist a confirmed-intent statement that brainstorming consumes. The directive MUST be
hard phase-gated and MUST NOT fire when an approved brief already exists or for mechanical
asks. It MUST ship only after a red-first quality eval demonstrates a measurable intent-capture
improvement over brainstorming alone.

#### Scenario: Fires on an underspecified ask
- **WHEN** a DESIGN-phase prompt is underspecified (missing who/why/success/constraint) and no approved brief is in session state
- **THEN** the activation context MUST surface the intent-extraction directive instructing confidence-tracked, one-question-at-a-time extraction with an explicit "what would you actually want?" probe and an out-of-scope line
- **AND** it MUST instruct writing a `confirmed-intent` statement to session state before brainstorming proceeds

#### Scenario: Suppressed when a brief already exists
- **WHEN** an approved discovery brief or confirmed intent is already present in session state, or the ask is mechanical (rename/typo/file move)
- **THEN** the intent-extraction directive MUST NOT appear in the activation context

#### Scenario: Brainstorming consumes confirmed intent
- **WHEN** brainstorming activates and a `confirmed-intent` statement exists in session state
- **THEN** the activation context MUST reference it so brainstorming builds on the confirmed intent rather than re-eliciting it

### Requirement: Scope-manifest IMPLEMENT→REVIEW context contract

The activation hook SHALL provide a phase-gated directive instructing the implementer to
emit a scope manifest (files intended to change + an explicit "not touching" list) during
IMPLEMENT, and instructing the REVIEW phase to consume that manifest for scope-creep
detection. The directive MUST be hard-gated to the IMPLEMENT and REVIEW phases and MUST be
advisory (it MUST NOT block the hook on absence of a manifest).

#### Scenario: Implementer emits a scope manifest
- **WHEN** the IMPLEMENT phase is active for a multi-file change
- **THEN** the activation context MUST instruct emitting a scope manifest listing intended-change files and an explicit not-touching list

#### Scenario: Review consumes the manifest for scope-creep
- **WHEN** REVIEW activates (agent-team-review or implementation-drift-check) and a scope manifest exists
- **THEN** the activation context MUST instruct diffing actually-changed files against the manifest and flagging out-of-scope changes

#### Scenario: Degrades open when absent
- **WHEN** no scope manifest exists at REVIEW
- **THEN** the directive MUST degrade silently and MUST NOT block or error the hook
