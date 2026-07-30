# Spec delta: pdlc-safety — the publication leak gate must never fail silently

## ADDED Requirements

### Requirement: A body the gate cannot read MUST be announced, never reported clean

The gate MUST distinguish "checked and clean" from "could not check". Every path
that allows a publication without having compared its body against the corpus
MUST emit a `systemMessage` stating that the check did not run.

A body whose text is not present in the literal command string — because it is
produced by command substitution, a backtick, a parameter expansion, or process
substitution — MUST be announced as unchecked. The gate MUST NOT deny on this
basis: an unexpanded body is evidence the gate could not look, not evidence of a
leak. This check MUST be independent of whether a `--body-file` was also
resolved, because one command may carry both.

A failure to READ the corpus or the body (including a non-regular body path)
MUST surface as cannot-check, and MUST NOT surface as a clean result. Where the
read is performed by a command in a pipeline whose exit status is masked by a
later stage, the implementation MUST inspect that command's own status.

An error inside the gate itself — an unresolvable plugin root, unparseable hook
input, or a detection result carrying no detail — MUST reach an announcement
path. No such error may terminate the hook before its announcement paths are
reachable.

#### Scenario: a command-substituted body is announced, not silently allowed

- **GIVEN** a memory corpus containing a 16-word run absent from tracked content
- **AND** a command `gh issue create --title t --body "$(cat leaky.md)"` whose
  file reproduces that run
- **WHEN** the gate evaluates the command
- **THEN** the gate MUST emit a `systemMessage` stating the body may be
  shell-expanded and was not visible to the gate
- **AND** the gate MUST NOT emit `permissionDecision: deny`
- **AND** the output MUST be exactly one JSON object

#### Scenario: an unreadable corpus file reports cannot-check, not clean

- **GIVEN** a memory corpus in which one `*.md` file cannot be read
- **AND** a body reproducing a private run from the corpus
- **WHEN** the detection engine runs
- **THEN** the engine MUST exit 3 (cannot check)
- **AND** the engine MUST NOT exit 0

#### Scenario: an unresolvable plugin root announces instead of exiting silently

- **GIVEN** `CLAUDE_PLUGIN_ROOT` is unset and the script's own location cannot be
  resolved
- **WHEN** the gate evaluates a publication command
- **THEN** the gate MUST emit a `systemMessage` stating the check did not run
- **AND** the gate MUST NOT exit without output

#### Scenario: a literal clean body produces no announcement

- **GIVEN** a body containing no private run and no shell-expansion token
- **WHEN** the gate evaluates the command
- **THEN** the gate MUST produce no output

### Requirement: An incomplete public exemption MUST NOT be reported as a leak

The public-content exemption MUST NOT be partially discarded. (Text present in
the repository's tracked content is definitionally not a leak.) If the exemption
cannot be built completely — because a tracked path is unreadable, or the
command is run outside a repository — the engine MUST report cannot-check.

The engine MUST NOT emit a leak verdict derived from an exemption it knows to be
incomplete, because such a verdict is indistinguishable from a true positive
while being false.

#### Scenario: a deleted tracked file does not turn public text into a leak

- **GIVEN** a run present both in the memory corpus and in tracked repo content
- **AND** one other tracked file deleted from the working tree
- **WHEN** the engine checks a body containing that run
- **THEN** the engine MUST NOT exit 1 (leak)
- **AND** the engine MUST exit either 0 (exempt) or 3 (cannot check)

#### Scenario: a deny does not suppress a co-occurring cannot-check

- **GIVEN** a command carrying both a leaking body file and a second body the
  gate could not read
- **WHEN** the gate evaluates the command
- **THEN** the emitted deny message MUST also report the unchecked portion
- **AND** the output MUST be exactly one JSON object
