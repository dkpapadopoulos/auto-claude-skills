# Proposal: the verdict's `sha` must be measured when the gate ran, not when the record is written

## Why

`scripts/verify-and-record.sh` captures the verdict's `sha` **after** the gate
commands have run (line 140), ~10 minutes after the gate loop starts on this
repo's suite. Any commit made in that window is silently adopted by the
verdict, so the artifact names a commit whose tree no gate ever executed
against.

Observed live while shipping #180: a run that started at `e836f3f` and tested
that tree wrote `"sha":"2b6be3a…"` because a commit landed mid-run. The
record was indistinguishable from a truthful one.

`hooks/lib/verdict.sh` accepts a verdict whose `sha` equals HEAD or is a
branch-local ancestor, so a mislabelled verdict lets the push gate accept a
commit no gate ever ran against — in the one layer whose entire purpose is
measured provenance. The script's header claims "HONEST BY CONSTRUCTION …
nothing is asserted, only measured"; `sha` is currently the exception,
because it is measured at a different time from everything else in the record.

This file already solved this exact bug class once: the session token is
captured **before** the gate loop with a comment (issue #122) describing
precisely this hazard. Same window, same failure shape — `sha` just never got
the fix.

Not a trust boundary (the artifact is shell-writable; external CI is the
boundary), so this is an integrity/accuracy defect, not a security hole.

## What Changes

- `scripts/verify-and-record.sh`
  - Capture `SHA_BEFORE` immediately before the gate loop, alongside the
    existing token capture and for the same documented reason.
  - Capture `SHA_AFTER` after the loop. If the two differ, the run straddled a
    commit and covers no single commit: record
    `gate-run-straddled-commit` in `could_not_verify[]` and announce it on
    stdout.
  - Record `sha` = `SHA_BEFORE` — the commit whose tree the gate actually
    began measuring. Byte-identical to today's value in the overwhelmingly
    common non-straddled case.
  - Record a new advisory boolean `worktree_dirty` (tracked-file modifications
    present at gate start), because a clean `sha` on a dirty tree has the same
    "tested something else" problem. Advisory ONLY — not deny-wired.
- `tests/test-verify-and-record.sh`: a red-first case whose gate command
  itself commits in the fixture repo, asserting the verdict does not claim a
  clean result for an untested commit.

## Why `could_not_verify[]` rather than picking a sha

Capturing earlier is necessary but not sufficient: if the tree changes
mid-run, a pre-captured sha is equally a lie, just in the other direction.
`verdict_is_clean` requires `could_not_verify[]` empty, so a straddled run
stops satisfying routing-governance and the deploy-gate's clean predicate —
the failure becomes loud instead of silent. This is the same
fail-toward-not-clean posture the script already uses for an unrunnable
gate-gaming check.

`verify-hardening` is unaffected: it denies only on a non-empty `failed[]`
whose sha equals HEAD exactly, and a straddled run's `SHA_BEFORE` is an
ancestor — which is the correct reading, since a failure is authoritative
only for the commit it was measured at.

## Non-goals

- Locking the repo, or refusing to run while the tree is dirty. Too intrusive
  for an advisory-provenance script, and it would break the common
  background-run workflow rather than just labelling it accurately.
- Making `worktree_dirty` gate anything. Running the gate on uncommitted work
  and committing afterwards is a normal, intended workflow; promoting it to
  `could_not_verify[]` would false-block routine routing pushes.
- Treating a mid-run **worktree** change as a straddle. Gate commands
  routinely create untracked build/test artifacts, so a status-based straddle
  predicate would fire constantly and turn a real signal into noise. The
  straddle predicate is HEAD-sha-only.
- Re-basing the gate-gaming diff or `test_delta` on `SHA_BEFORE`. Both are
  diff-derived advisories computed at write time with no reported defect;
  a straddled record already discloses that it covers no single commit.
