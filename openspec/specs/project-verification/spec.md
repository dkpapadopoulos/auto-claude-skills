# project-verification Specification

## Purpose
TBD - created by archiving change project-verification. Update Purpose after archive.
## Requirements
### Requirement: Discover and run the repo's declared gate locally

The `project-verification` skill MUST discover the repository's declared test/lint/type gate using a deterministic-first ladder — (1) `.verify.yml`, (2) manifest-standard targets, (3) a bounded classifier over the `CLAUDE.md` `## Commands` table, (4) prompt the user — and MUST run the discovered command(s) on the local device. It MUST NOT require the user to author per-project config in the common case where a `.verify.yml` is absent but a declared gate is deterministically resolvable. When discovery is ambiguous (0 or ≥2 candidates survive the classifier) it MUST surface the candidates and offer to write `.verify.yml`, and MUST NOT silently guess.

#### Scenario: Declared gate discovered from CLAUDE.md and run locally with no per-project config
- **GIVEN** a repository whose `CLAUDE.md` `## Commands` table declares test, lint, and type commands and which has no `.verify.yml`
- **WHEN** the skill runs
- **THEN** it MUST execute the declared commands locally
- **AND** it MUST produce a structured result containing `substrate`, `passed`, `failed`, `command`, and `output_excerpt`
- **AND** it MUST NOT require any per-project configuration file to be authored first

#### Scenario: Ambiguous command table prompts instead of guessing
- **GIVEN** a `CLAUDE.md` `## Commands` table that lists the real gate alongside non-gate peers (a syntax check and a debug invocation)
- **WHEN** the deterministic classifier yields zero or more than one surviving candidate
- **THEN** the skill MUST present the candidate commands to the user
- **AND** it MUST offer to persist the chosen command(s) to `.verify.yml`
- **AND** it MUST NOT execute an unconfirmed guess

#### Scenario: `.verify.yml` overrides discovery
- **GIVEN** a repository containing a `.verify.yml` with `substrate: local` and a `commands` list
- **WHEN** the skill runs
- **THEN** it MUST use the `.verify.yml` commands verbatim
- **AND** it MUST NOT consult the lower ladder rungs

### Requirement: Emit structured evidence recording the substrate

The skill MUST write a structured evidence artifact to `~/.claude/.skill-project-verified-<token>` recording the substrate it actually executed on. In v1 the `substrate` field MUST be the literal string `local`; a `.verify.yml` declaring any other substrate value MUST cause an error rather than silent acceptance. The evidence artifact MUST be treated as advisory audit data, NOT as a trust boundary or enforcement gate, because a session-written marker is forgeable by the gated agent and may race across concurrent sessions sharing `~/.claude/`.

#### Scenario: Evidence records substrate and pass/fail breakdown
- **GIVEN** a successful discovery where lint and tests pass but type-checking fails
- **WHEN** the skill finishes running the gate
- **THEN** `~/.claude/.skill-project-verified-<token>` MUST contain `substrate: "local"`, `passed` including the lint and tests names, and `failed` including the type name
- **AND** `output_excerpt` MUST contain a bounded excerpt of the failing command's output

#### Scenario: Non-local substrate in `.verify.yml` is rejected in v1
- **GIVEN** a `.verify.yml` with `substrate: hosted-ci`
- **WHEN** the skill reads it
- **THEN** the skill MUST report an error indicating only `local` is supported in this version
- **AND** it MUST NOT silently fall back to running locally as if `local` had been declared

### Requirement: Run only as a model-invoked skill, never in a hook or the routing path

Gate discovery and command execution MUST occur only within the model-invoked skill. No hook (session-start, activation, completion, or push gate) MAY discover gates or execute the test/lint/type suite, because hooks cannot reason over freeform prose, cannot access the secrets/network a suite needs, and MUST fail-open within tight latency budgets.

#### Scenario: Hooks do not execute the suite
- **GIVEN** the verification primitive is installed
- **WHEN** any session-start, activation, completion, or push-gate hook runs
- **THEN** none of them MAY invoke the discovered gate command
- **AND** the verification run MUST happen only when the `project-verification` skill is invoked

### Requirement: Gate-Gaming Detection Before PASS

The skill SHALL inspect the working-tree diff before emitting a PASS verdict and SHALL classify a
`gate_gaming_status` of `clean` or `suspect`. A `suspect` classification SHALL downgrade the verdict
to a reported SUSPECT state and SHALL NOT be emitted as PASS. The check SHALL remain advisory (it
MUST NOT hard-block) and SHALL degrade to `clean` for ecosystems whose markers it does not match.

#### Scenario: Suite passes but assertions were deleted

- **GIVEN** the discovered gate exits 0
- **AND** the working-tree diff removes assertion lines from a test file or adds a `skip`/`xfail`/
  disabled marker
- **WHEN** the skill prepares its verdict
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** the verdict MUST NOT be PASS
- **AND** the offending diff lines MUST be shown to the human

#### Scenario: Clean diff passes normally

- **GIVEN** the discovered gate exits 0
- **AND** the working-tree diff contains no removed assertions and no added skip/xfail/disabled markers
- **WHEN** the skill prepares its verdict
- **THEN** `gate_gaming_status` MUST be `clean`
- **AND** the verdict MAY be PASS

### Requirement: Could-Not-Verify Tri-State Evidence

The evidence file SHALL distinguish three command outcomes via `passed[]`, `failed[]`, and a new
`could_not_verify[]` array. A gate command that could not execute (missing binary, runner error,
environment break — as distinct from a test failure) SHALL be recorded in `could_not_verify[]` and
SHALL NOT be silently omitted from all three arrays.

#### Scenario: A gate command cannot run

- **GIVEN** a discovered gate command whose tool is not installed
- **WHEN** the skill runs the gate and emits evidence
- **THEN** that command MUST appear in `could_not_verify[]`
- **AND** that command MUST NOT appear in `passed[]`
- **AND** the verdict for that command MUST be `could-not-verify`, never a silent pass

### Requirement: Deploy-Gate Local-Verification Acceptance

`deploy-gate` SHALL accept a local `project-verification` evidence file as verification-of-record
only when `failed[]` is empty, `could_not_verify[]` is empty, and `gate_gaming_status` is not
`suspect`. An evidence file failing any of these conditions MUST NOT be accepted as local
verification performed.

#### Scenario: Evidence with a could-not-verify gate is not accepted

- **GIVEN** hosted CI is absent
- **AND** a fresh evidence file with empty `failed[]` but a non-empty `could_not_verify[]`
- **WHEN** `deploy-gate` evaluates local verification of record
- **THEN** it MUST NOT accept the file as verification performed
- **AND** it MUST surface that verification was incomplete

#### Scenario: Suspect evidence is not accepted

- **GIVEN** hosted CI is absent
- **AND** a fresh evidence file with empty `failed[]` and empty `could_not_verify[]` but
  `gate_gaming_status: suspect`
- **WHEN** `deploy-gate` evaluates local verification of record
- **THEN** it MUST NOT accept the file as verification performed

### Requirement: Gate-Gaming Detector Limits Are Stated

The skill SHALL state the limits of the gate-gaming detector so trust is calibrated: a `clean`
result MUST NOT be presented as proof that no gate-gaming occurred. The guidance SHALL name the
structural blind spots the line-diff check cannot see (at minimum: stubbing the subject-under-test,
control-flow guards that skip assertions, block-comment- or docstring-muted assertions, and
uncommon per-language skip dialects) and SHALL note that the check can false-alarm on benign moves
and renames. The detector MUST remain advisory (it MUST NOT hard-block).

#### Scenario: A clean detector result is not reported as a guarantee

- **GIVEN** the gate-gaming check returns `clean`
- **WHEN** the skill reports verification results
- **THEN** the guidance MUST NOT claim "no gate-gaming"
- **AND** it MUST direct that a human reviewer still owns assertion integrity

#### Scenario: Structural blind spots are documented

- **WHEN** the skill describes the gate-gaming detector
- **THEN** it MUST list the gaming forms the line-diff check cannot detect
- **AND** it MUST NOT claim coverage of subject-stubbing or control-flow gaming

### Requirement: Gate-declaration weakening is suspect

The gate-gaming check MUST report `suspect` when the diff it receives deletes a gate entry (`- name:` or `run:` line) inside `.verify.yml`, and the verdict writer MUST include `.verify.yml` in the diff pathspec it feeds the checker. Detection is removal-only (rewrites/additions are a documented limit) and the checker remains advisory and fail-open (exit 0 on every path).

#### Scenario: Removed gate entry flags suspect

- GIVEN a unified diff whose `.verify.yml` hunk deletes a `- name: tests` line and its `run:` line
- WHEN the diff is piped into `gate-gaming-check.sh`
- THEN the output starts with `suspect` and quotes the offending deletion lines

#### Scenario: Unrelated .verify.yml edits stay clean

- GIVEN a unified diff whose `.verify.yml` hunk only adds a new gate entry or edits a comment
- WHEN the diff is piped into `gate-gaming-check.sh`
- THEN the output is `clean`

#### Scenario: name/run keywords outside .verify.yml do not false-positive

- GIVEN a unified diff deleting a `- name:` line inside a GitHub workflow file (not `.verify.yml`)
- WHEN the diff is piped into `gate-gaming-check.sh`
- THEN the `.verify.yml` weakening pattern produces no hit

### Requirement: Gate-gaming scope may be declared and is read from the merge-base

The verdict writer SHALL take the gate-gaming diff over the paths listed under `gate_gaming_paths:` in `.verify.yml`, plus `.verify.yml` itself, when a usable declaration exists at the merge-base with the mainline. The declaration MUST be read from the merge-base revision and MUST NOT be read from the branch head, the index or the working tree. When no declaration exists at the merge-base, or `.verify.yml` is not a regular file there, the writer SHALL use the name glob (`*test*`, `*spec*`, `.verify.yml`) unchanged.

#### Scenario: A marker on a file the gate runs

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the branch adds a skip marker to a test file under `tests/`
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** a push of that branch touching a routing path MUST be denied by routing governance

#### Scenario: The same marker quoted in a document

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the branch adds a file under `docs/` that contains the same marker inside a string
- **THEN** `gate_gaming_status` MUST be `clean`
- **AND** `gate_gaming_scope` MUST be `declared`

#### Scenario: No declaration

- **GIVEN** the merge-base has no `gate_gaming_paths` key
- **WHEN** the branch adds that file under `docs/`
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** `gate_gaming_scope` MUST be `default`

#### Scenario: A branch edits its own declaration

- **GIVEN** the merge-base declares `tests/`, or declares nothing
- **WHEN** the branch adds or re-points `gate_gaming_paths` — committed, staged or uncommitted — and adds a skip marker to a test file under `tests/`
- **THEN** the scope MUST be the one at the merge-base
- **AND** `gate_gaming_status` MUST be `suspect`

### Requirement: A changed declaration is suspect

The writer SHALL record `gate_gaming_status` as `suspect` in place of `clean` when the declaration committed at the branch head differs from the declaration at the merge-base, unless both are usable and every path declared at the merge-base is still declared at the head. The verdict SHALL carry `gate_gaming_scope_change` with the value `none`, `widened` or `changed`.

#### Scenario: A branch only narrows the declaration

- **GIVEN** the merge-base declares `tests/` and `docs/`
- **WHEN** the branch commits a declaration of `docs/` alone and changes nothing else
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** `gate_gaming_scope_change` MUST be `changed`

#### Scenario: A branch adds a first declaration

- **GIVEN** the merge-base has no `gate_gaming_paths` key
- **WHEN** the branch commits one
- **THEN** `gate_gaming_status` MUST be `suspect`

#### Scenario: A branch only adds a path

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the branch commits a declaration of `tests/` and `docs/`
- **THEN** `gate_gaming_status` MUST be `clean`
- **AND** `gate_gaming_scope_change` MUST be `widened`

### Requirement: An unusable declaration leaves the check unverified

When the declaration at the merge-base is an inline list, is declared more than once, has no entries, or contains an entry that is quoted, starts with `:`, `-` or `/`, contains `..` as a path segment, contains whitespace, or matches no file at the merge-base, the writer MUST NOT run the check over any pathspec. It SHALL record `gate_gaming_status` as `unverified`, add `gate-gaming-check` to `could_not_verify`, record `gate_gaming_scope` as `unusable`, and print the reason. It MUST NOT apply a subset of the declared paths and MUST NOT fall back to the name glob.

#### Scenario: Pathspec magic

- **GIVEN** the merge-base declares `docs/` and `:(exclude)tests/`
- **WHEN** the writer records a verdict
- **THEN** `gate_gaming_status` MUST be `unverified`
- **AND** `gate_gaming_scope` MUST be `unusable`

#### Scenario: A declared file the name glob would not select

- **GIVEN** the merge-base declares `checks/validate.py` and a second entry that matches no file
- **WHEN** the branch removes an assertion from `checks/validate.py`
- **THEN** `gate_gaming_status` MUST NOT be `clean`

### Requirement: The verdict records the scope that was used

The verdict SHALL carry `gate_gaming_scope` with the value `declared`, `default`, `unusable` or `unverified`, and `gate_gaming_paths` with the pathspec the diff was taken over. `unverified` and an empty list SHALL be recorded when no base could be resolved or the checker is missing.

#### Scenario: A declared scope

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the writer records a verdict
- **THEN** `gate_gaming_paths` MUST be `["tests/", ".verify.yml"]`

#### Scenario: A gate entry removed under a declared scope

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the branch deletes a `- name:` entry from `.verify.yml`
- **THEN** `gate_gaming_status` MUST be `suspect`

### Requirement: Net removal of unlisted assertion families is suspect

The gate-gaming check SHALL count, per file, the deleted and the added diff lines that call an assertion of a family its fixed list does not name: `assert_<name>`, `assert<Name>(` other than the listed names, and this plugin's `_record_pass` / `_record_fail`. It SHALL report a file when more such lines were deleted than added. A comment-only line and a definition of a helper MUST NOT be counted. The fixed list and its rule MUST run unchanged on the same input, and a diff they flag MUST still be flagged. A line MUST be attributed to a file by the diff's hunk structure, and MUST NOT be attributed by a line's resemblance to a file header.

#### Scenario: A deleted bash assertion

- **GIVEN** a branch diff that deletes an `assert_equals` line from a test file and adds none
- **WHEN** the verdict is written
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** the hit MUST name the file and both counts

#### Scenario: An assertion edited in place

- **GIVEN** a diff that deletes one such assertion line and adds one in the same file
- **WHEN** the check runs
- **THEN** that file MUST NOT be reported

#### Scenario: An assertion commented out, and one moved to another file

- **WHEN** an assertion line is replaced by a comment, or deleted from one file and added to another
- **THEN** the file that lost it MUST be reported

#### Scenario: A source line that imitates a file header

- **GIVEN** a diff in which an added source line reads like a `+++` header naming another file, followed by deleted assertions
- **WHEN** the check runs
- **THEN** the deletions MUST be charged to the file they were deleted from

#### Scenario: A helper definition is deleted

- **WHEN** the only deleted lines are definitions such as `assert_not_empty() {`
- **THEN** the check MUST NOT report the file

### Requirement: A not-clean verdict states a remedy that can be carried out

The verdict writer SHALL record the lines the gate-gaming check flagged, at most ten, with control characters removed. When the push guard denies a push because the verification verdict for exactly the pushed commit is not clean, its text SHALL name every blocker and what clears it, and for a `suspect` result SHALL state that re-running verification cannot clear it while the diff is unchanged. That text MUST NOT contain a flagged diff line, and MUST show a gate name only when the name is a plain label; other names MUST be counted. For a verdict at any other commit, or none, the previous text SHALL stand. The decision to deny MUST NOT change.

#### Scenario: A suspect verdict at the pushed commit

- **GIVEN** a routing change whose verdict at HEAD is `suspect`
- **WHEN** a push is attempted
- **THEN** the push MUST be denied by routing governance
- **AND** the reason given to the model MUST say that re-running cannot clear it, and how many lines were flagged
- **AND** the reason MUST NOT say to run verification until it reports a clean verdict

#### Scenario: Text chosen by the branch author

- **GIVEN** a verdict whose flagged line, or whose failing gate's name, is worded as an instruction
- **WHEN** the remedy is rendered
- **THEN** that wording MUST NOT appear in it

#### Scenario: A verdict for an earlier commit

- **GIVEN** a `suspect` verdict for an ancestor of the pushed commit
- **WHEN** a push is attempted
- **THEN** the push MUST be denied with the text that asks for a verdict at this commit

