## ADDED Requirements

### Requirement: Prompt delivery survives variadic CLI flags
The behavioral eval runner MUST deliver the constructed prompt to the inner `claude -p`
process via stdin, NOT as a trailing positional argument, because the current Claude CLI
parses `--disallowedTools` as a variadic flag that consumes following positionals.

#### Scenario: Inner invocation under current CLI
- **WHEN** `tests/run-behavioral-evals.sh` invokes the inner `claude -p` with
  `--disallowedTools` present
- **THEN** the scenario prompt MUST arrive on the inner process's stdin
- **AND** no part of the prompt SHALL be interpreted as a permission deny rule

#### Scenario: Stub regression guard
- **WHEN** `tests/test-run-behavioral-evals-variance.sh` runs with a runner that passes
  the prompt as a positional argument
- **THEN** the stubbed `claude` MUST emit a non-matching result within a bounded read
  timeout
- **AND** the test suite MUST fail rather than hang

### Requirement: Format-comparison eval driver
The plugin MUST provide an opt-in driver (`tests/run-format-evals.sh`) that evaluates the
same eval-pack scenarios against multiple renderings of the same artifact and aggregates
per-format pass rates by assertion kind.

#### Scenario: Matrix execution with isolation
- **WHEN** the driver runs a (scenario × format) combination
- **THEN** it MUST inject the format's rendering via `SKILL_PATH`
- **AND** it MUST use a per-format artifacts directory so concurrent per-format
  invocations do not collide on per-iteration artifact files

#### Scenario: Cost gating
- **WHEN** the driver is invoked without `BEHAVIORAL_EVALS=1`
- **THEN** it MUST exit with code 2 without spending any `claude -p` calls

#### Scenario: Kind-tagged aggregation
- **WHEN** variance reports exist for a format
- **THEN** the driver MUST aggregate pass/fail per assertion kind from `[kind]`-tagged
  description prefixes (comprehension, absence, drift)

### Requirement: Deterministic extraction-robustness eval
The plugin MUST include a deterministic test (`tests/test-frontmatter-extraction.sh`)
comparing design-guard heading-grep extraction against flat YAML front-matter extraction
across realistic heading mutations, without any LLM calls.

#### Scenario: Mutation coverage
- **WHEN** `bash tests/test-frontmatter-extraction.sh` runs
- **THEN** the front-matter extractor MUST succeed on all heading mutations
- **AND** the test MUST document (not aspirationally fix) the guard-grep misses,
  including the real-specimen miss of `## Out of Scope` (spaces) against the guard's
  `^## Out-of-Scope` (hyphenated) pattern
