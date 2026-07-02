# Design: Correction-Ergonomics Message Rewrite

## Architecture

Three prose/string edits in owned files + one red-first behavioral A/B pack. No runtime
control flow changes.

### The rewrite pattern

Every rewritten message follows:

```
<GATE-NAME> — Expected: <the invariant the gate protects>.
Actual: <the observed state that violated it>.
Do now: <imperative remediation the reader can execute>, then <verify/retry>.
```

### The four messages (owned files only)

| File | Anchor | Family | Rewrite |
|------|--------|--------|---------|
| `hooks/openspec-guard.sh` | L82 | hard-gate | code-review PUSH GATE → expected/actual/do |
| `hooks/openspec-guard.sh` | L94 | hard-gate | verification PUSH GATE → expected/actual/do |
| `skills/agent-team-review/SKILL.md` | §5 | hard-gate | `On blocking_issues` imperative paragraph |
| `skills/runtime-validation/SKILL.md` | Step 5 item 5 + Coverage Gaps / Manual Checks | could-not-verify / fix-loop | explicit per-failure hand-off |
| `hooks/consolidation-stop.sh` | CONSOLIDATION REMINDER `_MSG` | session-end could-not-persist | expected→actual→imperative **+ preserved opt-out** (anti-theater) |

### Eval: red-first A/B via `--directive-file`

> **This subsection is the *planned* design (pre-outcome). The probe actually returned a
> negative — see Decision #6 and the pack README. The shipped pack is `text`-only, and no lift
> is claimed.**

- Reuses `tests/run-behavioral-evals.sh` prominent `<activation_directive>` injection (the
  faithful mode established by PR #75's intent-extraction eval). Baseline and treatment share
  the same scenario context; only the injected message wording differs (passive vs imperative).
- **Assertions** are deterministic and `text`-only (the shipped pack uses no `tool_call`: a bare
  `claude -p` cannot invoke plugin Skill tools, per PR #75 C3, so we assert on the model naming
  the concrete corrective action). No LLM judge.
- **Red-first (planned):** the intent was baseline-fails / treatment-passes as the in-repo
  replication of the TrueCall lift and the gate for shipping. **Actual outcome: no red→green
  headroom — baselines already pass; no lift measured (Decision #6).**
- **Pinned judge (repo precedent):** "pinned judge" = pinned inner `claude -p --model <model>`
  + recorded gating-run date in the pack README, exactly as PR #75 defines. Pinned `sonnet` and
  `haiku` in the calibration.
- **Adversarial subset + pre-registered safety-stop:** one scenario injects an opt-out advisory
  (a SHIP `…or proceed if not needed` warning) in imperative-styled wording. If the agent is
  induced to force a corrective action on an opt-out advisory (imperative theater), HALT the
  ship and revise. The developer running the gate can call the stop.
- Scenarios are append-only; deprecate with a dated rationale, never delete.

## Trade-offs

- **Deterministic assertions vs LLM judge.** We measure "did the agent take the corrective
  action" via tool_call/text, not a judge grading "self-correction." Rationale: repo convention
  (PR #75) is regex-only; memory guidance favors deterministic, incentive-external checks over
  self-graded prose. Cost: the assertion measures the *action*, a proxy for self-correction, not
  the internal reasoning — acceptable because the action is what downstream consumers depend on.
- **Narrow scope vs broad sweep.** Rewriting only hard-gates/could-not-verify avoids the
  imperative-theater failure mode that killed the prior broad version. Cost: some advisory
  messages that *could* read more actionably are left as-is; deliberate.
- **Small-n risk.** Behavioral A/B with `claude -p` has high variance at small n
  (memory: n=2→100%, n=5→20%). Mitigation: run each arm with `--variance N` (N≥5) and gate on
  the pass-rate delta, not a single run.

## Dissenting views

- *"Rewriting a hook string is trivial; skip the eval."* Rejected: the whole adoption claim is
  a behavioral lift. Without the red-first A/B we'd be shipping wording on faith — exactly what
  the "measured quality benefit" bar (lean-injection rejection) forbids.
- *"Also rewrite the SDLC phase directives — bigger self-correction surface."* Deferred: those
  are owned (`hooks/skill-activation-hook.sh` + `config/default-triggers.json`) but out of the
  task's scope; a broad directive sweep re-opens the theater risk. Park for a follow-up if the
  A/B shows a strong lift.

## Decisions

1. Fold into `pdlc-safety` (MODIFIED, ADDED requirement) — no new capability.
2. openspec-guard: hard-blocks only (L82/L94); five SHIP advisories stay advisory.
3. Pinned judge = pinned `--model sonnet` + recorded date (repo precedent), not new judge infra.
4. Eval pack opt-in (`BEHAVIORAL_EVALS=1`); CI gets only a JSON-validity/append-only guard.
5. Codex sparring (repo-grounded `--fresh`, no web) attacks the rewrites for theater and the
   assertion regexes for false-pass before ship.
6. **Red-first probe returned a negative (2026-07-02).** On both `sonnet` and `haiku` the passive
   baseline already produces the corrective action — no red→green headroom. The TrueCall lift does
   not replicate here for capable subject models with ambient context. Per the pre-registered
   discipline we did NOT tighten assertions to force baseline-red (that would measure structural
   echo = theater; a *pre-registered* semantic assertion could in principle be valid — future
   work). The rewrites ship on clarity / actionability merit (gate logic unchanged → no gate-logic
   regression); the lift claim is not asserted. Method caveats: `--bare` is unusable in
   nested sessions (auth), so the subject ran with ambient plugin context (identical across arms);
   the `text` regex assertions proved too brittle to gate on. Harness retained as a recorded
   negative experiment. Full run record in the pack README.

## Out-of-scope

- superpowers-owned skill bodies (verification-before-completion, requesting-code-review,
  executing-plans, finishing-a-development-branch, brainstorming) — referenced, never edited.
- The five opt-out SHIP advisories in openspec-guard.
- SDLC phase directives / methodology_hints.
- Any change to gate block/allow logic, verdict routing, or fix-loop iteration counts.

## Implementation Notes (synced at ship time)

- **Concurrent adoption of consolidation-stop.** A parallel session merged an imperative
  consolidation nudge to `origin/main` independently during this work. On rebase, this branch's
  consolidation-stop contribution narrowed to adding the honest opt-out clause ("if nothing
  durable emerged, say so and stop") on top of the already-merged nudge.
- **Rebased onto an advanced `origin/main` (+8 commits).** The `push-gate-verdict-split` work
  merged meanwhile and added two NEW passive hard-gate push messages (verification-verdict and
  routing-governance) in `openspec-guard.sh`. These were **left out of scope** (they postdate the
  approved scope) — a follow-up could apply the same expected→actual→imperative shape to them.
- **Negative eval outcome** is recorded in Decision #6 and the pack README; the rewrites shipped
  on clarity merit, not a measured lift.
