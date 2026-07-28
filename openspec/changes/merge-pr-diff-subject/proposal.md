# Proposal: resolve the real PR diff for merge-path IMPLEMENT events (#161)

## Why

PR #163 widened the IMPLEMENT-evidence leg to fire on `gh pr merge`, so the
Stage C1 shadow corpus now records merge events. Review of #161 found that the
predicate behind those records reads the **wrong subject**.

`_diff_touches_material_source` resolves `material_source` via
`_branch_diff_names` — the branch-local `merge-base(mainline,HEAD)..HEAD` delta.
For `gh pr merge <other-PR>` that delta describes the *invoking session's local
branch*, not the PR being merged. Run a merge from a session sitting on an
unrelated branch with local edits and the leg fires because **your** branch
touched source, while the thing being merged is someone else's PR. The record's
`material_source`, `branch`, and `head_sha` all describe the wrong thing.

This is not a new hazard — it is the documented reason
`_flush_push_advisories` is push-gated:

> PUSH-only: `_STALE_MSG` staleness text is computed from the LOCAL branch
> HEAD, which for `gh pr merge <other>` is the wrong delta — pre-flush
> behavior for gh-merge outside SHIP was silence, and that is preserved.

So the suppression #161 reported was **protecting users from a misleading
message**. Un-gating it without fixing the subject would surface exactly the
wrong text. The Stage C1 design triaged this as a doc-only caveat (I4, "segment
merge records at adjudication"); that triage was too weak — a corpus whose
records describe the wrong subject cannot be segmented back into correctness by
a reader who was not there.

## What Changes

- A new `hooks/lib/pr-diff.sh` resolving a merge command's **actual** PR file
  list: extract the PR ref from the command, fetch changed paths via `gh`.
- `material_source` for merge events is computed from that list; the push path
  keeps `_branch_diff_names` unchanged.
- A new `diff_base` field on the shadow record — `pr:<n>`, `branch-local`, or
  `unresolved` — so every record states what it was measured against.
- `_flush_push_advisories` emits the advisory for merges **only** when the PR
  diff actually resolved, preserving the existing suppression otherwise.
- `IMPLEMENT_SHADOW_PREDICATE_VERSION` → **2**. The predicate's meaning changes
  for merges, so v1 records MUST NOT be pooled with v2.

## Capabilities

**Modified**
- `pdlc-safety` — the IMPLEMENT-evidence leg's material-source predicate becomes
  subject-correct on the merge path, and its advisory reaches merges when the
  subject is known. Warn-first posture, evidence semantics, and the push path
  are unchanged.

## Impact

- **Risk: low, but non-zero and new in kind.** This is the first time the guard
  makes a **network call**. It is confined to the merge path, behind an
  advisory, and every failure degrades to today's behaviour (silence + a record
  marked `unresolved`). The push path is byte-unchanged and never calls out.
- **Latency:** measured ~620ms for `gh pr view --json files`. It lands only on
  `gh pr merge`, which is already a multi-second network operation, and never on
  `git push`.
- **Security:** the PR ref is parsed from model-authored command text. It is
  validated as a bare integer before reaching `gh`; anything else resolves
  `unresolved`. This prevents a crafted command injecting flags such as
  `--repo other/repo` into the fetch.
- **Corrects a shipped change one day old.** #163's merge coverage stays, but
  its records gain the subject they were missing. Records already written under
  `predicate_version: 1` are excluded by the version bump rather than reinterpreted.
