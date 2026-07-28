# Spec delta: pdlc-safety — merge-path PR-diff subject

## ADDED Requirements

### Requirement: Merge-path material-source is measured against the merged PR

The IMPLEMENT-evidence leg MUST compute `material_source` for a `gh pr merge`
action from the **merged PR's** changed-file list, not the invoking session's
branch-local delta. The push path MUST continue to use the branch-local delta
with unchanged semantics.

Every shadow record MUST carry a `diff_base` field stating what it was measured
against: `pr:<n>`, `branch-local`, or `unresolved`.

The PR reference MUST be extracted from the command and validated as a bare
integer (`^[0-9]+$`) before being passed to any subprocess, and MUST be passed
as a single argument. A reference failing validation MUST yield `unresolved`
and MUST NOT reach `gh`.

Any resolution failure — `gh` absent, unauthenticated, offline, unknown PR, or
timeout — MUST yield `unresolved`, MUST still write the record, and MUST leave
the guard's stdout and exit code unchanged. The leg MUST remain advisory; this
requirement MUST NOT introduce a `permissionDecision`.

`IMPLEMENT_SHADOW_PREDICATE_VERSION` MUST be incremented, and records of
differing `predicate_version` MUST NOT be pooled when computing any rate.

#### Scenario: a merge is measured against the PR's own files

- **GIVEN** an active chain containing `executing-plans`, no IMPLEMENT evidence,
  a local branch whose diff touches only `docs/`, and a PR whose diff edits
  `src/app.py`
- **WHEN** the model runs `gh pr merge 7 --squash`
- **THEN** a shadow record MUST be written with `action: "gh-merge"`,
  `diff_base: "pr:7"`, and `material_source: true`
- **AND** the guard MUST NOT emit a `permissionDecision`

#### Scenario: an unresolvable PR yields an unresolved record and silence

- **GIVEN** the same chain and evidence conditions, and a merge command whose PR
  reference cannot be resolved
- **WHEN** the model runs that command
- **THEN** a shadow record MUST be written with `diff_base: "unresolved"`
- **AND** the guard's stdout MUST carry no IMPLEMENT advisory text
- **AND** the guard MUST exit 0

#### Scenario: a non-integer PR reference never reaches the fetch

- **GIVEN** a merge command whose PR reference position contains a non-integer
  token such as `--repo other/org`
- **WHEN** the leg resolves the reference
- **THEN** the reference MUST be rejected as `unresolved`
- **AND** no subprocess MUST be invoked with that token

#### Scenario: the push path is unchanged

- **GIVEN** an active chain containing `executing-plans`, no IMPLEMENT evidence,
  and a push whose branch diff edits `hooks/foo.sh`
- **WHEN** the model runs `git push`
- **THEN** the record MUST carry `diff_base: "branch-local"` and
  `material_source: true`
- **AND** the guard's stdout MUST be byte-identical to its output before this
  change
