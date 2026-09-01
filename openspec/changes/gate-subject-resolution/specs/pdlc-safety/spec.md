# Spec delta: pdlc-safety — push-gate subject resolution

## ADDED Requirements

### Requirement: The push gate measures the subject the gated command names

The push gate's diff predicates and verdict lookup MUST be evaluated against the
git subject the gated command acts on, not against the hook process's working
directory.

The subject is a pair. The subject **directory** MUST be taken, in order, from
an explicit `-C <path>` or `--work-tree` on the git invocation, then from a
`cd <path>` in an earlier segment of the same compound command, then from the
process working directory. The subject **revision** MUST be taken from the
source half of the push's refspec when the command names exactly one refspec
that is not `HEAD`, not a wildcard, and not a deletion; otherwise it MUST be the
subject directory's `HEAD`.

A directory named by the command MUST NOT be used unless it exists and resolves
to a worktree of the **same repository** as the process working directory
(equal, canonicalised `--git-common-dir`). A ref named by the command MUST NOT
be used unless it resolves under `refs/heads/` in the subject directory, and it
MUST be passed to git fully qualified as `refs/heads/<name>`. A candidate
failing either check MUST be discarded, and the gate MUST then behave exactly as
it did before this requirement existed.

Resolving the subject MUST NOT widen what counts as a covering verdict: sha
binding (HEAD-or-ancestor for the session's own token, exact HEAD for the
cross-token bridge) is unchanged, and only the commit being asked about moves.

Branch-ledger evidence lookups MUST continue to resolve their key from the
process working directory, because the ledger's writer keys records the same
way; re-pointing only the reader would hide existing records and produce
additional denials.

When the resolved subject differs from the process working directory, or a
subject hint was discarded, the gate MUST say so. That statement MUST accompany
a denial as well as an allowance, because a denial whose stated predicate
describes a different tree is the failure this requirement addresses.

Changing what the IMPLEMENT-evidence leg measures MUST increment
`IMPLEMENT_SHADOW_PREDICATE_VERSION`, and records of differing
`predicate_version` MUST NOT be pooled when computing any rate.

#### Scenario: a push from a private worktree is measured in that worktree

- **GIVEN** a routing repository whose shared checkout is on a concurrent
  session's branch that edits `config/`, a private worktree holding a branch
  that edits no routing path, and a clean verification verdict bound to that
  worktree's HEAD
- **WHEN** the model runs `git -C <worktree> push origin <branch>` from the
  shared checkout
- **THEN** the routing-governance gate MUST NOT deny
- **AND** the gate MUST state that it measured the worktree

#### Scenario: a refspec names the branch being pushed

- **GIVEN** the same repository state
- **WHEN** the model runs `git push origin <branch>` from the shared checkout,
  where `<branch>` is a local branch touching no routing path
- **THEN** the routing-governance gate MUST NOT deny

#### Scenario: a subject that genuinely lacks a covering verdict still denies

- **GIVEN** a worktree whose branch edits `config/` and a clean verdict bound to
  a different commit
- **WHEN** the model pushes that branch
- **THEN** the routing-governance gate MUST deny

#### Scenario: an unvalidatable directory hint is ignored and named

- **GIVEN** a shared checkout on a branch that edits `config/` with no covering
  verdict
- **WHEN** the model runs `git -C <path-in-an-unrelated-repository> push`
- **THEN** the gate MUST deny as it would have without the hint
- **AND** the denial MUST state that the named directory is not a worktree of
  this repository
