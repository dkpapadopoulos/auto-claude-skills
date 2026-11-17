# #409 pasted-content scoring: pre-registration (FROZEN v1)

Status: FROZEN 2026-11-17 by the owner ("use your draft bar, freeze it"), with G2 as written
below. The confirmation window starts at the time of the merge commit that brings this file to
main. Nothing in the window may be read before then, and no row below changes after it.

## Question

Does rule R (below) stop routing mandates that come only from text inside harness-wrapped
`<pasted_content>` blocks, without hiding mandates the user's request needed, and without
changing any routing state?

## Development data (already spent; never part of the confirmation)

Measured 2026-11-16/17 on all top-level transcripts on the owner's machine before any
pre-registration. Kept privately at `~/.local/state/acs/409-corpus/` (0700, outside git).

- 3,001 distinct prompts; 79 with real wrappers (76 human, 3 unlabelled); 21 paste-only,
  43 typed-before, 9 before-and-after, 3 after-only, 3 two-block; 0 unterminated, mismatched
  or nested. Every wrapper: opener with `id="hhhh"` (4 hex), closer repeating the same id.
- Current hook: 73/79 carry a MUST INVOKE. Two blind labellers (opus-5-5, sonnet-5-5), raw
  agreement 183/199.
- Correction (2026-11-17, T3): the dev line parser missed `Required when …:` lines and the
  role-less layout, so the domain/workflow counts below are incomplete; process counts stand.
  The confirmation reads selections from the shadow records, not from rendered text.
- Strip-in-scorer (rejected): removes 56 WRONG / 2 RIGHT / 7 unsure-or-split process
  mandates, substitutes 4 WRONG, and deletes the chain state on 50/79 (push-gate bypass).
- R on dev data: hides 56 WRONG / 2 RIGHT / 7 unsure-or-split process mandates; leaves 5
  WRONG shown; domain lines: 0 WRONG left shown, 1 RIGHT kept.
- Multi-turn replay (to paste turn + 10): 14 of 65 hidden mandates re-shown by the chain
  later (10 WRONG); identical in both arms because state is identical.
- Codex round 1 (2026-11-17): proposed R (its "B3"); its harm bar is replaced below because
  it is unreachable at this paste rate (see Bars).

## Rule R (predicate_version 1) — the shipped shadow code IS the rule

1. Parse the raw prompt (before lowercasing), only when it contains the literal
   `<pasted_content id="`: every pair "opener with a 4-hex id, lazily up to the first closer
   with the SAME id, with no opener of that id in between" becomes one newline. An opener
   without a matching closer strips nothing. More than 16 openers: no regex (`capped`).
2. If no pair matched: R does nothing.
3. If the stripped text exceeds 16,384 characters or the hook has run 3 s: R does nothing
   (`skipped`). Otherwise score the stripped text with the hook's own scorer, sticky
   injection (from the chain's step before this turn's writes; not after a pure cancel) and
   role caps, without the context bonus: the stripped selection.
4. R keeps a skill of the full-text selection iff it is in the stripped selection, or it is
   the step sticky composition injected for the full prompt. Everything else R would hide.
   R never adds a skill and never substitutes a process skill.
5. Blind spot (amended after the whole-branch review, before any freeze): the confirmation
   replay below runs each prompt in a fresh HOME, so it never sees a chain or a last-invoked
   signal; the sticky clause in step 3 and the missing context bonus are visible only in the
   production records.
6. Shadow: nothing displayed changes and no routing state changes. One text-free record per
   wrapped prompt is written after every state write.

## Data for the confirmation

- Population: distinct prompts with `origin.kind == "human"` containing at least one pair
  matched by R's parser, whose first transcript timestamp is after the freeze merge commit.
- Read on the first day both hold: >= 100 such prompts and >= 40 sessions; at the latest
  2027-03-31. If not reached by then: INCONCLUSIVE, stop.
- Each prompt is replayed through the shipped hook in a fresh HOME seeded with the then
  registry cache; its mandate set and R's kept set are taken from the shadow fields.

## Labels

- Fresh blind labellers L1 (opus-5-5) and L2 (sonnet-5-5), `--tools ""`, isolated HOME, the
  dev rubric verbatim (RIGHT / WRONG / UNSURE per selected skill for the work the message
  asks for), told nothing about pastes or R. Items shuffled with seed 409.
- The owner labels only L1/L2 disagreements, from a blind worksheet.
- A dead labeller run is rerun, never adjudicated around.

## Bars (all must hold; first failing row decides)

| Gate | Pass condition |
|---|---|
| G0 mechanics | Zero differences in any `.skill-*` file between baseline and shipped hook over every confirmation prompt (with base-vs-base = 0 and the strip-in-scorer mutant > 0). At least one shadow record with matched pairs exists (else: the hook payload carries no wrapper; close as moot). |
| G1 benefit | R would hide >= 50% of consensus-WRONG process mandates, and a session-clustered bootstrap 95% interval (10,000 resamples, seed 409) excludes 0. |
| G2 harm | Consensus-RIGHT process mandates R would hide <= 1 per 10 consensus-WRONG it would hide, AND the one-sided 95% Clopper-Pearson upper bound on (prompts losing any RIGHT process mandate / population) < 10%. |
| G3 sensitivity | Re-score G1 and G2 counting every UNSURE or unresolved label as RIGHT. If the verdict flips: INCONCLUSIVE, not PASS. |

Codex proposed G2 as an upper bound < 5%. At the dev rate (2/79) that needs about 300
prompts (n=150: 6.0%, n=200: 5.2%, n=300: 4.8%), about six months of pastes. The owner
chose this G2 at freeze (2026-11-17); Codex's < 5% bar with N >= 300 is not used.

## Decisions

- PASS: build stage 2 (a session-randomized trial arm that renders R's display), under its
  own pre-registration; the behavioural claim needs the trial, not this replay.
- FAIL on G0: revert the shadow code.
- FAIL on G1 or G2, or INCONCLUSIVE: keep or remove the shadow code by owner decision; R is
  not displayed.

## Not decided here

Methodology-hint triggers (`P` at the hint loop) are out of scope; #412 is frozen.
