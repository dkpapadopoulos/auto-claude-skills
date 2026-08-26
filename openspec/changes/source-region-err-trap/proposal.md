## Why

#137 guarded every `.`/`source` call site in `hooks/openspec-guard.sh` so a lib returning non-zero could not trip `trap 'exit 0' ERR`. That fix is real, but it is **status-only**, and its own spec said so: the `&&`/`||` exemption suppresses the trap for the `.` builtin's return status and NOT for a command that fails *inside* the sourced file. That trap fires during the sourced file's execution, above every deny check, and the hook exits 0 with **empty stdout** — which the harness cannot distinguish from an allow.

Measured at `b05925c` against the real guard with a `git push origin HEAD` payload, one fault at a time and gate state otherwise identical:

| `hooks/lib/*.sh` failure mode | Result |
|---|---|
| healthy | `deny` (460 bytes) |
| `return 1` mid-source | `deny` / announced degradation — #137, correct |
| `false` mid-source | **EMPTY STDOUT — silent allow** |
| command-not-found mid-source | **EMPTY STDOUT — silent allow** |
| `X="$(cd /nope && pwd)"` mid-source | **EMPTY STDOUT — silent allow** |

Reproduced at two injection points each for the six libs the new matrix covers, which are **exactly** the six entries of `_GATE_ENFORCE_LIBS` (`hooks/session-start-hook.sh:640`) — `phase-attest.sh` is already one of them, so an earlier draft describing this as "the five plus `phase-attest.sh`" was wrong and is corrected here; the matrix population itself was always right. The guard sources eleven distinct libs across thirteen sites; the other five are diagnostic or advisory and are converted too, but they are not what the matrix is for. Adversarial review verified that "diagnostic" claim empirically rather than taking it: under truncation, mid-source `return 0`/`return 1`, `set -e`, `set -u` and a hostile `trap`, all five leave the decision byte-identical to the healthy control. It holds for every fault shape except `exit` — four of the five are sourced ABOVE every deny site, so an `exit` there is as fatal as in a gate lib. Carrying no decision is not the same as being unable to end the hook.

The third shape is a live line in this repo: `hooks/lib/phase-evidence.sh:10` is `_PHASE_EVID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`. `phase-evidence.sh` is sourced behind `|| true`, which does not help — the trap fires inside the sourced file, not on the source's status.

Nothing in the repo could see this. `bash -n` reads a parse-clean file; `tests/test-hook-source-guards.sh` reads a correctly-guarded call site and stays green through every row above; the session-start canary source-probes only the six `_GATE_ENFORCE_LIBS` and never the guard that sources them.

## What Changes

- **`_guard_load` in `hooks/openspec-guard.sh`** — the one way this hook may source anything. It disarms the ERR trap across the load, sources, re-arms, and returns the source's own status so every #137-shaped call site keeps its form. All 13 lib source sites now route through it.
- **Belt-and-braces, deliberately.** Two independent mechanisms hold: the explicit `trap - ERR`/re-arm, and the fact that bash does not inherit an ERR trap into a function without `set -E` (measured on 3.2.57). The failure mode is a silent gate bypass, so a single mechanism that a later `set -E` or a refactor could quietly remove is not enough.
- **Fixing one site would not have worked.** `phase-attest.sh` re-sources `session-token.sh`; a trap re-armed too early just fires one lib later.
- **New runtime test** (`tests/test-hook-source-guard-runtime.sh`) + committed per-shape fixtures (`tests/fixtures/hook-source-guard-runtime/`): 6 libs x 3 fault shapes x 2 injection points against the real guard, plus a healthy control and a red control. Mutation-verified — reverting only the guard turns it red.
- **The #137 lint's matcher now covers `_guard_load` too** — found in review, and it was a real regression introduced by this change: routing the sources through a helper dropped `openspec-guard.sh`'s lint population from **13 lines to 1**, moving every site the lint exists to protect out of its own scope while the "never allowlistable" assertion kept passing vacuously. The call shape still decides — a bare `_guard_load lib` on a failing lib is a failing simple command at top level, i.e. the same silent allow (measured: bare call printed nothing and never reached the decision path; `|| true` reached it). Mutation-tested: a bare call in a disposable copy is now flagged.
- **`_guard_load` is re-entrant** — the re-arm is depth-counted, not unconditional. Found by a fifth review of the committed tree: a nested call restored the trap while the outer source was still running, which is this document's own "fixing one site would not have worked" argument recursed one level, and is exactly where the trap line's justification ("it survives someone adding `set -E`") stopped holding. Latent, not live — no lib calls the helper — but fixed because it falsified the rationale for keeping the line.
- **The lint gained a population floor over matched source LINES.** Its only sanity check counted ERR-trap FILES, which is why the 13-to-1 collapse passed every assertion; renaming the helper would reopen the identical vacuum. Prose in the spec is not a gate.
- **`tests/test-push-gate-degradation-advisory.sh` cell 3b updated.** It asserted EMPTY output as an explicit `#192 boundary` marker so it would fail the day this landed. It did. It now asserts the same announced degradation as the absent-lib cell.

## Capabilities

### Modified Capabilities

- `pdlc-safety`: a command failing *inside* a lib sourced by the push gate must not exit the gate; the residual gap recorded by #137 is closed for `hooks/openspec-guard.sh` and remains open, by name, for the non-outbound hooks.

## Impact

- `hooks/openspec-guard.sh` — `_guard_load` added; 13 source sites converted. No change to any decision, message, ordering, or gate state on the healthy path: the pinned byte-identical healthy-control fixture (`tests/fixtures/guard-lib-fault/healthy-control.json`) is unchanged.
- Two behavioural changes, both toward enforcement: a lib that fails mid-source no longer exits the hook, and the `branch-ledger.sh` site's stderr is now suppressed like every other site's.
- Scope is `hooks/openspec-guard.sh` only. `compact-recovery-hook.sh`, `compact-recovery-prompt-hook.sh`, `consolidation-stop.sh`, `skill-completion-hook.sh` and `skill-gate.sh` still source libs directly and remain exposed to this class; none gates an outbound action, and `publish-guard.sh` — the other outbound deny — sources nothing. The helper cannot be shared into `hooks/lib/`: sourcing a lib to make lib-sourcing safe leaves the first source unprotected.
- No change to `_GATE_ENFORCE_LIBS`, the canary manifest, or the drift manifest — this adds no gate-enforcement lib.

## Residual gaps found by review, NOT closed here

Both are pre-existing, both were confirmed against `b05925c` as well as this branch, and both are recorded so a green run of the new test is not read as "the gate can no longer go silent".

- **A lib that `exit`s during source still kills the hook** (empty stdout, exit code 7), on ten of the eleven libs. `trap - ERR` cannot stop `exit`. Closing it needs a subshell pre-probe per lib on the hot path. No lib does this today.
- **With `jq` absent the ENTIRE push gate is a silent no-op.** Measured with a PATH shim omitting only `jq`, everything else identical: no jq → empty stdout; jq relinked → `deny`. Two independent causes — the no-jq payload fallback greps only `command`, so no token resolves and the hook takes the empty-token exit; and even with a token seeded, every gate body sits behind `command -v jq`, so the guard walks the whole gate, decides nothing and exits 0. #198's degradation inventory has no note for missing `jq`, and the empty-token exit only announces when the token lib failed — which it has not here — so the one case that warrants "nothing was gated" is precisely the case that stays quiet. This is a gap in #198's inventory, not in #192, and deserves its own change.
