# Delta: pdlc-safety — push-gate observability (gate-status)

## ADDED Requirements

### Requirement: Push-gate status is explainable on demand

The plugin SHALL provide `scripts/gate-status.sh`, a purely observational
command (exit 0 always) that replays the push gate's decision for the current
branch in `hooks/openspec-guard.sh`'s exact gate order, sourcing the guard's
own evidence libraries (`session-token.sh`, `branch-ledger.sh`, `verdict.sh`)
rather than reimplementing evidence parsing, and reporting the first denying
gate with its remedy.

#### Scenario: missing evidence explained with remedy

- WHEN the command runs on a branch with no REVIEW or VERIFY record
- THEN it reports WOULD DENY at the global fail-closed gate, names the
  missing milestone(s), prints the remedy and the human-only bypasses, and
  exits 0

#### Scenario: evidence satisfied

- GIVEN branch-ledger milestones for review and verification and, in a
  routing repo with routing-path changes, a clean verification verdict at HEAD
- WHEN the command runs
- THEN every replayed gate reports pass and the summary reports WOULD ALLOW

#### Scenario: observational invariant

- WHEN the command runs in ANY state, including outside a git repository or
  with every gate denying
- THEN it exits 0 and writes no state

### Requirement: Enforcement surfaces are documented in one map

The plugin SHALL document every blocking and advisory enforcement surface in
`docs/enforcement-map.md`, and `gate-status.sh --help` SHALL stay in sync
with it (shared phrases pinned by `tests/test-gate-status.sh`).

#### Scenario: help/map drift is caught

- WHEN a pinned shared phrase is removed from either the map or the help text
- THEN `tests/test-gate-status.sh` fails

### Requirement: REVIEW staleness stays observational pending live data

The staleness line SHALL be observation only: the post-review delta between
the recorded review SHA and HEAD, docs-vs-source split, computed by
`hooks/lib/staleness-delta.sh`. Hardening it to a deny MUST be preceded by a
re-run of the pre-registered backtest protocol
(`openspec/changes/gate-status/backtest-protocol.md`) meeting its frozen
decision rule — false-block rate ≤5% AND ≥1 catch (2026-07-15 measurement:
56–94% false-block, 0 catches).

#### Scenario: staleness reported, never denied

- GIVEN a review ledger SHA that is an ancestor of HEAD
- WHEN the command runs
- THEN the post-review delta is printed with a docs/source split and framed
  as observation only, and no replayed gate denies because of it
