# Design: replication instrument for the design seed

## Status

This document registers **rules**. It freezes no brief, fixture, property list
or measure. Each of those is frozen later by its own dated entry in this file,
committed and pushed before any arm runs. No arm runs under this change.

Revision 2, 2026-09-29. Revision 1 was reviewed by another model family and
changed substantially as a result. What changed and what was not adopted is in
"Review" at the end.

Revision 3, 2026-10-01. The sandbox check and the arms are built (Dion pull
requests 251, 252, 253 and a fourth that follows them). The registered outcome
measures and the decision rule are unchanged. This revision records changes to
the execution configuration, made after the build was observed, and narrows the
stated assurance about judge blinding to the absence of direct access. It was
written after implementation and after the dry-run observations reported below;
no claim is made that those decisions were specified before the observations.
Revision 3 was critiqued by another model family before it was committed, and
its rewrites are adopted where noted.

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
| The snapshot of Dion the picker may see | a rule, stated below | sanitising by rule, then a scan of the result, with its search terms and everything removed recorded |
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

**That commit is not clean.** Revision 2 assumed it was, and the first plan had
a cell asserting that its export scans clean. Measured on 2026-09-29, when the
export was built: `972f4ea` holds recorded terms in ten files. One of them is
Dion's own instruction file, which names the pilot's branch. So the export is
sanitised by rule and not only scanned:

- a file or directory whose path matches a term is omitted;
- a line that matches a term is replaced by a marker, so the file keeps its
  line count;
- a file that is not text is still searched, as bytes, and omitted whole if it
  holds a term;
- a file that cannot be opened makes the verdict "cannot check";
- everything removed is recorded, the result is scanned again, and an export
  that still holds a term is refused and deleted.

Only the registered commit may be exported. Sanitising cannot make a later
commit safe: the harness there names the pilot in files the term list does not
know.

Two consequences for the reader. The picker sees a Dion with those lines
missing, which is a Dion that never existed. And the record of what was removed
names the terms, so it goes to the reviewer and never to the picker.

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
configuration the real run will use. As built (Dion, `tests/design_seed_pilot/
exposure/sandbox_check.py`), it launches one session per probe under the
manifest and reads what the launcher captured; the model is not asked what is
in its context. Each probe has more than two outcomes, and "cannot check" is
never a pass: a probe the session never attempted, or whose record cannot be
read, stops the run. A run that cannot check is repeated; a run with findings
does not proceed until the configuration changes, and is not repeated as it is.

The probe matrix, as built:

| Probe | Tool | Path as the session is asked for it | Passes when |
|---|---|---|---|
| `inside` | Read | a name in the working directory | the planted value is in the record |
| `inside_write` | Write | a name in the working directory | the file exists with the content asked for |
| `outside_read_abs` | Read | absolute, outside | refused |
| `outside_read_rel` | Read | `../outside/...` | refused |
| `symlink_out` | Read | a link inside the directory that leads out | refused |
| `outside_grep` | Grep | an absolute directory, outside | refused |
| `outside_glob` | Glob | an absolute pattern, outside | refused |
| `outside_write` | Write | absolute, outside | refused, and no file exists at the target |
| `outside_values` | the whole run | | no value planted outside is in any session's record |
| `payload_terms` | the whole run | | no term of the list is in any session's record; not applicable to a seeded manifest |
| `loaded` | every session's `init` | | the inventory is as declared |

"Refused" is read from the CLI's own refusal event for the very call that asked,
never inferred from a value's absence, and a call that was refused and also
answered, or answered by another tool at a path outside, makes the probe
"unclear". These results establish refusal for the tested tools and spellings;
they do not establish that every possible access is refused. In particular a
call that spells its path with a wildcard in a directory name, or that starts
above the planted file, is not recognised as a try.

The two write probes were added after a dry run under CLI 2.1.285 and the
default permission mode in which every attempted write of both arms was refused:
a session launched headless has nobody to approve a write. The arms and the
picker now run with edits accepted; the restricted mode still confines them to
the working directory, which the outside write probe is what tests.

What the `loaded` probe compares, in every session of the run: the tools, which
must equal the manifest's list; the MCP servers, which must be the declared
ones, loaded and connected, and which the check launches itself from the
declaration so that a launched server is a script of the harness; the
permission mode; and hook events, which must be zero. Plugins the CLI reports
with `path: builtin` are recorded in the report and exempted from the
declaration: two sessions under the same manifest on CLI 2.1.285 reported
different sets of them, two and three, and the cause was not established. A
passing result therefore does not establish identical builtin-plugin exposure
across sessions. Any other plugin must be declared, and none is.

The term scan reads the captured stream and the transcript the CLI wrote, every
line decoded as JSON and every string inside decoded again where it is JSON,
with written line breaks read as breaks, against the recorded term list
(`exposure/terms.json`). A match makes the probe "present", the run "findings",
and the stage does not run. It does not inspect context the launcher did not
capture, and it does not detect paraphrase, encoding or style. It is not
applied to arm S's manifest, which is given the seed on purpose and says so.

The arm launcher requires a passing report whose manifest hash equals the hash
of the manifest as it is now. That binds the manifest's bytes: the argument
vector, the tool list, the permission mode, the declared servers with their
script names and arguments (the lint's digest among them), and the seeded flag.
It does not bind the CLI version, which the report records and nothing
compares, nor the harness's own code and sandbox profile, which are not
digest-pinned. Those may change without invalidating a report.

What the check does **not** test, stated so it is not assumed: the network. A
restricted session reaches its model provider, and nothing here measures what
else it could reach; the restricted mode removes the web tools, which the
inventory probe confirms absent, and that is the whole of it. The inventory
probe does not establish subprocess confinement either: the lint runner starts
a subprocess and the harness launches the MCP server, and their restrictions
are assessed by the runner's own cells, below, not by the check.

If a check cannot be made to pass, the stage does not run.

**No general-purpose shell, and the lint runner.** No arm or picker session is
configured with a general-purpose shell or command-execution tool. Arm S alone
receives `run_lint`, which executes a pinned shell script through a fixed
runner. The check compares the reported tool inventory against the manifest's
exact list and fails on any unexpected tool; that verifies the reported
interface, and does not by itself establish that the allowed tools cannot be
used to execute something else. The remaining execution boundary is the runner.

Why: arm S must run the seed's lint, and the plan had taken that to mean arm S
needs a shell. Three ways were weighed on 2026-10-01: rely on the CLI's own
shell sandbox (probed on 2026-09-29 with inconsistent results); run arm S
without its lint, which weakens the treatment; or one macOS account per arm. A
critique from another model family (Codex) made the point that decided it:
needing the lint is not needing a shell, and a per-account shell keeps the
shared temporary directory, localhost and the network as channels between arms.
If a general shell ever becomes necessary, this confinement design is revised
and tested again; separate virtual machines are the candidate mechanism, and
shared storage, networking and artifact transfer would still need explicit
controls.

The runner, stated so that it can be checked against the code
(`exposure/lint_server.py`, `lint.sb`, cells in `test_lint_server.py`):

- One tool, `run_lint`, with one optional argument, `files`: a list of paths
  relative to the working directory. Any other tool name is a protocol error
  and runs nothing.
- It reads the bytes of `design/checks/token-lint.sh` under the working
  directory once, requires their SHA-256 to equal the digest pinned in the
  manifest, writes those bytes to a scratch directory made for the call, and
  executes that copy. A file changed between the check and the run is not what
  runs; the arm can write its copy, and a changed copy is refused, not run.
- The argument vector is `/usr/bin/sandbox-exec -D ROOT_DIR=<directory> -D
  SCRATCH_DIR=<scratch> -f lint.sb /bin/bash <scratch>/token-lint.sh
  [files...]`, with the working directory as the current directory and an
  environment of `HOME` and `TMPDIR` set to the scratch and `PATH` set to
  `/usr/bin:/bin:/usr/sbin:/sbin`. The script sources nothing and calls `find`,
  `sed`, `awk`, `tr`, `mktemp`, `basename`, `dirname` and `rm` through that path.
- The profile permits reads of `/`, `/System`, `/usr`, `/bin`, `/sbin`,
  `/Library`, `/opt`, `/dev`, `/private/etc`, `/private/var/db`,
  `/private/var/select`, `/var`, `/etc`, the working directory and the scratch;
  writes to the scratch, `/dev/null`, `/dev/dtracehelper` and `/dev/fd`; and
  denies the network, loopback included.
- A named file is resolved, links followed, before the run, and must lie under
  the working directory. A file replaced by a link to the outside between that
  check and the run is read by the lint under the profile, which refuses the
  read; the lint then reports the file unscannable and exits 3.

The cells, each with a stand-in lint pinned by its own digest where the shipped
one would not exercise the boundary: the verdict and exit code come back; a
tree with a literal is rejected through the runner (exit 1), so an exit 0
through the runner is the lint's verdict and not its failure mode; a changed or
missing lint is refused; a path outside the directory and a link out of it are
refused before anything runs; the lint cannot read outside the directory, with
the control that it can read inside; cannot write into the directory; cannot
reach a loopback listener, with the control that the same stand-in does when
run bare; is given none of the caller's environment; runs from the scratch
copy; and a file named like an option is passed as a file. Twelve mutants of
the runner and its profile are killed by these cells. Not tested: a `bash`,
`sandbox-exec` or utility on the system that lies. The profile and the runner
are files of the harness, which is not digest-pinned; the lint cannot read the
harness directory, which the profile does not name.

The pinned seed's lint has a failure mode found while building the runner: it
reported clean, exit 0, when it could not read back its own work files (fixed
in this repository by PR #319; the replication keeps the seed at the commit it
pins, so the pinned copy still has it). Under the final profile the lint's work
directory is readable, so the condition does not arise there, and the cell above
shows a literal rejected through the runner. Exit 0 through the runner is
therefore the lint's verdict within its declared scope, not that failure mode.
Re-pinning the seed is a registration decision.

**What had been observed before this revision was written.** The sandbox
check's results for every manifest; one dry-run pair on a smoke task, not the
registered brief, run twice: once under the default permission mode, in which
every write of both arms was refused, and once with edits accepted, in which
both arms wrote their files, arm S invoked `run_lint` once after reading the
styleguide's own sentence about the lint, and its stylesheet held sixteen
`var(--` references and no `#` colour literal while arm C's held four literals
and no reference (counted by pattern; the pinned lint run bare over the same
files reported clean for S and five violations for C). No judge scores. That
pair does not enter the registered analysis. The configuration changes made
after those observations: edits accepted; the two write probes; builtin plugins
set aside; the runner executing its verified bytes. This is an implementation
observation from one pair on a toy task, not an estimate of the treatment
effect.

### What this does not establish

- That a model has no knowledge of the seed from training or from public
  sources. This repository is public.
- That inputs the author shaped are neutral. The reviewer's audit reduces this
  and does not remove it.
- **That the judge remains unaware of the treatment assignment.** The
  restriction this design claims is on supplied inputs and reachable resources:
  the judge receives the judging package, without the seed document, the arm
  directories, the launch records or S/C labels, and its configured tools
  cannot retrieve those. The judge's launch configuration is not yet registered;
  that claim holds for it only once its manifest passes the same sandbox check,
  and until then it is a design intent, not a measured property. The artifacts
  remain an information channel: arm S's page may quote or name the seed, show
  that a lint was run, or carry a recognisable style, and a judge may infer the
  assignment from it. The package check's term scan detects matches to its
  configured terms and nothing else; it does not establish blinding. Three
  claims are kept apart here: labels withheld and resources unreachable are
  claimed; assignment unknowable is not. Named in the Codex critique of
  2026-10-01 and accepted, not closed.

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

### What review changed for the owner

The owner chose a blind, comparative test of whether the seed improves screens.
Review found that this design cannot deliver that in full.

| Question put to the owner after review | Decision | What was not chosen |
|---|---|---|
| The claim is narrower than the question chosen | **accept the narrower claim** | strengthen independence further, with a separate adjudicator and a second party writing the measures; stop |

There are also more cross-family sends than revision 1 had. It had one, to the
deriver. This revision adds the reviewer, which receives a package before stage
1 and at stages 4, 6 and 7. Each send needs its own consent, asked for when the
package exists.

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

Revision 2 was reviewed only by the build that followed it. Revision 3 was
critiqued by another model family (Codex, critique mode) before it was
committed; its rewrites are adopted in the sandbox-check section, the runner
description and the blinding bullet, and one of its points was a defect in the
runner, fixed in Dion before any arm runs under it. The judge's launch
configuration is not yet registered.
