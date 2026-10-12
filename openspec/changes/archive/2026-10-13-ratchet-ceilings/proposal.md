## Why

PR #349 pinned the seven per-phase hint byte totals and PR #348 pinned the session-start fork count as equality ratchets: growth fails, and an unbanked reduction fails too. The 2026-10-12 value review of PRs #347 to #352 found that equality pins on internal counts tax every PR with a re-pin for a number no user sees: the fork count was re-pinned by PR #351 hours after PR #348 introduced it, and the injection baseline moved five times across PRs #349 and #350 and the combined instruction-size baseline four times across PRs #352 and #353. The two totals a user actually pays (the injection budget on every prompt, the instruction-file total every session loads) keep equality; the two internal counts become ceilings.

Separately, `CLAUDE.md`'s Style section said the activation hook takes "~50ms". Measured 2026-10-12 the median is 172 ms, 178 ms on a chained render, and session start takes about 1.6 s with twelve plugins against its stated 200 ms. A hook author reading a false budget mis-judges every cost decision.

## What Changes

- `tests/test-phase-hint-brevity.sh` and `tests/test-session-start-fork-budget.sh` compare with `-le` against their constants: growth fails and must be explained in the commit that raises the constant; a reduction passes; a sum or count that could not be computed still fails. The headers state the policy and the evidence for it.
- `CLAUDE.md` carries the measured latencies beside the stated budgets and labels the budgets as targets; three hook comments that said "~50ms hot path" say "measured median ~170 ms". Comments only.
- `_COMBINED_BASELINE` moves for the longer `CLAUDE.md` line, reason in its comment.
- The two canonical requirements that demanded equality ratchets are modified to demand ceilings, so the spec does not invite reverting the tests.

## Capabilities

### Modified Capabilities

- `skill-routing`: "Phase hints name the owning skill and stay short" and "Session-start fork count is pinned" now specify ceilings, not equality ratchets.

## Impact

- `CLAUDE.md`, `hooks/skill-activation-hook.sh` (comments), `tests/test-phase-hint-brevity.sh`, `tests/test-session-start-fork-budget.sh`, `tests/test-claude-md-rule-split.sh` (baseline), `CHANGELOG.md`, `openspec/specs/skill-routing/spec.md` (two requirements).
- No behaviour a user sees changes.
