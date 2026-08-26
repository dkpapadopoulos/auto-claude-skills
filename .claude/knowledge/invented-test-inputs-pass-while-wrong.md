---
type: convention
title: Any test input you invented rather than observed can pass while the code is wrong
description: The fixture rule generalises — an imagined input corpus, a hardcoded payload shape, or a baseline captured from already-modified code all produce green suites over broken components, because the test only ever proves the code agrees with the author's assumption.
tags: [testing, fixtures, false-positive, corpus, payload, baseline, hooks]
source: hooks/reviewer-evidence-hook.sh
timestamp: 2026-08-26T11:40:00Z
---

[[classifier-fixtures-from-real-producer]] says a classifier's **fixture** must
come from the real producer. One change produced **four** instances of that same
root cause at different levels, **three of which shipped green**. The rule is
broader than fixtures:

> Any test input you **invented** rather than **observed** can pass while the
> component is wrong — including the input corpus, the payload shape, and the
> baseline you compare against.

In every case below the suite was green and the component was broken. None was
found by a test. Two were found by reviewers, two by driving the real thing.

## The four measured instances

**1. An imagined input CORPUS.** A predicate matched review intent with
`[Rr]eview*` — a prefix. Its 12 assertions passed. Measured against the
`description` strings **actually dispatched** in that session, it credited
**3 of 9** genuine reviewer dispatches: real ones read `"Task 1 review: spec +
quality"` and `"Scoped re-review of Task 1 fix"`, never `"Review …"`. The test
author invented plausible descriptions; nobody collected real ones. A predicate
missing two thirds of its population does not measure the population — it
measures its own blindness, and every miss enters the corpus as evidence of
non-compliance on work that complied.

**2. A hardcoded payload SHAPE.** The recorder read
`.tool_response.is_error`. Every test built its payload through one helper that
hardcoded `tool_response:{is_error:$er}` — an **object**, always. But
`.foo.bar` is a *typed index* in jq: it raises on an array, string, or number.
Measured end-to-end, an array-shaped `tool_response` — a plausible shape for an
agent returning content blocks — made jq exit 5, the `|| exit 0` fire, and the
hook record **nothing, forever, silently**. No assertion could see it, because
every assertion varied the *value* and none varied the *shape*. Fix:
`(.tool_response | objects | .is_error)`.

**3. A BASELINE captured from already-modified code.** A byte-identical control
fixture was to be captured from the pre-change guard. The plan had the
implementer capture it — *after* they had begun editing that guard. A control
generated from the code under test proves only that the code equals itself.
Caught before capture; the fixture was taken from the unmodified guard instead.

Second-order trap in the same fixture: with all milestones seeded the guard
emits **zero bytes**, so the control is an empty file — and an empty-output
assertion passes just as well when the harness never ran. It is only meaningful
paired with a case that must produce **non**-empty output; the pair is the test,
neither half alone.

**4. A pattern copy-pasted into a verification probe.** Checking whether a
predicate fix had landed, the reviewer's own probe embedded a copy of the
shipped `case` statement instead of driving the real hook. It faithfully
reported the **pre-fix** behaviour after the fix had landed, and briefly
"confirmed" the fix had failed. Written by someone actively hunting this exact
bug class, inside a probe for it.

## Why tests cannot catch this

A test asserts that the component behaves as expected **on the inputs the test
supplies**. When the author supplies the inputs from imagination, the test
proves internal consistency between two products of the same misunderstanding.
Adding assertions does not help — instances 1 and 2 both had thorough suites.
More assertions over invented inputs is more of the same measurement.

The tell is never a failure. It is an **absence**: no real-world input in the
corpus, no shape variation in the payload builder, no independent origin for the
baseline.

## What to do

1. **Collect the corpus, do not imagine it.** Before writing a predicate over
   free text, gather the actual strings from transcripts, logs, or git history.
   Put the measured recall/false-positive numbers in a comment beside the
   pattern, and re-measure in the SAME commit if the pattern ever changes —
   otherwise the code is judged against a profile documented nowhere.
2. **Vary the SHAPE, not just the value.** If a payload helper hardcodes a
   type, every assertion inherits that assumption. Add cases where the field is
   an array, a string, `null`, and absent. In `jq`, guard typed indexes with
   `| objects` before assuming a lookup.
3. **Capture baselines before touching the code**, and record who captured them.
   A control taken after modification is not a control.
4. **Pair every empty-output assertion with a non-empty one.** Alone it cannot
   distinguish "checked and clean" from "never ran".
5. **Probes must drive the real component.** Never copy a pattern, `case`, or
   regex into a verification script — the copy stops tracking the original the
   moment either changes.
6. **When a result looks impossibly clean, suspect the harness first.** Zero
   files matched, an identical result across four runs, a suite that reports
   passes but no summary line — treat these as harness bugs until proven
   otherwise.

## Related

Same family as [[classifier-fixtures-from-real-producer]] (of which this is the
generalisation) and [[behavioral-eval-subject-read-contamination]]: in all
three, the test passed while measuring something other than what its author
believed.

The mirror image is worth naming even though it has no note here: the same
false assumption can live in the **verification shell** rather than the test —
an ad-hoc check that exits 0 with plausible numbers while measuring nothing.
Instance 4 above is that shape. When a verification result looks impossibly
clean, suspect the harness before the artifact.
