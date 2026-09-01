# Design: gate subject resolution (#219)

## The defect in one sentence

`hooks/openspec-guard.sh` answers "what is being pushed?" with "whatever the
session's shell happens to have checked out", and those are different questions
as soon as two sessions, or one session and one worktree, are in play.

## Measured, against the real guard (2026-08-29)

Fixture: a routing repo whose shared checkout sits on a concurrent session's
routing branch, plus a private worktree holding a branch that touches **no**
routing files, plus a clean verdict bound to the worktree HEAD.

| process cwd | gated command | before | after |
|---|---|---|---|
| shared checkout | `git -C <worktree> push origin mine` | `deny:routing-governance` | allow |
| shared checkout | `git push origin mine` | `deny:routing-governance` | allow |
| shared checkout | `cd <worktree> && git push origin HEAD` | `deny:routing-governance` | allow |
| the worktree | (identical payload) | allow | allow |

The pre-fix denies are the live symptom: the message asserts "this push modifies
routing files" of a branch that modifies none, and prescribes
`project-verification`, which had already run and passed on the pushed tree.

## Resolution

The subject is a **pair**, not a directory — that was the first thing the
implementation got wrong and the reproduction corrected. A directory alone
cannot express `git push origin mine` typed in a checkout sitting on another
branch, which is the sharper of the two reported symptoms; a commit alone cannot
express `git -C <worktree> push` when the two trees have diverged.

- **`_SUBJ_ROOT`** — from `git -C <path>` / `--work-tree` on the git invocation,
  else a `cd <path>` in an earlier segment of the same compound command, else the
  process cwd.
- **`_SUBJ_REV`** — from the single refspec's source half, when there is exactly
  one and it is not `HEAD`, a wildcard, or a deletion; else `HEAD`.

The payload's `.cwd` is deliberately **not** consulted. On this harness it is the
session cwd, i.e. the same value the process already has, so reading it would add
a field and no information. If that ever stops being true it belongs between the
`cd` leg and the process cwd.

### Validation, and why it is the security boundary

The gated command is model-authored, so both hints are claims, not facts —
`hooks/lib/git-command.sh` only *reports* them and validates nothing, exactly as
`pr_ref_from_command` does. The guard then:

- accepts a directory only if it exists and `git rev-parse --git-common-dir`,
  canonicalised, equals the process repo's — so a path can only ever redirect the
  gate to **another worktree of the same repository**, never to an unrelated
  clone and never outside git;
- accepts a ref only if it resolves under `refs/heads/` inside that root, and
  passes it to git as `refs/heads/<name>` — a fully-qualified revision, so no
  value from the command can be read as a flag or a path;
- **discards** anything else and keeps the process-derived subject, i.e. exactly
  today's behaviour. Discarding never opens a gate.

### Why this is not a bypass

The obvious objection is that a model could point the gate at a clean tree to
escape a deny. It cannot escape anything it is not already entitled to: the
command it is running genuinely acts on that tree, and the gate's job is to
measure the command. `git -C <other-worktree> push` pushes *that* worktree's
branch; if that branch is clean, allowing the push is correct, and the dirty
branch the session is sitting on is not being pushed at all. The forgery-relevant
property is unchanged — verdict acceptance is still sha-bound (HEAD-or-ancestor
for the own token, exact-HEAD for the cross-token bridge, #51/#156). What changed
is which sha we ask about, not what counts as covered.

## What deliberately did NOT move to the subject

**Branch-ledger reads** (`branch_ledger_has`, `_bridge_has`, `_ledger_has`,
`phase_step_satisfied`). The ledger's writer, `hooks/skill-completion-hook.sh`,
keys records on *its* process cwd and branch. Re-pointing only the reader at the
subject would make every existing record invisible to it — strictly **more**
denies, which is the wrong direction for a false-block fix. The cross-location
bridge (#131) exists precisely to span that split, and `_HEAD_SHA` stays
process-derived so the bridge's branch-locality rule keeps comparing like with
like.

**`pr_changed_files`.** Its `proot` argument only scopes `gh` to the right
repository, and a `gh pr merge` yields no subject hints at all (both helpers are
push-only), so the subject and the process root are identical there by
construction.

Review raised the mirror-image argument for moving it: `gh` auto-detects the
target GitHub repo from the local origin remote of whatever directory it runs in,
so if a merge really executed via `cd <worktree> && gh pr merge`, the gate should
match. Rejected as a no-op, on the fact that makes it one: `_SUBJ_ROOT` is only
ever accepted after it validates as a worktree of the **same repository**, and
worktrees share the origin remote — so both roots resolve to the same GitHub
repo by construction. Moving it would add a call-graph fork for no measurable
difference. If subject-directory resolution is ever extended to `gh` commands,
revisit this line first.

**`phase_step_satisfied`.** Also stays on the process root, and this one is
higher-stakes than it looks: it backs the DESIGN/PLAN outbound leg, which CAN
deny. Only its branch-ledger leg reads the argument at all, and that leg must
share the writer's key for the same reason as above — "it is diff-adjacent" is a
shape, not a reason.

## Coupling: the IMPLEMENT shadow corpus

`_diff_touches_material_source` feeds the warn-only IMPLEMENT-evidence leg, whose
records carry a `predicate_version` that CLAUDE.md forbids pooling across. Moving
it to the subject changes **when the leg fires** — a push measured against a
concurrent session's branch could report `material_source` on a branch touching
no source, and vice versa — so `IMPLEMENT_SHADOW_PREDICATE_VERSION` goes **2 → 3**
and the v2 records stop being poolable.

Leaving the leg on the wrong subject to protect the corpus was **argued for in
review** — the leg is advisory-only, so a wrong subject costs a misclassified
record rather than a bad gate outcome, and the bump discards a corpus already far
behind schedule. Rejected on #161's own finding: *a corpus whose records describe
the wrong subject cannot be segmented back into correctness by a reader who was
not there.* A smaller correct corpus beats a larger one that is not evidence, and
#161 set exactly this precedent by bumping v1 → v2 for this defect class on the
merge path. Leaving one leg measuring the session's branch while every other leg
measures the pushed branch would also read as an oversight, not a decision, to
the next person in this file.
The cost is small and already sunk — the v2 corpus holds **2** would-block
episodes, both from 2026-08-02/03, neither adjudicated. The records also now
carry the subject's branch and sha rather than the checkout's, so episode
identity `(repo, branch, session_token)` names the work it actually describes.

This makes the corpus-accumulation problem in #199 strictly worse and should be
read alongside that issue's re-registration, not separately.

## Announcement (#198)

A gate that silently measures something other than what it says it measured is
the failure this issue is about, so:

- when the subject differs from the process cwd, or a hint was discarded as
  unvalidatable, the guard says so;
- **the note rides on the deny itself**, which is a deliberate exception to
  "advisories are dropped where a deny fires". The other advisories are
  commentary; this one names the tree and ref the decision was computed over, and
  a deny whose predicate is false of the command is the whole bug. It is empty
  for every command that offers no subject hint — that is, for every command that
  could reach a deny before this change, so no existing deny text moves.

## Regression

`tests/test-push-gate-subject.sh`, 12 cells against the real guard and real git
repositories. The three flips are paired with controls that must keep denying: a
routing subject with no covering verdict, and a verdict bound to a **different**
commit than the subject (acceptance must not widen). Two security cells drive a
`-C` into an unrelated repository and into a missing directory and assert the
deny still stands, and two more assert the discarded hint is named rather than
swallowed. Measured red before the fix: 5 of 10 failing, with every control
already green — so the suite cannot pass by simply denying less.

## Out-of-scope

- `--git-dir=`, and any path or ref arriving through a variable, command
  substitution, or `bash -c` — the documented string-detection ceiling.
- A path containing whitespace (the segment scanner splits on it); such a hint
  fails validation and is announced, never guessed at.
- Widening what counts as a covering verdict.
- The IMPLEMENT deny-flip itself, and the decision rule behind it (#199).
