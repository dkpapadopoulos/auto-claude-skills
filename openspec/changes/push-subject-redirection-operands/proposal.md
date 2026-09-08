# Proposal: shell redirection operands are not refspecs

## Why

`git push … 2>&1 | tail -N` is what an agent naturally writes. The push gate's
subject parser counted the redirection words as refspecs, which produced two
failures — and issue #238 names only the first.

1. **A false statement, on a very common shape.** `command_push_subject_is_partial`
   returned "partial", so the gate announced that the push "carries more than one
   ref" and "may UNDER-measure what this command ships" — about a push it had
   measured correctly. This repo already decided (#198) that a confident
   over-report is worse than silence, because it instructs the reader to distrust
   a measurement that was in fact right.

2. **Subject resolution silently stopped working.** `command_push_ref` returned
   EMPTY for the same commands, so `_SUBJ_REV` fell back to the checkout's HEAD —
   defeating #219's whole point for any redirected command. Not found by the
   issue; found by reproducing it. It is safe (a discarded hint falls back to the
   old subject, never to an allow) but it means the fix #219 shipped was inert
   for the shape agents write most.

Pipes were already handled, because they are segment boundaries. Redirections are
not, so they had to be recognised as words.

## What Changes

`hooks/lib/git-command.sh` gains `_gc_redir_kind`, and both refspec scanners —
`command_push_ref`'s own loop and the shared `_gc_push_seg_shape` — skip
redirection words, consuming the following word when the operator is bare.

**The matcher is STRUCTURAL, not an enumeration.** The obvious fix is a list of
`>`, `>>`, `2>`, `&>`, `2>&1` — and this predicate family has now been bypassed
five times by lists of shell syntax that were each complete until they were not
(CLAUDE.md, `command_push_is_all_deletions`). So it matches the SHAPE a
redirection has: an optional `&`, an optional file-descriptor digit run, then `<`
or `>`. That covers `10>`, `3>&-`, `<<<` and forms nobody wrote down.

A word is judged by its first characters only, so a quoted word that merely
begins with an operator character — a ref pathologically named `">weird"` — is
not a redirection. This must never swallow a real refspec.

## Known limitation, pinned rather than fixed

An `&`-bearing redirection (`2>&1`) still prevents `command_push_is_all_deletions`
from certifying, because `&` is a SEGMENT boundary: the command splits into
`… 2>` and `1`, and `1` is not on the inert whitelist, so the ALL-form refuses to
vouch for it.

That refusal is correct and must stay. Widening the whitelist to admit a bare
number is exactly the "enumerate what looks safe" move that has bypassed this
predicate before, and the cost of refusing is one-directional: the command loses
the deletion skip and is measured against HEAD, as every push was before #229 —
never a new deny.

Fixing it properly means teaching `_gc_split_segments` that the `&` in `>&` is
part of a redirection rather than a control operator. That is the #155 scanner
and is deliberately out of scope. A cell pins the current behaviour so the
limitation is a recorded decision, and so a future scanner change has something
that visibly flips.

## Capabilities

### Modified Capabilities
- `pdlc-safety`: the push gate's subject parser distinguishes redirection
  operands from refspecs.

## Impact

- `hooks/lib/git-command.sh` — one new helper, two scanners updated.
- `tests/test-push-gate-detection.sh` — redirection cells plus controls.
- No change to any deny decision: the SUBJECT leg is announce-only, and subject
  resolution can only move the gate from "measured HEAD" to "measured the named
  ref", which is what #219 intended.
