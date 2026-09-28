# Design: replication instrument for the design seed

## Status

This document registers **rules**. It freezes no brief, fixture, property list
or measure. Each of those is frozen later by its own dated entry in this file,
committed and pushed before any arm runs. No arm runs under this change.

Precedent for the form: the pilot's registration, archived at
`openspec/changes/archive/2026-09-24-design-seed-capability/design.md`. Rule
numbers such as v2-2 refer to that document.

## Architecture

Six stages. The column that matters is the last one.

| # | Stage | Done by | May see |
|---|---|---|---|
| 1 | Choose the task and write the brief | blind picker | Dion at a commit holding no pilot document and no `design/` |
| 2 | Build the fixture | author, running Dion's store-then-retrieve path | the picker's choice of stored report |
| 3 | Derive the property list | blind deriver | the brief, the fixture, the operator's decisions |
| 4 | Audit each property for task relevance | author, under rule v2-2 | everything |
| 5 | Turn each property into a measure and calibrate it | author | everything except any arm's output |
| 6 | Freeze, then run the arms | the pilot's harness | per the pilot's arm setup |

"Author" is the party writing this document. The author has read the seed
closely and amended it in #299, so the author is not blind and performs no
stage that chooses what is measured or what is built.

### What the author may and may not decide

- **May:** how a property is computed, how the fixture pipeline is run, how the
  harness launches an arm.
- **May not:** which task, which stored report, which states the fixture
  exercises, which properties, which direction of a property is better.

The fixture is where this is easiest to get wrong. Whoever chooses its contents
can include the states the seed handles well. So the picker names the stored
report and the states, and the author only runs the pipeline.

## Blindness is enforced, then checked

A subagent dispatched from a session in this repository is blind **by
instruction only**. Observed on 2026-09-29:

- A dispatched subagent started in a working tree that contains
  `assets/design-seed/`.
- It read files outside that tree, by absolute path, without being stopped.
- In the **dispatching** session, this plugin's prompt hook added a line
  beginning `DESIGN SEED:` to a prompt, naming the seed's files by absolute
  path.

Whether a dispatched subagent's own prompt carries that line was not measured.
If it does, the harness tells a blind party about the seed. The fourth probe of
the canary below exists to answer that before it matters.

### The two ways to enforce it

| | A. One frozen text package to another model family | B. Headless session with reads denied outside one directory |
|---|---|---|
| Blind by | what is sent | the launch configuration |
| Can explore a repository | no | yes |
| Sends Dion content off the machine | yes, through the consent gate | no |
| Used in the pilot | yes, for the deriver | no |

- **The picker uses B.** It has to explore Dion to choose a task. A text package
  would need a description of Dion written by the author, which hands the
  framing back to the party who is not blind.
- **The deriver uses A**, as in the pilot. It needs the brief and the fixture
  and nothing else.

### The canary

Before a blind party runs, the same launch configuration runs a probe. All four
results are recorded.

| Probe | Must |
|---|---|
| Read a file inside the permitted directory | succeed |
| Read `assets/design-seed/styleguide.md` by absolute path | fail |
| Read a canary file placed outside the permitted directory | fail |
| Search the session's first prompt context for `design-seed` and `DESIGN SEED` | find neither |

The first row is the positive control. Without it, a configuration that can
read nothing passes the other three.

If the canary cannot be made to pass, the stage stops. It does not proceed
under the label "blind".

### Arm C

Arm C has the same exposure to the prompt hook. The pilot's record does not say
whether arm C's session rendered the `DESIGN SEED` line. That is checked before
launch with the fourth probe above, and the answer is recorded for the pilot as
well as for the replication.

## Decisions

**Presentation properties are measured, not judged.** Every divergence between
the pilot's judges fell on a dimension that was both unanchored and graded. A
script has no such spread, and cannot recognise which arm it is reading.

**A property a script cannot measure goes to a judge only with an anchor for
each score.** The deriver writes the anchors. A property with neither a measure
nor anchors is listed as not measured. It is not dropped from the record.

**Each measure is calibrated in both directions before freeze.** Two pages are
built by hand: one that has the property and one that lacks it. The measure has
to separate them. The pages are built before any arm exists.

**A difference below the tolerance is no difference.** Each measure's tolerance
is set at calibration, from its variation across repeated renders of the
calibration pages.

**The fidelity dimensions carry forward with their anchors.** R1 and R2 were
scored identically by four judges across two reads. They are re-derived for the
new task by the deriver, in the same form.

**The decision rule is v2-4, unchanged in shape.** A fidelity failure in one arm
decides the pair. Otherwise the arm ahead on more properties is favoured. A tie
is no direction.

**Each pair's outcome is the result.** No rule combining pairs is registered,
and none may be added later (v2-6).

**The audit rule is v2-2, unchanged.** A property is kept when the task
justifies it, or the brief states it. Overlap with the seed does not disqualify
a property and does not justify one.

## What a feasibility probe showed

Run on 2026-09-29 against the pilot's six preserved pages, at 1280 and 400
pixels wide. The probe was throwaway and is not part of the instrument.

| Question | Result |
|---|---|
| Were the fixture's 15 values found on the page? | all 15, on all 6 pages, at both widths |
| Was each its own text node, with its own position? | yes, everywhere |
| Was extraction identical from run to run? | yes, 12 of 12 |
| Did it depend on table markup? | no: values sat in `td`, `dd`, `span` and `b` |

Limits:

- It ran on Chromium 129. The pilot pinned Playwright 1.49.0, whose browser
  build is incomplete on the author's machine.
- It reported no presentation property.
- It labelled pages by a hash of their bytes. The author did not map pages to
  arms.

## Trade-offs

- A blind party reduces the chance that the properties track the seed. It does
  not remove it. The statement of what is wanted, which the picker receives, is
  written by the author.
- A script measures geometry and computed style. It does not measure whether a
  reader transcribes faster or makes fewer errors.
- The picker may choose a task on which presentation matters little. That is a
  result about the task and is reported as one.
- Enforcement B depends on the harness honouring its deny rules. The canary
  checks one configuration on one day.
- The deriver's package leaves the machine. The pilot accepted the same, behind
  a mechanical check that the package holds fixture data only.

## Safety classification

| Leg | Present | Where |
|---|---|---|
| Private data | yes | Dion's store; the fixture is derived from it |
| Untrusted input | yes | arms' generated HTML, rendered in a browser |
| Outbound action | yes | the deriver's package; judge calls, if any property is judged |

All three legs are present, as they were in the pilot. The pilot's controls
carry forward: arms have no outbound capability, captures block every request
that is not `file:`, and an artifact is refused for transmission unless its
embedded data hash-matches the fixture.

An agent safety review of this design is required before it leaves DESIGN. It
has not been done.

## What the replication can claim

The strongest claim a completed replication may license:

> On this task, fixture, model configuration and budget, the seeded arm's pages
> measured higher on more of the registered properties than the comparator's,
> in this many of the pairs run.

It cannot license a claim about another task, another model, or the seed's
effect on a reader.

## Open, and for the owner to decide

1. **How many pairs.** The pilot ran three on one task. It saw one dimension
   scored 3/3, then 0/0, then split across them.
2. **Whether the deriver is another model family**, as in the pilot, which
   sends the fixture off the machine.
3. **Whether the pilot's brief is retired or kept as a second task.** Kept, its
   identification dimension has to be declared contaminated.

## Out of scope

- Running any arm.
- An adherence check. It answers a different question and was not chosen.
- Any change to the seed.
- A claim about the pilot's result. It stands as recorded.

## Dissenting views

None yet. This document has not been reviewed.
