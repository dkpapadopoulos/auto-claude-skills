## Why

`tests/run-tests.sh` — the entirety of this repo's declared `.verify.yml` gate — hung indefinitely whenever its stdin was a socket or FIFO rather than `/dev/null`. The suite parked mid-run with no error and near-zero CPU. One observed run sat idle roughly two hours; before an `lsof -p <pid> -d 0` check identified the socket stdin it read as "the suite is slow tonight" and as a 10-minute foreground timeout, not as a bug.

The root cause chain was traced by running the suite under a never-EOF FIFO and `bash -x`-tracing the parked child:

1. `hooks/session-start-hook.sh:61-63` reads its payload with `$(cat)` behind a `[ ! -t 0 ]` check. **A TTY check is not an "input available" check**: a socket or FIFO is not a TTY, so `cat` runs and blocks forever waiting for an EOF that never arrives.
2. `tests/test-context.sh:671` and roughly fifteen sibling call sites invoke that hook with no stdin redirect, so it inherits the suite's fd 0.
3. `tests/run-tests.sh` had no stdin guard, so fd 0 was whatever the caller happened to have — a unix socket in an agent session.

The mitigation until now was caller discipline (`always invoke < /dev/null`) carried **only in auto-memory** — not in `CLAUDE.md`, and `docs/plans/` is gitignored — so any fresh session or CI path that forgot it re-hung. A few call sites in `tests/test-registry.sh` already carried an explicit `< /dev/null`, i.e. this had bitten before and been patched locally rather than systemically.

This taxes every future agent session, and the failure presents as a slow suite rather than a defect.

## What Changes

- `tests/run-tests.sh` self-guards its stdin with `exec < /dev/null`, placed after `set -u` and before test discovery and the execution loop. Because every discovered test file is invoked as a child, one redirect covers all 114 entrypoints at once — which is why the fix is one line rather than a sweep. No test reads the runner's stdin.
- `tests/test-suite-stdin-guard.sh` pins the behaviour. It copies the real runner into a temp dir beside a synthetic stdin-consuming test and drives it over a never-EOF FIFO under an inline watchdog (macOS ships no `timeout(1)`), then asserts the runner terminates *and* that the fixture test actually ran to completion.
- The test carries a **red control**: the same harness run against a guard-stripped copy of the runner must observe the hang. This is what keeps the test from silently going vacuous if the reproduction ever stops working.

## Capabilities

### Modified Capabilities

- `project-verification`: the declared local gate must be able to run to completion regardless of the caller's stdin, and that property is pinned by a regression test that proves it can still observe the failure.

## Impact

- `tests/run-tests.sh` — one `exec < /dev/null` plus an explanatory comment.
- `tests/test-suite-stdin-guard.sh` — new.
- `CHANGELOG.md`, `CLAUDE.md` — the boundary of the guard is now written down rather than carried in memory.
- No hook, gate, or enforcement path is touched. The redirect is per-process and applies only to the test runner.

**Scope boundary, deliberate:** this closes the hang for `tests/run-tests.sh` only. `bash hooks/session-start-hook.sh` under a FIFO still hangs (re-confirmed in review), so a single test file, a hook, or a CI step invoked directly still needs its own `< /dev/null` — which is exactly why `.github/workflows/done-gates.yml:62` carries a comment calling the redirect "REQUIRED on every invocation, not decorative". Hardening the `[ ! -t 0 ]` check itself means changing how a fail-open, gate-adjacent hook acquires stdin, which is a different risk class from a test-harness redirect; it is tracked as issue #188. Issue #189 tracks the separate finding that `tests/run-tests.sh` is absent from `_EVALUATOR_SURFACES` despite being the whole gate.
