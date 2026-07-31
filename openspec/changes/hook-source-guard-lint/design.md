# Design: Hook source-guard lint

## Architecture

Two layers, both deterministic:

1. **Static classification.** For every `hooks/*.sh` matching `trap 'exit 0' ERR`, each line matching `^\s*(\.|source)\s+` is guarded iff it contains `&&` or `||` — i.e. iff the source is a non-final operand of a list, where a non-zero **source status** cannot trip the ERR trap. Everything else is a violation. A trailing comment is stripped before classifying, so `. lib  # see foo && bar` cannot read as guarded on its comment.
2. **Behavioural fixtures.** A committed red hook (unguarded source of a lib that `return 1`s mid-source) and its guarded twin, plus an end-to-end leg that runs the *real* `openspec-guard.sh` against a deliberately broken `session-token.sh`.

The second layer exists because the first is a line-grep and could drift into agreeing only with itself. The fixtures make the detector's own failure visible.

## Dependencies

None. No new scripts, libs, or CI wiring — the file is auto-discovered by `tests/run-tests.sh`.

## Decisions & Trade-offs

**Fix the two gate-critical lines, allowlist the other five.** The issue's decision text specifies "zero runtime risk", which argues for lint-only. But an allowlist containing the two `openspec-guard.sh` lines would leave the exact bypass the lint exists to prevent in place indefinitely. The split confines runtime change to the push-gate hook — where the failure is a silent allow — while the five remaining sites (advisory hooks: consolidation-stop, compact-recovery, skill-completion) become documented debt gated against regression.

**`|| true` alone is not the fix, and shipping it would have looked correct.** A partially-sourced lib leaves `resolve_session_token_from_transcript` undefined; the command-not-found on the very next line trips the same ERR trap, reproducing the bypass with a guard that reads as fixed. The form used is:

```
. lib 2>/dev/null && command -v <fn> >/dev/null 2>&1 && _OK=true || true
```

The flag is load-bearing: it is what makes the `else` fallback reachable. Without it the fallback is dead code, which is why `[ -f "$lib" ]` never protected anything — it proves existence, and the failure under test is a lib that exists and fails while sourcing.

**Allowlist keyed by source text, not line number.** Line numbers drift with every unrelated edit above them, so a number-keyed allowlist silently stops pointing at what it exempted. The key is `<basename>|<trimmed source line>`, which stops matching exactly when that line is touched — forcing a fresh decision at the moment the code changes.

**A stale-entry assertion.** An allowlist whose entries are never re-validated degenerates into a permanent blanket: fix a line, and its exemption outlives it, silently covering whatever appears next. The lint therefore fails when an allowlisted entry no longer matches a real violation. A third assertion pins that `openspec-guard.sh` can never be allowlisted at all, so the #137 decision cannot be quietly reversed.

**Assert on reaching the decision, never on the exit code.** Both fixtures exit 0 — that is precisely the silent-failure signature under test. An exit-code assertion would pass against the bypass. The red fixture is required to *not* print its deny marker; the green one is required to print it.

**Own fixture repo for the e2e leg.** The diff-dependent gate legs need a repo whose state the test controls, so the end-to-end assertion builds a throwaway `git init` repo rather than running against the checkout.

## Verification

The new test against the pre-fix tree — 3 of 10 assertions red, including both end-to-end legs:

| Assertion | Pre-fix | Post-fix |
|---|---|---|
| no unguarded source outside allowlist | **FAIL** — flags both `openspec-guard.sh` lines | PASS |
| guard reaches its push decision when the token lib fails mid-source | **FAIL** — stdout empty, no `permissionDecision` | PASS |
| guard denies rather than falling open | **FAIL** | PASS |

Gate-adjacent suites, all green after the guard change: `test-push-gate-failclosed` (23), `test-push-gate-canary` (10), `test-push-gate-detection` (56), `test-push-gate-verdict` (20), `test-push-gate-ledger` (12), `test-skill-gate` (84), `test-session-token-race` (18), `test-evaluator-surface` (39).

## Known residual gap (found in review, measured)

The `&&`/`||` exemption suppresses the ERR trap for the `.` builtin's own **return status**. It does **not** suppress it when a command *inside* the sourced file fails — that trap fires during the sourced file's execution and still exits the hook. Measured against the guard as shipped here:

| `hooks/lib/session-token.sh` failure mode | Result |
|---|---|
| `return 1` mid-source | deny — covered |
| sources clean, resolver undefined | deny — covered |
| runs `false` mid-source | **silent allow** |
| command-not-found mid-source | **silent allow** |
| `X="$(cd /nope && pwd)"` mid-source | **silent allow** |

The last shape is live in this repo: `hooks/lib/phase-evidence.sh:10` is `_PHASE_EVID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`.

Closing it needs `trap - ERR` around the whole lib-loading region at **every** source site — one site is not enough, because a downstream lib re-sources and re-arms the trap (`hooks/lib/phase-attest.sh:56` re-sources `session-token.sh`). That is a materially larger change to a live gate than this one, so it is tracked as issue #192 rather than folded in here.

The consequence for readers is recorded in the lint's header, the spec, and `CLAUDE.md`: a green run means "no source line can be tripped by its own exit status", **not** "no sourced lib can exit this hook".

## Out of scope

Issue #192, above. Also the five allowlisted sites in `consolidation-stop.sh`, `compact-recovery-hook.sh`, and `skill-completion-hook.sh`. They are advisory paths, not deny paths, so their early exit loses a hint rather than opening a gate. Guarding them is mechanical but each needs its own reachability review of the `else` branch it would newly expose.
