# Gate-Gaming Detection (REVIEW-honesty hardening)

## Why

Our REVIEW/SHIP verification trust path can be satisfied by **gaming the gate** rather than
passing it. Two concrete holes, both confirmed against the repo:

1. **Gamed green.** `project-verification` keys PASS to exit code 0 (`SKILL.md:53-58`). An agent
   can make a red suite green by deleting assertions, adding `@skip`/`xfail`, or stubbing the
   subject-under-test — the gate exits 0, PASS evidence is written, and `deploy-gate` reads it.
   (OpenTrajectory's "agent wins by gaming the gate" / reward-hacking failure mode.)
2. **Absence reads as pass.** `deploy-gate:44` accepts a local evidence file with an **empty
   `failed[]`** as "verification performed". A gate command that *could not run* (missing tool,
   env break) is silently absent from both arrays → `failed[]` empty → accepted. (TrueCall's
   "done ≠ done" / fail-closed.)

This change was selected by a 4-perspective design debate (architect/critic/pragmatist + Codex)
from a 7-item candidate portfolio. The debate's load-bearing finding: prose self-policing inside
the same agent's self-run skill is **theater** — it catches honest mistakes while labeling itself
anti-reward-hacking. The fix is to make the flagship a **deterministic shell check over the diff**
(external to the model's incentive, and the only honestly testable form), kept **advisory** to
respect the settled "project-verification is not a trust boundary; enforcement keys on external
CI" decision.

## What Changes

- **Deterministic gate-gaming check** in `project-verification`: before PASS, grep the working-tree
  diff for removed assertion lines and added skip/xfail/disabled markers; emit
  `gate_gaming_status: clean | suspect`. `suspect` downgrades the verdict to SUSPECT (reported,
  not a hook block).
- **Tri-state evidence**: add a `could_not_verify[]` array for gates that errored to run; gates
  that could not execute land here, never silently absent.
- **deploy-gate coordination**: local-verification-of-record acceptance requires `failed[]` **and**
  `could_not_verify[]` empty (and `gate_gaming_status` ≠ `suspect`).
- **implementation-drift-check**: one-line reference consuming the gate-gaming finding at REVIEW
  (defense-in-depth at a second phase), not a reimplemented grep.

## Capabilities

- **Modified:** `project-verification` — gate-gaming detection, tri-state evidence, and the
  deploy-gate consumption contract.

## Impact

- `skills/project-verification/SKILL.md` (Verification section + evidence JSON shape + deterministic check)
- `skills/deploy-gate/SKILL.md` (local-verification-of-record acceptance condition)
- `skills/implementation-drift-check/SKILL.md` (Step 3 reference)
- `tests/fixtures/project-verification/evals/behavioral.json` (red-first scenarios)
- `tests/test-project-verification.sh` (deterministic grep unit test)

## Out of Scope

- Making `project-verification` or the push gate a hard trust boundary — known-unsolvable in-hook
  (forgeable, races); enforcement keys on external CI only.
- Retry-classification taxonomy in `batch-scripting` (contradicts that skill's documented
  "no backoff logic" anti-pattern), the `runtime-validation` imperative-remediation template
  (theater — the fix-loop is already directive), and the `agent-team-review` inter-lens
  disagreement section (unvalidatable under the single-turn runner) — all deferred with revival
  triggers in `design.md`.
- Importing TrueCall's "8%→64%" / OpenTrajectory accuracy numbers as claims — re-measure on our
  own harness before any effect-size claim survives.
