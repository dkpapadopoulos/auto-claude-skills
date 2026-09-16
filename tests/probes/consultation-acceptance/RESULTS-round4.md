# Round 4 acceptance — measured 2026-09-16

Set: `cases-round4.json`, sha256 `8ad097c6dcf42bd46db615bfa489f660eb2863ccb532a4fe929dc1cd7a6a226a`
(hashed BEFORE measuring, verified identical after committing).
Measuring commit: `eb5fd6d`. Raw output: `RESULTS-round4.txt`.

## Result

| | score |
|---|---|
| Precision (no false dispatch on 14 non-consultation prompts) | **14/14** |
| Recall (correct skill on 25 consultation prompts) | **5/25** |

`pd-2` was EXCLUDED, on the author's own disclosure — see `round4-provenance.txt`.
It flagged that a MEMORY.md line about the `merge`/`unmerged` bug was in its context and
may have shaped that one decoy. Dropping it is the conservative direction: a decoy the
system was effectively tuned for would inflate precision.

## Provenance

The author recorded zero deliberate inspection and volunteered the passive context it
could not decline (project CLAUDE.md, the skill listing including panel's description,
the memory index). Independently verified: **zero verbatim overlap** between the 40
prompts and the 445 strings already in `tests/fixtures/routing/*` and `tests/probes/*`.

## The recall number splits in two, and the split is the finding

- **15 of 20 misses name no AI vendor.** These are blocked BY DESIGN. Every outbound
  trigger requires an AI-participant token, because without one the triggers matched
  legal depositions, HR candidate reports, finance, science and econometrics prose
  (see `848593d`). "let them argue it out and show me the back and forth" routes
  nowhere, and that is the price of 14/14 precision. It is a PRODUCT trade-off, not a
  defect, and it is the open question a human should rule on.
- **5 of 20 name a vendor and still missed.** Genuine defects, and the lists were not
  the problem — the grammar was. English separates particle verbs ("tear IT apart" vs
  the listed "tear apart"), and "second PAIR of eyes" is as common as "set of eyes".
  Fixed, requiring NO weakening of the AI-token rule, which is what made it safe.

Per-contract recall: second_opinion 3/5, answer_critique 2/5, standalone_panel 0/5,
models_interact 0/5, synthesized_plan 0/5. The three zeros are the by-design half:
none of those 15 prompts names a model.

## This set is now SPENT

The failure list was inspected to diagnose the five phrasing gaps, exactly as happened
to round 3. Any number produced from this set after commit `eb5fd6d` is development
data, not a measurement. A round 5 must be authored the same way — contracts only,
zero tool uses, verified by overlap check — and frozen by hash before measuring.

## What a round 5 should settle

Whether the by-design recall loss is acceptable. Concretely: does a user who writes
"have the two of them respond to each other's points" EXPECT routing, and is the answer
"name a model, or name the skill"? That is a question about the product, and no amount
of regex work answers it.

---

## Policy decision (2026-09-16): relax, with the consent gate carrying egress

The user ruled on the product question above: **vendor-free consultation phrasing should
route again**, moving the egress boundary from the triggers onto the skill's confirmation
step. Implemented in that order, deliberately:

1. **Consent gate first.** An audit found both outbound skills proceeding on "the user's
   go-ahead **from the invocation itself**" — i.e. being routed WAS consent. That is safe
   only while routing implies intent, which is exactly the assumption this decision
   removes. Relaxing first would have turned every routing false positive into an
   authorised dispatch. Both skills now require an explicit affirmative go-ahead and say
   that being routed is not consent (`tests/test-second-opinion-content.sh` fails if the
   old wording returns).
2. **Then the triggers.** Each vendor-free clause requires TWO co-occurring contract
   signals, never one — one signal is always some profession's ordinary vocabulary, which
   is the failure this branch hit seven times.

### The post-relaxation numbers are DEVELOPMENT DATA, not a measurement

`RESULTS-round4-after-relaxation.txt` shows 25/25 recall, 0/14 false dispatch. **This set
was already spent, and these clauses were built against these prompts.** 25/25 is what
fitting produces. It demonstrates the clauses do what they were written to do, and
nothing more. Only a round 5 — contracts only, zero tool uses, frozen by hash — can say
whether vendor-free routing generalises.

### Residual risk, stated plainly

Egress protection now rests on a SKILL.md instruction asking a model to stop and confirm.
That is weaker than a hook-enforced gate. The enforceable version would be a PreToolUse
guard on the dispatch itself, refusing an outbound call with no recorded confirmation for
the current payload. Not built here; it is the natural next hardening step.
