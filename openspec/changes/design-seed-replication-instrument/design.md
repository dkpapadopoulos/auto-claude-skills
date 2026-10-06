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

Revision 6, 2026-10-07. **The instrument as registered decides nothing, and the
plan that was building it has stopped, by the owner's decision.** Stages 1 to 4
are done. Stage 5 was built. At stage 6 the reviewer refused the content test
and the display test, the only two things that can decide a pair, since the
owner ruled that no judged construct gives a vote. Asked what could be approved,
it gave rules for a rebuild and approved nothing. Stage 7, the freeze and the
arms were not begun. Nothing of stage 5 was calibrated. No arm has run, no judge
has scored anything, and no result exists. The entries from "The gate, the one run over the acceptance pages, and
the reviewer refuses two tests" to the end are the record.

This revision changes no rule. It corrects lines that later entries had made
stale, each marked "(Revision 6)" where it stands. Some of those notes name the
entry they rest on and some do not; the entries are all under "Stages 2 to 7,
as they are done". The plan had the entries of stages 2 to
7 moved into the sections they amend. They are not moved: that was to ready the
document for a freeze, and none is coming. "How to go on" is whole. Like
revisions 3 to 5, this one was written after what it reports.

Precedent for the form: the pilot's registration, archived at
`openspec/changes/archive/2026-09-24-design-seed-capability/design.md`. Rule
numbers such as v2-2 refer to that document.

## What this design can and cannot deliver

It can deliver a **descriptive comparison**: ten generated pages (Revision 6:
twenty, a builder delivering a page for each of two data files), measured by an
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
| 2 | Build the fixture | author, from Dion's own test database with nothing added: the author's recommendation, taken as ruled by the owner's "proceed" of 2026-10-04. The brief's own step loads a real statement and was not done. (Revision 6; it said "author, running a transformation the picker specified", from "the picker's specification") | Dion's test database and its tests' configuration, which the author chose; the reviewer audited the two files against the brief's sections on states and fixture |
| 3 | Specify what is measured | deriver | the brief, the two data files, the frozen instructions. No list of operator decisions was frozen apart from the brief: the deriver lists them, each with the sentence it rests on. (Revision 6; it said "the brief, the fixture, the frozen list of operator decisions") |
| 4 | Audit each construct for task relevance | reviewer, under rule v2-2 | the brief, the fixture, the deriver's specification |
| 5 | Implement and calibrate each measure | author | the deriver's specification |
| 6 | Approve each implementation against its specification | reviewer | the specification, the code, the calibration results |
| 7 | Assess the interpretation gate's pre-run checks | reviewer | everything from stages 1 to 6 |
| 8 | Freeze, then run the arms | the harness | per arm setup |

The picker, the deriver and the reviewer each have controlled exposure. The
deriver and the reviewer are separate dispatches, so the party that approves a
measure is not the party that specified it.

(Revision 6) That last sentence did not hold for the fidelity tests. The audit
found their rules undefined, and the owner ruled on 2026-10-06 that the reviewer
defines them and later approves the code written to them, stated as a limit.
How each stage went is under "Stages 2 to 7, as they are done". Stages 1 to 4
were done. Stage 5 was built and nothing was calibrated; what was built is the
three fidelity tests, written to the reviewer's replies of rules and not to the
deriver's specification alone. Stage 6 was put to the reviewer with the rules,
the code and the results on its acceptance pages, and ended in two refusals.
Stages 7 and 8 were not begun.

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
| Where the fixture's data comes from (Revision 6; was "how the fixture is transformed", by the picker) | the author recommended Dion's own test database with nothing added, taken as ruled by the owner's "proceed"; which database, configuration and date is the author's | reviewer audited the two files against the brief's sections on states and fixture |
| The instructions given to the deriver (Revision 6; no row before) | author | reviewer, twice; then frozen, with the sentences the reviewer did not read named |
| The fidelity dimensions, and the rules for them the audit found undefined (Revision 6; no row before) | deriver; then reviewer | reviewer; then nobody else: the same party approves the code, by the owner's ruling |
| Constructs, their direction, scope and grouping | deriver | reviewer, under v2-2 |
| Which operationalisations of a construct are acceptable | deriver | recorded |
| What size of difference matters | deriver | recorded |
| The code for each measure | author | reviewer approves or rejects |
| Rendering-noise tolerance | measured at calibration. (Revision 6) Never measured: nothing was calibrated | recorded |
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
  package builder's to control, and that builder is not built. (Revision 6) It
  is built, `build_judging_package.py` in Dion: every picture is read to its
  pixels and written again from them, and a file is named by its width and its
  number in the order of the crops.
  The reviewer has not read it, and no arm's page has been through it.
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

(Revision 6) No measure of a construct was registered or built. That the
comparison is run as registered, and that no code measure of a construct is
asked for, is the author's recommendation of 2026-10-05, which the owner took
in advance and did not rule on ("How to go on"). The measures built are the
three fidelity tests, and two of them were refused.

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
  (Revision 6) Not measured: no calibration was made.
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

One pair is two pages from arm S and two from arm C, one for each data file
(Revision 6; it said one page from each, and the owner ruled on 2026-10-05 that a
builder delivers a page for each data file), built from the same brief,
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

(Revision 6) "One page" is now four results for a builder: two pages, each at
two widths. What the rule left unsaid was ruled by the owner on 2026-10-05: a
page that does not render fails fidelity; a fidelity test that cannot be
carried out counts as failed for that builder; a construct only a judge can
score gives no vote. The secondary analysis, in which such a test is unknown,
is not of that ruling. It is from "How to go on", the recommendation the owner
took in advance, and the owner's ruling of 2026-10-06 speaks of both analyses.
With no code measure of a construct either, step 2 never applies, and a pair
is decided by fidelity or has no direction. `decide_pair.py` in Dion is that
rule in code, with readings nobody ruled: that any failed test fails the
builder, and the three recorded under "What fidelity decides for a pair". The
reviewer has not read it. Both tests it counts were refused by the reviewer on
2026-10-06. The plan of these stages, and no entry of this document, has a
refused test not used; by that, every pair would have no direction.

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

(Revision 6) The four checks made before a run were never put to the reviewer:
the plan stopped at stage 6.

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
| `private_data` | Present as registered. (Revision 6) The owner stated on 2026-10-04 that the store is not on this machine. No check here shows it; the package builder looks at two paths and records "not applicable" when no store is at either | Dion's store of real holdings is on the machine the stages run on |
| `untrusted_input` | Present | arms' generated HTML and scripts run in a browser, and the measures read the result |
| `outbound_action` | Present | packages to the deriver and the reviewer; a judge's input, if any construct is judged |

### Classification

**Risk level:** lethal trifecta, as the pilot was. (Revision 6) The level is
kept though the first field now rests on the owner's statement. One control was
loosened on that statement and nobody ruled that it may be: see "The store, and
a control that changed with it".

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
  (Revision 6) The store is stated not to be on this machine, and that check
  stops when it finds none. Nothing of these stages runs it on an arm's page: no
  arm has run. A judge would be sent pictures, which it does not read.
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
  the brief is built, which is a later stage. (Revision 6) Two packages carried
  the brief whole, to the deriver and to the reviewer on 2026-10-05, both built
  by the package builder. It scanned them for recorded terms, paths, addresses
  and the account's name. Its scan against the store recorded "not applicable":
  no store was at either path. So the brief was not compared with a store.

**4. The fixture is built from the real store.**

- Threat region: the fixture's bytes.
- Control region: the pilot's builder opens its database in memory and takes no
  path argument. Its rows come from a random generator with a fixed seed and
  from test configuration. Read from the builder's source on 2026-09-29.
- Overlap: the control covers the threat for that builder. The store cannot be
  reached from it.
- Not looked at: a new builder written for a new task. Nothing stops one from
  opening a file. (Revision 6) One was written: `build_replication_fixture.py`.
  It takes no argument and opens its database in memory, and a cell fails
  unless it makes exactly one database connection, in memory. A route to a
  database that is not such a call would not be seen; the source holds none.
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
  runs, which do not exist yet. (Revision 6) They exist. The measuring script
  applies the same request policy, runs only under the isolation, and refuses a
  page that asked for another file or opened another page. The fidelity tests
  read a page from a world of their own, which keeps the browser's functions
  from a page's script and not the document: a page that alters its own
  document while it is read is still not seen.
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
| The pilot's brief | retired. (Revision 6) The picker then chose the screen the pilot used; see "What the brief chose" | kept as a second task with one dimension declared contaminated |

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

(Revision 6) There were many more. For stages 2 to 6 seventeen sends are logged,
nine and then eight, each with its own consent: the reviewer was also asked for
the rules the audit found undefined, three times; for the pages the tests were
developed against and the pages they were accepted against; and, after it
refused, for what could be approved. Stage 7's was never made.

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
for the freeze. (Revision 6: that builder was built on 2026-10-06; see "The
judge".)

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
judged it: whether it stands is not decided by what it says. (Revision 6) It
stands, by the owner's ruling of 2026-10-02 that nothing is rerun for what a
brief says. It was sent whole to the deriver and the reviewer and is not frozen
by an entry of its own.

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

Open after revision 5: the arm launcher binds neither the CLI version, the
harness nor the term list; the package builder is not built (Revision 6: the
builder of text packages was built on 2026-10-04 and the builder of a judging
package on 2026-10-06); the cost of
composing the brief in one message is not measured; the picker's brief is kept and
not frozen; the deriver's and the
reviewer's packages, the freeze and the arms each have their own plan.

## Stages 2 to 7, as they are done

Entries are added here as each thing is fixed. Revision 6 of this document, which
will correct what earlier revisions say of these stages, is written when they are
done. Until then this section is the record, and where it differs from an earlier
section it is the later word.

(Revision 6, 2026-10-07) It was written when the plan stopped, at stage 6. The
entries stay here, in the order they were made. This section is still the later
word where it differs from an earlier one, and the earlier sections now say so
where they stand.

### What the brief chose, 2026-10-04

Read from the brief by the author. The screen is `dion report <identifier>`, the
stored review report. **It is the screen the pilot used.**

Dion has no web or graphical screen. It has more than one command that retrieves
something stored by an identifier: `dion report`; `dion research report`, which
retrieves stored research output in the same kind of envelope; and
`dion flex inspect`. So the statement, which asks for "one screen implemented in
this project that displays a stored report", did not force the choice: the
picker chose among at least two. The brief's own account of its choice says the
research commands compute their output when run. That is not so of
`research report`. This is recorded and decides nothing.

By the owner's ruling of 2026-10-02 nothing is rerun for what a brief says, and
the brief stands. No page, data file or result of the pilot is used to build,
calibrate or try anything in these stages. The author has seen them, and no rule
undoes that.

### What the owner ruled for these stages

On 2026-10-04 the owner answered the plan and its five recommendations with
"review this with Codex and proceed". The plan was reviewed (one package, the
owner consenting), and the first five rows below are those recommendations,
taken as ruled by that answer and not ruled one by one. The others were put as
questions and answered.

| Question | Ruling | When |
|---|---|---|
| Consent for a package too large for the consent dialog to show whole | The owner reads the package file, whose path and manifest are given before the question | 2026-10-04, by "proceed" |
| Who writes the list of operator decisions the architecture table names | Nobody apart from the brief. The deriver lists them with the sentence each rests on, and the reviewer audits the list | 2026-10-04, by "proceed" |
| The pilot's screen | Recorded, as above | 2026-10-04, by "proceed" |
| The data file | The report Dion's own test database gives, with nothing added by the author. Not a real statement, which the brief's own steps propose | 2026-10-04, by "proceed" |
| Viewport widths, which the brief does not state | The deriver states them, and why | 2026-10-04, by "proceed" |
| The owner's real store | Not on this machine | 2026-10-04, stated |
| Who defines the fidelity dimensions, which no revision had said | The deriver, as a part of its specification, audited by the reviewer | 2026-10-05 |
| What a builder delivers, there being two data files and no way for a page to load one when shown | One page for each data file | 2026-10-05 |
| What an unavailable result does to a pair, which "Failures and reruns" leaves to "the rule above" and the rule above does not say | A page that does not render fails fidelity. A fidelity test that cannot be applied to a page that rendered counts as failed for that builder. A construct on which either builder has no value gives no vote | 2026-10-05 |
| Whether a construct only a judge can score votes, "Judges" saying only that judged scores are reported apart | It gives no vote. Its scores are reported beside the result | 2026-10-05 |
| Whether the instructions' last form goes to the reviewer a third time | No. They are frozen, and this document says which sentences the reviewer did not read | 2026-10-05 |

Some of these change what earlier sections say, and are not only additions.

**How a consent is bound to what the owner read.** A question names its package by
the dispatcher's digest, the approval's preview must hash to that digest, and the
copy that is sent is checked against it again. That digest is taken with the line
breaks at the end left off, so for a package the builder made, which always ends
in line breaks, it is never the file's own digest. The manifest carries both
since 2026-10-05, so that the file that was read can be matched to the question.
No send made before that had such a manifest: for those, the match rests on the
dispatcher having been given that file, and was not shown to the owner.

Of the first five sends, one package was built by the builder and had a
manifest: the fixture audit's. The plan's critique and the two packages that put
the instructions to the reviewer were written by hand and had none; the owner read
the first in the consent dialog and was given the path of the other two. The two for the instructions were scanned after the
fact, on 2026-10-05, with the builder's term list and its patterns for paths and
addresses, and nothing was found.

**The store, and a control that changed with it.** The safety assessment says the
store is on the machine the stages run on. The owner states it is not. The
pilot's check of a page against the store treats a store it cannot find as
"cannot verify", which is a stop. The package builder of these stages does
otherwise: when no store exists at Dion's default path, in this checkout or the
main one, it records "not applicable" in the manifest, with how many places it
looked at, and builds the package. (The first manifest that went with a send,
the fixture audit's, was built before that wording: it says "no store on this
machine" and gives no count.) A stop became a note. Nobody was asked whether
the control may be loosened, and nobody ruled that it may: the owner stated a
fact and the author built the note on it. What stands behind it is that
statement, that the data file is synthetic, and that the brief was written from
an export of one commit's files, which holds no store. It is the owner's to
reverse.

**A pair.** "Decision rule and claim" says a pair is one page from each arm. It is
two pages from each: the screen built with each data file. The
instructions below say how a builder's two pages enter fidelity and a
construct's value. What else follows is not yet worked out and is for the plan
under which arms run: the picker's
frozen statement speaks of "a single self-contained web page", nothing that
instructs a builder exists yet, whether one session builds both pages is not
said, and twice as many pages are rendered. Sentences elsewhere that count ten
pages, or a budget for one page, are stale.

**The decision rule's unstated parts.** The registered rule is unchanged in what
it says. What it left unsaid about an unavailable result, and about a construct
that is only judged, is now said by the owner's rulings, before any
specification, measure or arm exists.

Two more things the instructions say were not ruled by anyone. The registered
rule speaks of one page failing "a fidelity dimension". With several dimensions,
two pages for each builder and several widths, the instructions say a builder
fails fidelity if any test that applies to its pages fails. The reviewer called
how failures combine the largest gap, and gave its wording on the stated
assumption that any failure fails the builder. That reading was taken. And the
instructions give a construct a vote only where it has a supported direction,
which the registered rule does not say; the wording is the reviewer's. The owner
was not asked either question. Both are stated to the owner with the deriver's
package, before it is sent.

### Stage 2: the data files, 2026-10-04

`tests/fixtures/design_seed_replication/report.json` (SHA-256 `690c8ebe…1d76e`,
7199 bytes) and `report-not-found.json` (`d5e4b21c…05150`, 220 bytes), built by
`tests/design_seed_pilot/build_replication_fixture.py`.

The architecture table has the picker specify how the fixture is made and the
author run it. The brief's second step loads a real brokerage
statement; the brief says it had not established whether the project ships a
synthetic database. That step was not done: it would put the owner's holdings into every page and package
(risk 4). So the source of the data is the author's and the owner's, and not the
picker's. The file is the report that `tests/review/_db_fixtures._setup_full_db`
gives when Dion's review is run on it, stored, and read back with the command's
own query in the command's own envelope. Nothing is added to that database. A
cell asks the command itself, on a database of the same content, and compares,
setting aside the three things every review makes anew: the run id, the report
id and the creation time. The report body and its content hash are not among
them: two builds gave the same of each, and a cell says so. `report.json` is
therefore one build, and its digest names that one build: a rebuild gives the
same report under other ids.

The function that builds takes no argument and opens its database in memory. A
cell records every call to `duckdb.connect` while it runs and fails unless there
is exactly one, in memory; a route to a database that is not such a call would not be seen,
and the source holds none.

What the author chose: that database; the configuration Dion's own tests review
it with, `tests/config`, which sets the optimiser's policy and the costs (it has no FX
section, so the FX thresholds are the defaults of Dion's configuration loader,
and those give the four FX lines among the file's seven action items); the review date the database is
pinned to; the indent of two that the brief's `--pretty` gives; the identifier
`no-such-report` for the second file; the two file names. Before choosing, one
thing was looked at, apart from the file's size: whether this database's report has the two things the brief
prefers, orders and an FX section. It has three orders and a non-null FX section.
The author reports that no other database and no other date was tried.

The reviewer audited the two files (one package of 13,086 bytes, the owner
consenting from the file). It was sent two sections of the brief, States and
Fixture, word for word, and not the rest; the two files; and the author's list of
choices, which did not then name the configuration. Within that, it found each
file to be what those sections specify, and found nothing in the choices listed
to it that favours a way of building the page. It listed the states the brief
names that neither file exercises: a found report with no FX section, with no
orders or action items, or with an FX section whose warnings or breaches are empty; the compact and the
text forms of output; a database that is missing or cannot be read. It also said
the files cannot show a lookup by both kinds of identifier: the builder asks by
run id only. Nothing was
added to supply them: that would be a database of the author's making. It asked
for things it was not sent, among them the rest of the brief.

The example is small: three instruments, all in one currency, with blank symbols,
no policy violation, no restricted or unknown instrument, no suppressed trade and
no earlier weights to drift from. A page built only against it could overlook what
a larger one would show. That is a limit of the example.

### Frozen: the deriver's instructions, 2026-10-05

Dion `tests/design_seed_pilot/exposure/derive/instructions.txt`, SHA-256
`1d7b58ab0b96397134efa85b40a884f48782caaf462b747d49e04b81d25e7992`, 6355 bytes.
A cell pins the digest. Other cells look for a phrase of the text and for a line
of the harness's source, for nine things: the viewport height; the wait after
load; that it waits for load; that animation is stopped; the light scheme; the
device scale; the reduced motion asked for; the range of widths it takes; and
that a judge's images are of the whole page. For six of them the line is the one
that does it. For the height, the wait and the range of widths it is the line
that declares the value; the lines that apply them are held by the measuring
script's own cells and mutants, which need a browser and skip without one. All
nine read the source as text. None runs the harness.

```text
You are given a brief for building one screen as a web page, and two data files. Two builders will each build the screen from that same brief and the same data files, and what they build will be compared. A page cannot load a file when it is shown, so each builder delivers two pages: the screen with the content of one data file built in, and the screen with the content of the other. Write the specification of what is compared. Ground every substantive claim about what matters, and about which way is better, in the brief and the data files. Keep those claims apart from the operational choices and the threshold conventions that are asked for below. Do not infer anything about the builders, and do not bring a design preference from outside these materials.

How the comparison works, so that you can write for it.

A pair is one builder's two pages against the other builder's two pages. It is decided in two stages.

First, fidelity. Each builder is assessed across all fidelity dimensions and all the pages and widths they apply to. A builder fails fidelity if any fidelity test that applies to its pages fails. A page that does not render fails. A test that applies to a page and cannot be carried out on it, though the page rendered, also counts as failed for that builder. If exactly one builder fails fidelity, the pair is decided for the other. If both fail, the pair has no direction. If both pass, constructs are compared.

Second, constructs. Only a construct measured by code votes, and it gives at most one vote, however many things are measured for it. A construct that only a judge can score gives no vote: its scores are reported beside the result. A builder gets that vote only if the construct has a supported direction and the difference favours that builder by more than both the threshold of part 6 and the rendering noise, which is measured later: that is, by more than the larger of the two, on the same scale. A construct on which either builder has no value gives no vote. The builder with more votes is favoured. A tie has no direction.

A measure is code. It is given one render of one page at each viewport width you name, from 200 to 4000, at a viewport height of 900, in the light colour scheme, at a device scale of 1, with reduced motion asked for, after the page has loaded and a further 750 ms, with animation stopped. Those are how the harness renders. Two more are rules a measure is written to and checked against: it does not interact with the page, and it reads only the rendered layout and the document of that page.

A judge, where there is one, is a model given the judgment rubric and images of the whole of each page at those widths. It is given nothing else about the pages.

Your reply is the specification. Use these nine parts, in this order.

1. Decisions. The reader decisions the brief explicitly supports, each with the sentence it rests on, quoted. If naming a decision takes an inference, label it and explain it. If the brief supports none, say so.
2. Requirements. What the brief requires of the page that is not a decision, each with its sentence, quoted.
3. Fidelity. Which of those requirements are fidelity dimensions. For each: a test that code could apply to a render, returning pass or fail when it can be applied and a distinct status when it cannot; which data file's page it is applied to; and why a failure of this requirement belongs in fidelity and not in a graded construct. Being an explicit requirement is not by itself enough.
4. Constructs. Each quality of a page that a decision, a requirement or a fact of the data makes relevant. For each: what it estimates and what it does not; the specific evidence that makes it relevant, including why any data fact you cite matters to the page's stated purpose; which way is better, if either; the elements of the page it reads and how they are grouped. Find the overlap between constructs and resolve it, by merging constructs or by restricting what each measures: the same quality must not give more than one vote.
5. Measures. For each construct measured by code, define the measure so that code could be written from it and checked against it: which data file's page it is taken on, what it observes, how it extracts it, and what it excludes. Say how all the observations for a construct, across data files, viewport widths and component measures, combine into one comparable value for each builder. Keep the construct apart from the proxy that is measured. A fallback only in a stated order, saying whether it measures the same thing. Say what is reported in each of these cases, which are not the same and are not all a poor result: the page did not render; the measure does not apply to this page; what it reads is absent; what it reads is present and not rendered. Name any requirement of the brief that one render with no interaction cannot assess.
6. Difference. For each construct measured by code, the threshold a difference must exceed to count, in the units of the construct's final value. Where the brief or the data supports that threshold, give the basis. Where neither does, give a threshold all the same and label it a convention; do not claim that it is the smallest difference that matters to a reader.
7. Central. The constructs without which the comparison would not address an explicit purpose or requirement of the brief. Cite that purpose or requirement. This does not change how a pair is decided; it is used to judge whether what was measured covers what matters.
8. Viewports. The viewport widths each measure is taken at, and why. Keep widths the materials require apart from widths you propose.
9. Judgment. Where code reading one render cannot measure a construct adequately, say whether a judge shown images of the pages can. If it can: the rubric, the scale, and an anchor for every score. If it cannot, mark the construct not measured and say why.

Label a choice needed to make a test or a measure reproducible as an operational choice, and give its basis. Label a threshold that part 6 requires and the materials do not support as a convention. Neither establishes a requirement or a preference of the materials. Do not invent requirements or preferences that the materials do not hold, and say so plainly where they do not support a fidelity dimension, a construct, a direction or a conclusion.
```

**What the text says that no cell ties to anything.** This list is what the author
and two reviews found. It is not shown to be complete.

- That a measure does not interact with a page, and reads only that page. These
  are rules for whoever writes a measure. The harness hands a measure the whole
  page object and does not enforce them. The reviewer's approval of each measure,
  at stage 6, is what checks them, and the text says they are rules and not facts.
- That a judge's images are "at those widths". **This is not true of the capture
  as built.** It takes two fixed widths, the pilot's, and no argument for others.
  It must be made to take the specification's widths before any judging package
  is built. Open.
- That a judge is given the rubric and "nothing else about the pages", and that a
  judged construct's scores are reported beside the result. The builder of a
  judging package is not built, nothing registers what such a package holds, and
  nothing that reports a result is built.
- That a page cannot load a file when it is shown. It is true of the capture and
  of the measuring script, which refuse such a page, and no cell sets the
  sentence beside them.
- How a pair is decided, and that rendering noise is measured later. Nothing that
  decides a pair or measures noise is built. A cell checks only that the
  sentences are in the text.
- That a fidelity test is one code could apply to a render. Nothing that applies
  a fidelity test is built.

**How it was reached, with what went wrong.** The text was frozen four times. The
first three were mistakes, each caught before anything was sent to the deriver.

The author wrote a first text of eight parts. It went to the reviewer (Codex,
critique mode, told nothing of the comparison's subject; one package, the owner
consenting). The first send ended with no reply: Codex had reached a usage limit,
and the dispatcher reported that the package might have left the machine. It was
sent again, the same 2870 bytes, with the owner's consent again. The reviewer
found six phrases that steer what a construct may be and none that sets a visual
preference; six things a writer would need that were missing; and, as what it
called the biggest defect, one conflict: the text asked for exact definitions
and forbade filling in anything the brief does not settle.

*First freeze (3526 bytes).* The author reworded the text and froze it. A fresh
review of this section against the code, by a reviewer of the author's family,
found that the frozen text gave the constructs step of the registered rule as
the whole rule, with no fidelity stage and no part for fidelity dimensions,
which no revision had said who defines; that it spoke of human judgment, where
this design's judge is a model; that it named two data files and never said
which a page shows; and that the reviewer had read a draft and not the bytes
that were frozen.

The owner then ruled who defines the fidelity dimensions and what a builder
delivers. The text was corrected and went to the reviewer a second time (one
package of 6226 bytes, the owner consenting from the file). It found the rule
still left things for a writer to invent: how failures of different fidelity
dimensions combine; how observations across pages and widths become one value;
what an unavailable result does; and that calling a threshold "the smallest
difference that matters" presents a convention as a finding. The owner ruled
what an unavailable result does.

*Second freeze (6017 bytes).* The reviewer's rewordings were worked in, close to
its words, with that ruling, and the text was frozen. A package for the deriver
was built from it and not sent. A second local review of this section found
that the text let a judged construct vote, which this design does not say. The
owner ruled that it does not, and that the text would not go to the reviewer a
third time.

*Third freeze (6294 bytes).* The ruling was written in, and more of what the
harness does was stated: the scheme, the scale, the motion asked for and the
range of widths. A package was built and not sent. A third local check, of this
section against the reviewer's packages and replies, found that working the
rewordings in had also dropped two phrases the reviewer had read and nobody had
asked to remove: that a fidelity test is one "that code could apply to a
render", which left the text not saying what applies a fidelity test, and that
the cases of a missing result "are not all a poor result".

*The form above (6355 bytes)* restores those two phrases. That is the author's
correction of the author's slip. No ruling was asked for it, and it is stated to
the owner with the deriver's package.

The local reviews' reports are in the session's record. They were not kept as
files.

**Not adopted.**

- The reviewer would have let a size of difference be "undetermined". This design
  needs one for every measured construct. The text requires one and has it
  labelled a convention where nothing supports it.
- The reviewer would have a construct reported apart with no overall result
  unless a rule were supplied. The registered rule was supplied instead.
- The reviewer would have had the deriver define when a page is ready and what a
  measure may read. Those are the harness's, and the text states them.

The plan's first review asked that the choice among acceptable ways to measure a
construct be frozen in the specification, with exact definitions and the
aggregation of several measures. The author's first draft made that "one exact
definition of a measure". The text now asks how a construct is measured and how
everything measured for it combines into one value, which is what was asked.

**What the reviewer did not read.** The frozen bytes, by the owner's ruling. It
read two earlier forms. Split at full stops and colons, the frozen text has
92 pieces, and 53 of them stand as they were in the form it read second. Most
of the rest are its own proposed wording or close to it. "Being an explicit
requirement is not by itself enough", in part 3, is the reviewer's but for its
last word, which was "sufficient".

What is in the frozen text that the reviewer neither read nor proposed:

- the three sentences that say what an unavailable result does, and "any fidelity
  test that applies to its pages", which rewords its "any applicable fidelity
  test";
- the two sentences that say a judged construct gives no vote;
- the added conditions of the render;
- "of the whole of each page", which answers a question it asked and never saw
  answered;
- the first sentence of part 3, and the order of the words around "that code
  could apply to a render";
- the second clause of part 7;
- "the rubric" in part 9;
- part 6 as narrowed to constructs measured by code.

One removal it did not see: the sentence that a fidelity dimension decides a pair
outright and that only what the brief requires for a page to be the screen
belongs there. It had said of "to be the screen at all" that the phrase does not
establish which breaches deserve an outright loss.

What the reviewer said the instructions cannot let a specification say, kept as
limits: anything that happens after an interaction; whether a reader in fact
succeeds; stability across renders or between widths.

**Where the sends are logged.** `dispatch-log.md` in the stage's evidence
directory on the owner's machine: every package, its size, the dispatcher's
digest shortened, the mode, what allowed it, and where the reply is kept.

### Stage 3: the specification, 2026-10-05

**The send.** One package, built by the builder: the frozen instructions, the
brief whole, the two data files, and the dispatcher's closing lines. 29,363 bytes, SHA-256 `df44411c…8c10`; the
digest the consent carried is `cc19a025…1f82`, and the manifest gives both.
Independent mode. Before the question the owner was given the file's path and
manifest and was told of three things in the instructions nobody had ruled on:
that any failed fidelity test fails the builder; that a construct votes only
with a supported direction; and that two dropped phrases had been put back, so
that the text was a fourth freeze. The owner approved the send. That is consent
to the send with those three stated. It is not recorded here as three rulings.

One send. No second was made, and none is owed: every part is in the reply.

**The reply.** Dion `tests/fixtures/design_seed_replication/specification.md`,
17,620 bytes, SHA-256
`3ce12db28ed36b6279ea366fb9df430f5d3263eca8a9d1c9b3e20adee93e6552`, as it came,
with the digest beside it. Cells pin the digest, find the nine parts in order,
and find no recorded term. Nobody edits it.

**Read for form only, by the author.** The nine parts are there. It holds
sentences in the imperative ("Give the judge the relationship inventory", "Use
the harness conditions exactly"). They say what the instrument is to do, which
is what a specification is for; the author found none addressed to whoever
handles the reply. Nothing was asked again.

**What it says,** in the author's summary. The file is what counts.

- *Decisions.* None beyond asking for a report that already exists.
- *Fidelity.* Three dimensions, each on both pages at each width: the content is
  complete and accurate; the retrieval state is the right one; the content is
  displayed, and not hidden or left behind something that must be opened. It gives a protocol for reading a
  page's content back, by two routes in order, and a third outcome,
  `UNASSESSABLE`, where neither route maps what is shown.
- *Constructs.* Two: how well the report's stated relationships are
  communicated, and how readable the whole output is. It marks both central.
- *Measures.* **None.** "No construct is measured by code." It says code could
  measure sizes, contrast, distances and page length, that the materials
  establish no preferred value for any of them, and that a score built from them
  "would introduce unsupported preferences".
- *Judgment.* Both constructs are for a judge, each on a scale of 0 to 4 with an
  anchor for every score, each page and width scored apart and not averaged.
- *Viewports.* 375 and 1440, labelled an operational choice.

**What follows, which the specification says itself.** "Both passing gives no
direction because neither receives a code construct vote", and "That limitation
is intentional." Under the registered rule, with the owner's ruling that a
judged construct gives no vote, a pair in this replication can be decided only
by fidelity, and "Decision rule and claim" says a fidelity-decided pair says
nothing about presentation. The judged scores are reported beside that.

One of the four checks made before any arm runs is construct coverage, which
fails when "measured constructs omit what the deriver marked as central". Both
constructs are marked central and neither is measured. That check is the
reviewer's to assess at stage 7, not the author's. If it fails, the registered
consequence is that the result is reported as inconclusive about improvement,
with the measurements still reported, and that would be known before an arm is
launched.

Four things together produce this: the instructions told the deriver that a
judged construct gives no vote; the instructions, in wording nobody ruled on,
give a vote only where a construct has a supported direction; the deriver found
no quality of this screen for which the brief supports a direction that code
could measure; and the registered rule counts votes. The author changes none of them, and by the
plan's rule nothing is put to the deriver again because of what a construct is
or which way it points. What is done with this is the owner's.

**For the reader, and with no power over anything:** the author, who knows the
treatment, notes that both constructs lie where a treatment of this kind acts,
in how content is grouped and how readable it is, and that the specification
moves the only decisive stage to where it does not.

**What this changes in the stages that follow.**

- Stage 5 has no measure of a construct to write. What is written as code is the
  three fidelity tests. The protocol for reading a page back leaves the writer
  of that code a choice the specification names: which structures the reader
  supports. A page it cannot map is `UNASSESSABLE`, and by the instructions that
  fails the builder. So the choice can decide a pair, and it is the author's
  unless it is taken from the author. It was not put to the reviewer as a
  question. The audit raised it unasked and says the specification must define
  it.
- The capture must take 375 and 1440. As built it takes 1280 and 400. Open, as
  above.
- The specification says what it cannot assess from one render: a lookup by
  either identifier, extra keys, the output forms, and whether a page depends on
  anything outside itself. It claims no complete test of self-containment.

### Stage 4: the reviewer's audit, 2026-10-05

Before it was sent, the owner was told what the specification says and what
follows from it, and was asked how to go on: the audit as planned, the audit
with one more question (whether the specification's reasons for measuring
nothing by code hold), or a stop. The owner chose the audit as planned.

**The send.** One package, built by the builder: the audit's wording (1475
bytes, the plan's, with two questions added: one on the fidelity dimensions,
because the owner ruled that the reviewer audits them, asking also whether code
could carry each test out; and one asking what the reviewer would want to know
that is not there); the frozen instructions; the brief; the two data files; the
specification; and the dispatcher's closing lines. 48,519 bytes, SHA-256 `1d064641…e71e`;
the consent carried `ad0e7168…cf14`. Critique mode. The owner consented from the
file. The plan's list for this package did not hold the instructions. The author
added them so that the reviewer could see the rule the deriver wrote for, and
said so before the question.

The reviewer has therefore now been sent the frozen bytes of the instructions,
as context for the audit and not for review. That overtakes the owner's ruling
that they would not go to the reviewer a third time, the paragraph "What the
reviewer did not read" above, and the note in the log of what was not sent,
which are true only up to this send.

**The reply.** Dion `tests/fixtures/design_seed_replication/audit.md`, 14,586
bytes, SHA-256
`216c086e7a7948f075057050a8bd0f036e2d8bfb23aef6344fbaf53c9bb23d00`, as it came.
Cells pin it and find no recorded term. The reviewer's decisions stand.

**What it decided,** in the author's summary. The file is what counts.

| Thing | Decision | Its reason, shortly |
|---|---|---|
| Part 1, decisions | correct | retrieval is the evidenced purpose and no other |
| Part 2, requirements | all kept | incomplete as a list: the stated relationships, the stated meanings of values, and that structure and membership are kept, should each be a named requirement |
| Fidelity: complete, accurate content | kept | code can carry it out by the first route; the second route is not yet defined enough |
| Fidelity: correct retrieval state | kept, to be merged into the first or marked a redundant check | it follows from comparing the whole inventory |
| Fidelity: displayed and not hidden | kept | only partly specified: clipping, covering and what is readable are not defined |
| Construct A, relationships communicated | kept, narrowed | the part on the metrics repeated in two sections is cut as a scored relationship; the two parts for the not-found page are merged |
| Construct B, readable output | kept, all its parts | |
| Central | both, at the level of the construct | |
| Room for two pages that pass fidelity to differ | yes, on both | less on the not-found page, and not none |

Its verdict on the whole: "largely sound on content fidelity and restraint about
reader tasks", and "The specification should be retained after these
corrections."

**What it found wanting,** which bears on what can be built.

- The second route for reading a page back "describe[s] a strategy, not
  sufficient matching rules". The specification must say which structures are
  supported, how a path is rebuilt, how repeated values are told apart and how a
  conflict is resolved. "Promising that an extractor will publish these rules
  later does not supply them now."
- A box that is laid out is not text that is seen: another element can cover it.
  How partial clipping is treated is not settled.
- A region that scrolls inside the page needs a rule.
- Because `UNASSESSABLE` fails the builder, "extraction coverage materially
  affects the comparison. That limitation must not be mistaken for proof that
  the page violates the brief."
- The lowest anchors of both rubrics partly describe fidelity failures, which a
  page that passed fidelity cannot show.
- It would want to know the resolution and scaling of the images a judge is
  given, and a rule for scoring groups of very different size alike.
- Which changes of representation the reference form allows is not stated.
- Labels, types, units and associations belong within content fidelity and
  "need explicit tests there".
- The ordering of the eligibility counts with their total, and the relationship
  of the restricted count to its warning, are not carried into the rubric.
- For wider coverage it would want data files with extra keys, null fees and no
  FX section, the optional optimiser fields, earlier weights to drift from, and
  a restricted instrument.

**On measuring nothing by code,** which the reviewer was not asked. It says the
specification's conclusion, that two builders who both pass fidelity get no
direction, "is valid under the supplied comparison rules", and that scores by a
judge alone are permissible. It also says the specification "overstates the
reason when it implies that these materials cannot support any directional code
proxy. A narrowly defined ordering measure could be grounded in the explicit
order requirement", and calls that "an option, not an obligation". Nothing is
done with that here. It is for the owner.

**One finding of the audit is the author's doing and not the specification's.**
The audit says the specification points at the wrong documents for its two
pages. The specification names them by their numbers in the package the deriver
was sent, where the data files were documents 3 and 4. In the audit's package
the audit's wording is document 1 and the instructions, which the plan's list
did not hold, are document 2, so the data files were 4 and 5. With the plan's
list they would have been 3 and 4, as the specification has them. The author's
addition caused the mismatch, and the reviewer was not told. The specification
is right about what it was sent. The audit calls this "an
executable-specification error" and puts it first among its corrections.

**Not done, and why.** The plan's next step asks the reviewer for pages against
which a measure of each kept construct is developed. No construct has a
measure. What code there is to write is the fidelity tests. The audit says the
first route for reading a page back can be carried out as written, and that the
second route, covering, partial clipping and scrolling inside the page are not
yet defined; and that what the reader supports can decide a pair. Those rules
are not the author's to write. So the plan stops here, before its re-plan
point, for the owner.

### How to go on, 2026-10-05: run as registered

**This entry replaces one that stood for under half an hour.** At commit `1835f2e6`,
pushed at 21:50,
this section was headed "The registered comparison is not run" and recorded a
decision to write a replacement protocol in which a judged construct votes. That
decision is withdrawn. Nothing was built or sent under it. Why it was wrong is
below, because the way it went wrong is the thing this design is built against.

**What the owner said.** Told where the plan had stopped and given three ways on
(run it as specified, stop before the arms, change something registered), with
the author declining to recommend because the author knows the treatment, the
owner answered: "spar and get another opinion from codex, go with your final
recommendations." What follows is therefore the author's recommendation, taken
by the owner in advance. The owner did not rule on its merits and may reverse
it. The author's reason for declining still holds of the recommendation.

**First round, and what was wrong with it.** The author put a proposal to Codex
for critique (one text of 2552 bytes, written by hand, holding no file of the
project; the owner consenting; row 8 of the log): do not run it as registered;
amend so that a judged construct votes under a rule whose numbers come from the
reviewer; let a fidelity test that cannot be carried out decide nothing. Codex
ranked "amend, then stop, then run as registered", with six objections, and said
its answer "depends on information you have not supplied": whether earlier
outputs of these builders had been seen.

The author recorded the amendment as the decision without going back. A fresh
local check of that entry against the records then found:

- The author had told Codex that a pre-run check "fails". **It has not been
  assessed.** Construct coverage is one of the interpretation gate's four
  pre-run checks and is the reviewer's to assess. Read by its words it would
  fail. Its registered consequence is a label, "inconclusive about improvement",
  with the measurements still reported. It is not a stop, and the plan leaves
  going on to the owner.
- **The answer to Codex's question is yes.** The author and the owner have both
  seen the pilot's pages and its result, on this same screen. Someone who knows
  the treatment and has seen that could foresee which way of scoring favours
  which builder. Codex had made its ranking depend on this and was not asked
  again.
- The amendment would have **reversed two rulings the owner made on their
  merits** the same day, before the specification existed: that a judged
  construct gives no vote, and that a fidelity test which cannot be applied
  counts as failed. The entry did not name them.
- Codex had not been told that the reviewer said the specification "should be
  retained", nor of its remark on a code measure of ordering.
- The entry said each of Codex's six objections was adopted. Three were adopted
  only in part.

**Second round.** The author put those corrections to Codex (2587 bytes, by
hand, no file of the project; the owner consenting; row 9), with one thing more:
that under "run as registered" and under the amendment the same pages go to the
same judges with the same rubrics, and the two differ only in whether scores
become votes and in how an unassessable fidelity test is treated. Codex answered:
"No. The ranking does not survive." Its reasons, in its words:

- The amendment "now has the structure of rescuing a result". "Having the
  reviewer supply the numbers does not remove the informed choice to introduce
  those numbers and make the constructs vote."
- "The original protocol's inability to deliver the improvement conclusion you
  want is not, by itself, a defect authorizing a replacement. Its registered
  provisions expressly allow measurements without that conclusion."
- "running as registered does not discard the central evidence. It limits the
  conclusion drawn from it. On these facts, that limit is something to honour,
  not rescue the study from."
- The rule that an unassessable fidelity test fails its builder "has a real
  validity problem, but that does not make a retrospective correction clean."

Its ranking on the corrected facts: "run as registered first; a transparently
exploratory amendment second; stop last", provided the measurements remain worth
collecting.

**The recommendation, which the author now holds and the owner has taken in
advance.**

1. **The comparison is run as registered.** The registered rule for a pair
   stands, with the owner's rulings of 2026-10-05. The specification is kept,
   with the audit's decisions on it.
2. **The four pre-run checks go to the reviewer at stage 7,** as registered. If
   construct coverage fails, the result carries the registered label,
   inconclusive about improvement, and the measurements are reported.
3. **Both judged constructs are scored and reported in full,** each page and
   width apart, as the specification says. No score becomes a vote.
4. **The registered treatment of a fidelity test that cannot be carried out
   stays the primary analysis:** it counts as failed for that builder. Beside
   it, fixed now and before any page exists, a secondary analysis is reported in
   which such a test is unknown and decides nothing for the pair. It is labelled
   secondary. Any pair whose result differs between the two is named. "Unknown"
   is never reported as passed. This is Codex's proposal.
5. **Nothing is asked of the deriver again,** and no code measure is asked for.
   The reviewer called a measure of ordering "an option, not an obligation". It
   is not taken up: the author will not add a deciding measure after seeing the
   specification, for the reason that sank the amendment.
6. **What the audit says is not yet defined** (the second route for reading a
   page back, covering, partial clipping, scrolling inside the page) goes to the
   reviewer before any code is written, as the plan already says for a choice
   the specification leaves open.
7. **If judged constructs are to decide a result in later work,** this document
   is revised for that work before anything of it is seen. Not for this one.

**What this replication can then say.** How many pairs were decided by fidelity
and for which builder, with the secondary analysis beside it; and what blind
judges scored each page on two constructs the brief supports. It cannot name a
direction on presentation. That was fixed by the registration and the owner's
rulings before the specification existed, and it is kept.

**The author's slips here, for the record.** The first recommendation was written
into this document and pushed before it had been checked against the records,
and before Codex's condition had been answered. An author who knows the
treatment recommended making the instrument able to find a direction, in the
area where the treatment acts, three hours after learning that it could not. The
check that caught it was a reviewer reading the entry against the files.

### Three reviews of the code of these stages, 2026-10-05 and 2026-10-06

The code of these stages (the fixture builder, the package builder, the measuring
script and the cells that pin the kept texts) was reviewed three times before it
was pushed, each time by a fresh reviewer of the author's family that read the
code and ran nothing. Each review found something the one before had not, and
the first two found controls that did not hold. All of it is in Dion's branch
`derive-measures`.

| Review | Of | Found | Then |
|---|---|---|---|
| First | everything the branch added | 2 Critical, 12 Important, 9 Minor | Dion `38279d4`, `eb9625b` |
| Second | the first repair | 1 Critical, 5 Important, 6 Minor | Dion `868aa02`, `9da22eb` |
| Third | the second repair | none Critical, 2 Important, 10 Minor | Dion `453b5fe` |

The third repair was not reviewed. Its cells were written first and failed, and
its mutants are all killed, and that is what stands behind it.

**The package builder let through what it said it refused.** One character that
shows as nothing, set inside a word, hid that word from five of its six scans:
the store's tokens, a path, an address, a forged heading, a recorded term. The
first repair refused such characters by their kind. The second review named
characters that are letters or symbols by kind and show as nothing all the same.
A list of what to refuse grows each time someone names another, so the builder
now holds a list of what is **let in**: the ASCII that prints, Latin-1, the
dashes and quotation marks, and the arrows; within those only letters, digits,
punctuation and symbols; and only characters that compatibility folding leaves
alone, but for the ellipsis. Anything else is refused and its code point named.
A reply that holds a character outside the list cannot go into a later package
until the list is widened by a dated change. That is on purpose, and it will
happen: the list holds no currency sign and no sign for "at most".

What the list does not close, and what was done: the dashes are let in, since
every text holds them, and they are look-alikes of the hyphen that three scans
look for, so the scans read each dash as a hyphen; the ellipsis folds to three
full stops, so the scans read it both ways. A look-alike used on purpose by the
author is outside what the builder is for.

**A failed call to git was read as "no store".** In a linked worktree, which is
where this branch lives, the main checkout is the only place a store could be.
The builder now cannot check unless git answers with one line that names a
directory called `.git` that is there, and one cell asks real git in a real
linked worktree.

**The measuring script decided whether to refuse a page before the measure ran,
and never looked again.** A page could wait for the first thing done to it, ask
for another file, and still be measured. The first repair read the counts after
the measure, in the same turn. The second review said a request made a moment
later would not yet be counted, and a cell showed it: of three pages that ask at
once, 30 ms later and 300 ms later, the last two were given a value. The script
now waits the settle time again before reading. Its header says what that does
not guarantee: a request made in the last moments of that wait.

**Other things found and repaired:** the conditions a page is rendered under were
written into the output and never read back from the page; the fixture's cells
compared parsed values, where 3 and 3.0 and true are equal; the cell said to
build "beside a store" arranged nothing the project would follow; the
manifest's digest of a file came from a second read of it; a label was not
scanned as a document is; a package that could not be written whole was left
behind; the account's name and the stores had defaults that could switch a scan
off with nothing said.

**What was sent before the repairs.** Nine sends were made in these stages, of
eight packages. Seven of the eight are kept as files, and each passes the scans
of the builder as it now stands. The three that the builder built (the fixture
audit's, the deriver's and the audit's) are rebuilt by it from their kept
sources byte for byte. Every reply kept so far can go into a package. The
plan's critique, the first send, was not kept as a file and could not be looked
at again. So the controls were weaker than this document said when those
packages went, and nothing shows that anything got through.

**The counts, and what they do not show.** Cells: 161 for the builder, 16 for the
kept texts, 47 for the measuring script, 18 for the fixture. Mutants, all
killed: 92 for the builder, run on the final code; 36 for the measuring script
and 11 for the fixture, run before the third repair, which changed neither but
for a comment. A killed mutant shows a cell can fail. It does not show the code
is right: the first list of mutants was all killed too, and the builder was
letting a zero-width space through.

**Left for the plan that follows,** each named by the third review and not done:
the measuring script exits with a trace and no output if a page closes itself
during the second wait; what counts as a value it can print does not check that
a record is a plain one; how long the second wait is, is pinned by no cell; the
check that reads a package back opens it in the locale's encoding and not in
UTF-8; and the capture reads one of its three counts before its image.

### Stages 5 to 7 begin, 2026-10-06

Under the plan for running the comparison as registered. The owner answered four
questions before anything was asked of the reviewer, each put as a question:

| Question | Ruling | When |
|---|---|---|
| The audit cuts one part of a construct and merges two. Who turns that into what a judge is given | Nobody rewrites. The judging package holds the specification's parts 4 and 9 and the audit's section 3, each word for word, and one fixed sentence: where the audit cuts or merges a part, the audit governs | 2026-10-06 |
| The reviewer defines the rules the audit found undefined, and later approves the code written to them. May one party do both | Yes, stated as a limit: an error in the rules is not caught by the approval | 2026-10-06 |
| If the reviewer says the second way of reading a page back cannot be defined | Go on. Only the first way then exists, and a page not shown as JSON is unassessable: failed in the primary analysis, unknown in the secondary | 2026-10-06 |
| Who writes the pages the fidelity tests are developed and accepted against | The reviewer: development pages first, acceptance pages after the code is committed | 2026-10-06 |

**The question a judge is asked afterwards** is not written in these stages. "Two
turns", above, leaves its wording to the freeze, and the launcher refuses one that
holds a recorded term, so it cannot name what the builders differ in. The plan
for these stages first had the reviewer write it and then, for a few hours, the
author with the owner's approval, on the ground that it must name the difference.
Both were wrong about what is already registered, and neither was done: it was
left out of the reviewer's package, and the author told the owner a draft would
come and has taken that back.

**The rules the audit found undefined.** One package, built by the builder: a
question of seven items (1998 bytes), the specification, the audit and the two
data files. 42,015 bytes, SHA-256 `4bc6b211…2cff`; the consent carried
`1862f211…f128`. Critique mode. The owner consented from the file. Its first
paragraph says which documents the specification's "Document 3" and "Document 4"
are in this package, which the audit's package had not said.

The reply is kept as it came: Dion
`tests/fixtures/design_seed_replication/fidelity-rules.md`, 12,088 bytes, SHA-256
`f3e87728a70aadf87722ad5349aed3241252f0d1ba97b7fcb9a435ac966be6cf`. Cells pin it,
check it can go into a package, and find the seven answers in order. None is
"cannot be defined". It opens by saying what the rules are: "operational
conventions, not claims that the brief specifies these thresholds".

In the author's summary; the file is what counts:

| Asked | The rule, shortly |
|---|---|
| The second way of reading a page back | One grammar and no other: a single outermost `dl` of `dt` and `dd` pairs; a nested `dl` for an object; an `ol` for a list; a table with one header row for a list of objects; and every value written as a complete JSON token, so that text is in quotation marks and nothing is `null` unless it says so. Anything else is `UNASSESSABLE`. A path is matched by where it is, never by its value |
| Covering | By the ink of the text, not by its box. A value is shown only if every glyph of it has some ink that nothing later painted covers whole. Not one glyph may be covered whole |
| Clipping | Not one sample of ink may be clipped. No tolerance by geometry |
| Scrolling inside the page | A new status, `LAID_OUT_IN_SCROLL_REGION`: it meets the display requirement under conditions, and is "not a claim of observed visibility" |
| Changes of representation | Spacing, styling, the order of an object's members, and the grammar above. Not thousands separators, rounding, a percent sign in place of a fraction, or a label in other words |
| Tests within content fidelity | Labels, types, values with zero tolerance, units, the sign of drift and of delta, associations by the whole tree, and that only the proposed metrics exist |
| A judge's images | One captured pixel for one CSS pixel, never resized. A page taller than 1600 pixels is cut into crops of 1600 with 200 of overlap. If the judging system "cannot consume these pixels without automatic reduction", the assessment is `NOT_SCORED` |

**What follows from the rules, in the author's reading.** Three things, none of
them decided here.

- A page that is neither plain JSON nor written in that one grammar is
  unassessable, and in the primary analysis that fails its builder. The audit
  had said that what the reader supports "materially affects the comparison".
  The secondary analysis is what shows how much.
- For covering and for clipping the rules say what to do when the harness cannot
  find out: `UNASSESSABLE`, and of covering, "not `PASS`". Whether the harness can
  find out, from one render in a browser, is not known. It is found by building
  against the reviewer's pages.
- A judge here is a session that reads an image file. Whether an image of 1440 by
  1600 pixels reaches such a session with no reduction is not known, and has to
  be measured before any judging package is built. If it does not, the rule as
  given scores nothing, and the rule goes back to the reviewer with what was
  measured. The author does not pick another size.

**The capture takes its widths from the caller,** which closes the open item above:
it had two of its own, the pilot's. It has no default, so that a caller who leaves
them out does not get the pilot's without knowing. The count of pages, which it
read before its image, is now read after it with the other two, and after the
settle time again: a page that opened another page when the capture added its
style was photographed and its image kept, and a cell showed it. The limit a
cell pinned at 750 ms after load has moved with that and is pinned where it now
stands: a page that waits past both settles is still not refused.

### The pages the tests are developed against, and what the reviewer settled, 2026-10-06

Three more sends to the reviewer, each built by the builder, each with the
owner's consent from the file, all in critique mode. They are rows 2 to 4 of the
stage's log.

| What was asked | Bytes sent | Reply kept as | Reply, bytes and SHA-256 |
|---|---|---|---|
| A small data file of the reviewer's own and twenty pages of it, one for each case, each with the status the rules give each test | 54,357 | `validity/development/pages.md` | 21,911, `985c468f…e62c` |
| Six things those pages marked as not settled by the rules | 36,360 | `fidelity-settlement.md` | 7876, `83ced066…d1e2` |
| Five things still undefined when the code was about to be written | 44,370 | `fidelity-further.md` | 5760, `ffab27b1…d149` |

All under Dion `tests/fixtures/design_seed_replication/`. The plan allowed one
further send for a gap and gave a second to the owner. The owner was told the
third send was a second one and approved it.

**The pages are of a small data file, not of the data file of stage 2.** That
file is 7 KB, and twenty pages of it in the rules' grammar would not have come
back whole. The author asked for a small one and said why to the owner before
the send. The reviewer chose what it holds. The pages an arm builds are still
tested against the two data files of stage 2, and two of the twenty pages are of
the not-found one.

Each page, the data file and the list of expected statuses are cut out of the
replies by a script, and cells cut them out again and compare, so none can be
changed by hand. The pages were read as text before they were filed: no script,
and no reference to anything outside the page.

**The reviewer marked eighteen of its own sixty statuses "UNSETTLED"**, on twelve
pages, saying its rules did not determine them. It then settled them. In the
author's summary; the files are what count:

- Extraction reads text that is laid out, before clipping and covering, and
  leaves out text hidden by `display`, by `visibility`, by an opacity of zero or
  in a closed disclosure. So a hidden value is missing to the content test, and
  a clipped or covered one is not.
- A leaf that is not exactly one JSON token (a blank, a number with a thousands
  separator) makes content `UNASSESSABLE`. Never `FAIL`: nothing is repaired.
- The state test "copies content". It decides nothing of its own.
- Display is assessed apart from content: a proved failure first, then
  `UNASSESSABLE`, then `PASS`.
- The first way of reading a page back is one `pre` element whose text is the
  whole stored document as one JSON object.
- Controls inside a value are unsupported. Of generated text only literal strings
  are read. The number an ordered list shows is never part of a value.
- Text with no visible fill, or of a font size of zero, is hidden text. Text laid
  out where the document cannot be scrolled to is a display failure.

**And one rule that decides more than the rest.** Of its first answer on text
outside the mapped structure the reviewer said: "The previous classification of
outside text was not executable." Its rule now: after mapping, any text outside
the mapped structure other than white space makes content `UNASSESSABLE`. "Thus
an outside heading 'Report' is **not proved invented**, but it is also **not
automatically ignored**." One status changed by it: the page that shows the
not-found file and a report beside it is unassessable, where it had failed.

**What follows, in the author's reading. The owner is told; nothing is decided
here.**

- A page is assessable on content only if it shows the stored document as one
  `pre` of JSON, or in the one grammar of definition lists, ordered lists and
  tables with every value written as a JSON token, **and shows no other text**:
  no heading, no caption, no sentence. Nothing tells a builder so. The brief asks
  for a page that shows a stored report.
- So for most pages a builder would make, content is `UNASSESSABLE`. In the
  primary analysis, as registered and as the owner ruled, that fails the
  builder. Where both builders of a pair are so, the pair has no direction.
- **Where one builder shows nothing but the JSON and the other shows the same
  content with a heading, the primary analysis decides the pair for the first.**
  It would favour the plainest page for a reason that is the reader's and not the
  brief's. The audit had said extraction coverage "materially affects the
  comparison" and "must not be mistaken for proof that the page violates the
  brief". The secondary analysis, in which unassessable is unknown, is where that
  shows: every pair whose result differs between the two is named.
- The owner ruled on 2026-10-06 to go on if the second way of reading a page
  could not be defined. It was defined, narrowly, and the consequence is of the
  same kind. The ruling is read as covering it. It is the owner's to say
  otherwise.

### The fidelity tests, the judging package and the pair decision, 2026-10-06

The owner, told the consequence of the rule on outside text and given three ways
on, ruled on 2026-10-06: "Build as ruled". What follows is built to the
reviewer's rules as they stand. All of it is on Dion branch
`fidelity-and-judging`, commits `1a1fac2` to `3663a87`, local and not pushed.

**The three tests.** `tests/design_seed_pilot/fidelity/` and three measures:
`fidelity-content`, `fidelity-state`, `fidelity-displayed`. Each gives `PASS`,
`FAIL` or `UNASSESSABLE` and what stands behind it. The measuring script hands a
measure the data file a page is of.

- Content reads a page by one of two routes and no other: one `pre` whose shown
  text is the whole stored document as JSON; or one outermost `dl` and the
  grammar under it, every leaf one JSON token. Text that is hidden is not read.
  Anything the page shows outside the structure makes content `UNASSESSABLE`. A
  proved failure comes first, then anything unresolved, then `PASS`.
- State copies content, as the reviewer settled. It is a measure of its own
  because the specification names it, and it is not counted again for a pair.
- Display asks of every glyph of every required key and value whether any of
  its ink reaches the picture and whether any of its ink is clipped. The page is
  painted twice with nothing changed but the colour of the glyphs asked about,
  and a pixel that differs is that ink. Several ways of painting tell covering
  from clipping from a scroll region. Where clipping cannot be taken off without
  the layout moving by other than whole pixels, the answer is `UNASSESSABLE`: the
  rules allow no tolerance.

**Against the reviewer's twenty pages, at 375 and 1440, all three tests give the
status the reviewer gave, and for display the note too.** That is 120 of the 122
cells of `test_fidelity_pages.py`. The author wrote the tests and did not write
the pages or the statuses.

**What that does not show.** The twenty pages each turn on one thing; the rules
say much more. 174 further cells (`test_fidelity_rules.py`, 114 of content and
60 of display) are each one sentence of the rules on a page the AUTHOR wrote,
with the status the author reads the sentence to give. They show the tests do
what the author read. They cannot show the author read the rules as the reviewer
meant. The reviewer's acceptance pages are for that; see below.

**Where the rules say nothing, or can be read two ways.** Twenty-seven places,
listed in `fidelity/README.md` for the reviewer to rule on. Each goes towards
`UNASSESSABLE` unless the list says otherwise: a `FAIL` claims proof, and none of
these is one. None was chosen to favour a page. The ones most likely to matter
on a page a builder makes:

- a `text-transform` on a value: the rules say to read text nodes and to keep a
  string's case exactly, and not which gives way. Text a transform would change
  is not read;
- a scroll region inside a card that clips: with the region stopped clipping,
  what is out of view spills and the card cuts it. Whether the card would cut it
  once it is scrolled to is not told by where it lies now. Unassessable;
- what counts as text outside the structure: text, what a style sheet writes,
  any control, a picture shown as its `alt` words, any frame. Not a picture or a
  canvas, so words in a picture are not seen;
- the braces and commas of a `pre` are not "required" for display;
- a page with a shadow tree anywhere is not read at all.

**Four things measured on the way, each of which changed the code.**

1. One pair of pictures cannot carry three sets of glyphs, one to a colour
   channel. The browser shapes a glyph's soft edge by how light its colour is, so
   a glyph turned from black to green changes red at its edge, by up to 43 of
   255. It made the covered glyph of the reviewer's page l pass. One set of
   glyphs to a pair.
2. The browser gives back `attr()` in a computed `content` as the text it found.
   A literal string cannot be told from one built from an attribute, so where any
   style sheet of a page uses `attr()`, every generated string on that page is
   unsupported.
3. **Taking a picture of a whole page changes how this browser lays out its
   text, once.** A line of 87 characters of 13px monospace was 678.72 px wide
   before the first such picture and 680.92 px after it, at both widths, and
   stayed so. Time alone did not do it, nor a picture of the viewport. The first
   picture already shows the changed layout (its pixels equal the second's
   wherever both have them) and is made the size the page was before. **So the
   capture's one picture, which is what a judge is given, was cut short on a page
   wider than its viewport:** two columns of pixels on the page that showed it.
   `capture.mjs` now takes a picture, throws it away and keeps the next. A cell
   holds it: a page whose last 20 px are blank showed 18 of them and shows 20.
   The display test does the same before it reads where any glyph lies. This
   reopens stage 5's capture, which the entry above had closed.
4. Found by asking the tests about the data file of stage 2 itself, shown as a
   `pre`: it passes all three at both widths, 4,230 glyphs in three to five
   seconds a test. Item 3 was found by this; before the fix the display test did
   not run on it at 375.

**Does a judge see an image at the size it was captured? Measured, in part.** A
headless session with the judge manifest's own flags (CLI 2.1.285; the session's
own `init` gives the model as `claude-opus-5-5`) was asked to Read four PNGs:
1440x1600, 375x1600, 1440x1500, 1440x900. For each, the image in the Read
tool's result is the same bytes as the file. So the CLI hands a crop on
unchanged. **Not measured: what the API does with it after that.** Its vision
page, read the same day, says images over a model's limits are downscaled, and
gives the limits as 2576 px on the long edge and 4784 visual tokens for "Claude
4.7 and later models", and 1568 px and 1568 tokens for all others. By that rule
a 1440x1600 crop (3016 tokens) is not reduced on the first tier and is on the
second. So the reviewer's rule 7 can be met as written only while a judge's
model is of the first tier. The launcher records each judge's model. Which
models may judge, and a check of the recorded model against that, are the
freeze's. Evidence, outside the repository: `read-measure/` of the stage's
evidence directory.

**What a judge is given** (`build_judging_package.py`). The owner ruled that
nobody rewrites the rubric. `INSTRUCTIONS.md` is, in order: the specification's
parts 4 and 9; the audit's section 3; the one sentence "Where the audit cuts or
merges a part, the audit governs."; and the reviewer's rule 7, each cut from its
kept file by its heading and each kept file, the sentence too, checked against
its digest. It is 11,738 bytes, the same for every page of every builder,
SHA-256 `cbb45433…0dbd`.

Departures from the plan, which said "and nothing else". The owner was told the
first two before the reviews; all go to the reviewer with the code.

- **Rule 7 is in the instructions.** It says what to do with a page cut into
  several images ("Do not score crops independently or average crop scores"),
  and only a judge can do that.
- **Five lines of `INSTRUCTIONS.md` are the author's:** four headings (`# From
  the specification`, `# From the audit of the specification`, `# Which
  governs`, `# The images`) and "The images of this page are listed in
  IMAGES.md, in order." Without them a judge cannot tell which of three texts is
  the audit.
- **`IMAGES.md` is the author's words too:** a table (image, page and width,
  size of the whole page, rows shown); the line "Stored values with text inside
  a region of the page that scrolls, some or all of it out of view:" over the
  paths the display test found so; and, for a width at which that test did not
  pass, "not known for every stored value; the test that looks could not examine
  them all". Rule 4 has every stored value missing from the images reported.
  Only a pass has examined every value, and on most pages a builder makes the
  display test maps nothing, so silence would have read as "none scrolls".
  These words are pinned by a digest of their own, `0dec3d5b…0f6f`.
- **The display test's output is required at both widths** before a package is
  built. Whoever builds a package knows whose page it is, and does not choose
  whether a judge is told what is in no image.
- **A page is named F or N** in `IMAGES.md`: rule 7 asks for a "page–width
  identifier", and the rubric reads different things on each.

An author who is not blind wrote those words. They say where a text is from and
what the images are, and nothing of a builder.

Images are the captured pixels and nothing else of the capture's files: every
picture is read to its pixels and written again from them, so that no text chunk
or trailing byte of a file reaches a judge, and a picture that is not whole is
refused. A page of at most 1600 rows is one image; a taller one is cut by rows
as rule 7 says. **A page wider than its window gives a picture as wide as the
page, and goes at that width; the rules do not speak of such a page,** and a
`pre` of JSON at 375 is one. That too goes to the reviewer. How many judges
score a page, in what order, and what they are asked afterwards remain the
freeze's.

**What fidelity decides for a pair** (`decide_pair.py`). Fidelity decides a pair
or the pair has no direction; no construct gives a vote. Content and display are
counted. Primary: a test that could not be carried out is failed. Secondary: it
is unknown. A pair is exactly four rows for each builder: F and N at 375 and
1440.

Three readings, each where the registered words or the plan leave a case open.
The owner was told the first before the reviews.

- "Such a test is unknown and decides nothing for the pair": if one builder has
  an unknown test and the other fails outright, is the pair decided for the
  first? **It is read as no: a builder with an unknown test is never the one a
  pair is decided for.** The other reading drops the unknown test and decides on
  the rest, which would favour a builder whose content could not be read. The
  entry "How to go on" says "'Unknown' is never reported as passed", and Codex's
  own words were that it "should not silently become 'passed'". So the secondary
  differs from the primary in exactly one case: one builder unknown, the other
  passing everything.
- **`NOT_APPLICABLE` is not a status of a fidelity test here, and is refused.**
  The plan's table had it as "never a failure". It is the specification's word
  for an assessment of a construct that does not apply to a page; no fidelity
  test gives it, and the reviewer settled that display is "never
  `NOT_APPLICABLE`". Read as a pass it let a builder with no test at all be the
  one a pair was decided for.
- **Two analyses "differ" when one decides and the other does not,** or they
  decide for different builders. Two that both give no direction, for different
  reasons, do not differ: neither names a builder.

A page that was refused or could not be rendered fails in both, whichever of the
three tests did not run. `status_of` says what one run of the measuring script
comes to: its exits 3 and 5 are `RENDER_FAILED`; any other exit but 0 is a fault
of the run, not a status of the page, and is an error. Nothing yet builds the
table of a pair from the runs: that is the run's own plan.

**Two reviews of this code, by reviewers with no part in it, before anything was
run over the acceptance pages.** Both read-only. What they found, and what was
done:

- **The acceptance run could not tell a dirty tree from a clean one** (critical).
  It asked git from its own directory about paths written from the top, so the
  answer was always "clean", and its results could have named a commit that was
  not the code that ran. Fixed, with what else that review found in the same
  script: the commit is read before and after; a record is written before the
  first page is asked, so a run that broke off is not made again unseen; every
  filed file and each data file is held to its digest list; the digest of each
  page and of the data each test was handed are kept with the results.
- **The fidelity tests said FAIL, or PASS, on readings that were the author's
  and not the rules'** (two critical, seven important). A `text-transform` on a
  value; a scroll region inside a clipped card; hidden text beside a shown
  token; a key that could not be read; a wrapper around a nested structure; a
  structure of another kind than is stored; a key in a `pre` in another case;
  an offset before the page begins on a page that runs right to left. Each now
  goes to `UNASSESSABLE`, or to what the settlement's own words give, and is on
  the list for the reviewer. Where the reviewer's words did decide (a structure
  in a leaf is "parsed as a container"), the code now does that.
- **Things the tests did not see:** zero alpha in a colour not given as `rgb`;
  an opacity of nought by a filter; a pseudo-element's own paint; text painted
  by a background cut to its shape on an element above; `attr()` by way of a
  custom property. Each is now seen.
- **Three ways a measure failed where nothing was the page's fault:** a page
  that scrolled itself; brackets nested thousands deep; a page that changes
  while it is read. A failed measure counts against a builder in both analyses.
  None of the three fails now.
- **The pair decision and the package builder,** as the paragraphs above now
  describe them. Before the review a state that did not run beside a content
  that passed was read as a pass; a pair could be decided on any rows both
  builders happened to have; a file handed to the package builder could write a
  heading into what a judge reads.

After the fixes the reviewer's twenty pages give the same 120 statuses.

**The acceptance pages are asked for and not yet read.** Row 5 of the stage's
log. The request went with the reviewer's three rule replies, its small data
file and the not-found file: 29,015 bytes. **It went without the specification,
the audit, the found data file and the twenty pages,** and says so. With them it
was 89,727 bytes, and a package has to be shown whole in the question that asks
the owner's consent; that one could not be. So the reviewer wrote these pages
from its rules alone, which it had not done before. The reply is kept, 14,357
bytes, SHA-256 `ad9293a8…89e2`: 22 pages, each with its line. Its form differs
from the one asked for (the number of a page stands on the line before its
block), seen from the fence lines alone, and the filing script reads both. The
author has not read the pages and will not until the mutant run on the final
code is done. No code is changed for a page's sake after the one run over them.
**The code did change after the pages were asked for and before they were
read:** the two reviews above. The reviewer is told so with the results.

**Names in the plan that did not survive the rules:** no
`fidelity_inventory.mjs` (the inventory is the tree `json_tree.mjs` reads); three
test files and three mutant lists where the plan had one of each.

### The gate, the one run over the acceptance pages, and the reviewer refuses two tests, 2026-10-06

**The reviewer refused the content test and the display test.** By the plan a
refused test is not used, and a refusal of the content test is one of its four
stop conditions: the owner is asked. This entry is the record the owner is asked
on. Dion branch `fidelity-and-judging`, commits `3663a87` to `ee8d239`, local
and not pushed.

**The gate, on `3663a87`,** the last commit that changed a file a list mutates,
from a frozen copy of it:

| List | Run against | Mutants | Killed |
|---|---|---|---|
| `fidelity-pure.tsv` | 100 cells | 38 | 38 |
| `fidelity-content.tsv` | the author's 114 cells of content | 66 | 66 |
| `fidelity-display.tsv` | the author's 60 cells of display | 50 | 50 |
| `judging-package.tsv` | 100 cells | 37 | 36 |
| `decide-pair.tsv` | 50 cells | 27 | 25 |
| `measure.tsv` | 59 cells | 44 | 42 |
| `capture-policy.tsv` | 72 cells | 25 | 21 |

Three of the nine survivors were faults no cell could see. One cell of the
package builder could not fail: it replaced `json.dumps` for everything, so its
own helper failed before the build began and it passed without a build. For the
other two there was no cell: none gave a run that had failed, or had not said
it extracted, a status in what it printed. Cells were mended and added (`61b6ab4`, `8a79ebe`), and both
lists run whole again on `a0f2414`: 37 of 37 and 27 of 27 killed. Two survivors
of `measure.tsv` stand
behind a second check that catches the same fault and are left, named in the
README. The four of the capture list are the four already recorded. Ten branches
of the display test have neither a mutant nor a cell that names their reason;
`mutations/README.md` lists them as untested.

The two fidelity lists were run against the author's cells and not against the
reviewer's pages. A count above says a fault is seen by the author's reading of a
rule, and no more than that.

**That gate was not the repository's own, and the tree was red under it.**
Dion's `scripts/ci.sh` was first run on this branch on `95a2c9e`, after the
refusals. One cell failed: `build_fixture.py`, held to a digest frozen with the
pilot, had changed. Commit `216e937` of 2026-10-06 ran the formatter over the
directory, and twelve files it had no business with were rewritten. Every commit
from there to `95a2c9e` carries them, the commit of the acceptance run among
them. None of the twelve is a file of the fidelity tests, the judging package or
the pair decision, so the code that run asked is unchanged by it; each is
restored to what it is on main (`e56b23f`). The entry above says "after the
fixes" of a gate that never ran the repository's cells. The mutant lists and the
cells they name were the whole of it.

**The acceptance pages.** 22 pages. The reviewer wrote them from its rules
before the code was final: its reply came at 13:19 on 2026-10-06, and the two
reviews changed the fidelity code after that (`9263bb6`, `3663a87`, 14:18). The
pages were kept unread through that, and until five of the seven lists had run
on the final code: the three of the fidelity tests, the package and the pair.
Then they were filed as they came (`6b00904`, 15:10) and run. **The lists of
the measuring script and of the capture finished after the run,** at 15:34, on
the same copy of `3663a87`; every acceptance run goes through the measuring
script. No code changed between, so no result is affected, and "kept unread
until the gate was done" would not have been true. The form of the reply (where
a page's number stands) was seen at 13:20, from its fence lines, when the
filing script was made to read it. Every test was asked about every page once,
at 375 and 1440, from that commit with a clean tree. `RESULTS.json` holds what each
said beside what the reviewer expected.

- Content: the expected status in 44 of 44 runs.
- State: the content test's status in every run, which is also the status the
  reviewer expected of it in all 44.
- Display: 42 of 44. Page 12, a value a style sheet writes as literal strings,
  was expected to pass and is `UNASSESSABLE` at both widths: "part of it is text
  a style sheet wrote, which cannot be examined glyph by glyph".

No code was changed after that run.

**What was sent for approval.** Two packages, because one that holds the rules
and the code of all three tests cannot be shown whole in the question that asks
the owner's consent. Rows 6 and 7 of the stage's log.

- Content and state, 64,059 bytes: the request; the reviewer's three rule
  replies; `extract.mjs`, `compare.mjs` and `content.mjs` as they ran, but that
  five comment lines of the first (they name the directory the rules are kept
  in, which holds a recorded term) are left out and one line of the second (a
  pattern the package builder takes for a path) is replaced by a note, both said
  in the request; and what the content test said of the 22 pages.
- Display, 64,995 bytes: the request; the three rule replies; `display.mjs` and
  `ink.mjs` as they ran; what the display test said of the 22 pages.

**Not sent.** The first request names as left out `snapshot.mjs`, which
collects from the browser the facts the reading turns on, and `json_tree.mjs`.
The second names the reading of a page's structure and `png.mjs`. Both name the
list of twenty-seven places where the rules are silent, which was to go as a
third package. **Left out and named in neither request:** `measure.mjs`, the
script that renders a page and calls a test, and `world.mjs`.

**What the reviewer answered.** Both replies are kept as they came, in Dion
under `validity/approval/` with their digests, and a cell holds the verdicts to
them. Its last lines, word for word:

> content: REFUSE, because the implementation contains unsupported status rules
> and extraction departures despite matching all 44 acceptance runs.
>
> state: APPROVE, because copying content’s status exactly implements the state
> rule, although this does not authorize using the refused content test.
>
> display: REFUSE, because the implementation can issue unsupported PASS and FAIL
> verdicts and replaces some explicitly required failures with UNASSESSABLE.

Of page 12 it said its own expected `PASS` was wrong and the test's status
stands, and: "The disagreements in Document 7 do not themselves justify
refusal." It refuses over the code read against the rules.

Content, twelve places, a defect in what is published, and contracts of the
files it was not sent:

- **Four where the reviewer itself says its rules do not settle the case,** and
  the code chose: a key in a `pre` that differs only as a label may; a
  `text-transform`; white space before a disclosure's summary or in it; a label
  that matches no stored key taken as possibly a missing key's.
- **Four where it says the rule speaks and the code does otherwise,** each a
  choice the author had on its own list as a place the rules are silent, which
  they were not: `attr()` anywhere on a page making every generated string
  unsupported ("the rule concerns the participating pseudo-element's content
  form"); controls and frames counted as text outside the structure ("the rule
  enumerates eligible textual contributions"); more unmatched labels than
  missing keys taken as proof of an invented member, "for which rule 1 requires
  `UNASSESSABLE`"; a shadow tree anywhere stopping the reading, which "can
  suppress a proved comparison failure in an ordinary `pre`".
- **Four the author's list does not name as choices:** a `br` adds a line break
  without the hiding rules being applied to the `br` itself; hidden text beside
  a structure makes it unsupported, where the settlement has hidden characters
  absent from what is read (the list names text beside a structure, and not
  that hidden text counts); a `colgroup` is passed over unread; a string a style
  sheet writes is not decoded by every rule CSS has for one.

Display, fourteen places:

- seven are about the evidence and not about a branch: a grapheme cluster is not
  a glyph; a glyph given another colour is not its own ink, alpha or stroke; a
  difference of eight-bit colours is not an exact measure of ink or of alpha; the
  render with covers off changes more than what covers; the margin in which ink
  is looked for is not proved to hold it; two pictures are not proved to differ
  in the glyphs' colour alone; a movement within 1/128 px is taken as whole,
  where rule 3 allows no tolerance;
- six are about statuses, three of them resting on evidence too: where no route
  reads a page the test returns at once and looks for no failure, though the
  settlement allows one that is "independently attributable"; a glyph with no
  ink while clipped fails without its ink being set side by side; where a glyph
  lies is taken from its box and not its ink; the far edges have a pixel's leave
  the rules do not give; ink cut by another clip while out of view in a scroll
  region is `UNASSESSABLE` here and `FAIL` by rule 4; a glyph covered whole in a
  scroll region has no failing branch;
- one is about what is reported and, in its words, "does not necessarily change
  the aggregate display status": text shared by several stored paths is
  reported for one of them.

It also says two things for the code. "The generated-text fallback and
conservative uncertainty for unsupported rendering situations are not themselves
violations." And of a scroll region inside another, that rule 4 does cover it,
that a harness unable to establish the ink may still return `UNASSESSABLE`, and
that the code's comment saying the rules do not speak of nesting "is incorrect".

**One finding reverses a change made on the way.** Ink cut by another clip while
out of view in a scroll region failed at first. One of the two readers who read
the code before the acceptance pages were read held that the rules do not say
at which scroll position "all other clips still apply", and it was made
`UNASSESSABLE`. The reviewer has it fail. A reader of the author's family read
the rule one way and the rules' own writer reads it the other; the entry above
recorded the change as a repair.

**What the refusals come to, as the plan stands.** A refused test is treated as
a rule that cannot be defined: every page is unassessable on it. With content
and display both refused, every builder fails both in the primary analysis and
is unknown on both in the secondary, so every pair has no direction in both,
whatever the pages are. No construct gives a vote. **As it stands the instrument
would decide nothing, and that is known before any arm is run.**

**What the author can and cannot say about the findings.** The author is not
blind, wrote the code, and is not the one to weigh a refusal of it. Three things
are fact:

1. The acceptance pages did not find these. Content and display agreed in 86 of
   88 runs (130 of 132 with state), and on the other two the reviewer withdrew
   its own expectation. Everything the reviewer refuses over it found by reading
   the code.
2. Some findings say the package does not establish a thing which a file not
   sent would have shown or denied: that the measuring script stops motion
   before any picture is taken; how the page-wide `attr()` flag is found and why
   (the browser gives back the text and not the form); which elements the
   collector walks. The reviewer said so itself: "Findings about the omitted
   extraction and pixel-reading implementations cannot be established from this
   package." Whether any finding would fall with those files is not known.
3. Rule 2 says "Use the browser's text paint operations and paint order from the
   captured render", and has `UNASSESSABLE` where the harness "cannot obtain
   sufficient paint information". This code takes pictures and compares them.
   The entry above said so, and so did the request.

And two things are the author's reading, written before the reviewer was asked
what it could approve, and no more than that. The reviewer's pages were a much
weaker test of this code than the reviewer reading it; the plan ranked neither,
and had the pages' results go with the source. And the seven findings about
evidence are not mended by changing a branch: they ask for another kind of
evidence, or for `UNASSESSABLE` wherever a picture proves nothing.

**The owner's answer, 2026-10-06: "Ask what is approvable".** One further send,
no code changed: row 8 of the stage's log, 54,156 bytes, with consent to that
text. It held the reviewer's three rule replies, its two refusals, and the list
of twenty-seven places, which it had not seen. It was asked for the rule at each
finding and each place, which evidence for display it could approve, and what it
would need to be sent.

**What the reviewer answered.** Kept as it came, 18,388 bytes, SHA-256
`1fc01491…2a2c`, and in Dion under `validity/approval/`. It opens: "These are
implementation rules for a rebuild, not approval of the unseen code." Its last
lines:

> content: CAN BE APPROVED IF the rebuild implements these settled extraction,
> comparison, precedence and reporting rules and supplies the complete collector
> and dependency evidence for review.
>
> display: CAN BE APPROVED IF every categorical verdict has sufficient attributed
> rendering evidence under these rules, unresolved checks abstain, and
> independently proved failures retain precedence.

- **It is a fourth reply of rules, and it amends the first three.** A key in a
  `pre` is compared exactly, and another spelling fails. In the grammar a label
  that matches no stored key is unresolved, "a new conservative amendment":
  never an invented member, never proof that a member is absent, and nothing is
  inferred from how many there are. A `text-transform` that changes what is
  shown, or cannot be shown to leave it alone, is `UNASSESSABLE` for labels and
  generated text as for values. A shadow tree stops nothing elsewhere on a page.
  What is published for an occurrence grows: every container, every unresolved
  claim, node identities with character ranges, exact decimals.
- **Of the twenty-seven places:** ten as done (4, 7, 8, 10, 11, 13, 18, 19, 20,
  23); ten otherwise (5, 6, 14, 15, 16, 21, 24, 25, 26, 27); and "Places 1–3,
  9, 12, 17 and 22 are settled by section 1", its rules for the findings. The
  reply does not say how those seven compare with the code. The author reads
  each as differing from it in some part, though not in every part: a move of
  other than whole pixels stays `UNASSESSABLE`, as in place 22.
- **Display evidence.** Pictures compared "can be approved only as a restricted,
  abstaining method": an ink-based `PASS` or `FAIL` needs guarantees held apart
  from the pictures (the glyphs the browser shaped, their whole ink, alpha kept,
  exact registration, proof that rounding to eight bits hides nothing), and
  "Aggregate `PASS` requires every required check to be established." The
  browser's own paint record, which the author had put to it as a possibility
  and not tried, "is a potentially approvable basis, but the description alone
  is insufficient"; it would have to give shaped glyphs, exact alpha, the order
  across layers and text that was clipped or culled. Of both: "a and b can be
  approved conditionally; neither has been established as sufficient here." If
  neither can give its guarantees, "the needed evidence is an instrumented
  rendering trace exposing glyph attribution, original ink, clip/mask effects
  and compositing survival. This package does not establish whether the
  intended browser can supply that trace." No display test at all "is
  acceptable as a decision not to assess display" and "must be labelled as an
  unperformed assessment, not a successful fidelity gate".
- **What an approval would need.** The rules as one text; every file a verdict
  depends on, the collector and the capture among them; the browser's exact
  build; lockfiles; raw evidence behind example verdicts. "Parts read
  independently with no memory of the others do not suffice for whole-system
  approval": component packages, then one integration package that stands by
  itself.

**What that comes to. The author is not blind, and only the middle of the first
is a consequence of the code.**

1. The reviewer does not say pictures cannot pass a page. It says they may give
   a `PASS` or `FAIL` from ink "only for cases with independently established
   guarantees", and lists them. Nothing here holds those guarantees, and the
   author knows no way to get them from this browser without the trace the
   reviewer names; that is the author's judgment and was not tried. Without
   them a display test on pictures can fail a page (a member absent, text
   hidden) or abstain, and cannot pass one. What follows from that is a
   consequence of `decide_pair.py`, checked by running it: a pair is decided
   for a builder only when that builder passes everything, so no pair is
   decided. One part of that code is the author's reading and not a ruling:
   that a builder with an unknown test is never the one decided for.
2. Leaving display out is open, and the reviewer says how it must be labelled.
   A pair would then be decided on content alone, once a content test is built
   again and approved. That changes the decision as it stands, which counts
   content and display, and is not this plan's to make.
3. Size. Content: the rules are now given and can be written to; it is most of
   the reading and comparing code again, its cells and mutants, new acceptance
   pages, and an approval in several packages where this one took two. Display
   to a pass: first a trial of whether this browser gives the trace at all,
   which may end in "it does not"; if it does, a test built on it from nothing.
   The author cannot put a number of days on the second and will not guess.

**Not done, and waiting on the owner:** every word of the author's a judge reads
and the three questions about the judging package have gone to nobody; the four
pre-run checks; Revision 6.

### The plan stops, 2026-10-07

The owner, given the reviewer's answer and what a rebuild would take, chose:
"Stop the plan here". Put beside it and not chosen: a trial of whether the
browser can give its own paint record; a rebuild of content with display left
out, which would change the registered decision; and going on to the four
pre-run checks with no test approved.

So, as of this entry:

- **Done:** stages 1 to 4; the capture at the specification's widths; the three
  fidelity tests, the judging package builder and the pair decision as code;
  the reviewer's twenty development pages and twenty-two acceptance pages; one
  run of the tests over the acceptance pages.
- **Refused by the reviewer, and not used:** the content test and the display
  test. The state test is approved and copies a refused test.
- **Never sent to the reviewer:** the pair decision; the judging package
  builder; every word of the author's that a judge would read; the question
  whether rule 7 belongs in a judge's instructions; what is done with a page
  wider than its window; the four pre-run checks. And of the fidelity tests
  themselves, the collector of a page's facts, the JSON reader, the picture
  reader, the measuring script and the module that opens a world in the page.
- **Not begun:** the freeze, the arms, any judging, any result.

**What this record supports, and no more.** An instrument whose only deciding
tests are written to rules by a reviewer of another model family, and approved
by that reviewer reading the code, was not built to that reviewer's approval in
one round. Its pages did not find what its reading found. Part of what it
refused over, it settled only afterwards: its fourth reply calls one rule "a new
conservative amendment" and says of an earlier distinction that it "was not
executable". For display, the reviewer's own rules ask for evidence that nothing
here shows a browser can give. That is a finding about this instrument. It says
nothing about the design seed: no page of either arm was built.

**Open after revision 6,** should the work be taken up again, each needing a
plan and most a registration of its own: whether the browser can supply the
paint record the author proposed, or the trace the reviewer names; a content
test written to the fourth reply of
rules; whether a pair may be decided on content alone; the arm launcher still
binds neither the CLI version, the harness nor the term list; which models may
judge, given what the API does with a large image; how many judges score a
page and in what order.

Dion branch `fidelity-and-judging` ends at `ee8d239`, on `derive-measures`,
neither pushed by this entry. The code is kept as it was refused, and the README
of the fidelity tests says so at its head.
