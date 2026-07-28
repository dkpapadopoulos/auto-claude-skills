# Spec delta: pdlc-safety — done-gate CI enforcement

## ADDED Requirements

### Requirement: The owned done-gates run in CI, and the claim is pinned

The two owned done-gates — routing-fixture coverage and skill-content coverage — MUST run
in a GitHub Actions workflow on every pull request, so their enforcement does not depend on
a local hook that a web-UI merge bypasses by construction.

A regression test MUST pin that workflow's existence and its invocation of both gate
scripts, so that deleting, renaming, or narrowing the workflow fails the suite rather than
silently reverting the enforcement claim.

Documentation describing enforcement MUST distinguish the CI-run gates from
`.verify.yml`, which is `substrate: local` and is read by no workflow. A document MUST NOT
describe the full `tests/run-tests.sh` suite as running in CI while no workflow invokes it.

Every test invocation in that workflow MUST close stdin, because these suites hang when
stdin is a socket and on a runner that surfaces only as an uninformative timeout.

The workflow is scoped to the two named gates; wiring the full suite is explicitly NOT
required by this requirement.

#### Scenario: the coverage gates are checked on a pull request

- **GIVEN** a pull request against the default branch
- **WHEN** CI runs
- **THEN** a workflow MUST execute both `tests/test-fixture-coverage.sh` and
  `tests/test-skill-content-coverage.sh`
- **AND** each invocation MUST redirect stdin from `/dev/null`

#### Scenario: removing the workflow fails the suite

- **GIVEN** the done-gates workflow is deleted, renamed, or edited so that it no longer runs
  one of the two gate scripts
- **WHEN** the test suite runs
- **THEN** the pinning regression MUST fail
- **AND** the failure MUST identify which gate is no longer covered

#### Scenario: enforcement documentation matches reality

- **GIVEN** a document that states which checks block a merge
- **WHEN** it describes the owned done-gates
- **THEN** it MUST name the workflow that runs them, and MUST state that hard-blocking
  additionally requires the check to be marked Required in branch protection
- **AND** it MUST NOT claim that `.verify.yml` or the full suite runs in CI
