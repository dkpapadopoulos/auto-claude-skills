# skill-routing: the branch diff base

## ADDED Requirements

### Requirement: The branch diff base does not depend on how the push is spelled

The push gate's branch diff MUST be the subject commit's net change against the
mainline: the base is the merge-base of the subject with the first of
`origin/HEAD`, `origin/main`, `main`, `origin/master`, `master` that shares
history with it, and only when none does, with the subject branch's own
upstream. A push that names its branch and a push that names `HEAD` MUST
resolve the same base for the same commit.

#### Scenario: Both spellings with origin/HEAD unset

- **GIVEN** a repository whose `origin/HEAD` is unset and which has a `main`
- **AND** a feature branch that has an upstream and one unpushed commit
- **WHEN** the base is resolved for `HEAD` and for `refs/heads/<branch>`
- **THEN** both MUST be the merge-base with `main`

#### Scenario: No mainline name resolves

- **GIVEN** a repository with none of the mainline names and `origin/HEAD` unset
- **WHEN** the base is resolved for `HEAD` and for `refs/heads/<branch>`
- **THEN** both MUST be the merge-base with that branch's own upstream

#### Scenario: A file restored to its mainline content

- **GIVEN** a branch that changed a file, pushed, then restored the file to the mainline's content
- **WHEN** the branch diff is listed
- **THEN** that file MUST NOT be in it
