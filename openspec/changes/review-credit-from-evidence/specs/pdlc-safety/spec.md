## MODIFIED Requirements

### Requirement: Gating milestones enter composition state only through invocation evidence

The composition walker's computed done-prefix MUST NOT contain
`requesting-code-review` or `verification-before-completion`, regardless of
whether the prefix derives from the chain-anchor index or the last-invoked
index. These two names MUST enter the `.completed` array only via (i) the
PostToolUse completion hook recording an actual successful Skill return,
(ii) preservation of already-recorded on-disk entries through the monotonic
union, or (iii) for `requesting-code-review` only, a prompt whose leading token
is a typed slash command naming an installed, credited REVIEW skill, recorded by
passing it through the same completion hook. All
other chain steps MUST continue to be back-filled into the computed prefix
exactly as before. The filter MUST be fail-open: if it cannot be applied, the
walker MUST degrade without aborting the hook, and the two names MUST NOT be
emitted into the computed prefix.

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

#### Scenario: A typed slash command records the same evidence as a Skill return

- **GIVEN** a prompt whose text is `/superpowers:requesting-code-review` followed by arguments
- **WHEN** the routing hook handles the prompt
- **THEN** the invocation evidence, branch-ledger milestone and `.completed` entry MUST equal those a successful `Skill(superpowers:requesting-code-review)` return records
- **AND** a prompt that only mentions `/superpowers:requesting-code-review` after other text MUST record nothing
- **AND** a typed `/superpowers:verification-before-completion` MUST record no gating milestone

## ADDED Requirements

### Requirement: Equivalent review skills and typed review commands credit REVIEW

The push gate MUST accept as REVIEW evidence a successful return, or a typed
slash command naming an installed skill or a Claude Code built-in command, of
`requesting-code-review`, `subagent-driven-development`,
`agent-team-execution`, `agent-team-review`, `code-review`, `review-pr` or
`security-review`, with or without a plugin prefix. A typed command MUST be the
prompt's first token; the same command later in the prompt MUST NOT credit. A
typed built-in (`code-review`, `security-review`, bare) MUST credit only when
the Claude Code version read from `AI_AGENT` is 2.1.308 or later, because an
unknown slash command reaches the hook identically; a missing, unparseable or
older version MUST give no built-in credit. The list MUST be defined once and
read by the routing hook, the completion hook, the guard,
`hooks/lib/phase-evidence.sh` and `scripts/gate-status.sh`. If that definition
cannot be read, each reader MUST fall back to the four names credited before
this change, never to accepting any name, and the routing hook MUST give no
typed credit. A prompt that is a task notification or a cross-session message
MUST NOT be read as a typed command.

#### Scenario: A typed /code-review satisfies REVIEW

- **GIVEN** a branch with no REVIEW evidence, the standard chain, and Claude Code 2.1.308 or later
- **WHEN** the owner types `/code-review` as the prompt's first token and the agent then runs `git push`
- **THEN** the push gate MUST NOT deny for missing REVIEW

#### Scenario: A typed built-in on an older or unknown Claude Code credits nothing

- **GIVEN** a branch with no REVIEW evidence and `AI_AGENT` absent, unparseable, or naming a version before 2.1.308
- **WHEN** the owner types `/code-review` and the agent then runs `git push`
- **THEN** no REVIEW evidence MUST be recorded and the push gate MUST deny for missing REVIEW

#### Scenario: A task notification naming a review skill credits nothing

- **GIVEN** a branch with no REVIEW evidence
- **WHEN** a `<task-notification>` prompt whose text contains `/superpowers:requesting-code-review` arrives
- **THEN** no REVIEW evidence MUST be recorded and a subsequent `git push` MUST be denied for missing REVIEW

### Requirement: A returned reviewer covering the pushed changes credits REVIEW

The push gate MUST accept the branch ledger's `reviewer-returned` milestone as
REVIEW evidence only when (a) the reviewer was matched by the allowlisted
`subagent_type` arm of the reviewer classifier, recorded in the milestone, and
(b) the commit it records is an ancestor of the command's subject and no
material source file changed between them. A `reviewer-returned` at a commit
with material changes since, or one without a recorded allowlisted match, MUST
NOT credit. Every reader of REVIEW status MUST apply the same rule.

#### Scenario: A covering reviewer credits

- **GIVEN** a `reviewer-returned` milestone at HEAD, recorded for an allowlisted reviewer type, and no other REVIEW evidence
- **WHEN** the agent runs `git push`
- **THEN** the push gate MUST NOT deny for missing REVIEW

#### Scenario: A description-matched reviewer does not credit

- **GIVEN** a `reviewer-returned` milestone at HEAD for a `general-purpose` agent matched only by its description, and no other REVIEW evidence
- **WHEN** the agent runs `git push`
- **THEN** the push gate MUST deny for missing REVIEW

#### Scenario: A stale reviewer does not credit

- **GIVEN** a `reviewer-returned` milestone at an earlier commit, followed by a commit changing a material source file
- **WHEN** the agent runs `git push`
- **THEN** the push gate MUST deny for missing REVIEW

### Requirement: Shadow records carry harness ids, versions and review coverage

Every IMPLEMENT, REVIEW and VERIFY shadow record written after this change MUST
carry the hook payload's `session_id` and `tool_use_id`, the Claude Code version
(empty when it cannot be read without a process), and the plugin version, under
a schema bump. The REVIEW leg's predicate version MUST increase, because this
change widens the population it fires on. The IMPLEMENT leg's predicate version
MUST also increase, because a typed `subagent-driven-development` or
`agent-team-execution` (credited REVIEW names that are also IMPLEMENT-slot
names) now satisfies that leg, and records from before and after MUST NOT be
pooled. The VERIFY predicate version MUST NOT change. Each REVIEW record MUST also
carry `review_witness` and `review_coverage`, computed when the guard decides.
The REVIEW reader's evidence-miss report MUST count as a miss only a
would-block record whose witness is an allowlisted returned reviewer covering
the push, never an invocation, and MUST count only records that carry
these fields and the new REVIEW predicate version, and MUST state that it is a
lower bound on one kind of false block, not the registered false-block rate.

#### Scenario: A would-block with covering review evidence is reported as an evidence miss

- **GIVEN** a REVIEW shadow record with `would_block: true`, `review_witness: "reviewer-returned"` and `review_coverage: "covered"`
- **WHEN** the reader runs with `--evidence-miss`
- **THEN** that episode MUST be counted as an evidence miss
- **AND** records from earlier predicate versions MUST be excluded from the count and reported as excluded

#### Scenario: A typed credited name that is also an IMPLEMENT-slot name satisfies the IMPLEMENT leg

- **GIVEN** a chain with `executing-plans`, a push whose diff touches material source, REVIEW and VERIFY in the branch ledger, and no IMPLEMENT evidence
- **WHEN** the owner types `/superpowers:subagent-driven-development` as the prompt's first token and the agent then runs `git push`
- **THEN** no IMPLEMENT advisory MUST be emitted and no IMPLEMENT shadow record MUST be written
- **AND** when the owner instead types `/superpowers:executing-plans`, which is not a credited REVIEW name, the IMPLEMENT advisory MUST fire and a would-block IMPLEMENT shadow record MUST be written at the new predicate version
