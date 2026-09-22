# Amendments required before a second pair

Written 2026-09-22, after the v1 run and after putting both proposals to an outside
model to attack. It rejected the first and accepted the second with a condition; both
outcomes are recorded below, including where my framing was wrong.

These amendments change the instrument, so a second pair is a **new registration** whose
results do not pool with v1. That cost was accepted when the change was held open.

## Defect 1 — criterion (a): adaptation

### What I had wrong

I recorded this as "criterion (a) is uncommunicable". That is not the defect. The
accurate statement is that **it cannot be reliably satisfied under the protocol's own
communication constraints** — a real difference, because "uncommunicable" implies no
instruction could ever work, and one could, at a price stated below.

A second correction, and the more consequential one: **missing documentation is missing
evidence, not evidence of deficient adaptation.** To the extent criterion (a) counted
against arm S, it partly measured compliance with a reporting requirement the arm was
never given. The v1 record already declines to score it against the arm; this states why
in the right terms.

### Why the obvious fix does not work

The proposal was to extend the harness preamble — identical for both arms — with: "if you
change, or deliberately decline to change, any existing convention or configuration
already present in this repository, say so briefly and why."

Three reasons it fails, none of which is about symmetry:

1. **It does not elicit what (a) asks for.** (a) wants the original rule, its predicted
   failure against this task, the change, and a check distinguishing original from
   adapted. "Say so briefly and why" produces none of those reliably. The amended
   protocol could reproduce the identical missing evidence with every arm fully
   obedient.
2. **"Any existing convention" is an unbounded obligation.** The arm must guess which of
   its many decisions merit mention.
3. **Identical wording is not neutrality.** The sentence points at a substantial supplied
   resource in arm S and at little in arm C, so it can interact with the treatment. That
   does not invalidate a comparison, but it changes what the comparison estimates: the
   effect of the seed *when agents are prompted to account for decisions about existing
   conventions*. If that is the intended quantity, say so; it is not what v1 claimed to
   measure.

The manufacturing risk is also more precise than I stated: the prompt does not force a
change, it creates demand for a *reportable decision* — which can produce unnecessary
changes **or** invented justifications for leaving things alone.

### What to do instead

**Remove the reasoning requirement from the primary evaluation**, and measure what is
observable without asking:

- whether any file in the frozen seed changed (already available from the freeze commit);
- **whether the implementation used, overrode, or bypassed the seed's rules** — this is
  the part v1 missed entirely. An unchanged seed directory does **not** establish
  unchanged *application* of the seed: an arm can override tokens elsewhere, restyle
  components, or ignore the seed while leaving its files pristine.

If adaptation rationale is genuinely wanted, obtain it as a **separate, standardised
post-freeze follow-up**, asked of every builder after the artifact is frozen, and label
it **retrospective self-report** — not evidence that the reasoning happened during
construction. It cannot prevent retrospective rationalisation, but it cannot contaminate
the build either.

And if the objective really is that arms *perform and document* an adaptation assessment
while building, then **ask for it explicitly and accept it as part of the task**. An
otherwise invisible deliberative activity cannot be required while treating the
instruction that elicits it as inconsequential.

**Rejected:** retaining the seed's `ADOPT.md` in the worktree as the channel. It can
encourage adaptation without eliciting the required evidence, and keeping a document
against its own adoption instructions needs its own justification about which stage of
adoption is being studied.

## Defect 2 — the capture procedure

### What I had wrong, again usefully

I described the procedure as recognising one theming mechanism. Sharper: it **produced
renders under two OS-preference conditions, and I reported them as two theme states.**
Those are different claims, and conflating an environmental condition *requested* with a
theme state *reached* is the protocol's clearest mistake here.

On that framing the original capture was **correct as an OS-preference probe** and wrong
only as general theme capture. What the v1 result establishes is that neither artifact's
appearance changed under that probe — not that the two have equivalent theme capability.

Arm S's attribute-gated styles may be dormant, unfinished, or intended for a host that
sets the attribute. Absent any requirement for theme access or OS adaptation, their
dormancy is **not automatically a task failure** — and v1 must not be read as finding one.

### What to do

Capture **one precisely specified condition**, registered in advance: OS preference,
clean browser and storage state, viewport, and any permitted interactions. State in the
rubric:

> Evaluation covers the appearance rendered under this capture condition. Theme
> availability, switching, and appearance in other theme states are outside scope.

Choose that condition **before** the run. Selecting whichever appearance flatters an
artifact after the fact is the failure this whole apparatus exists to prevent.

**Acknowledged cost:** dropping the pair does narrow the evidence. R6 (consistency of
repeated elements and state treatments) could legitimately consume theme variation even
though no dimension is named for it. That objection is real in general — it just does not
rescue *this* pair, which never delivered distinct theme states.

### If theme quality is ever to be scored

There is **no universal implementation-independent way to discover and activate arbitrary
theme states.** Someone must supply the semantics — the task, the interface, or a
per-artifact adapter. Pick the capability first, then the instrument:

| capability wanted | requirement to register | capture |
|---|---|---|
| automatic OS adaptation | the artifact must respond to OS preference | both OS-preference conditions |
| user-selectable themes | a discoverable, operable theme control | drive the control to each state |
| quality of supplied variants | a standardised interface exposing states | drive that interface |

Each specifies externally observable behaviour or a testing contract, so implementations
stay free and the evaluator never guesses attribute names.

Note honestly: requiring OS-preference response is **a change to the task, not only to
the instrument**. A capture instruction sets the environment; requiring the artifact to
respond to it adds a product requirement. A new registration permits that — it does not
erase the distinction.

## Summary of what a v2 registration must state

1. Criterion (a) replaced by two observable measures (seed files changed; seed rules
   used/overridden/bypassed), with rationale — if wanted — as a labelled post-freeze
   retrospective self-report analysed separately.
2. One registered capture condition, specified in full, with theming explicitly out of
   scope unless a capability is chosen from the table above and its requirement
   registered.
3. An explicit statement of which quantity is being estimated, since any prompt that
   elicits decision narration changes it.
