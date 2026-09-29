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

## Agent safety assessment

**Design:** the six-stage pipeline above. **Date:** 2026-09-29.

### Risk fields

| Field | Status | Evidence |
|---|---|---|
| `private_data` | Present | Dion's store of real holdings is on the machine the stages run on |
| `untrusted_input` | Present | arms' generated HTML is rendered in a browser and its output is read by the measures |
| `outbound_action` | Present | the deriver's package leaves the machine; so does a judge's input, if any property is judged |

### Classification

**Risk level:** lethal trifecta, as the pilot was.
**Autonomy:** execute-reversible. Each party writes files in its own worktree.
**Oversight:** strong. A person launches each stage, arms have no outbound
capability, and every freeze is a reviewed commit. No autonomy advisory.

### Placement

Four risks. The pilot's controls were written for the first. They are checked
here against all four, by what each control reads.

**1. An arm inlines real holdings into its page, and the page is sent out.**

- Threat region: values in the page's visible text and embedded JSON.
- Control region: the pilot's egress check reads visible text, embedded JSON,
  identifiers and numbers, and compares them with the fixture and the store.
- Overlap: the control reads the region the threat occupies.
- Not looked at: anything the page loads at render time. See risk 2.
- `unvalidated-against`: none recorded by the pilot.

**2. A page pulls a local file into the capture at render time.**

- Threat region: a `file:` subresource, such as an `iframe`, an `object` or an
  image, whose contents appear in the screenshot and not in the page's source.
- Control region: the capture script aborts requests that are not `file:` or
  `data:`. The egress check reads the page's source.
- Overlap: **none**. The capture allows every `file:` request, and the egress
  check never reads what a subresource loads.
- Measured on 2026-09-29, Chromium 129: a page opened from disk loaded another
  local file through `iframe` and through `object`. The file's text appeared in
  the screenshot and was absent from the main frame's text. A `fetch` of the
  same file was blocked.
- Also measured: none of the pilot's six preserved pages contains an embedding
  tag or a `file:` reference. Nothing left the machine this way in the pilot.
- **This risk is unmitigated.**

**3. The picker writes private data into the brief, and the brief is sent to
the deriver.**

- Threat region: the brief's text.
- Control region: enforcement B denies the picker any read outside a Dion
  worktree that holds no store. The consent gate shows the package to a person.
- Overlap: partial. The deny rule covers the threat only while the canary
  passes. The pilot's own egress check notes that a person previewing a package
  cannot tell real positions from fixture positions.
- Not looked at: the brief is prose, and the egress check was written for HTML.
- `unvalidated-against`: a picker that reached the store. The canary has not
  been built.

**4. The fixture is built from the real store.**

- Threat region: the fixture's bytes.
- Control region: the pilot asserts in a test that the builder is given a
  throwaway database path.
- Overlap: the control reads the path the builder uses.
- Not looked at: where the throwaway database's own rows came from.

### Mitigation

| Risk | Required before any stage runs |
|---|---|
| 2 | The capture allows one `file:` URL, the artifact's own, and aborts every other request. A capture with any aborted `file:` request is refused, and the count is recorded |
| 3 | The egress check's identifier and number legs are run over the brief before it is packaged. The canary is built and passes |
| 4 | The record names the source of the throwaway database's rows |

The control for risk 2 sits at the request layer on purpose. A list of
embedding tags would have to be complete, and a request is a request whatever
tag made it.

**Trade-off:** a page that legitimately splits itself across local files can no
longer be captured. The pilot's brief already required a single self-contained
file.

**Residual risk:** the measures and captures run a generated page's scripts in
a browser. Blocking requests does not stop a script from computing on what the
page already holds.

Risk 2 applies to the pilot's harness as it stands today, in Dion. It is filed
there as issue 250 and has not been fixed.

## What the replication can claim

The strongest claim a completed replication may license:

> On this task, fixture, model configuration and budget, the seeded arm's pages
> measured higher on more of the registered properties than the comparator's,
> in this many of the pairs run.

It cannot license a claim about another task, another model, or the seed's
effect on a reader.

## Decided by the owner, 2026-09-29

| Question | Decision | What was not chosen |
|---|---|---|
| What the replication asks | whether the seed improves screens, blind and comparative | an adherence check; both, registered separately |
| Who chooses the task and writes the brief | a blind agent | the owner naming a screen; a task outside Dion |
| How many pairs | **five, on one task** | three on one task; three on each of two tasks |
| Who derives the property list | **another model family, sent one text package** | the same family under denied reads |
| The pilot's brief | **retired** | kept as a second task with one dimension declared contaminated |

Five pairs is about ten arm runs. The pilot ran three pairs and saw one
dimension scored 3/3, then 0/0, then split across them, so three was too few to
tell a repeat from a coincidence. Five is more room, not proof: the limit the
pilot recorded as v2-9 still holds, and no rule combining the pairs is
registered.

The deriver's package leaves the machine. It therefore passes the consent gate
and the mechanical check named under risk 3 before it is sent.

## Out of scope

- Running any arm.
- An adherence check. It answers a different question and was not chosen.
- Any change to the seed.
- A claim about the pilot's result. It stands as recorded.

## Dissenting views

None yet. This document has not been reviewed.
