# Proposal: Correction-Ergonomics Message Rewrite (TrueCall adoption, Phase C)

## Why

TrueCall's correction-ergonomics finding: rewriting agent-facing gate messages from
passive notices into an **expected → actual → imperative-remediation** shape lifted
self-correction from 8% to 64%. Our owned hard-gate / could-not-verify / iterative-fix-loop
messages are currently passive ("report remaining failures as requiring human review",
"PUSH GATE: X has not been completed…"). Adopting the imperative shape on exactly these
messages should raise the rate at which a downstream agent actually performs the remediation
instead of narrating a passive status.

Scope is deliberately narrow. A prior broad imperative sweep was killed for "imperative
theater" — forcing corrective action on hints that legitimately offer an opt-out. This change
rewrites **only** hard-gates and could-not-verify/fix-loop terminals in files **we own**, and
leaves genuinely-advisory opt-out warnings advisory.

**Empirical note (negative result).** The claimed self-correction lift was probed red-first and
**did not replicate in this n=1, non-bare, ambient-context calibration**: on both `sonnet` and
`haiku` the passive baseline already elicits the corrective action, leaving no headroom for the
imperative wording to lift. This is not a claim that a lift is impossible under a cleaner setup.
The rewrites ship on clarity / actionability merit only; the lift claim is explicitly not asserted.

## What Changes

- **`hooks/openspec-guard.sh`** — rewrite the two hard-block PUSH GATE deny strings (L82
  code-review gate, L94 verification gate) to expected → actual → imperative. Leave the five
  SHIP-phase `…or proceed if not needed` advisory warnings untouched (opt-out = advisory).
- **`skills/agent-team-review/SKILL.md`** — add an imperative `On blocking_issues` paragraph
  under the §5 verdict-routing table (expected zero blocking → actual N remain → return to
  IMPLEMENT, fix each cited finding, re-review, do not SHIP).
- **`skills/runtime-validation/SKILL.md`** — rewrite the Step 5 fix-loop terminal
  ("after 3 iterations…") to an explicit per-failure hand-off; fold in the Coverage Gaps /
  Manual Checks imperative edits (same could-not-verify family).
- **`hooks/consolidation-stop.sh`** — rewrite the session-end CONSOLIDATION REMINDER to the
  expected → actual → imperative shape, **preserving an explicit honest opt-out** ("if nothing
  durable emerged, say so and stop") so it does not force consolidation theater when there is
  nothing to persist.
- **New red-first behavioral A/B pack** `tests/fixtures/correction-ergonomics/evals/behavioral.json`
  probing the lift. **Result: negative in this n=1, non-bare, ambient-context calibration** — on
  both `sonnet` and `haiku` the passive baseline already produces the corrective action (ceiling
  effect), so no red→green lift was measured. The rewrites therefore ship on **clarity /
  actionability merit** (gate logic unchanged → no gate-logic regression), NOT on a claimed
  behavioral lift. The pack is retained as a recorded negative experiment. See the pack README
  for the run record and method caveats.

## Capabilities

### Modified
- **pdlc-safety** — adds a requirement that owned hard-gate / could-not-verify messages use the
  expected → actual → imperative-remediation shape, probed red-first (a lift is claimed only if
  measured), while opt-out advisories stay advisory. No new capability is minted; this extends the
  existing safety-gate + eval-strategy surface.

## Impact

- Message prose only in four owned files; **no runtime gate/skill behavior change**. Push-gate
  block/allow decisions, verdict routing, fix-loop iteration counts, and stop-hook exit behavior
  are unchanged — only the wording of the human/agent-facing text.
- Additive test surface (not a runtime-behavior change): a new opt-in eval pack
  (`BEHAVIORAL_EVALS=1`, not in CI) plus a deterministic shape-guard `tests/test-correction-ergonomics-pack.sh`
  that `run-tests.sh` auto-discovers, so the pack cannot rot silently.
- No change to superpowers-owned skills; those are referenced, not edited.
