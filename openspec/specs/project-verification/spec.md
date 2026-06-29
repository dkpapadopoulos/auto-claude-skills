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

