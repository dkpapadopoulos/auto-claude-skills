# skill-routing — Push-gate branch milestone ledger (delta)

## ADDED Requirements

### Requirement: Push-gate readiness survives composition chain re-anchors

The push gate SHALL determine whether a gating milestone (`requesting-code-review`,
`verification-before-completion`) is satisfied from **either** a durable per-(repo+branch) milestone
ledger **or** the transient composition `.completed`. A genuinely-completed milestone MUST remain
satisfied across a composition chain re-anchor (a later prompt detecting a different phase) within
the same repo+branch. The gate SHALL deny a push only when a gating milestone is present in the
active chain and **neither** source records it. The `.completed` state and its writers MUST be
left unchanged by this mechanism.

#### Scenario: Chain re-anchor does not re-block a reviewed+verified branch

- **GIVEN** `requesting-code-review` and `verification-before-completion` completed on the current branch (recorded in the ledger)
- **AND** a subsequent prompt re-anchors the composition chain so `.completed` no longer lists them
- **WHEN** the user pushes
- **THEN** the push gate MUST NOT deny on the missing gating milestones (the ledger satisfies them)

#### Scenario: A new branch must re-earn the milestones

- **GIVEN** the milestones are recorded for branch `feature/a`
- **AND** the working tree is now on a different branch `feature/b` with no ledger entries
- **WHEN** a composition chain on `feature/b` contains the gating milestones and the user pushes
- **THEN** the push gate MUST deny until the milestones are completed on `feature/b`

#### Scenario: In-flight session without a ledger falls back to `.completed`

- **GIVEN** no milestone ledger exists for the current repo+branch (e.g. a session predating this feature)
- **AND** `.completed` lists the gating milestones
- **WHEN** the user pushes
- **THEN** the push gate MUST accept (the `.completed` path is preserved, no regression)

### Requirement: Branch ledger is repo-scoped and isolated

The milestone ledger SHALL be keyed by a **repo+branch** identity (not branch name alone), and a
detached HEAD SHALL form its own boundary. A same-named branch in a different repository or worktree
MUST NOT inherit another repo's recorded milestones. If the repo+branch identity cannot be
determined, the gate SHALL fall back to the `.completed`-only check rather than failing open.

#### Scenario: Same branch name in a different repo does not inherit milestones

- **GIVEN** milestones recorded for branch `main` in repo X
- **WHEN** the gate evaluates a push for branch `main` in a different repo Y
- **THEN** repo Y's gate MUST NOT treat repo X's milestones as satisfying repo Y's gate

### Requirement: HEAD advancement past a recorded milestone emits a soft warning

The gate MUST emit an advisory staleness warning, and MUST NOT deny on that basis, when it is
satisfied via the ledger but the recorded HEAD sha differs from the current HEAD. The warning MUST
name both the recorded sha and the current sha.

#### Scenario: New commits after review warn but do not block

- **GIVEN** `requesting-code-review` was recorded at sha `A` on the current branch
- **AND** the current HEAD is `B` (commits added since)
- **WHEN** the user pushes
- **THEN** the gate MUST emit a staleness warning referencing `A` and `B`
- **AND** the gate MUST NOT deny the push solely because HEAD advanced
