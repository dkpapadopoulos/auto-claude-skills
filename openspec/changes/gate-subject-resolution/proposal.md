# Proposal: resolve the push gate's git subject from the gated command, not the session cwd (#219)

## Why

`hooks/openspec-guard.sh` resolves every git fact — HEAD, mainline merge-base,
the branch diff, the verdict's covering commit — against the hook **process**
working directory, which the harness sets to the **session** cwd. It never reads
the payload's `.cwd`, and a `cd` inside the gated command does not move it.

So whenever the gated command acts on a different tree or a different branch
than the session cwd happens to be sitting on, the gate measures the **wrong
subject**. Reproduced against the real guard on 2026-08-29 (three live
occurrences on 2026-08-27/28, each needing the documented human bypass):

- `git -C <worktree> push origin mine`, process cwd = shared checkout on another
  session's routing branch -> **deny:routing-governance**, on a branch whose diff
  touches **zero** routing files.
- `git push origin mine` from that same shared checkout -> the same deny, for the
  same reason: `_routing_base`/`_branch_diff_names` measured the *checked-out*
  branch, not the ref named in the refspec.
- Identical payload with the process cwd inside the correct worktree -> allow.

Two distinct failures ride on the one root cause:

1. **Misattribution.** The deny's stated predicate ("this push modifies routing
   files") is simply false of the command being gated, and the remedy it names
   (`project-verification`) had already run and passed. This is the #161 defect
   — a predicate measured against the wrong subject — on the push path rather
   than the merge path.
2. **Inverted incentive.** A session that isolates its work in a worktree (what
   `agent-team-review` mandates after #204, and what this repo's guidance
   recommends for concurrent sessions) is blocked; a session that checks out
   over a concurrent session's work passes.

It is not a rare race. Any parallel-session workflow — `agent-team-execution`,
`using-git-worktrees`, background reviewers — can leave the gated command and
the session cwd in different trees, and **any** concurrent session that parks
the shared checkout on a routing branch makes every other session's pushes deny.

## What Changes

- A new `command_git_subject_dir` in `hooks/lib/git-command.sh`: the directory
  the gated git command actually acts in, from an explicit `-C <path>` /
  `--git-dir=<path>` on the git invocation, else a `cd <path>` in an earlier
  segment of the same compound command. Returns nothing when it cannot tell.
- A new `command_push_ref` in the same lib: the ref a `git push` names in its
  refspec, when it names exactly one.
- `hooks/openspec-guard.sh` resolves a **subject** (`root`, `commit`) once,
  next to the existing `_proot`, and uses it for the diff predicates and the
  verdict lookup. Every candidate path is validated as a worktree of the *same*
  repository before any `git -C` consumes it; the refspec candidate is a ref
  name resolved inside that repository, never a path.
- `hooks/lib/verdict.sh` gains an optional trailing `<commit>` argument on the
  helpers that today hardcode `HEAD`, so the subject commit reaches
  `_routing_base`, `_branch_diff_names`, `verdict_covers_head`,
  `verdict_sha_is_head`, `verdict_routing_delta` and `verdict_resolve_token`.
  Omitting it is byte-for-byte the current behaviour.
- The guard **announces** when the resolved subject differs from the process
  cwd, and when a subject hint was discarded as unvalidatable (#198).

## What does NOT change

- **Verdict acceptance is not widened.** HEAD-or-ancestor, exact-HEAD for the
  cross-token bridge; sha-binding stays the forgery-resistant property
  (#51/#156). Only the tree and commit we ask *about* change.
- **Branch-ledger reads stay on the process-derived root.** The ledger's writer
  (`hooks/skill-completion-hook.sh`) keys records on *its* process cwd, so
  re-pointing the reader at the subject would make existing records invisible —
  strictly more denies. The cross-location bridge exists for exactly that split.
- No `permissionDecision` is added, and no existing deny is removed.
