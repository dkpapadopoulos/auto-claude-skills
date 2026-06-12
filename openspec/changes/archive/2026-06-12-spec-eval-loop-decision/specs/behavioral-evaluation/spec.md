# behavioral-evaluation — delta spec: spec-eval-loop-decision

## ADDED Requirements

### Requirement: Advisory behavioral-pack coverage report

The project MUST provide a deterministic, fail-open coverage report (`scripts/scenario-coverage.sh`) that surfaces skill-execution capabilities whose acceptance scenarios describe probabilistic model behavior but which have no backing behavioral eval pack. A capability is in scope only if a runnable `skills/<cap>/SKILL.md` exists AND its `openspec/specs/<cap>/spec.md` contains at least a threshold number (default 3) of probabilistic-verb `THEN` clauses; pure hook/registry/state capabilities are out of scope (covered deterministically by the bash suite). The report MUST report linkage existence (does a `tests/fixtures/<cap>/evals/behavioral.json` or `tests/fixtures/<cap>/behavioral.json` exist) and MUST NOT claim scenario-level percentage coverage. It MUST exit 0 in advisory mode regardless of gaps; a `--strict` flag MAY exit non-zero when an uncovered gap exists, for opt-in CI. It MUST live outside the default `tests/run-tests.sh` discovery path and MUST NOT run inside any session hook. All error modes (missing specs directory, unreadable file, missing jq) MUST fail open.

#### Scenario: Uncovered skill-execution capability is surfaced
- **GIVEN** a capability with a `skills/<cap>/SKILL.md` and a spec containing ≥3 probabilistic `THEN` clauses but no behavioral eval pack
- **WHEN** `scripts/scenario-coverage.sh` runs
- **THEN** the capability is reported with status `UNCOVERED` and listed in the uncovered summary
- **AND** the report exits 0 (advisory)

#### Scenario: Backfilled pack flips the capability to covered
- **GIVEN** a behavioral eval pack exists at `tests/fixtures/<cap>/evals/behavioral.json` for an in-scope capability
- **WHEN** the report runs
- **THEN** the capability is reported `has-pack` and is absent from the uncovered list

#### Scenario: Out-of-scope capabilities are excluded
- **GIVEN** a capability whose spec has probabilistic `THEN` clauses but no runnable `skills/<cap>/SKILL.md`, OR fewer than the threshold of probabilistic clauses
- **WHEN** the report runs
- **THEN** that capability is not listed

#### Scenario: Strict mode gates only on real gaps
- **GIVEN** at least one in-scope capability is `UNCOVERED`
- **WHEN** the report runs with `--strict`
- **THEN** it exits non-zero
- **AND** with no uncovered gaps, `--strict` exits 0

#### Scenario: Fail-open on missing inputs
- **GIVEN** the target root has no `openspec/specs` directory
- **WHEN** the report runs
- **THEN** it prints a nothing-to-report message and exits 0

### Requirement: Behavioral execution packs for security-scanner and incident-trend-analyzer

The `security-scanner` and `incident-trend-analyzer` skills MUST each have a behavioral execution pack at `tests/fixtures/<skill>/evals/behavioral.json`, conforming to the `run-behavioral-evals.sh` schema (an array of `{id, prompt, expected_behavior, assertions:[{text, description}]}` where each `text` is a valid ERE). Each pack MUST cover the skill's genuinely-probabilistic scenarios — for `security-scanner` at minimum the tool-absent LLM-only fallback; for `incident-trend-analyzer` at minimum failure-mode normalization across differently-worded incidents.

#### Scenario: security-scanner fallback behavior is guarded
- **GIVEN** `tests/fixtures/security-scanner/evals/behavioral.json`
- **WHEN** the schema is validated
- **THEN** it contains a case asserting that, with no scanners installed, the skill falls back to LLM-only review and recommends installing opengrep (preferred) / semgrep (fallback)

#### Scenario: incident-trend-analyzer normalization is guarded
- **GIVEN** `tests/fixtures/incident-trend-analyzer/evals/behavioral.json`
- **WHEN** the schema is validated
- **THEN** it contains a case asserting that differently-worded incidents ("request timed out" vs "deadline exceeded") are grouped as one `timeout` failure mode
