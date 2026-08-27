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

The existing read-only rule MUST be retained. No reviewer MUST be granted write access to
the shared tree.

#### Scenario: worktree rule present alongside the retained read-only rule

- **GIVEN** any reviewer lens prompt
- **WHEN** its `## Rules` section is read
- **THEN** it contains both `Read-only: do NOT modify any files` and a
  `git worktree add --detach` instruction

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

#### Scenario: errored reviewer is not counted as covered

- **GIVEN** a dispatched reviewer that errors or times out
- **WHEN** the lead computes review coverage
- **THEN** that reviewer is re-dispatched and excluded from coverage, and if it still does
  not deliver the recorded verdict is `could-not-review`

### Requirement: The dispatch-brief eval set MUST be pinned and non-vacuous

`tests/fixtures/agent-team-review/dispatch-brief/` MUST exist and MUST NOT be deleted. It
MUST contain the literal required clauses and a sha-bound range plus the pre-registered
unprompted-delivery metric for the behavioral leg.

The deterministic gate MUST fail rather than silently pass when the clause fixture is
empty or unreadable, and MUST fail when a lens prompt block cannot be extracted.

#### Scenario: emptied fixture fails the gate

- **GIVEN** an empty `required-clauses.txt`
- **WHEN** the deterministic gate runs
- **THEN** it fails on the non-vacuity control rather than reporting all tests passed

#### Scenario: moved prompt anchor fails the gate

- **GIVEN** a lens prompt whose `name:` anchor has been renamed
- **WHEN** the deterministic gate runs
- **THEN** it fails on that lens's block extraction
