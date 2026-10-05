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

Revision 4, 2026-10-02. The judge's launch configuration is registered: a
manifest, a change to the sandbox check that lets a manifest with one tool be
checked at all, and a launcher (Dion, branch `judge-launch`). The registered
outcome measures and the decision rule are unchanged. The proposal was critiqued
by another model family before it was built, and one of its points removed a
defect from the proposal: see "Review". Like revision 3, this one was written
after the build and after the live results it reports, and makes no claim that
its wording preceded them. No arm has run, no judging package exists, and no
judge has scored anything.

Revision 5, 2026-10-02. The picker's launch is registered: its manifest gives up
the tool that writes, and it has a launcher (Dion, branch `picker-launch`). The
registered outcome measures and the decision rule are unchanged. Four things
this document said are corrected: that the picker runs with edits accepted; what
the snapshot holds; what the reviewer is sent of the record of what was removed;
and which launchers bind a check report to the version and the harness. The
proposal was critiqued by another model family before it was built, the choice
of tools was argued with it a second time at the owner's request, and both are
in "Review". Like revisions 3 and 4, this one was written after the build and
makes no claim that its wording preceded it.

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
names the terms, so it never goes to the picker.

Revision 2 also said the record "goes to the reviewer". It names the terms, so
it would fail the reviewer's own package check and would expose the reviewer to
them. Ruled by the owner on 2026-10-02: the reviewer is sent a summary made from
the record, of paths, line counts and kinds of term and never a term, and the
record stays on the machine. What that loses, named in the critique: from a
summary the reviewer can judge whether what was removed leaves a misleading
tree, and cannot judge whether the sanitising removed the right things. That
audit is the author's and the owner's, who know the treatment, and it is not
blind.

**What the snapshot holds that revision 4 did not mention.** Measured on
2026-10-02: `972f4ea` holds 1272 files and no link. Among them are Dion's own
`CLAUDE.md` and a `.claude/` directory with a settings file, four agent
definitions and six skills. The settings file defines hooks, for the start of a
session, the end of a turn and after every tool call among others, and each runs
a shell command. The CLI can load such names into a session with no Read call,
which is why the judge's launcher refuses them in a package. Ruled by
the owner on 2026-10-02: they stay in the picker's copy, as files of the
repository that it may read, and its own session is checked for having been
given them unasked: for a hook event, for an agent, a skill or a command they
define, and for an instruction file the CLI attached. "The picker", below, says
what was measured and what is checked.

The export is deterministic: two exports on 2026-10-02 gave the same record and
the same tree, byte for byte. Its record now carries a digest of the tree as it
was left, so that a tree and a record can be told to belong together.

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
| Used by | deriver, reviewer | picker, arm S, arm C, judge |
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
exposure/sandbox_check.py`), it launches one session for each probe it runs,
under the manifest, and reads what the launcher captured; the model is not asked what is
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
| `project_files` | the whole run, for a manifest that says its session runs where a repository's own files are (revision 5) | | no planted value is in any record and no planted hook left its file |

"Refused" is read from the CLI's own refusal event for the very call that asked,
never inferred from a value's absence, and a call that was refused and also
answered, or answered by another tool at a path outside, makes the probe
"unclear". These results establish refusal for the tested tools and spellings;
they do not establish that every possible access is refused. In particular a
call that spells its path with a wildcard in a directory name, or that starts
above the planted file, is not recognised as a try.

A probe is launched only for a tool the manifest declares (revision 4). Until
then every manifest was given all eight sessions, and a session without Grep,
asked to grep, never tries: "not attempted", which cannot check. So no manifest
with fewer tools than an arm's could pass, and the judge would have been given
Write, Grep and Glob only so that the check could refuse them. A probe whose
tool is not declared is now reported "not applicable" and no session is launched
for it. That the tool is absent is the `loaded` probe's claim, read from every
session's inventory. It is a claim about the inventory. It is not a claim that
anything was refused: only a call that was made and refused is. A manifest that
declares no Read cannot be checked, because every outcome rests on a planted
value read back through it.

The first proposal for this had the undeclared-tool sessions launched and passed
when no call by that tool appeared. The critique named what that is: a session
that makes no call at all satisfies it, which is "not attempted" passing under
another name. It was not built.

The two write probes were added after a dry run under CLI 2.1.285 and the
default permission mode in which every attempted write of both arms was refused:
a session launched headless has nobody to approve a write. The arms run with
edits accepted; the restricted mode still confines them to the working
directory, which the outside write probe is what tests. The picker ran so too
until revision 5, in which it gave up the tool: see "The picker".

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
For the arm launcher it does not bind the CLI version, which the report records
and that launcher does not compare, nor the harness's own code and sandbox
profile. Those may change without invalidating an arm's report. The judge
launcher binds both, as "The judge" below says; the arm launcher was not changed
in revision 4, and bringing it to the same rule is open. Since revision 5 a
report also carries the digest of the term list its term probe looked for, and
the judge's and the picker's launchers refuse a report made with another list.
The arm launcher binds none of the three: no arm runs in the picker's stage, and
it is left for the plan under which arms run.

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
are files of the harness and are not among the six whose digest a check
report carries (four in revision 4; revision 5 added the export script and the
picker's launcher); the lint cannot read the harness directory, which
the profile does not name.

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

### The judge

Registered in revision 4. The manifest is Dion's
`tests/design_seed_pilot/exposure/launch/judge.json`; the launcher is
`exposure/launch_judge.py`, with its cells in `test_launch_judge.py`.

**The manifest.** `claude -p --restricted --safe-mode --strict-mcp-config
--tools Read`, permission mode `default`, not seeded, no MCP server, no plugin.
One tool. The judge's scores are its last message, which the launcher captures,
so it needs nothing that writes; with nothing that writes, the default mode has
nothing to approve. It has no MCP server, so it can run in safe mode, which an
arm cannot.

**What the check measured, live, on 2026-10-02, CLI 2.1.285, model
`claude-opus-5-5`.** Status pass, four sessions:

| Probe | Result |
|---|---|
| `inside` | read |
| `outside_read_abs`, `outside_read_rel`, `symlink_out` | denied, each by the CLI's refusal of that call |
| `outside_grep`, `outside_glob`, `outside_write`, `inside_write` | not applicable: the tool is not declared |
| `outside_values` | absent: none of 11 values planted outside is in any record |
| `payload_terms` | absent |
| `loaded` | as declared: every session's tools were exactly `Read` |

Measured beside it, in one session of two turns: a PNG read through `Read` was
answered with an image, so a judge can be given screenshots; and a session
resumed with `--resume` kept its one tool and its mode, and an outside read in
the resumed turn was refused.

**What the launcher refuses, before any session is launched.** It runs
`claude --version` first, to learn which version is installed.

- A check report that is not a pass of the manifest's bytes as they are now.
- A report made by other harness code: the report carries one digest over the
  check, the two scanners and the launcher, and it must equal that digest now.
  Since revision 5 the digest also covers the export script and the picker's
  launcher, so a change to either makes a judge's report one to make again.
- A report made on another version of the CLI than the one installed.
- A package holding a file its listing does not name; a listed file missing, or
  not the bytes listed; anything that is not a plain file, a link included; a
  name the CLI loads by itself (`AGENTS.md`, `CLAUDE.md`, any dot-name); no
  `INSTRUCTIONS.md`; or a recorded term in a file, a file's name, or the
  question for afterwards.
- Such a name in a directory above where the judge would run. The copy is made
  under `/private/tmp`, where any process can write. An empty `.claude`
  directory holds nothing to load and is let through: one was there on the day.
- A question for afterwards that is one of the package's own files.
- A run directory that already holds a launch.

The rule about `AGENTS.md` comes from a measurement: the CLI's builtin plugin
that reads that file is loaded under safe mode too. Such a file would reach the
judge with no Read call, by a route the record of its calls does not show.

**Where the judge runs.** Each of the package's files is read once. Its bytes are
hashed against the listing, and the judge's working directory is written from
those same bytes, at a fresh path under `/private/tmp` that names nothing, with
every file and directory read-only. It is scanned there, names and bytes, since
the copy is what the judge is given. A session's working directory is in its
context, so the run directory's own name, which says the pair and could say the
arm, is never where a judge runs. The copy is removed afterwards.

**Two turns.** The first prompt is fixed in the launcher: read
`INSTRUCTIONS.md` and follow it. Its stream is written and its digest recorded
before the second turn is launched. The second, in the same session, asks the
question for afterwards, a file given to the launcher apart from the package,
whose digest is recorded. It is not fixed in the launcher as the first prompt
is: its wording is for the freeze. A session whose first turn was not valid is
not asked it.

**The judge's own session is checked.** The check's probes are other sessions
and show nothing about the one that scored. After each turn the launcher reads
that turn's stream:

- it ran to a result, the result is not an error, and the CLI exited 0;
- every line is an event;
- every `init` shows the manifest's tools, servers, plugins and permission
  mode, by the same function the check uses, with no hook event, on the
  version the report was made on;
- every call names a file under the copy, or was refused and never answered;
- no recorded term is in it. The package held none, so one here came from the
  CLI or from the judge;
- the copy holds what it held: no file changed, and nothing appeared, a
  directory, a link or a pipe included, none of which is opened;
- nothing the CLI loads by itself has appeared above the copy.

After the last turn the transcript is read as well: a line that is not an event,
a hook event, or a recorded term in it counts as it would in a stream.

If any of this fails, the evidence is kept, the launch record says the run is
not valid and why, and the launcher exits 6. A first turn that failed is not
followed by a second. An error nobody foresaw after the judge was launched is
recorded the same way, so a judged pair is never left with no record. Refusals
in the judge's stream are counted and recorded; a judge that tried to read
outside and was refused is a fact about that judge, not a fault of the run.

The first build read less. It compared the inventory and nothing of what the
judge read, asked the second question of a session already found wrong, took an
errored result for scores, and lost the record on an unforeseen error. A fresh
review of the branch found these; each has a cell now.

**Live dry runs**, on a toy package of two plain coloured squares that is
neither a pilot nor a replication artifact. Two, one before the review's fixes
and one after: each valid, two turns, three Read calls, all inside the copy and
all answered, nothing left behind. In the second those calls are checked by the
launcher and not by eye. A report made before the fixes was then refused,
because the harness had changed. This shows the launcher runs. It is not a
judging result.

**Cells and mutants.** As counted in the Dion pull request that carries this.

**What this does not show.**

- What reaches a judge beyond the package's files: the fixed prompt, which is
  recorded; the CLI's own system prompt and tool description; and anything a
  managed setting or policy on the machine adds. The launcher keeps the stream
  and the transcript. That they are the whole of a model's input is assumed, not
  shown. Zero hook events in a stream shows no hook reported firing in that
  session. It does not show that none is configured.
- Anything about the network. The judge has no web tool, which is an inventory
  claim. What the session could otherwise reach is untested, as for the arms.
- That the package is clean. A hash shows the bytes are the ones listed. The
  term scan finds its terms and nothing else. Image metadata, a provenance-
  bearing anchor, a revealing file name inside the package: these are the
  package builder's to control, and that builder is not built.
- Read spellings other than the three tested.

### The picker

Registered in revision 5. The manifest is Dion's
`tests/design_seed_pilot/exposure/launch/picker.json`; the launcher is
`exposure/launch_picker.py`, with its cells in `test_launch_picker.py`.

**The manifest.** `claude -p --restricted --safe-mode --strict-mcp-config
--tools Read,Grep,Glob`, permission mode `default`, not seeded, no MCP server.
Three tools, none that writes. Until this revision the picker had Write and
accepted edits, and was to write its brief as a file. Its brief is now its last
message, which the launcher keeps.

Why. With a tool that writes, a picker could change a file, read it and put it
back, and a comparison of the copy afterwards would pass: the comparison is of
what was left, not of what happened. The copy is now read-only, and that no tool
writes is what the manifest declares and every `init` is compared with. What it
costs was named in the second critique and is not measured: a model that drafts
to a file, reads the draft and revises may write a better brief than one that
composes it in one message. A tool confined to one brief outside the copy would
give that back; it needs an MCP server, which cannot run in safe mode, and the
owner did not choose it. It is the next step if the brief is unusable. Write is
not.

**Measured on 2026-10-02, CLI 2.1.285, model `claude-opus-5-5`.**

- With these three tools and the default mode, a final message of 5386 bytes
  arrived whole in the `result` event and was the text of the last assistant
  message. One session. It shows a brief of that size can arrive, not that every
  brief will.
- Two sessions under the picker's flags, in a directory holding `CLAUDE.md`,
  `AGENTS.md`, a `.claude/settings.json` with an environment value and a
  `SessionStart` hook, a skill and an agent, each carrying a random value, and
  neither session calling a tool. No value was in either stream or transcript;
  the transcript holds the system prompt, so that was looked at too. `init`
  listed neither the skill nor the agent, no hook event was reported, and the
  file the hook would have made was not made. Asked for the planted words, the
  session replied "unknown", which is its own account and counts only as not
  contradicting the rest. The builtin plugin that reads `AGENTS.md` was loaded
  in both. This shows no loading was observed in two sessions on one version. It
  does not show those files are inert, and it says nothing of a picker that
  reads them, which it may.
- With a control that goes red, after the review asked for it. One directory
  holding a `CLAUDE.md` with a random word and a settings file with a hook for
  each of five events, each hook making a file; one session each, asked to read
  a plain file. With neither restricting flag: all five hooks ran, and asked for
  the word the session replied with it. With `--restricted` alone, and with
  `--restricted --safe-mode` as the picker has: no hook ran, no hook event was
  reported, and the word was in neither stream nor transcript. So it is
  `--restricted` that keeps a repository's own settings and instruction file out
  of a session, on this version. The earlier two sessions had no such control
  and planted a hook for the start of a session only, in sessions that called no
  tool.
- In the recorded sessions Glob and Grep were called with no `path`, and Read
  with an absolute path.

**The check covers the directory the picker runs in.** A measurement made once
is not what a launch should rest on, and the report the launcher requires was
made in a directory that held no such files. So the picker's manifest says its
session runs where a repository's own files are, and for such a manifest the
check plants them in the probe directory: a `CLAUDE.md`, a settings file with an
environment value and a hook for each of five events, a skill and an agent, each
with a value of its own. No probe asks for them. The probe `project_files` is
"not loaded" when no such value is in any session's record and no hook left its
file; otherwise it is "loaded", and the run has findings. Measured beside it: a
session that loaded a `CLAUDE.md` holds it in its transcript as an attachment,
whether or not it speaks of it, and not in its stream; the check reads both. The
environment value has no way into a record of a session with no tool that
executes, and is not counted. The probe's red control is a live cell: the open
configuration, given the same files, must show both that all five hooks ran and
that the instruction file is in a record. The first form of that cell asked only
for "loaded", which the hooks satisfy alone; a second review named that. The
launcher refuses a report without this probe, or with it "loaded".

**What the check measured, live, on 2026-10-02, CLI 2.1.285.** Status pass, six
sessions, under the manifest as revision 5 has it:

| Probe | Result |
|---|---|
| `inside` | read |
| `outside_read_abs`, `outside_read_rel`, `symlink_out` | denied, each by the CLI's refusal of that call |
| `outside_grep`, `outside_glob` | denied, likewise |
| `outside_write`, `inside_write` | not applicable: the tool is not declared |
| `outside_values` | absent: none of 11 values planted outside is in any record |
| `payload_terms` | absent |
| `loaded` | as declared: every session's tools were exactly `Glob`, `Grep`, `Read` |

That run was made before the `project_files` probe existed. With the probe, on
the same day and version, the live cell for the picker's manifest passed with
`project_files` "not loaded", and its red control passed: an open session given
the same planted files ran all five hooks and held the instruction file in a
record. Both reports are scratch. A report is to be made again on the day the
picker runs. That is procedure: a report carries no date, and the launcher takes
any report that passes of the same manifest, harness, term list and version.

**What the launcher refuses, before any session is launched.**

- A check report that is not a pass of the manifest's bytes as they are now, by
  the harness as it is now, on the installed version of the CLI, with the term
  list as it is now; or one that does not list the skills its sessions had.
- A statement that is not the bytes whose digest is given on the command line,
  is empty, holds a recorded term, names no heading, or begins like an option.
- A reviewed record that is not of the registered snapshot, was made with
  another term list, does not say that its last scan found nothing, or names no
  tree. The last scan is the scan of what was left; what was removed is in other
  fields of the record.
- An export that could not be made, or whose record is not the reviewed record,
  byte for byte, or whose bytes are not the tree that record names, or that
  holds anything that is not a plain file.
- A copy that holds a recorded term, or a name the CLI loads by itself in a
  directory above the copy.
- A run directory that is not empty, or is a link.

**The launcher makes the export itself.** No tree is an argument. The first
proposal had the launcher handed a tree and its record, and checked one against
the other. The critique named what that leaves open: a record that names a
commit does not show that the tree came from it. So the launcher runs the export
script on the registered commit, into a directory only it can read, and requires
the record made then to be the reviewed record, byte for byte. Each file is read
once; those bytes must give the record's tree digest; the picker's working
directory is written from those bytes at a fresh path under `/private/tmp` that
names nothing, read-only, and is scanned there. Read-only is not private: other
accounts on the machine can read the copy while the picker runs. The export made for this is
removed before the session starts. The record is never in the copy or the
prompt.

**One turn.** The prompt is the statement, without the white space around it,
and nothing else. The digest is of the file's bytes.

**The picker's own session is checked.** After the turn the launcher reads its
stream:

- it ran to a result, the result is not an error, and the CLI exited 0;
- every line is an event;
- every `init` shows the manifest's tools, servers, plugins and permission mode,
  no hook event, the version the report was made on, and the copy as its working
  directory;
- no `init` lists a skill the check's first session did not have (the report
  carries one session's list, and builtin plugins have differed between sessions
  under one manifest, so a plugin that brought a skill would make a clean run
  not valid), or an agent, a
  skill or a command that a `.claude/` directory of the export defines, by its
  file's name or by the name it declares; and a list the session did not report
  is not read as an empty one;
- every call is inside the copy, by its own tool's fields, or was refused and
  never answered. Read: its file. Grep: its `path` and its `glob`, when given;
  its `pattern` is a regular expression over what files hold and is no path, a
  confusion the first proposal made and the critique named. Glob: its pattern,
  and its `path` when given. A call with no `path` is inside because the working
  directory is the copy. Inside means the resolved path is the copy or under it:
  a path that only begins as the copy's does is not, and neither is one that
  climbs out, or one that begins with `~`, holds a `$`, a quote or a backslash,
  has white space at either end, or begins like `file:`, since the launcher
  does not know what would be made of it. A pattern over file names is
  written out, brace groups first, and every pattern it stands for must be
  inside: `{,}/etc/*` is `/etc/*`. A Grep `glob` is read as a list as well,
  split at commas and white space. A field nobody knows is read as a path,
  however deep its text is nested, and is not ignored. What the CLI recorded as
  sent to the tool is read by the same rule as what the model asked for, and a
  call with no such record is not inside;
- no recorded term is in it;
- the copy holds what it held, and nothing has appeared in it.

The transcript is read as well: it must be there, be this session's, and hold no
line that is not an event, no hook event, no recorded term, and no instruction
file the CLI attached by itself, which is where a loaded `CLAUDE.md` is and the
only place it is. How many of each kind of thing the CLI attached is recorded.
The transcript is taken before the checks that could fail in a way nobody
foresaw, so that it is kept then too.

Things that make a run not valid and are not the picker's doing: a name the CLI
loads by itself appearing, during the run, in a directory above the copy, which
is `/private/tmp` and above; the kept stream changing after it was kept; the
copy failing to be removed. And a session has one hour: one that has not ended
by then is stopped, and its run is not valid.

**The brief.** It is the text of the last assistant message that holds text. It is accepted only
when that is the text of the one `result`, the result says the turn ended by
itself and completed (`stop_reason` `end_turn`, `terminal_reason` `completed`),
it is not empty and not over 64 KB, it holds every heading the statement names,
each on its own line and in the statement's order, and nothing but blank lines
comes before the first. The headings are read from the statement, so the
launcher holds no second copy of it. Nothing is trimmed or repaired: the file
kept is those bytes. A file gives none of this for free either: an interrupted
run leaves a partial file, and a file can hold a preamble.

If any of this fails, the stream and the transcript are kept, the launch record
says the run is not valid and why, no file that could be taken for a brief is
written, and the launcher exits 6. The same holds when the launch cannot be
recorded: a brief with no record beside it is removed. A run directory must be
empty before a launch, so that nothing left from another run is taken for this
one's. And a mark is written into it before the session exists: a launcher that
is killed writes no record, and without the mark a second launch would give the
picker the statement again with nothing to say it had it once. The mark is in
that run directory: a launch into another, empty one is not refused, and giving
the picker the statement once is procedure. A killed launcher
leaves its copy and the session's transcript where they were; nothing removes
them.

**No session has run on the export before the registered run.** Ruled by the
owner on 2026-10-02. The launcher makes its own export, so a dry run of it would
put the real export before a session. It is exercised by its cells, by their
mutants, and by the live check of its manifest. Its first live run is the
registered one.

**Reruns of the picker.** Ruled by the owner, 2026-10-02. The picker's run has an
allowance of its own, apart from the pairs': one rerun for a fault of the
harness, declared and recorded, with the evidence of both runs kept. A fault of
the harness is one the picker did not make: the launcher or the CLI failing, the
time limit, a name appearing above the copy, the copy that cannot be removed,
the kept stream changing, a skill a builtin plugin brought that the check's
session did not have. A run that is not valid through the picker's own doing (a
heading missing, a preamble, a call answered outside the copy, a recorded term)
is not rerun: its record is kept and reported, the stage stops, and the owner
decides what follows. If the statement is found to be at fault, a changed
statement is a new one, reviewed and frozen again, and recorded as a restart and
never as a rerun. Nothing is rerun for what a brief says, and the author does not
read a brief's merits to decide whether it stands.

**Cells and mutants.** As counted in the Dion pull request that carries this.
The module was written before its cells, which then passed at once; what shows
that a cell can fail is the mutant list, one fault for each refusal and each
check that has one. Without a mutant: that a statement, a record or a report can
be read at all; that the export left a record; the time limit on the export; and
the refusal of a file in the export that is not a plain one, which two guards
make, so that removing either changes nothing a cell can see. The counts are in
the Dion pull request; at the branch's head the launcher's list and the lists
for the check, the judge's launcher and the export were each killed in full.

**What this does not show.**

- That the picker learned nothing of what the terms name. A run that is fully
  logged and holds no term can still have been steered by a synonym, a file
  name, or the pattern of what is missing.
- That Dion's own instruction files did not steer it. It may read them; that is
  a read inside the copy. What is shown is that they were not loaded unasked, by
  a check made in a directory that held planted ones.
- That the calls the launcher read are the calls that ran. It reads what the
  stream says the model asked for and what it says was sent to the tool. It does
  not read the transcript for calls, and it counts the stream's own record of
  transformed inputs without judging them.
- How the CLI reads `~`, a brace group or a list of globs. The launcher treats
  each as the wider reading and marks the run not valid if such a call was
  answered. None was measured.
- That a file was not changed and put back. Nothing compares the copy during the
  run. What stands against it is that no tool writes.
- What a refusal's wording gave away. A refused call is counted, and what the
  CLI said in refusing it is not examined.
- That the export script made the reviewed record on the day it was reviewed.
  The launcher shows the script gives that record now.
- Anything about the network, or about what a managed setting added that no
  event reports, as for the judge.
- That every hook the snapshot defines stays silent. The probe plants five
  events; Dion's settings also define hooks for compacting a session, which no
  probe session reaches. A hook that ran in the picker's own session would be an
  event in its stream or transcript, and those are read.

### What this does not establish

- That a model has no knowledge of the seed from training or from public
  sources. This repository is public.
- That inputs the author shaped are neutral. The reviewer's audit reduces this
  and does not remove it.
- **That the judge remains unaware of the treatment assignment.** The
  restriction this design claims is on supplied inputs and tested access. As of
  revision 4: the only material of the experiment the launcher supplies to a
  judge is the listed package, which holds no seed document, arm directory,
  launch record or S/C label that the scan's terms name; the first prompt is
  fixed, and the second is a file whose digest is recorded; in the check's
  sessions the judge's one tool, Read, was refused at the three spellings of an
  outside path the check tries; and it has no tool that searches, writes or
  executes, which is a claim about its inventory. No judge has run. For each
  one that does, its own calls and its own record are read afterwards, and a
  call that reached outside, or a term, makes that run not valid. Revision 3 said the judge's
  "configured tools cannot retrieve" the rest. That is stronger than what was
  measured and is withdrawn: probes are evidence for the paths they tried, not
  an enumeration of what can be reached, and the network is untested. The artifacts
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
and how sure they were, in a second turn that starts only after the scores are
kept.

That answer is a report made afterwards. A judge can form the belief for the
first time when asked, or explain a score it already gave. An answer better than
chance does not show that anything leaked, and an answer at chance does not show
that the judge scored without a belief. It is reported as a secondary
observation and may be "cannot tell". A later judge is not to be given it;
that is procedure, and nothing in the launcher enforces it.

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
- `unvalidated-against`: a picker that reached the store. The check is built
  and the picker's own calls are read after its run ("The picker"); whether the
  brief holds anything of the store is looked at when the package that carries
  the brief is built, which is a later stage.

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
runner, fixed in Dion before any arm runs under it.

### The judge's configuration, 2026-10-02

The proposal for the judge was sent to Codex in critique mode before it was
built, as one package the owner approved. It saw the proposal and a summary of
the check. It read no file and ran no command.

| Finding | Response |
|---|---|
| An outcome that passes when an undeclared tool makes no call passes a session that makes no call at all | Adopted. The outcome was not built. An undeclared tool is not probed, and its absence is claimed from the inventory only |
| "Only the package" leaves out the prompt, the system prompt and the runtime context | Adopted. The claim names them, and says the capture's completeness is assumed |
| A passing report survives a change of the CLI or of the harness | Adopted for the judge launcher, which binds both. Open for the arm launcher |
| Zero hook events in the probes says nothing of the judge's run | Adopted. The judge's own streams are read after the run, both turns |
| A hash is identity, not cleanliness; a copy after a check is a race; links | Adopted. Plain files only, read once, copied from the verified bytes, scanned as copied, read-only |
| The answer about the arm is a report made afterwards | Adopted. Worded as that under "Judges" |
| "Its tools cannot reach anything else" needs enforcement independent of the model, such as a file broker or a boundary of the operating system | Not adopted. The owner accepted the narrower claim on 2026-09-29. The sentence is withdrawn instead, and the claim is what the probes tried |
| Managed settings and policy hooks still apply under these flags | Recorded as a limit. Not measured |

The build was then reviewed by a fresh reviewer of the same family as the
author, reading both branches and running nothing. It found nothing Critical
and eight Important defects, all in what the launcher read of the judge's own
session, and several sentences of this revision that said more than the code
did. The defects are fixed and the sentences corrected. Not fixed, and listed
in the Dion pull request: the listing and the question for afterwards are each
read twice; the report does not bind the term list the check ran with (it does
since revision 5); a
launcher that is killed leaves its copy behind.

Open after revision 4: the arm launcher does not bind the CLI version or the
harness; the package builder, which decides what a judge sees, is not built;
how many judges score a pair, and in what order they are shown the pages, is
for the freeze.

### The picker's launch, 2026-10-02

Two packages went to Codex in critique mode, each one text the owner approved,
each scanned for the recorded terms first. It read no file and ran no command.

The first was the proposal, before anything was built.

| Finding | Response |
|---|---|
| A Grep `pattern` is a regular expression, not a path; the proposal applied path rules to it | Adopted. Each tool is read by its own fields |
| A string prefix is not containment, and a path can climb out after it is joined | Adopted. Resolved paths, and a cell for each |
| A call with no path is safe only if the search root is known | Adopted. Every `init` must show the copy as the working directory |
| A record that names a commit does not show the tree came from it | Adopted. The launcher makes the export and requires the reviewed record again |
| "The record says nothing matched" confuses what was removed with what was left | Adopted. The two are named apart |
| A result that is not an error is weaker than complete evidence | Adopted. An empty brief, a transcript that is missing or another session's, a line that is not an event: not valid |
| Two sessions do not establish that `CLAUDE.md` and `.claude/` are inert, and a picker can read them | Adopted as wording. Whether they stay was the owner's ruling: they stay |
| A summary lets the reviewer check consistency and not the sanitising, and paths can themselves reveal | Adopted as wording. What the reviewer is sent was the owner's ruling: the summary |
| A run with no listed term can still carry what the terms name | Recorded as a limit. Not closed |
| What a refusal says can give something away | Recorded as a limit. Not measured |
| Enforce the boundary by isolating the filesystem, and treat the transcript as support | Not adopted, as for the judge. The owner accepted the narrower claim on 2026-09-29 |

The second argued the tools, at the owner's request, with the author's position
stated and Codex asked to argue the other side.

| Finding | Response |
|---|---|
| Three tools, for a reason stronger than the author's: with Write a file can be changed, read and restored, and the comparison passes | Adopted. It is the reason given under "The picker" |
| Two of the author's reasons are weak: the extra probes are a cost worth paying if drafting helps, and which of two briefs counts is settled by saying so | Accepted. Neither is relied on |
| The strongest case for Write: a draft that is re-read and revised may be part of how a good brief is made; one whole message says nothing of quality | Recorded as an unmeasured cost |
| A third option: an unchangeable copy and one narrowly writable output | Not chosen by the owner. It needs an MCP server, which cannot run in safe mode. It is the next step if the brief is unusable |
| With three tools the launcher needs a rule for accepting the last message | Adopted: "The brief" |

The owner's rulings of 2026-10-02 on this stage: three tools; Dion's
`CLAUDE.md` and `.claude/` stay in the copy and the session is checked; the
reviewer is sent a summary of the record; no dry run on the export.

The build was then reviewed by a fresh reviewer of the same family as the
author, reading the branch and running nothing. Two Critical and ten Important.
The Critical ones: the rule for calls took several spellings of an outside path
for an inside one (a leading `~`, a brace group that writes out to a path from
the root, a list of globs, a field it did not know), with no cell for any; and
the claim that Dion's own files are not loaded rested on a measurement nobody
could find in the branch, made without a control, while the report the launcher
required came from a directory holding no such files. Both are fixed as "The
picker" now says, the second by a probe and not by a sentence. The Important
ones were paths on which a run could end with a brief and no record, a run
directory that could already hold a brief, an export asked to go and not seen to
have gone, lists a session did not report read as empty, and eight guards no
cell could fail. Each has a cell and a mutant now. Not fixed, and listed in the
Dion pull request: the term list is read twice; a clean harness tree is recorded
and not required; the launcher's `prepare` and the judge's are two copies of one
rule; a killed export can leave its archive in the temporary directory.

The fix pass was itself read by a second fresh reviewer, the commit alone. No
Critical, seven Important: the control named above; the killed launcher; text
nested in an unknown field, and spellings the sibling check already treats as
real, taken for inside; a report read three times where the docstring said once;
and cells and mutants that did not test what they were named for, three of them
killed in the run by a neighbour's cell. Fixed, with a cell and a mutant each.
Its list of what a well-behaved picker might do and be refused for was short and
each item unlikely; the snapshot holds no file name with a `$`, a `~`, a brace
or a space.

One thing the review's measurement shows about a later stage, not this one: the
arms also run under `--restricted`, and in one session under that flag alone an
instruction file in the working directory was not loaded. An arm's session is
not that session: it has a server and accepts edits. Whether an arm loads such a
file, and so how the seeded arm is told where the seed is, belongs to the plan
under which arms run and must be measured there.

### Frozen: the picker's statement, 2026-10-03

The prompt the picker is given, and nothing else is. Dion
`tests/design_seed_pilot/exposure/picker/statement.txt`, SHA-256
`0a5d36ad6c0a21280be1947cbb19f2fea20f5a5d1730c4ec0b10c1a99b71b4be`, 2788 bytes.
A cell in `test_launch_picker.py` pins the digest. The launcher takes the digest
on its command line and refuses any other bytes.

```text
The current directory holds a copy of a software project. Explore it with the tools you have.

Choose one screen implemented in this project that displays a stored report. If the project has no such screen, say so and choose nothing else.

A builder without access to this project will implement that screen as a single self-contained web page that displays one report from a data file. Reply with a brief for that builder. Your reply is the brief: write nothing before or after it. Use these six headings, each on its own line, exactly as written and in this order.

## Task
The screen, and what a person comes to it to do.

## Content
Every item the screen shows a reader, in the project's names; where the files leave open which items appear, say so. Say what a reader uses the screen to do (find, compare, check) only where the files show it; otherwise write "none evidenced". Say which items belong together because of what they mean, and give an order only where the order carries meaning (by time, by rank, parts before their total), each with its reason. Leave out order and grouping that is only how the files happen to arrange things, and where you cannot tell which it is, leave it out and say that you did. Every sentence here must stay true if the screen were completely redrawn: do not describe position, layout, spacing, colour or typography.

## Data
The report type, and for each item its field, type and meaning, with the files that define them; for an item with no field of its own, say that it is fixed text or which fields it is derived from. The form of each value where the files establish one: precision, units, sign convention, dates as stored and as shown, and what is shown for an absent value; otherwise write "not established". Specify the format of the data file the builder will receive: the project's own where it has one, otherwise one you propose, saying which it is.

## States
Each state the screen can be in as the files establish it (for example empty, partial, failed, and any a reader brings about, such as a filter), what causes it, and what the reader is shown or can do in it. Describe behaviour, not appearance.

## Fixture
Reproducible steps for a person with access to this project to create the data file. Say how to select or construct one report. Include no values from individual report records; include schema constants where they are needed to interpret the data.

## Why this screen
What in the project led you to it.

Support claims about the project with file paths, and put the relevant details in the brief, since the builder cannot open those files. Keep project-defined facts apart from your proposed data-file and fixture instructions. Where the files do not settle something, state the gap and do not invent project behaviour.
```

**How it was reached.** The author wrote a first text, kept to what is wanted
and silent on how a page looks. It went to the reviewer (Codex, critique mode,
one package the owner approved, told nothing about the comparison). The reviewer
found no phrase that favours a look, and proposed rewordings, all adopted but
one: that the brief carry the existing screen's "structure, presentation rules,
order, grouping, layout and formatting as established by the files".

The author is not blind and would not adopt that, and the owner asked for a
design debate on it (three same-family agents, two rounds; seed-aware, so
advice and not a check). All three rejected the reviewer's wording, the
author's "content and behaviour only", and a middle "order and grouping only",
and converged on a rule: the brief binds only what stays true if the screen
were completely redrawn. Order and grouping are given only where the data
carries them, with a reason; the form of values is data; what a reader uses the
screen for is asked where the files show it. Against the reviewer's wording:
the existing presentation, given to both arms, is a rival seed, and the deriver,
who sees only the brief, would derive "matches the described layout", which is
the adherence check the owner declined. Against the author's: a seed-aware
author would be drawing the line around what the seed governs, fidelity would
have no anchor, and five pairs cannot absorb arrangement noise. Taken by the
owner on 2026-10-02.

The three changed paragraphs went back to the reviewer once (one package, the
owner approved). It answered that the text describes more than the report but
does not carry the screen's presentation hierarchy, which it called a coherent
choice if the builder is to redesign the presentation; found no preference for
a kind of screen or look, a preference for separating meaning from
presentation, and a mild lean towards analytical tasks in "find, compare,
check"; and named six places where a session that can only read files could not
comply or could read two ways. Those six are adopted as clarifications: items
the files leave open, a grouping whose reason cannot be told, an item with no
field of its own, states a reader brings about, a data file's format the project
does not define, and dates as stored and as shown. The changed text was not sent
a third time.

**Dissent recorded.** The reviewer holds that the brief should carry the
existing screen's presentation hierarchy. The statement does not, by the owner's
ruling, for the reasons above. A brief written under it describes what a page
must show and do; how it is arranged is the builder's, and that is what the arms
are compared on.

### The picker ran, 2026-10-03

One run, the registered one, and the launcher's first live run. It was valid.

| | |
|---|---|
| Dion commit | `22c372282a4193b01174ec61651277b5c1fb3815`, pushed, tree clean |
| CLI, model | 2.1.285, `claude-opus-5-5` |
| started | 2026-10-03T19:49:35Z; 23 turns, about 97 seconds |
| statement | `0a5d36ad6c0a21280be1947cbb19f2fea20f5a5d1730c4ec0b10c1a99b71b4be` |
| export | `972f4ea`, 1271 files, tree `047d9771…1341`, record `8c1d9753…d762` |
| check report | `78b0a47a…9e86`: pass, `project_files` not loaded, made that day |
| manifest, harness, term list | `87c156b1…942a`, `d9f5608d…1952`, `c7065fb3…180e` |
| calls | Glob 3, Grep 9, Read 10; every one inside the copy; none refused |
| attachments | the CLI's own (environment, model, date, session context, prompt snapshot and the like); no instruction file |
| stream, brief | `a898ce16…d970`; brief `72d201cf…935a`, 15,228 bytes, the six headings |

The brief, the stream and the transcript are kept on the owner's machine, outside
any repository, because the transcript holds the account's address. The brief's
text is not reproduced here. Freezing it is the next stage's, and nobody has
judged it: whether it stands is not decided by what it says.

What the reviewer was sent of the removal record, and what it said. A summary of
paths, line counts and kinds of term, with Dion's file paths in it (one package,
the owner approved). It answered that from a summary it could not tell whether
the removals mislead a party choosing a screen, and named what it would need:
what the removed lines and the omitted file said, and whether anything left
refers to them. That audit was then made on the machine, by the author, who knows
the treatment, so it is not blind: eight of the nine removed lines are workflow
steps in plan documents naming the development plugin's skills, the ninth is a
note in Dion's instruction file naming the pilot's branch, and the omitted file
is feedback to that plugin's maintainers, which nothing left in the tree refers
to. None concerns a screen of the application, a stored report or its data.

## Stages 2 to 7, as they are done

Entries are added here as each thing is fixed. Revision 6 of this document, which
will correct what earlier revisions say of these stages, is written when they are
done. Until then this section is the record.

### What the brief chose, 2026-10-04

Read from the brief by the author, as a fact and not as a judgement of it. The
screen is `dion report <identifier>`, the stored review report. **It is the
screen the pilot used.** Dion has no web or graphical screen and one command whose
job is to retrieve a stored report, so a statement that asks for "a screen that
displays a stored report" leads to it. The owner had ruled that nothing is rerun
for what a brief says, and it stands. No page, data file or result of the pilot
is used to build, calibrate or try anything in these stages. The author has seen
them, and no rule undoes that.

### Owner rulings for these stages, 2026-10-04

Given as "review this with Codex and proceed", after the plan and its five
recommendations were put, and after the review contradicted none of them.

| Question | Ruling |
|---|---|
| Consent for a package too large for the consent dialog to show whole | The owner reads the package file, whose path and manifest are given before the question. Packages that fit stay under 2.4 KB |
| Who writes the list of operator decisions the architecture table names | Nobody apart from the brief. The deriver lists them with the sentence each rests on, and the reviewer audits the list |
| The pilot's screen | Recorded, as above |
| The data file | The report Dion's own test database gives, with nothing added by the author. Not a real statement, which the brief's own steps propose |
| Viewport widths, which the brief does not state | The deriver states them, and why |
| The owner's real store | Not on this machine (stated by the owner). A package is scanned against a store when one exists at Dion's default path; when none does, its manifest says so |

The last of these corrects the safety assessment, which says the store is on the
machine the stages run on.

### Stage 2: the data files, 2026-10-04

`tests/fixtures/design_seed_replication/report.json` (SHA-256 `690c8ebe…1d76e`,
7199 bytes) and `report-not-found.json` (`d5e4b21c…05150`, 220 bytes), built by
`tests/design_seed_pilot/build_replication_fixture.py`.

The brief proposes making the data file from a real brokerage statement. That
was not done: it would put the owner's holdings into every page and package
(risk 4). The file is the report that `tests/review/_db_fixtures._setup_full_db`
gives when Dion's review is run on it, stored, and read back with the command's
own query in the command's own envelope. Nothing is added to that database. A
cell asks the command itself, on a database of the same content, and compares.
The builder takes no argument and opens its database in memory; a cell fails if
any connection is not.

What the author chose, all of it: that database; its pinned review date; the
indent of two that the brief's `--pretty` gives; the identifier `no-such-report`
for the second file; the two file names. Before choosing, one thing was looked
at: whether this database's report has the two things the brief prefers, orders
and an FX section. It has three orders and a non-null FX section. No other
database and no other date was tried.

The reviewer audited the files against the brief (one package of 13,086 bytes,
the owner consenting from the file). It found both conform to what the brief
specifies, and nothing in the author's choices that favours a way of building
the page. It listed the states the brief names that neither file exercises: a
found report with no FX section, with no orders or action items, or with an FX
section and no warnings; the compact and the text forms of output; a database
that is missing or cannot be read. Nothing was added to supply them: that would
be a database of the author's making. The example is small, three instruments,
all in one currency, with blank symbols, and a page built only against it could
overlook what a larger one would show. That is a limit of the example.

### Frozen: the deriver's instructions, 2026-10-05

Dion `tests/design_seed_pilot/exposure/derive/instructions.txt`, SHA-256
`4ee83130648470ac2dc0d66169fea9668053a7a242e837301ea0b574e3ed971e`, 3526 bytes.
A cell pins the digest, and that what the text says of the harness is what the
harness does.

```text
You are given a brief for building one screen as a single web page, and two data files. Two builders will each build the page from that same brief and the same data files, and their pages will be compared. Write the specification of what is compared. Ground every claim about what matters, and about which way is better, in the brief and the data files. Do not infer anything about the builders, and do not bring a design preference from outside these materials.

How the comparison works, so that you can write for it. Each construct is compared separately between the two pages. For a pair of pages the result is which page is ahead on more constructs; a construct counts once, however many things are measured for it. A measure sees one render of a page at each viewport width you name, at a viewport height of 900, after the page has loaded and a further 750 ms, with animation stopped and with no interaction. It may read the rendered layout and the document of that one page, and nothing else.

Your reply is the specification. Use these eight parts, in this order.

1. Decisions. The reader decisions the brief explicitly supports, each with the sentence it rests on, quoted. If naming a decision takes an inference, label it and explain it. If the brief supports none, say so.
2. Requirements. What the brief requires of the page that is not a decision, each with its sentence, quoted.
3. Constructs. Each quality of a page that a decision, a requirement or a fact of the data makes relevant. For each: what it estimates and what it does not; the specific evidence that makes it relevant, including why any data fact you cite matters to the page's stated purpose; which way is better, if either; the elements of the page it reads and how they are grouped. Say where two constructs overlap, so that no quality counts twice.
4. Measures. For each construct, one reproducible measure: what it observes, how it extracts it, how what it reads combines into one value, and what it excludes. Keep the construct apart from the proxy that is measured. A fallback only in a stated order, saying whether it measures the same thing. Say what is reported in each of these cases, which are not the same and are not all a poor result: the page did not render; the measure does not apply to this page; what it reads is absent; what it reads is present and not rendered. Name any requirement of the brief that one render with no interaction cannot assess.
5. Difference. For each construct, the smallest difference between two pages that matters. Say whether the brief or the data supports that size, and give the basis; where neither does, give a size all the same and call it a convention.
6. Central. The constructs without which the comparison would not address an explicit purpose or requirement of the brief. Cite that purpose or requirement.
7. Viewports. The viewport widths each measure is taken at, and why. Keep widths the materials require apart from widths you propose.
8. Judgment. Where code reading one render cannot measure a construct adequately, say whether structured human judgment can. If it can: what a judge may look at, the scale, and an anchor for every score. If it cannot, mark the construct not measured and say why.

Do not invent requirements or preferences that the materials do not hold. A choice you must make to make a measure reproducible is allowed: label it as an operational choice and give its basis. Where the evidence does not support a construct, a direction, a size or a conclusion, say so.
```

**How it was reached.** The author wrote a first text of eight parts. It went to
the reviewer (Codex, critique mode, told nothing of the comparison's subject)
with four questions. The first send ended with no reply: Codex had reached a
usage limit, and the dispatcher reported that the package might have left the
machine. It was sent again, the same bytes, with the owner's consent again, and
is logged as one resend after a failed send.

The reviewer found no phrase that sets a visual preference, and one defect that
mattered: the text asked for exact definitions and also forbade filling in
anything the brief does not settle, and a deriver cannot do both. Its rewordings
are adopted: a decision is listed only where the brief supports it, quoted;
evidence for a construct must say why a fact of the data matters to the page's
purpose; a construct is kept apart from the proxy measured for it; four ways a
measure can come up empty are told apart and are not all a poor result; a
choice needed to make a measure reproducible is allowed and labelled.

Three of its points were answered from what this design already fixes, and not
left to the deriver. It said "one vote" names no rule: the registered rule is
stated, that the page ahead on more constructs is favoured and a construct
counts once. It asked the deriver to define when a page is ready and what a
measure may read: those are facts of the harness and are stated as they are. It
would have let a size of difference be "undetermined": the design needs one for
every construct, so the deriver gives one and says whether the materials support
it or it is a convention.

What the reviewer said the instructions cannot let a specification say, kept as
limits: anything that happens after an interaction; whether a reader in fact
succeeds; stability across renders or between widths. The changed text was not
sent again.

Open after revision 5: the arm launcher binds neither the CLI version, the
harness nor the term list; the package builder is not built; the cost of
composing the brief in one message is not measured; the picker's brief is kept and
not frozen; the deriver's and the
reviewer's packages, the freeze and the arms each have their own plan.
