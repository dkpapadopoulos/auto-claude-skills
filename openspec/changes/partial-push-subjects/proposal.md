# Proposal: stop measuring deletions and multi-ref pushes at the checkout's HEAD (#229)

## Why

`command_push_ref` (added by #219/#227) returns **nothing** for three different
situations, and the guard cannot tell them apart:

1. a bare `git push` — the checkout's HEAD really is the subject;
2. a **deletion** (`--delete`, `-d`, or an empty-source refspec `:branch`) —
   which pushes no content at all;
3. a **multi-ref** push (`--all`, `--mirror`, `--tags`, or 2+ refspecs) — which
   pushes several, of which HEAD is at best one.

All three fall through to `_SUBJ_REV=HEAD`, so (2) and (3) are then measured as
though HEAD were the subject. Two consequences, both pre-existing rather than
introduced by #227:

- `git push --delete origin foo` can be denied by **routing-governance** for
  routing files the deletion does not carry — a **false block**, and the one
  users actually hit. The deny's stated predicate ("this push modifies routing
  files") is false of the command being gated: the #161/#219 defect class again,
  now on the refspec rather than the tree.
- `git push --all` **under-measures**: the gate examines only HEAD while the
  command ships every branch.

#227 added `command_push_subject_is_partial` and announced the ambiguity, but
deliberately did not act on it: that predicate fires when **any** push segment is
partial, so letting it suppress a gate would allow
`git push --delete origin x; git push origin main` to excuse the second push.

## What Changes

- A new `command_push_is_all_deletions` in `hooks/lib/git-command.sh`: the
  **ALL-form**. It returns 0 only when the command contains at least one
  `git push` segment and **every** push segment is a deletion. That is the
  property that makes it safe to act on where the ANY-form is not.
- A new `command_push_is_multi_ref` in the same lib, so the two shapes can be
  reported separately instead of sharing one message.
- A shared `_gc_push_seg_shape` helper factors the segment-parsing preamble the
  four push parsers had been repeating.
- `hooks/openspec-guard.sh` skips the **content-dependent** legs —
  routing-governance, verify-hardening, the evaluator-surface advisory, and the
  IMPLEMENT-evidence leg — when every push in the command is a deletion, and
  says that it did.
- `IMPLEMENT_SHADOW_PREDICATE_VERSION` 3 → 4, because skipping that leg changes
  when it fires. The bump was taken only after measuring that the v3 corpus was
  empty; see `design.md`.
- A multi-ref push keeps measuring HEAD and now says it may **under-measure**,
  rather than sharing the deletion's message.
- Bug found while extending the parsers: a word made up entirely of group
  closers was counted as a refspec, so `( git push origin main )` — spaces, no
  trailing `;` — resolved **no** ref (the gate fell back to HEAD) and was
  announced as carrying more than one. Fixed in all three parsers.

## What does NOT change

- **The composition-chain REVIEW/VERIFY gates and the global fail-closed gate
  still fire on a deletion.** They gate the phase, not the shipped commit, and
  deleting a remote ref is still an outbound action. Narrowing the subject must
  not become "a deletion is ungated".
- **Multi-ref pushes are not narrowed.** Measuring every named ref is a separate
  change with its own false-block surface, for a shape this repo's workflows do
  not produce. This proposal records the decision to keep measuring HEAD and say
  so.
- **`command_push_subject_is_partial` stays announce-only** and keeps its ANY-form
  semantics; it is still the right predicate for "this command mixes a deletion
  with a real push", which neither new predicate covers.
- No new `permissionDecision`, and no gate is added.
