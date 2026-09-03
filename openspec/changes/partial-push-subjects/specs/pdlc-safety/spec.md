# Spec delta: pdlc-safety — partial push subjects

## ADDED Requirements

### Requirement: A push that ships no content is not measured at the checkout's HEAD

When every `git push` segment in a gated command deletes a ref, the command
ships no content, and the push gate's **content-dependent** checks MUST be
skipped rather than evaluated against the subject directory's `HEAD`, which the
command does not push. The content-dependent checks are routing-governance,
verify-verdict hardening, the evaluator-surface advisory, and the
IMPLEMENT-evidence leg.

Because skipping the IMPLEMENT-evidence leg changes when that leg fires, the
shadow corpus's `predicate_version` MUST be bumped, and records written under the
previous version MUST NOT be pooled with the new ones.

The predicate MUST be an ALL-form over push segments: it MUST NOT report a
deletion unless **every** push segment in the command is one. A command
containing both a deletion and a content-bearing push MUST be measured exactly
as it was before this requirement existed, so that a deletion can never excuse a
push in the same command.

Every segment of the command MUST be accounted for, not only the segments
recognised as `git push`. A segment that is neither a recognised `git push` nor
provably incapable of shipping content MUST disqualify the command. "Provably
incapable" is a whitelist — an empty segment, a segment consisting only of group
punctuation, or a `cd` — and MUST NOT be expressed as a list of git subcommands
or of other commands assumed to be harmless, because such a list would have to
be provably complete rather than merely plausible.

This requirement exists because a git alias makes a content-bearing push
unrecognisable as one: the segment reports the alias word, not `push`. Elsewhere
in the gate, an unrecognised segment degrades to measuring `HEAD`, which is safe;
here it would degrade to skipping a check, which is not.

A command whose text contains a command substitution or a process substitution
MUST NOT be reported as a deletion, wherever the construct appears — including
inside the arguments of the deletion itself. Such a construct executes
regardless of what the surrounding command does with its output, so it can carry
a content-bearing push inside a segment that is otherwise vouched for. This
check MUST be applied to the whole command text, not per segment and not per
token: segment splitting does not treat a substitution as a boundary, and word
splitting scatters it across tokens.

A command whose parse is not trustworthy MUST NOT be reported as a deletion. The
command scanner already reports this condition, and the predicate MUST consult
it, because a mis-parse can merge a content-bearing push into a segment that
appears accountable. This check MUST live in the predicate itself rather than at
a call site, so that no future caller can omit it.

That check MUST NOT be applied to the announce-only predicates. Their failure
mode is a possibly-wrong advisory rather than a skipped check, and the advisory
they emit is if anything more warranted when the parse is untrustworthy.

A segment counts as a deletion when it carries `--delete` or `-d`, or when it
has at least one refspec and every one of its refspecs has an empty source half
(`:<dst>` with a non-empty `<dst>`, optionally preceded by the `+` force
marker). A segment carrying `--all`, `--mirror` or `--tags` MUST NOT count as a
deletion regardless of its refspecs, because those flags push refs no refspec
names.

The predicate MUST fail toward saying nothing: an unparseable command, an
unrecognised segment, or any ambiguity MUST leave the gate measuring `HEAD`
exactly as before. No failure mode may result in a skipped check.

The composition-chain REVIEW and VERIFY gates, and the global fail-closed gate,
MUST continue to apply to a deletion. They gate the development phase rather
than the shipped commit, and deleting a remote ref remains an outbound action.

When the content-dependent checks are skipped, the gate MUST say so, and MUST
state that the review and verification gates still applied.

#### Scenario: a deletion is not denied for routing files it does not carry

- **GIVEN** a routing repository whose checked-out branch modifies routing files
- **AND** no clean verification verdict covering that branch
- **WHEN** the gated command is `git push --delete origin <branch>`
- **THEN** routing-governance does not deny
- **AND** the response states that the command ships no content

#### Scenario: a deletion does not excuse a content-bearing push

- **GIVEN** the same repository and verdict state
- **WHEN** the gated command is `git push --delete origin x; git push origin <routing branch>`
- **OR** the gated command is `git push origin :x <routing branch>`
- **THEN** the gate denies, exactly as it did before this requirement existed

#### Scenario: a failing verdict at HEAD does not deny a deletion

- **GIVEN** a verification verdict bound to the subject directory's `HEAD` that
  reports a failing gate
- **WHEN** the gated command is `git push --delete origin <branch>`
- **THEN** verify-verdict hardening does not deny
- **AND** the same verdict still denies an ordinary push of that branch

#### Scenario: a segment that cannot be accounted for disqualifies the command

- **GIVEN** a routing repository whose checked-out branch modifies routing files
- **AND** no clean verification verdict covering that branch
- **WHEN** the gated command is `git push --delete origin x && git -c alias.p=push p origin <routing branch>`
- **OR** the gated command is `git push --delete origin x && ./deploy.sh`
- **THEN** the gate denies
- **AND** the response does not state that the command ships no content

#### Scenario: a command substitution disqualifies the command

- **WHEN** the gated command is `git push --delete origin scratch && cd $(git push origin main)`
- **OR** the gated command is `git push --delete origin $(git push origin main)`
- **OR** the gated command is `git push --delete origin x < <(git push origin main)`
- **THEN** the command is not reported as a deletion
- **AND** an ordinary variable expansion such as `cd "$WT" && git push --delete origin foo` still is

#### Scenario: an untrustworthy parse disqualifies the command

- **WHEN** the gated command is `git push --delete origin scratch; cd \'; git push origin main`
- **THEN** the command is not reported as a deletion
- **AND** the gate denies rather than announcing that the command ships no content

#### Scenario: an inert extra segment does not disqualify the command

- **WHEN** the gated command is `cd <worktree> && git push --delete origin <branch>`
- **THEN** the content-dependent checks are still skipped

#### Scenario: a deletion adds nothing to the IMPLEMENT shadow corpus

- **GIVEN** an implementation-slot skill in the chain with no implementation
  evidence, and a branch whose diff touches material source
- **WHEN** the gated command is `git push --delete origin <branch>`
- **THEN** no IMPLEMENT advisory is raised and no shadow record is appended
- **AND** an ordinary push in the same state still raises the advisory and
  appends exactly one record

#### Scenario: a deletion still faces the review and verification gates

- **GIVEN** a composition chain whose REVIEW and VERIFY milestones are not
  completed
- **WHEN** the gated command is `git push --delete origin <branch>`
- **THEN** the gate denies

### Requirement: A multi-ref push is reported as possibly under-measuring

When a gated push carries more than one ref — `--all`, `--mirror`, `--tags`, or
two or more refspecs — the gate MUST continue to measure the subject
directory's `HEAD`, and MUST state that `HEAD` is at best one of the refs being
pushed so the checks may under-measure what the command ships.

That statement MUST be distinct from the statement made for a deletion. A single
shared message for both shapes is what allowed the deletion false block to go
unnoticed, and the two shapes are now resolved differently.

#### Scenario: --all is measured at HEAD and says so

- **GIVEN** a routing repository whose checked-out branch modifies routing files
- **AND** no clean verification verdict covering that branch
- **WHEN** the gated command is `git push --all origin`
- **THEN** the gate denies
- **AND** the response states that the checks may under-measure what is shipped
- **AND** the response does not claim that the command ships no content

### Requirement: Group punctuation is not counted as a refspec

A command word made up entirely of group closers (`)`, `}`) is punctuation, not
a refspec, and the push-command parsers MUST NOT count it as a positional
argument.

#### Scenario: a parenthesised push resolves its ref

- **WHEN** the gated command is `( git push origin main )`
- **THEN** the resolved push ref is `main`
- **AND** the command is not reported as carrying more than one ref
