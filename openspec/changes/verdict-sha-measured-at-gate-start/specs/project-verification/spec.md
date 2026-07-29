# Delta: project-verification — verdict sha measured at gate start

## ADDED Requirements

### Requirement: The verdict's commit binding is measured when the gate runs

`scripts/verify-and-record.sh` SHALL capture the repository HEAD immediately
before the declared gate commands execute and record that value as the
verdict's `sha`, so the record names the commit whose tree was actually
measured rather than whichever commit happens to be HEAD when the record is
written.

The script SHALL re-read HEAD after the gate loop. If HEAD changed while the
gate ran, the run covers no single commit and the script SHALL record
`gate-run-straddled-commit` in `could_not_verify[]` and report it on stdout,
so the verdict fails `verdict_is_clean` rather than silently claiming a
result for a commit it did not test.

The script SHALL additionally record an advisory `worktree_dirty` boolean —
whether tracked files were modified at gate start. `worktree_dirty` MUST NOT
affect `passed[]`, `failed[]`, `could_not_verify[]`, or `gate_gaming_status`:
verifying uncommitted work and committing afterwards is a supported workflow.

#### Scenario: a run that straddles a commit is recorded as unverifiable

- GIVEN a repository whose declared gate command creates a commit while it runs
- WHEN `verify-and-record.sh` runs
- THEN `could_not_verify[]` contains `gate-run-straddled-commit`
- AND `sha` is the HEAD that preceded the gate loop, not the commit created
  during it
- AND the artifact does not satisfy `verdict_is_clean`

#### Scenario: an ordinary run is bound to HEAD exactly as before

- GIVEN a repository whose declared gate makes no commit
- WHEN the script runs
- THEN `sha` equals the repository HEAD and `could_not_verify[]` is empty

#### Scenario: a dirty worktree is disclosed but never gates

- GIVEN a repository with a modified tracked file and a passing declared gate
- WHEN the script runs
- THEN `worktree_dirty` is `true`
- AND `could_not_verify[]` is empty and the verdict satisfies
  `verdict_is_clean`
