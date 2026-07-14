# Plan: walker-backfill-gating-milestones (3 TDD tasks)

Branch: `fix/walker-backfill-gating-milestones` (off main @ 33137ef, v3.70.2).
Spec: `openspec/changes/walker-backfill-gating-milestones/` (committed).
Fix shape: walker-side exclusion — the computed done-prefix never contains
`requesting-code-review` / `verification-before-completion`; those enter
`.completed` only via the completion hook or the monotonic union of on-disk
state. Non-gating back-fill unchanged.

## Task 1 — RED: walker fabrication regressions (tests/test-routing.sh)

- [x] `test_backfill_excludes_gating_milestones`: fresh state, prompt anchoring
      at `openspec-ship` (step 6) → `.completed` contains non-gating
      predecessors but NOT `requesting-code-review` NOR
      `verification-before-completion`. (Spec scenario 1, state half.)
- [x] `test_backfill_ship_prompt_excludes_review`: fresh state, "ship it"-class
      prompt anchoring at `verification-before-completion` (step 5) →
      `.completed` lacks `requesting-code-review`.
- [x] `test_backfill_preserves_disk_gating_entries`: seed on-disk `.completed`
      with `requesting-code-review` (as the completion hook writes it), then a
      re-anchoring prompt → entry survives the union. (Spec scenario 2.)
- [x] `test_backfill_nongating_steps_still_credited`: prompt anchoring at
      `requesting-code-review` (step 4) → brainstorming/writing-plans/
      executing-plans present (chore false-block guard). (Spec scenario 3.)
- [x] `test_lastinvoked_signal_excludes_gating`: last-invoked =
      `verification-before-completion` (beyond review in chain) → prefix does
      not add `requesting-code-review`; verification present only because the
      seeded disk state (completion-hook shape) carries it. (Spec scenario 4.)
- [x] Run: all five RED against current walker (fabrication reproduces);
      existing walker tests still green.

## Task 2 — GREEN: filter the computed prefix (hooks/skill-activation-hook.sh)

- [x] In the state-write block (~:1079-1081), fold the gating-name filter into
      the existing jq pipeline that builds `_comp_completed`:
      `map(select(. != "requesting-code-review" and . != "verification-before-completion"))`
      — one program, no new jq forks, applied to the computed prefix ONLY (the
      union at ~:1102-1110 is untouched so disk entries survive).
- [x] Hardcode the two names adjacent to the existing hardcoded gate invariants
      (max_iterations allowlist precedent) with a comment stating the contract:
      gating milestones require invocation evidence; NOT config-driven.
- [x] Fail-open check: jq failure degrades to `_comp_completed="[]"` exactly as
      today (existing `|| _comp_completed="[]"` path covers the filtered
      program too).
- [x] `/bin/bash -n hooks/skill-activation-hook.sh` (Bash 3.2 syntax gate).
- [x] Task 1 tests GREEN; full `bash tests/test-routing.sh < /dev/null` green.

## Task 3 — End-to-end deny regression + suite

- [x] New test in `tests/test-push-gate-failclosed.sh` (or sibling):
      simulate fresh session, late-anchor prompt writes composition state via
      the real activation hook, then run `openspec-guard.sh` against a
      `git push` payload → DENY naming the missing milestone. (Spec scenario 1,
      gate half — proves the fabrication path is closed end-to-end.)
- [x] Full suite: `bash tests/run-tests.sh < /dev/null` green.
- [x] Routing-governance dogfood note for SHIP: this branch touches `hooks/` —
      before push, run Skill(auto-claude-skills:project-verification) to write
      a clean verdict at HEAD; verdict-write and push as SEPARATE commands.
