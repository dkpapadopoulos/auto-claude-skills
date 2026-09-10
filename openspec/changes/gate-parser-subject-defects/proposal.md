# Two parser defects that made the gate say false things

## Why

A four-panelist review of the IMPLEMENT shadow corpus (three Claude lenses plus
a cross-family Codex run, two rounds) found that the 12 v4 would-block episodes
could not be adjudicated as recorded. Three of the twelve had a premise the
predicate never established, from two independent parser defects — and every one
of the twelve gated commands was written in the shape that triggers them:
`2>&1 | tail -N`.

**1. A redirection operand was read as a PR reference.** `pr_ref_from_command`
counts digit-leading tokens after `merge` and refuses when there is more than
one, so a plausible-but-wrong label is never emitted. `2>&1` is digit-leading.
Measured: **14 of 14** `gh-merge` records across 39 days carry
`diff_base: unresolved` — #161's merge-subject resolution has never once
produced a measurement in production. This is the #238 defect class exactly, and
`git-command.sh` already carries the structural fix (`_gc_redir_kind_var`) that
was never applied here.

**2. A deletion-shaped command was recorded as a content push.** A trailing
`| tail -N` is a segment `_gc_seg_is_inert` cannot vouch for, so
`command_push_is_all_deletions` refuses to certify, the subject falls back to the
checkout HEAD, and the IMPLEMENT leg then states "this push edits source" about a
command that ships nothing. Two of the twelve episodes are branch cleanups
recorded this way.

## What Changes

- `pr_ref_from_command` skips shell redirection operands, reusing
  `_gc_redir_kind_var` rather than listing redirection spellings.
- A new **advisory-only** predicate `command_push_recognised_are_all_deletions`
  answers the weaker question "does every RECOGNISED push here delete a ref?".
  The IMPLEMENT leg uses it to stop asserting something false; no gate decision
  consults it.
- The shadow record gains `advisory_emitted`, and the rate population is that
  field rather than an inference from `would_block`.
- `IMPLEMENT_SHADOW_PREDICATE_VERSION` 4 → 5; `IMPLEMENT_SHADOW_SCHEMA_VERSION`
  3 → 4.

## The deletion half is NOT a parser fix, and that is deliberate

There is no sound widening of `_gc_seg_is_inert`. The right-hand side of a pipe
executes arbitrarily — `git push --delete origin x | ./deploy.sh` runs
`deploy.sh` — so a whitelist that vouched for `tail` would have to distinguish it
from an arbitrary program by name, which is the enumeration this predicate family
has already been bypassed by eight times. The refusal is correct.

What was wrong is the CONSEQUENCE. CLAUDE.md justifies the lost certification as
"one-directional … never a new deny", which is true of **enforcement** and does
not transfer to **measurement** or to what the gate SAYS. So the strict predicate
keeps governing every skip, and a second, weaker predicate governs only the
sentence and the corpus record. The asymmetry is the design: mixing them up is
what nearly shipped a false ALLOW when the ANY-form was first written, and a test
asserts that swapping the strict form for the weak one at the gate site fails.

## Why the version bump, measured before taking it

Both changes alter WHEN THE LEG FIRES — merges begin resolving and emitting
advisories they never emitted; deletion-shaped commands stop emitting one — so
this repo's own rule forces a `predicate_version` bump, and v4 records must not
be pooled with v5.

Measured first, per #199: the live v4 corpus held **12** would-block episodes, at
least **3** of them known-bad, against a floor of **29**. The exact rule needs
`0.9^n < 0.05`; at n=12 that is 0.282. Nothing measurable was discarded. This is
the third reset, and three resets rooted in the same command-text parser being
incomplete in a new way is an argument for recording the pattern, not for pooling
across a predicate change.

## Impact

- `hooks/lib/pr-diff.sh`, `hooks/lib/git-command.sh`, `hooks/lib/implement-shadow.sh`,
  `hooks/openspec-guard.sh`, `scripts/shadow-adjudicate.sh`.
- No deny behaviour changes. `_SUBJ_DELETION_ONLY` still derives from the strict
  form alone.
- Capability: `pdlc-safety`.
