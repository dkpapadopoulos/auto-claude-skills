# Design: replication instrument for the design seed

## Status

This document registers **rules**. It freezes no brief, fixture, property list
or measure. Each of those is frozen later by its own dated entry in this file,
committed and pushed before any arm runs. No arm runs under this change.

Revision 2, 2026-09-29. Revision 1 was reviewed by another model family and
changed substantially as a result. What changed and what was not adopted is in
"Review" at the end.

Precedent for the form: the pilot's registration, archived at
`openspec/changes/archive/2026-09-24-design-seed-capability/design.md`. Rule
numbers such as v2-2 refer to that document.

## What this design can and cannot deliver

It can deliver a **descriptive comparison**: ten generated pages, measured by an
instrument whose contents were specified by parties with controlled exposure to
the seed, under rules fixed before any page existed.

It cannot deliver a test that is blind in the sense of "nobody who shaped the
instrument knew the treatment". The author knows the treatment and still writes
the code that measures. This design reduces the author's authority, records
what remains, and words the claim to match.

## Terms

- **Author.** The party writing this document. The author has read the seed
  closely and amended it in #299.
- **Controlled exposure.** A party's inputs are a closed, listed set, and its
  means of reaching anything else are denied and tested. It is a claim about
  what the party was given. It is not a claim about what a model knows.
- **Construct.** One quality of a page that the task makes valuable, such as
  "a reader can compare figures down a column". A construct may have several
  measures and has one vote.

## Architecture

Eight stages.

| # | Stage | Done by | Inputs |
|---|---|---|---|
| 1 | Choose the task, the stored report and the fixture's states; write the brief | picker | a sanitised export of Dion; frozen instructions |
| 2 | Build the fixture | author, running a transformation the picker specified | the picker's specification |
| 3 | Specify what is measured | deriver | the brief, the fixture, the frozen list of operator decisions |
| 4 | Audit each construct for task relevance | reviewer, under rule v2-2 | the brief, the fixture, the deriver's specification |
| 5 | Implement and calibrate each measure | author | the deriver's specification |
| 6 | Approve each implementation against its specification | reviewer | the specification, the code, the calibration results |
| 7 | Assess the interpretation gate's pre-run checks | reviewer | everything from stages 1 to 6 |
| 8 | Freeze, then run the arms | the harness | per arm setup |

The picker, the deriver and the reviewer each have controlled exposure. The
deriver and the reviewer are separate dispatches, so the party that approves a
measure is not the party that specified it.

### Who decides what

Revision 1 said the author "performs no stage that chooses what is measured".
That was false. Writing the code that computes a property is measurement
authority: "alignment" can mean shared right edges, aligned decimal points or
label-to-value distance, and each favours different pages.

| Decision | Made by | Checked by |
|---|---|---|
| The statement of what is wanted, given to the picker | author | reviewer, before the picker runs; then frozen |
| The snapshot of Dion the picker may see | a rule, stated below | a scan of the export, with its search terms recorded |
| The task, the stored report, the fixture's states | picker | recorded |
| How the fixture is transformed | picker specifies; author runs | reviewer audits the output against the specification |
| Constructs, their direction, scope and grouping | deriver | reviewer, under v2-2 |
| Which operationalisations of a construct are acceptable | deriver | recorded |
| What size of difference matters | deriver | recorded |
| The code for each measure | author | reviewer approves or rejects |
| Rendering-noise tolerance | measured at calibration | recorded |
| Whether a construct is cut | reviewer | recorded with reason |
| Whether a construct has no working measure | author reports; reviewer confirms | listed as not measured |

The author records where a construct overlaps the seed. That record is for the
reader and gives the author no power to keep or cut anything.

**The snapshot rule.** The picker sees an export of Dion at the last commit on
its main line that precedes the first pilot document. That commit is `972f4ea`.
The export is files only: no git history, no branches, no issue text.

The export is Dion's source, so it is not sent to another vendor for audit. It
is scanned on the machine for the seed's name, its file names, its distinctive
phrases and the pilot's documents. The search terms are recorded. A scan finds
what it was told to look for, so this shows the named things are absent and
nothing more.

## Controlled exposure

### What was observed

A subagent dispatched from a session in this repository has no controlled
exposure. Observed on 2026-09-29:

- A dispatched subagent started in a working tree that contains
  `assets/design-seed/`.
- It read files outside that tree, by absolute path, without being stopped.
- In the **dispatching** session, this plugin's prompt hook added a line
  beginning `DESIGN SEED:` to a prompt, naming the seed's files by absolute
  path.

Whether a dispatched subagent's own prompt carries that line was not measured.

### Two mechanisms, two checks

| | Package | Sandbox |
|---|---|---|
| What it is | one frozen text package sent to another model family | a headless session whose capabilities are restricted by its launch configuration |
| Used by | deriver, reviewer | picker, arm S, arm C |
| Sends Dion content to | a second vendor, behind the consent gate | the model provider the owner already uses in Dion |
| Exposure is controlled by | what the package contains | what the session can read, run and reach |

Revision 1 required one canary of four filesystem probes for every party. A
text-only recipient has no filesystem to probe, and its report of a failed read
would be invented. Each mechanism has its own check.

**Package check.** Done by the sender, on the frozen package:

1. The package's contents are listed in a manifest, item by item.
2. The package is scanned for the seed's name, its file names, its distinctive
   phrases, and the pilot's documents and results.
3. File names and headings inside it are neutral.
4. A person reads the manifest before consenting to the send.

**Sandbox check.** Done from outside the session, against the launch
configuration the real run will use:

1. The complete launch payload is captured by the launcher and searched. The
   model is not asked what is in its context.
2. A read inside the permitted directory succeeds. This is the positive
   control.
3. Reads outside it fail through every mechanism the session has: each file
   tool, each shell route, a symlink inside the directory pointing out, and a
   copy of the seed at a second path.
4. Network, connectors and sub-processes not needed for the stage are denied,
   and each denial is tested.
5. No plugin, hook, skill, memory or instruction file from outside the
   permitted directory is loaded. The list of what was loaded is captured.
6. The configuration checked and the configuration launched are bound to one
   manifest by hash.

If a check cannot be made to pass, the stage does not run.

### What this does not establish

- That a model has no knowledge of the seed from training or from public
  sources. This repository is public.
- That inputs the author shaped are neutral. The reviewer's audit reduces this
  and does not remove it.

### Arm C, and the pilot

Arm C runs under the full sandbox check, as arm S does.

Whether the pilot's arm C saw the `DESIGN SEED` line is **unknown**. Measured
on 2026-09-29: the pilot's record holds no arm prompt or transcript, and no
local transcript from those dates remains. The pilot's registration required
that "all arm prompts and edits" be preserved. They were not.

The replication therefore preserves, per arm, the captured launch payload and
the full transcript.

## Measures

Revision 1 said a script "has no such spread" as the pilot's judges had. That
confuses repeatability with validity. A script repeats a wrong reading
perfectly.

Each measure is registered with:

- the construct it estimates, and what it does not estimate;
- the elements it reads and how they are grouped;
- what it does when extraction fails;
- the rendering conditions: browser build, widths, fonts, colour scheme.

### Validity tests, before freeze

| Test | The measure must |
|---|---|
| Two pages that look the same and differ in markup | score them the same |
| Two pages that look different and share markup | score them differently |
| A page where the content is hidden, clipped or covered | not credit it |
| A page with the content duplicated, once visible and once not | read the visible one |
| A page that declares a style the render does not show | follow the render |
| Pages the reviewer specified and the author did not build to suit the code | pass the four rows above |

The last row exists because an implementer can always build two examples that
their own code separates.

### Two thresholds, kept apart

- **Rendering noise.** Measured at calibration, across repeated renders.
- **A difference that matters.** Specified by the deriver, per construct.

A measure that never varies can still report a difference too small to matter.
A pair differs on a construct only when the difference exceeds both.

### What a measure sees

One render per width, after load, with no interaction. It does not see hover,
focus, scroll position, animation or error states. Constructs that live there
are listed as not measured.

### Judges

A judge scores a construct only when no measure exists for it and the deriver
wrote an anchor for each score. Judged scores are reported apart from measured
ones. Judges are asked afterwards which arm they believed each page came from,
and how sure they were.

## Decision rule and claim

### A pair

One pair is one page from arm S and one from arm C, built from the same brief,
fixture bytes, model configuration, tool access and budget, in fresh sessions.
Budget is total, counted from launch, so the seed's context is paid for out of
arm S's budget.

Five pairs. Launch order within a pair is assigned by a coin toss recorded
before launch. All five appear in the final record, whatever happened in them.

### Rule for one pair

1. **Fidelity.** If exactly one page fails a fidelity dimension, the pair is
   **fidelity-decided** for the other. If both fail, the pair has no direction.
2. **Constructs.** Otherwise the page ahead on more constructs is favoured. A
   construct counts once, however many measures it has.
3. **Tie.** No direction.

Fidelity-decided pairs are reported separately. They say nothing about
presentation.

### Failures and reruns

One rerun is allowed for a fault in the harness, declared and recorded. None is
allowed for a result. A page that does not render, or a measure that cannot
extract, is reported as such and scored as the rule above says.

### The claim

The strongest claim a completed replication may make:

> Across these five prespecified paired runs on this task and fixture, S was
> favoured in X pairs, C in Y, and Z had no direction under the registered
> rule. These are outcomes of this instrument. They are not evidence that
> readers perform better, or that the seed improves screens in general.

Counting pairs is allowed. Naming an overall winner is not (v2-6).

### The interpretation gate

Six checks. Four are assessed before any arm runs, by the reviewer. Two can
only be assessed afterwards, by rules fixed now.

| Check | When | Fails when |
|---|---|---|
| Task opportunity | before | the reviewer finds no construct on which the task leaves room for pages to differ |
| Construct coverage | before | measured constructs omit what the deriver marked as central |
| Valid extraction | before | a measure fails a validity test |
| Exposure integrity | before | a package or sandbox check did not pass |
| Discrimination | after | on every construct, both arms fall within both thresholds in every pair |
| Complete execution | after | a planned pair is missing from the record |

If any check fails, the result is reported as **inconclusive about
improvement**. The measurements are still reported.

## What a feasibility probe showed

Run on 2026-09-29 against the pilot's six preserved pages, at 1280 and 400
pixels wide. The probe was throwaway and is not part of the instrument.

| Question | Result |
|---|---|
| Were the fixture's 15 values found on the page? | all 15, on all 6 pages, at both widths |
| Was each its own text node, with its own position? | yes, everywhere |
| Was extraction identical from run to run? | yes, 12 of 12 |
| Did it depend on table markup? | no: values sat in `td`, `dd`, `span` and `b` |

It shows that values can be located. It validates no construct. It ran on
Chromium 129; the pilot pinned Playwright 1.49.0, whose browser build is
incomplete on the author's machine. It labelled pages by a hash of their bytes,
and the author did not map pages to arms.

## Agent safety assessment

**Design:** the eight-stage pipeline above. **Date:** 2026-09-29, revised after
review.

### Risk fields

| Field | Status | Evidence |
|---|---|---|
| `private_data` | Present | Dion's store of real holdings is on the machine the stages run on |
| `untrusted_input` | Present | arms' generated HTML and scripts run in a browser, and the measures read the result |
| `outbound_action` | Present | packages to the deriver and the reviewer; a judge's input, if any construct is judged |

### Classification

**Risk level:** lethal trifecta, as the pilot was.

**Autonomy:** mixed. Work inside a worktree is reversible. Sending a package is
not: once data has left the machine it cannot be recalled.

**Oversight:** each send is approved by a person, for that exact package, once.
A person launches each stage. That is approval of each run. It is not review of
what a run did, and the design does not claim it is.

### Placement

Five risks. For each: where the threat is, what the control reads, and whether
the second contains the first.

**1. An arm inlines real holdings into its page, and the page is sent out.**

- Threat region: values in the page's visible text and embedded JSON.
- Control region: the pilot's egress check reads visible text, embedded JSON,
  identifiers and numbers, and compares them with the fixture and the store.
- Overlap: the control reads the region the threat occupies, for values written
  as identifiers or numbers.
- Not looked at: values put into prose, transformed or encoded. Matching
  identifiers and numbers does not show that a page holds no private data.

**2. A page pulls a local file into the capture at render time.**

- Threat region: a `file:` subresource whose contents appear in the screenshot
  and not in the page's source.
- Control region: the capture script aborts requests that are not `file:` or
  `data:`. The egress check reads the page's source.
- Overlap: **none**.
- Measured, Chromium 129: a page opened from disk loaded another local file
  through `iframe` and through `object`. The file's text appeared in the
  screenshot and was absent from the main frame's text.
- Measured on the pilot's six preserved pages, at both widths, 1.5 seconds
  after load with no interaction: each page requested only itself. The same
  counter reported two local files on a control page built to load them.
  Revision 1 inferred this from the absence of embedding tags in the source. A
  script can build a reference the source does not contain, so that inference
  was not sound. The request count is.
- **Unmitigated.** Filed in Dion as issue 250.

**3. The picker writes private data into the brief, and the brief is sent on.**

- Threat region: the brief's text.
- Control region: the sandbox check denies the picker any read outside an
  export that holds no store.
- Overlap: partial, and only while the sandbox check passes.
- `unvalidated-against`: a picker that reached the store. The check has not
  been built.

**4. The fixture is built from the real store.**

- Threat region: the fixture's bytes.
- Control region: the pilot's builder opens its database in memory and takes no
  path argument. Its rows come from a random generator with a fixed seed and
  from test configuration. Read from the builder's source on 2026-09-29.
- Overlap: the control covers the threat for that builder. The store cannot be
  reached from it.
- Not looked at: a new builder written for a new task. Nothing stops one from
  opening a file.
- Revision 1 described this control as "a throwaway database path", taken from
  the pilot's registration. Review rightly said a path shows nothing about
  where rows come from. The first draft of this revision then marked the risk
  unmitigated without reading the builder. Both descriptions were wrong.

**5. A generated page runs code where it is captured or measured.**

- Threat region: the browser process and whatever it can reach: local files,
  the measures' own observations, logs, traces and temporary files.
- Control region: request interception in the capture script.
- Overlap: partial. Interception sees requests. It does not see a script that
  alters the page to mislead a measure, and it is not applied to measurement
  runs, which do not exist yet.
- **Unmitigated.**

### Mitigation

The boundary is the environment. Request interception stays as a second layer.

| Required before any arm runs | Closes |
|---|---|
| Pages are rendered and measured in a disposable environment that contains the artifact and the browser, and no private store, credential or personal browser profile | 2, 5 |
| The same environment and the same rules apply to capture runs and to measurement runs | 5 |
| The capture allows one `file:` URL, the artifact's own, and refuses a capture with any other request | 2 |
| The controls are tested with pages built to defeat them | 2, 5 |
| A test fails if the fixture builder opens any database other than one in memory | 4 |
| Every outgoing package is checked whole, attachments included | 1, 3 |
| The sandbox check is built and passes | 3 |

How the disposable environment is built is for the plan. The author's machine
has no container runtime installed, which constrains the choice.

**Residual risk:** a page can still mislead a measure from inside the render.
The validity tests for hidden, covered and duplicated content address the
cases named there and no others.

## Decided by the owner, 2026-09-29

| Question | Decision | What was not chosen |
|---|---|---|
| What the replication asks | whether the seed improves screens, blind and comparative | an adherence check; both, registered separately |
| Who chooses the task and writes the brief | a blind agent | the owner naming a screen; a task outside Dion |
| How many pairs | five, on one task | three on one task; three on each of two tasks |
| Who derives the property list | another model family, sent one text package | the same family under denied reads |
| The pilot's brief | retired | kept as a second task with one dimension declared contaminated |

Five pairs is about ten arm runs. More runs reduce uncertainty from generation.
They do not correct an instrument that is biased, and they say nothing about
another task.

### What review changes for the owner

The owner chose a blind, comparative test of whether the seed improves screens.
Review found that this design cannot deliver that in full, and this revision
does not pretend to. Two things follow that the owner has not yet been asked
about:

1. **The claim is narrower than the question chosen.** See "The claim".
2. **There are more cross-family sends.** Revision 1 had one, to the deriver.
   This revision adds the reviewer, which receives a package before stage 1
   and at stages 4, 6 and 7. Each send needs its own consent.

## Out of scope

- Running any arm.
- An adherence check.
- Any change to the seed.
- A claim about the pilot's result. It stands as recorded.
- A claim that the pilot's losses were caused by its instrument. The pilot's
  record limits how those losses can be read. It does not explain them.

## Review

Revision 1 was sent to Codex (model `gpt-6-astra`) on 2026-09-29, in critique
mode, as one frozen package the owner approved. It saw the three documents of
this change and a background section. It ran no command and read no file.

### Its position

> As written, this can become a useful descriptive comparison of ten generated
> artifacts under a particular instrument. It cannot yet carry the claim that a
> blind process established whether the seed improves screens.

### Adopted

| Finding | Change |
|---|---|
| The author still chooses what is measured | "Who decides what"; the deriver specifies operationalisations and thresholds; a reviewer approves each implementation |
| One seed strength split into several properties gets several votes | one vote per construct |
| "Blind by construction" claims more than the controls show | replaced by controlled exposure, with its limits stated |
| One canary cannot serve a text-only recipient | separate package and sandbox checks |
| A model's report of its own context is not evidence | the launch payload is captured from outside |
| The historical question about arm C cannot be answered by a probe today | recorded as unknown, with what was measured |
| The egress boundary is incomplete | risk 5; the environment as the boundary |
| A database path does not show provenance | risk 4 rewritten from the builder's source; a test is required for any new builder |
| No embedding tags does not mean nothing was loaded | replaced by a request count |
| Sending data out is not reversible | autonomy is now mixed |
| Repeatability is not validity | validity tests; two thresholds |
| Two hand-built pages are a smoke test | pages specified by the reviewer |
| The claim and the rule did not match | fidelity-decided pairs reported apart; the claim reworded |
| Exact compliance can still be uninterpretable | the interpretation gate |

### Not adopted, or adopted in part

| Finding | Response |
|---|---|
| An adjudicator who has not seen the seed resolves disagreements | Not added as a separate party. The reviewer's decision stands, and a disagreement the author has with it is recorded here as a dissent |
| Deny network access outside the page's JavaScript context | Adopted as a requirement. How far the harness can enforce it is unmeasured |
| Oversight is not strong | Adopted in part. The design now says what the approvals are and what they are not, and no longer uses the word |

### Open

Revision 2 has not been reviewed.
