## ADDED Requirements

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
