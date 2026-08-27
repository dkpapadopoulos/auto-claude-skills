# Spec delta: pdlc-safety — reviewer dispatch brief

## ADDED Requirements

### Requirement: Every reviewer lens prompt MUST carry the delivery contract

Each reviewer lens prompt in `skills/agent-team-review/SKILL.md` MUST state, within that
prompt's own text, that the reviewer:

- time-boxes itself and reports even if incomplete, naming what it did not cover;
- delivers its report unprompted via `SendMessage` to `main` before going idle or ending
  its turn;
- sends a report saying so when it could not review, because silence is not a pass;
- says plainly when it finds nothing and does not manufacture findings.

The clauses MUST be present in **every** lens prompt. Stating them once in the skill's
protocol prose MUST NOT be treated as satisfying this requirement, because a reviewer
subagent reads only its own prompt.

#### Scenario: all four lens prompts carry every clause

- **GIVEN** `skills/agent-team-review/SKILL.md`
- **WHEN** each of the `security-reviewer`, `quality-reviewer`, `spec-reviewer`, and
  `adversarial-reviewer` prompt blocks is extracted
- **THEN** every needle in
  `tests/fixtures/agent-team-review/dispatch-brief/required-clauses.txt` appears inside
  each extracted block

#### Scenario: a clause outside the prompt blocks does not satisfy the requirement

- **GIVEN** a clause removed from a lens prompt and added to the skill's `## Red Flags`
  section
- **WHEN** the deterministic gate runs
- **THEN** it fails for that lens

### Requirement: A reviewer that executes or mutates MUST use its own worktree

Each reviewer lens prompt MUST require that any reviewer needing to run tests, builds, or
mutation testing first creates a detached worktree (`git worktree add --detach`), works
only there, and never writes to the shared working tree.

The existing read-only rule MUST be retained, scoped to the shared tree. No reviewer MUST
EVER be granted write access to the shared working tree.

The worktree path MUST be unique per invocation (`mktemp -d`), never a fixed
lens-derived path: lens names are constants, so a re-dispatched reviewer — which the
lead-side protocol mandates — reuses the name and fails with `fatal: already exists` on
its first command, as do two overlapping review rounds.

Each prompt MUST require the reviewer to confirm its worktree matches the subject before
labelling anything VERIFIED, because a detached worktree does not carry the shared tree's
uncommitted changes and would otherwise be a different tree from the one under review.

#### Scenario: worktree rule present alongside the retained read-only rule

- **GIVEN** any reviewer lens prompt
- **WHEN** the prompt is read
- **THEN** it contains `Read-only in the shared tree`, `do NOT modify any files`,
  `git worktree add --detach`, `mktemp -d`, `Never write to the shared working tree`, and
  `Confirm your worktree matches the subject`

### Requirement: The lead MUST have a defined recovery protocol for idle and errored reviewers

`skills/agent-team-review/SKILL.md` MUST define, as lead-side protocol, that:

- an idle notification is not a report, and the lead requests the report explicitly;
- a quiet reviewer is chased at least twice before being written off;
- an errored or timed-out reviewer is re-dispatched and never counted toward coverage;
- `git status` and `git log` are checked before any re-dispatch, because stalled subagents
  frequently leave completed work uncommitted in the tree;
- a lens that never delivers yields verdict `could-not-review`, not `clean`;
- reporting a round as complete without a lens is a named red flag ("silent drop"), so
  coverage counts reports delivered rather than agents spawned.

The `Verification` section's existing outcome assertion MUST reference this mechanism
rather than standing alone.

The lead MUST also reap reviewer worktrees at the end of a round. `git worktree add`
registers under the shared repo's `.git/worktrees/`, which `git status --porcelain` cannot
observe, so a reviewer killed before its own cleanup leaks invisibly to any main-tree
cleanliness check.

#### Scenario: the errored-reviewer rule is stated in Protocol §3

- **GIVEN** `skills/agent-team-review/SKILL.md`
- **WHEN** the block between `### 3. Parallel Review` and the next `### ` heading is
  extracted
- **THEN** it states that a timeout is not a pass and that such a reviewer is never counted
  toward coverage, that an undelivered lens is recorded as `--verdict could-not-review`,
  and that reviewer worktrees are pruned
- **AND** the assertion is scoped to that block, not to the whole file: `could-not-review`
  already occurs elsewhere in the skill, so a whole-file needle is satisfied by that
  pre-existing text and pins nothing

#### Scenario: the Verification outcome cites its mechanism

- **GIVEN** the `## Verification` section
- **WHEN** it is read
- **THEN** it names Protocol §3 as the mechanism producing the outcome it asserts, and
  states that a lens that never delivered means `could-not-review`, not APPROVE

### Requirement: The dispatch-brief eval set MUST be pinned and non-vacuous

`tests/fixtures/agent-team-review/dispatch-brief/` MUST exist and MUST NOT be deleted. It
MUST contain the literal required clauses and a sha-bound range plus the pre-registered
unprompted-delivery metric for the behavioral leg.

The fixture MUST NOT be the sole authority for what is asserted. The gate MUST
independently carry the issue-#204 clause anchors and MUST fail when the fixture no longer
contains one of them — otherwise deleting a needle silently deletes its own assertion, and
a fixture trimmed to the floor plus inverted prompts runs green.

The gate MUST derive the lens population from `skills/agent-team-review/SKILL.md` rather
than hardcoding it, so a lens added later cannot be silently exempt, and MUST assert that
the per-lens Delivery Contract blocks are identical, since duplication is the chosen design
and drift is its only cost.

The gate MUST fail rather than silently pass when the clause fixture is empty, unreadable,
or absent, and MUST fail when a lens prompt block cannot be extracted.

The gate MUST run in CI, not only in the local `.verify.yml` suite. `.verify.yml` is
`substrate: local` and is read by no workflow, so a test reachable only through
`tests/run-tests.sh` is not a CI check.

#### Scenario: emptied fixture fails the gate

- **GIVEN** an empty `required-clauses.txt`
- **WHEN** the deterministic gate runs
- **THEN** it fails on the non-vacuity control rather than reporting all tests passed

#### Scenario: moved prompt anchor fails the gate

- **GIVEN** a lens prompt whose `name:` anchor has been renamed
- **WHEN** the deterministic gate runs
- **THEN** it fails on that lens's block extraction

#### Scenario: a needle deleted from the fixture fails the gate

- **GIVEN** `required-clauses.txt` with an issue-#204 clause anchor removed
- **WHEN** the deterministic gate runs
- **THEN** it fails on the anchor control, rather than passing with one fewer assertion

#### Scenario: an unlisted fifth lens is not exempt

- **GIVEN** a fifth reviewer template added under `## Reviewer Spawn Templates` carrying
  none of the clauses
- **WHEN** the deterministic gate runs
- **THEN** it fails, because the lens population is derived from the skill rather than
  hardcoded

#### Scenario: the gate is invoked by the CI workflow

- **GIVEN** `.github/workflows/done-gates.yml`
- **WHEN** its `run:` lines are read
- **THEN** they invoke `tests/test-reviewer-dispatch-brief.sh` with stdin closed
