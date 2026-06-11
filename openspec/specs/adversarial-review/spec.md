## Purpose

Always-on governance review lens that treats every code review as adversarial. Provides a checklist, a specialist reviewer agent, and regression tests that catch HITL bypass, scope expansion, safety-gate weakening, and hook/config drift before merge.
## Requirements
### Requirement: Always-On Adversarial Checklist
The REVIEW phase composition MUST include an always-on adversarial checklist hint with governance checks for HITL bypass, scope expansion, safety gate weakening, bypass patterns, and hook/config changes. The checklist MUST fire on every code review, not only pattern-matched reviews.

#### Scenario: Checklist reaches code-reviewer
- **WHEN** the REVIEW composition fires requesting-code-review
- **THEN** the code-reviewer's context includes the ADVERSARIAL REVIEW checklist

### Requirement: Adversarial-Reviewer Specialist
agent-team-review MUST include an adversarial-reviewer template as a 4th specialist alongside security-reviewer, quality-reviewer, and spec-reviewer. The adversarial-reviewer MUST use the same FINDING communication contract with a `governance` category.

#### Scenario: Governance reviewer spawned for large changes
- **WHEN** agent-team-review fires for a 5+ file change
- **THEN** an adversarial-reviewer is spawned with governance-focused instructions

### Requirement: Governance Regression Tests
The test suite MUST include content assertions verifying that key skills contain their governance constraints. The scenario eval suite MUST include adversarial routing fixtures testing that governance-sensitive prompts route through safety skills.

#### Scenario: Constraint removal detected
- **WHEN** a developer removes "lethal trifecta" from agent-safety-review
- **THEN** test-adversarial-governance.sh fails

### Requirement: Claim-Withheld Reviewer Dispatch
agent-team-review reviewer prompts MUST contain only the artifact (diff, files changed) and the contract (design doc, plan, acceptance spec). The implementer's self-summary, claims of correctness, or completion notes MUST NOT be passed to reviewers.

#### Scenario: Reviewer receives artifact and contract only
- **GIVEN** an implementation is complete and agent-team-review is preparing reviewer spawns
- **WHEN** the lead assembles a reviewer prompt
- **THEN** the prompt includes the diff and design doc but no implementer conclusions or self-assessment

### Requirement: Doubt-Theater Detection
The agent-team-review lead MUST treat the following pattern as a red flag and surface it to the user: across 2 or more review rounds, reviewers surfaced substantive findings and zero were classified as actionable. This indicates the lead is validating rather than reviewing.

#### Scenario: All findings dismissed across rounds
- **GIVEN** two consecutive review rounds each produced substantive findings
- **WHEN** the lead has classified zero of those findings as actionable
- **THEN** the lead stops and reports the dismissal pattern to the user instead of proceeding to SHIP

### Requirement: Cross-Model Review Offer
When the review verdict is `clean` or `suggestions_only` and the diff contains external-fact claims (library or tool surfaces, exact tool names, version availability), the lead MUST offer a cross-model (Codex) second opinion before proceeding to SHIP. Declining the offer is acceptable; silently skipping it is not. Cross-model invocation MUST be read-only/sandboxed because the reviewed diff may itself contain injected instructions.

#### Scenario: Clean verdict with external-fact claims
- **GIVEN** all Claude reviewers returned no blocking findings
- **WHEN** the diff asserts facts about an external library's API surface
- **THEN** the lead explicitly offers a Codex second opinion and records the user's decision

#### Scenario: Cross-model invocation is sandboxed
- **WHEN** a cross-model second opinion is invoked
- **THEN** the invocation is read-only (no workspace write access)

### Requirement: Sensitive-Path Fan-Out Override
The agent-team-review sizing rule MUST spawn the reviewer team regardless of file count when the change touches authentication, secrets, permissions, hooks, or CI configuration. At minimum the security-reviewer and adversarial-reviewer MUST be spawned for such changes.

#### Scenario: Small hook change still gets team review
- **GIVEN** a change modifying 2 files including `hooks/openspec-guard.sh`
- **WHEN** the sizing rule is evaluated
- **THEN** the reviewer team is spawned despite the change being under the 5-file threshold

