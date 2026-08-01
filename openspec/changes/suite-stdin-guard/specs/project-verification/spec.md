## ADDED Requirements

### Requirement: The declared local gate MUST run to completion regardless of the caller's stdin

The runner that executes the repo's declared `.verify.yml` gate MUST NOT block on inherited stdin. `tests/run-tests.sh` SHALL redirect its own stdin from `/dev/null` before discovering or executing any test file, so that every test — and every hook those tests invoke — inherits a descriptor that yields immediate EOF. The guard MUST precede the test-execution loop; a redirect placed after it would satisfy a textual check while leaving the hang intact. This requirement covers the runner only: a test file, hook, or CI step invoked directly still supplies its own `< /dev/null`, because the underlying hook-side cause is out of scope here.

#### Scenario: Suite invoked with a never-EOF stdin

- **WHEN** `tests/run-tests.sh` is invoked with a socket or FIFO on file descriptor 0 that is held open and never written to
- **THEN** the suite runs every discovered test file and exits on its own, rather than parking indefinitely at the first test that invokes a stdin-reading hook

#### Scenario: Stdin-consuming test still executes

- **WHEN** a discovered test file reads stdin to EOF during a suite run
- **THEN** that test receives EOF immediately and runs to completion, and the runner reports it as passed rather than skipping or truncating it

### Requirement: The stdin guard MUST be pinned by a regression test that can still observe the failure

A regression test SHALL reproduce the original defect behaviourally — driving a copy of the real runner against a never-EOF stdin under a watchdog — rather than asserting that the runner contains a particular string, which would be a tautology over the diff. The test MUST additionally carry a control proving it is not vacuous: the same harness, run against a copy of the runner with the guard removed, MUST observe the hang. That control MUST verify the removal actually changed the runner, because asserting only that the guard pattern is absent from the stripped copy is equally true when the strip worked and when the pattern never matched, and therefore passes even with the guard deleted from the runner entirely.

#### Scenario: Guard removed from the runner

- **WHEN** the regression test's harness is run against a copy of `tests/run-tests.sh` whose stdin guard has been stripped
- **THEN** the harness observes a hang and the test fails, demonstrating that the assertion is gating rather than vacuous

#### Scenario: Strip silently fails to remove anything

- **WHEN** the guard-stripping step produces a copy byte-identical to the real runner, or the real runner carries no matching guard to strip
- **THEN** the test fails with a message naming the vacuous control, instead of passing on the absence of a pattern that was never present

#### Scenario: Guard rewritten in an equivalent form

- **WHEN** the runner's guard is written as an equivalent redirect such as `exec 0</dev/null` instead of `exec < /dev/null`
- **THEN** the test still passes, because a static check MUST NOT be stricter than the behaviour it stands for

### Requirement: The regression test MUST NOT be able to kill unrelated processes

The test's cleanup path SHALL verify that its temporary directory was created before using that path as a process-matching pattern. `set -u` does not protect this: a failed `mktemp` assignment succeeds with an empty value, and an empty pattern is rejected by BSD `pgrep` but matches every process owned by the user under glibc, so an unchecked failure would escalate from a skipped cleanup to killing the developer's session or an entire CI runner.

#### Scenario: Temp directory creation fails

- **WHEN** `mktemp -d` fails or yields an empty path
- **THEN** the test exits with an explicit error before running any fixture, and its cleanup trap performs no process-matching kill
