# Judging decisions, recorded BEFORE the judge calls

Written after the arms ran and before any judge saw anything. These are **not**
pre-registered: the frozen registration is unchanged and still governs. Where it already
answers a question, the answer is quoted and followed. Where it is silent, the resolution
is derived from it and labelled as a derivation, so the interpretive timeline is
inspectable.

## 1. What each dimension measures — taken from the frozen rubric, not reinterpreted

The rubric's eight dimensions are used exactly as written. Two need care given the
capture finding, and **neither is re-read to suit an artifact**:

- The rubric contains **no dark-theme dimension**. Nothing in it awards or deducts for a
  dark appearance, so the identical light/dark captures cost neither artifact a scored
  dimension. What is lost is not a score but a *claim*: this run cannot say anything
  about dark-theme quality.
- R3, R7 and R8 are explicitly "checked against the envelope, not inferred from the
  screens alone", which is why the frozen envelope is in the package.

## 2. What evidence controls a score

The rubric names the inputs: "HTML source plus matched browser screenshots", plus the
envelope for R3/R7/R8. Judges score what each dimension asks about, on that evidence.

Derivation, stated because the registration does not address it: a visual dimension is
about what the artifact **shows**, so source that declares an appearance the capture did
not exercise does not earn visual credit for that appearance. This resolves in no
artifact's favour by design — it is the same rule for both, and it is fixed here before
any score exists.

## 3. What the judges are told about the capture finding

**The neutral, symmetric fact only:** each artifact has one distinct rendered appearance.

They are not told which artifact is which, that a seed exists, that arms exist, that
anything is being compared beyond the two artifacts, why either pair is identical, or
that one artifact declares an unexercised theme. That last exclusion is deliberate and
is the one most tempting to violate: an explanation of artifact-b's `data-theme` would be
an **artifact-specific rescue narrative**, which would break blinding and hand one
artifact an excuse in the same stroke.

Blinding is presentational only, and the registration already concedes a judge may infer
provenance from semantic names. Provenance comments were stripped (verified: no leak);
class and variable names stand as authored.

## 4. How the captures are presented

As **one** image per artifact, because that is how many distinct appearances exist. The
two files are capture *conditions*, not two independent demonstrations of visual quality,
and presenting two identical PNGs would imply a second observation that was never made.

## 5. What counts as a verdict

From the frozen rubric: "which artifact scored higher overall, and on which dimensions
they differ most. If you cannot separate them, say so."

The overall preference is **the judge's own**, not a sum computed by me — the rubric asks
the judge for it, and re-deriving it from per-dimension numbers would substitute a rule
nobody registered.

Pre-registered outcomes, applied verbatim: both judges favour S → outcome 1; both favour
C → outcome 2; **split → inconclusive, and no third call is made**.

Derivation for a case the outcomes do not name: a judge that reports it **cannot separate
them** has favoured neither. Outcomes 1 and 2 each require *both* judges to favour the
same artifact, so any inseparable verdict lands in outcome 3 — inconclusive. Fixed here,
before any judge has spoken, precisely so it cannot be chosen later.

**No retries for an unfavourable or inconvenient result.** The registration permits one
rerun for an infrastructure fault only (harness crash, tool unavailable), declared and
recorded. A malformed or truncated response is an infrastructure fault; a response whose
verdict is unwelcome is not.

## 6. What the two consultations are worth

Two judgements from **one** model with presentation order reversed. They measure order
sensitivity and some judging variance. They are **not** independent perspectives, they
share systematic biases, and they do not add runs: there is still exactly one generated
artifact per arm. The registration says this; it is repeated here because the temptation
to read "two judges agreed" as corroboration arrives only once results exist.

## 7. What this pilot cannot establish, fixed before seeing any score

- dark-theme quality, for either artifact (§1, and `capture-notes.md`)
- whether adaptation reasoning occurred (`arm-consumption.md`, criterion (a))
- how often either arm would win — n=1 per arm
- that the seed's rules, rather than the workflow, caused any difference
