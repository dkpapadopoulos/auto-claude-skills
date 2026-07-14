# pdlc-safety (delta)

## ADDED Requirements

### Requirement: Gating milestones enter composition state only through invocation evidence

The composition walker's computed done-prefix MUST NOT contain
`requesting-code-review` or `verification-before-completion`, regardless of
whether the prefix derives from the chain-anchor index or the last-invoked
index. These two names MUST enter the `.completed` array only via (i) the
PostToolUse completion hook recording an actual successful Skill return, or
(ii) preservation of already-recorded on-disk entries through the monotonic
union. All other chain steps MUST continue to be back-filled into the computed
prefix exactly as before. The filter MUST be fail-open: if it cannot be
applied, the walker MUST degrade without aborting the hook, and the two names
MUST NOT be emitted into the computed prefix.

#### Scenario: A late-anchor prompt does not fabricate gate evidence

- **GIVEN** fresh composition state (no `.completed` on disk, no branch-ledger
  milestones for the current branch) and the standard
  DESIGN→PLAN→IMPLEMENT→REVIEW→SHIP chain
- **WHEN** a prompt trigger-matches a late chain anchor (e.g. `openspec-ship`,
  step 6) and the walker writes composition state
- **THEN** `.completed` MUST NOT contain `requesting-code-review` or
  `verification-before-completion`, and a subsequent agent `git push` MUST be
  denied by the push gate for the missing milestones

#### Scenario: Invocation-recorded milestones survive re-anchoring

- **GIVEN** `.completed` on disk contains `requesting-code-review`, recorded by
  the completion hook after the Skill actually returned successfully
- **WHEN** a later prompt re-anchors anywhere in the same chain and the walker
  rewrites composition state
- **THEN** `requesting-code-review` MUST remain in `.completed` (monotonic
  union preserved; the filter applies only to the computed prefix)

#### Scenario: Non-gating back-fill is preserved (chore false-block guard)

- **GIVEN** fresh composition state and a prompt that anchors at
  `requesting-code-review` (step 4)
- **WHEN** the walker writes composition state
- **THEN** `.completed` MUST contain the non-gating predecessors
  (`brainstorming`, `writing-plans`, `executing-plans`) and MUST NOT contain
  either gating milestone

#### Scenario: The last-invoked signal cannot leak the other gating milestone

- **GIVEN** `verification-before-completion` was actually invoked (recorded by
  the completion hook) but `requesting-code-review` never ran
- **WHEN** a subsequent prompt causes the walker to compute its prefix from the
  last-invoked index (which lies beyond `requesting-code-review` in the chain)
- **THEN** `.completed` MUST contain `verification-before-completion` (real
  evidence) and MUST NOT contain `requesting-code-review`
