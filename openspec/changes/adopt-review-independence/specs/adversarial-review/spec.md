# Spec delta: adversarial-review — review-independence grafts

## ADDED Requirements

### Requirement: Reviewers MUST NOT re-report findings owned by another gate

A reviewer lens MUST NOT raise a finding whose entire content is (a) a defect
already present on the merge base and untouched by the diff under review
(`pre-existing`), or (b) output another ACS gate already produces
(`tool-owned`) — lint, type-check, test failures, or SAST results, which
`project-verification` and `security-scanner` own as separate skills.

A reviewer MAY raise either where the diff changes the defect's blast radius,
or where the tool-owned signal is absent because the gate did not run — in
which case the finding is that the gate did not run.

This list MUST remain restricted to these two categories. It MUST NOT be
extended to `speculative` or any provenance category that would demote a
finding, because `security` and `governance` findings may be `blocking` on
structural grounds without an observable failure path, and a provenance filter
would silently drop them.

#### Scenario: A pre-existing defect in untouched code

- **GIVEN** a reviewer inspecting a diff
- **WHEN** it identifies a defect that exists on the merge base and appears in
  no changed hunk
- **THEN** it MUST NOT report it as a finding against this change
- **AND** the reviewer's coverage statement MUST still account for the file

#### Scenario: A lint failure another gate owns

- **GIVEN** a reviewer inspecting a diff whose repo ran `project-verification`
- **WHEN** it identifies a formatting or lint violation that gate already reports
- **THEN** it MUST NOT restate that violation as a review finding

#### Scenario: A structural security finding is never demoted by provenance

- **GIVEN** a reviewer that identifies a change removing an existing safety
  constraint
- **WHEN** the finding has no runnable proof-of-concept
- **THEN** it MUST still be eligible for `blocking` severity
- **AND** the do-not-flag list MUST NOT be applied to demote it

### Requirement: A reviewer that authored the diff MUST declare reduced independence

A review produced by the same context that authored the change under review is
not independent. When the reviewing context authored the diff, it MUST say so
explicitly in its report, and MUST downgrade its own claim from an independent
review to convention-checking.

This MUST NOT be implemented as a silent demotion of the findings themselves: a
self-review's findings retain their severity, and only the independence claim
is withdrawn.

#### Scenario: Self-review is declared, not silently accepted

- **GIVEN** a session that authored a change and then reviews it without
  dispatching a separate reviewer
- **WHEN** the review report is produced
- **THEN** the report MUST state that the reviewing context authored the diff
- **AND** it MUST describe itself as convention-checking rather than an
  independent review

#### Scenario: A dispatched reviewer is unaffected

- **GIVEN** a reviewer subagent dispatched in its own context
- **WHEN** it reports findings on a diff it did not author
- **THEN** the authorship guard MUST NOT apply
- **AND** the report MUST NOT carry the reduced-independence declaration
