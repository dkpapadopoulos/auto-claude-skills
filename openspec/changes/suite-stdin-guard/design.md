# Design: Suite stdin guard

## Architecture

The fix is a single redirect in `tests/run-tests.sh`:

```
set -u
exec < /dev/null      # <- inherited by every `bash "${test_file}"` below
SCRIPT_DIR=...
for test_file in ${test_files}; do bash "${test_file}"; done
```

Placement is load-bearing in one direction only: the redirect must precede the execution loop. It sits immediately after `set -u`, above discovery, so nothing in the runner can consume stdin before it applies.

Child processes inherit fd 0, so the redirect propagates to each `test-*.sh`, and from there to any hook those tests invoke. That inheritance is the whole reason one line substitutes for a per-call-site sweep.

## Dependencies

None. No new packages, no changes to hooks, libs, or gate paths.

## Decisions & Trade-offs

**Fix the runner, not the ~15 call sites.** Redirecting at each unredirected `bash .../session-start-hook.sh` in the tests would work but is a large, error-prone diff that has to be re-done every time a new call site appears — and `tests/test-registry.sh` shows exactly that failure mode, having already accumulated three ad-hoc `< /dev/null` patches without the class ever being fixed. The runner guard cannot be forgotten by a new test.

**Do not fix `[ ! -t 0 ]` in `session-start-hook.sh` here.** This is the true root cause and it remains live: the hook still hangs when invoked directly under a FIFO. It was deliberately excluded because the hook is fail-open (`trap 'exit 0' ERR`) and gate-adjacent — changing how it acquires stdin risks converting "no payload" into an early exit that skips registry building or gate enforcement, which is a strictly worse failure than a hang. In production Claude Code always pipes JSON and closes the pipe, so the hazard is confined to hostile or absent stdin. Tracked as issue #188 with its own red-fixture requirement.

**Consequence, stated rather than implied:** the caller-discipline rule survives everywhere except the runner. `.github/workflows/done-gates.yml` already encodes this on every step. The `CLAUDE.md` gotcha added by this change now states the boundary explicitly, since the prior rule lived only in auto-memory and gitignored `docs/plans/`.

**A behavioural regression test, not a grep.** Asserting that `run-tests.sh` contains the string `exec < /dev/null` would be a tautology over the diff. The test instead reproduces the original failure — real runner, real FIFO, real watchdog — so it fails for the reason the bug existed. An ordering assertion is kept alongside it because a redirect placed *below* the loop would satisfy a naive grep while fixing nothing.

**The red control, and why it needed fixing.** Because the positive assertion is "the suite terminated", a harness that stopped reproducing the hang would make the test pass for the wrong reason forever. The control therefore runs the same harness against a guard-stripped runner and requires it to hang.

Review mutation-tested this and found the control was itself vacuous in exactly the case its own comment named. It asserted only that the guard pattern was **absent** from the stripped copy — which is equally true when the strip worked and when the pattern never matched anything — so it passed with the guard deleted from the runner entirely. It now asserts the strip actually *changed* something (`cmp -s` against the real runner) and fails loudly when there is no matching guard to strip.

Relatedly, the three hardcoded `^exec < /dev/null` literals were replaced by one tolerant pattern (`^exec[[:space:]]+0?<[[:space:]]*/dev/null`). Previously a functionally identical `exec 0</dev/null` reformat produced two red assertions while the assertion designed to catch reformats passed — a static check stricter than the behaviour it stands for.

**Watchdog instead of `timeout(1)`.** macOS ships neither `timeout` nor `gtimeout` by default (verified). The test backgrounds the runner and polls `kill -0` on a `sleep 1` counter, which errs long under load rather than short. The red control is designed to hang, so it spends the full 10s budget on every suite run; that cost is inherent to proving non-vacuity, not slack.

**Safety of the cleanup trap.** `mktemp -d` is checked explicitly. `set -u` does not catch its failure — the assignment succeeds with an empty value — and the EXIT trap would then run `pkill -9 -f ""`. BSD `pgrep` rejects an empty pattern, but under glibc `regcomp("")` matches every process owned by the user, so on a Linux CI runner that is a SIGKILL to the whole session. The trap additionally refuses to `pkill` anything that does not look like its own temp dir.

## Verification

Measured A/B on the identical invocation — full suite, never-EOF FIFO on fd 0:

| | Result |
|---|---|
| Before (main @ `108a293`) | parked at `test-context.sh`, file 19/114; watchdog-killed at 900s |
| After | exited on its own at 730s — 114 files run, 114 passed, 0 failed |

Red-green on the regression test: red before the guard (4 failures, the behavioural assertion reporting `hung`), green after (6/6).

Mutation battery re-run against the fixed test:

| Mutant | Before review fixes | After |
|---|---|---|
| M0 unmutated | 6 PASS | 6 PASS |
| M1 guard deleted | 4 FAIL — red control passed **vacuously** | 5 FAIL |
| M2 `exec 0</dev/null` (identical redirect) | 2 FAIL — **spurious** | 6 PASS |
| M3 guard below the loop | 4 FAIL | 4 FAIL |
