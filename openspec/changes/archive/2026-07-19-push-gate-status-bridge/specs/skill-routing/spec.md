# skill-routing — delta for push-gate-status-bridge

## ADDED Requirements

### Requirement: Push-gate STATUS layer resolves evidence across locations without widening acceptance

The push gate's STATUS layer (REVIEW/VERIFY milestone resolution) SHALL
consult, after its primary branch-ledger and `.completed` checks miss:
(a) the same-token `.skill-invocation-evidence-<token>` artifact (written
only by real Skill returns, honoring the review-embedding proxy skills), and
(b) sibling branch-ledger locations, accepting a milestone only when its
recorded SHA is HEAD or a branch-local ancestor of HEAD (not reachable from
the mainline merge-base). The gating-milestone ledger write SHALL NOT depend
on composition state existing. Evidence provenance: issue #131, PR #130 live
false-block repro.

#### Scenario: Gating milestone recorded without composition state

- **GIVEN** no composition state exists under the session's resolved token
- **WHEN** the completion hook processes a successful
  `requesting-code-review` Skill return
- **THEN** the per-(repo+branch) branch-ledger records the milestone

#### Scenario: Same-token invocation evidence rescues a scattered push

- **GIVEN** the push branch's ledger and the token's `.completed` are empty,
  but `.skill-invocation-evidence-<token>` lists both gating skills
- **WHEN** the guard evaluates `git push`
- **THEN** the fail-closed gate does not deny

#### Scenario: Cross-location ledger evidence bridges only branch-bound SHAs

- **GIVEN** milestones exist only under a foreign ledger key, recorded at a
  commit of the push branch's local segment
- **WHEN** the guard evaluates `git push`
- **THEN** the gate does not deny and emits a cross-location advisory

#### Scenario: Mainline or unrelated SHAs never bridge

- **GIVEN** a foreign-key milestone recorded at a mainline-base commit or an
  SHA unknown to the push branch
- **WHEN** the guard evaluates `git push`
- **THEN** the fail-closed deny stands
