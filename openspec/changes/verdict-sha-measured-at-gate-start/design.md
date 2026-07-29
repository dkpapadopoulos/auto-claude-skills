# Design: verdict `sha` measured at gate start + straddle disclosure

Issue #181. Companion to `openspec/changes/verify-and-record/` (the original
writer) — this change fixes the one field in that record that is asserted at a
different time from everything it describes.

## Capabilities Affected

- `project-verification` — the verdict artifact's provenance contract.

## The window

```
line 100   ( cd "$ROOT" && eval "$run" )      # gate executes against tree T
   …       ~10 minutes on this repo's suite
line 140   SHA="$(git rev-parse HEAD)"        # HEAD read here
```

A commit landing between those points is adopted by the verdict. Downstream,
`verdict_covers_head` accepts `sha == HEAD` or a branch-local ancestor, so the
push gate treats an untested commit as covered.

## Decisions

### D1. `sha` = HEAD at gate start (`SHA_BEFORE`)

The record describes a measurement; the measurement began at `SHA_BEFORE`.
In the non-straddled case (the overwhelming majority) `SHA_BEFORE ==
SHA_AFTER`, so the written value is byte-identical to today's — no behaviour
change, no migration.

Rejected: keeping `SHA_AFTER`. It names a commit the gate demonstrably did not
run against, which is the defect.

Rejected: omitting `sha` when straddled. `verdict_covers_head` returns 1 on a
missing sha (fail-open to the status layer), so omission would be *quieter*
than today, not louder — the opposite of the goal.

### D2. Straddle ⇒ `could_not_verify[]`, not a sha choice

The load-bearing half. A straddled run covers no single commit, so neither sha
is honest. `verdict_is_clean` requires `could_not_verify[]` empty, so the
record stops satisfying routing-governance and deploy-gate — the same
fail-toward-not-clean posture already used for an unrunnable gate-gaming
check. Entry name: `gate-run-straddled-commit` (no comma — the field is
CSV-split by the writer's jq).

Interaction check, both consumers of `sha`:

| consumer | predicate | straddled-run effect |
|---|---|---|
| `verify-hardening` | `failed[]` non-empty AND `verdict_sha_is_head` | `SHA_BEFORE` is an ancestor ⇒ falls back to the status layer. Correct: a failure is authoritative only for the commit it was measured at. |
| `routing-governance` | `verdict_is_clean` AND coverage | not clean ⇒ deny with the `project-verification` remedy. Intended: re-run the gate against the settled HEAD. |

No false-block is introduced for a non-straddled run, because nothing about
that path changes.

### D3. Straddle predicate is HEAD-sha-only

A tempting generalisation — fingerprint HEAD **plus** `git status` before and
after — was rejected. Gate commands routinely produce untracked build/test
artifacts, so a status-based predicate would fire on ordinary runs, push
`could_not_verify[]` non-empty on most verdicts, and deny routine routing
pushes. That converts a rare true signal into constant noise, and the repo's
false-block discipline treats that as a net loss.

### D4. `worktree_dirty` is advisory, tracked-files-only

A clean `sha` on a dirty tree has the same "tested something else" problem, so
the record should say so. It is NOT promoted to `could_not_verify[]`:
verifying uncommitted work and committing afterwards is a normal, intended
workflow, and gating it would false-block routine pushes.

Measured with `git status --porcelain --untracked-files=no` at gate start:
tracked modifications are what make the tested tree differ from the sha's
tree, while untracked files are common, usually gitignored-adjacent scratch,
and would make the field near-constantly true.

New field, not a changed one — `hooks/lib/verdict.sh` reads named keys with
`jq`, so an added key is inert for every existing reader.

## Out-of-Scope

- Any locking, or refusing to run on a dirty tree (see proposal Non-goals).
- Deny-wiring `worktree_dirty`.
- Re-basing the gate-gaming diff / `test_delta` on `SHA_BEFORE`. Does not
  affect gating: a straddle forces `could_not_verify[]` non-empty, so every
  `verdict_is_clean` consumer rejects the record before those advisory fields
  are read.
- Backfilling or invalidating verdicts already on disk.
- **Two residual mid-run tree changes this predicate cannot see** (named here
  so they are not mistaken for coverage): a *tracked-file edit* made during the
  run with no commit, and a commit followed by `reset --hard HEAD~1` — both
  leave `SHA_BEFORE == SHA_AFTER`, and `worktree_dirty` describes a tree that
  no longer exists (it is sampled once, at gate start). Both are rarer than the
  case fixed here, neither is a regression, and closing them means the
  status-based predicate rejected in D3.
- **Repos whose declared gate legitimately commits** (auto-format-and-commit,
  `npm version` in a release check) will now produce permanently-unclean
  verdicts. Arguably correct — such a gate genuinely never measures a single
  tree — but it is a new class of "this repo cannot get a clean local verdict",
  recorded in the skill's limits prose rather than special-cased here.

## Acceptance Scenarios

1. **Straddled run is disclosed.** GIVEN a fixture repo whose declared gate
   command creates a commit while running, WHEN the script runs, THEN
   `could_not_verify[]` contains `gate-run-straddled-commit`, `sha` is the
   pre-run HEAD (not the commit the gate created), and `verdict_is_clean`
   returns non-zero for the artifact.
2. **Non-straddled run is unchanged.** GIVEN a repo whose gate makes no
   commit, WHEN the script runs, THEN `sha` equals HEAD, `could_not_verify[]`
   is empty, and `verdict_is_clean` succeeds.
3. **Dirty tree is recorded, not gated.** GIVEN a repo with a modified
   tracked file and a passing gate, WHEN the script runs, THEN
   `worktree_dirty` is `true` AND `could_not_verify[]` is still empty (the
   verdict stays clean).
4. **Clean tree records `worktree_dirty: false`.**

## Regression

`tests/test-verify-and-record.sh` — T16 (straddle), T17 (non-straddled
control: still clean and HEAD-bound), T18 (dirty advisory, must NOT gate),
T19 (untracked-only is neither dirty nor a straddle — pins D3), T20 (straddle
+ FAILING gate: the one case where an enforcement outcome changes, see the D2
table). All assert against the real script in an isolated fixture repo under
`TEST_HOME`, using `verdict_is_clean` / `verdict_sha_is_head` from
`hooks/lib/verdict.sh` as the end-to-end consumer assertions rather than
re-deriving the predicates in the test. T16 and T20 were both measured RED
against the pre-fix script.

`tests/test-project-verification.sh` — content asserts pinning the manual
path's half (capture before the gate, keep the pre-gate value, disclose the
straddle), including an `assert_not_contains` on the old JSON placeholder,
because the copied example — not the prose — is what the model transcribes.
