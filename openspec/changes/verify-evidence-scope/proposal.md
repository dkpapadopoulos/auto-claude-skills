# Verify evidence: say what it is, reject a verdict that checked nothing, retire the measured-verdict leg

## Why

Three open issues describe the same component, the VERIFY evidence the push gate reads.

- **#295.** `verdict_is_clean` accepts `{"sha":"<HEAD>","gate_gaming_status":"clean"}`: a record that names
  no check. Three gate legs read that predicate.
- **#343.** The measured-verdict advisory leg (#301) has rendered on every qualifying push for 44 days and
  recorded 299 would-block episodes. None has been labelled, and its rule needs every one labelled by the
  owner. The owner retired it on 2026-11-17.
- **#374.** `_routing_base` resolves a different diff base for the same push depending on how the push is
  spelled, when `origin/HEAD` is unset. With the `HEAD` spelling the base is the branch's own remote copy,
  so only unpushed commits are measured.

## What changes

1. `_routing_base` tries the mainline names before the subject's own upstream, and resolves that upstream
   for the `refs/heads/<b>` spelling too.
2. The measured-verdict advisory leg, its shadow writer, its reader and its test are removed. The
   registration is kept as history with a retirement section. No corpus file on a user's disk is touched.
3. `verdict_is_clean` requires one JSON object, array-typed result fields, and at least one named check in
   `passed`. The not-clean remedy gains a sentence for that case. Documentation and deny text stop
   describing the verdict as anything stronger than workflow evidence an agent can write.

## What does not change

- No leg starts requiring a measured verdict. Hand-authored verdicts with a named check stay accepted.
- The composition-chain VERIFY check still declines the verdict (#254, refused on measurement).
- Option A of #295 and the behavioural half of option C are not built.
- F9, F11, F13 and F14 from #295 stay enumerated and unmeasured.

## Impact

`hooks/lib/verdict.sh`, `hooks/openspec-guard.sh`, `scripts/gate-status.sh`, `scripts/verify-receipt.sh`
(reads the same predicate), `skills/project-verification/SKILL.md`, `docs/enforcement-map.md`, `CLAUDE.md`,
`.claude/rules/push-gate-telemetry.md`, and the tests that seed a verdict (29 files, 72 seed lines without
`passed`). Removed: `hooks/lib/verify-shadow.sh`, `scripts/verify-shadow-adjudicate.sh`,
`tests/test-verify-measured-verdict.sh`.
