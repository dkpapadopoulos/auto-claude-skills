# Proposal: Gate gh merges and compound mutate-then-push (audit F2)

## Why

The push gate intercepts only `git push` (and advisory `git commit`). The
2026-07-14 enforcement audit (F2, ranked high — "arguably critical" by the
Codex sparring pass) found two ways work reaches the remote around it:

1. **`gh pr merge` is completely ungated** — merging a PR to the default
   branch is the real outward boundary, and the guard's fast-path never sees
   `gh` commands. `gh api` can likewise hit the REST merge endpoint
   (`PUT repos/.../pulls/.../merge`) or GraphQL `mergePullRequest` directly.
2. **Compound mutate-then-push** (`git commit -m fix && git push`): the gate
   evaluates PRE-EXEC state — the verdict/ledger it checks describe the HEAD
   before the inline commit, so the actually-pushed commit is unverified.
   This also evades the routing-governance delta check (the not-yet-created
   commit cannot be diffed). CLAUDE.md already documents "verdict-write and
   git push must be separate commands"; this makes the same principle
   deterministic for content mutation.

## What Changes

- `hooks/lib/git-command.sh`: two new predicates reusing the existing
  quote-aware segment splitter — `command_invokes_gh_merge` (`gh pr merge` in
  any flag order incl. `--auto`/`-R`; `gh api` segments naming the REST merge
  path or `mergePullRequest`) and `command_git_mutate_before_push` (a segment
  invoking a content-mutating git subcommand — `commit merge cherry-pick
  rebase revert am` — ordered before a `git push` segment). The git-subcommand
  token walk is extracted into a shared helper; `command_invokes_git_write`
  semantics are byte-compatible (pinned by existing tests).
- `hooks/openspec-guard.sh`: pre-filter widened (`*git*|*gh*`); fast-path
  proceeds for git-writes OR gh-merges (substring fallback stays fail-closed:
  `gh pr merge` / `mergePullRequest` / `pulls/…/merge` literals). gh-merge
  flows through the SAME deny gates as push (composition REVIEW/VERIFY,
  verify-hardening, global fail-closed) with the deny message naming the
  action. Routing-governance stays push-only (its diff base is branch-local).
  New unconditional deny (before the evidence gates, human bypass honored):
  push preceded by a mutating git segment in the same command → remedy "run
  the push as a separate command".
- `gh pr create` is DELIBERATELY not gated — PR creation is the start of
  review, not the end. Pinned by a regression test.
- Docs: CLAUDE.md push-gate bullet notes the gh-merge coverage, the compound
  rule, and that GitHub branch protection is the real per-PR backstop —
  shell-string detection of `gh api` is best-effort by construction.

## Capabilities

- **Modified: pdlc-safety** — outbound-boundary coverage of the push gate.
- Touched: `hooks/lib/git-command.sh`, `hooks/openspec-guard.sh`,
  `tests/test-push-gate-detection.sh`, `tests/test-push-gate-failclosed.sh`,
  `CLAUDE.md`.

## Impact

- Closes audit F2's cheapest paths (`gh pr merge`, compound push). Known
  accepted limits: exotic `gh api` encodings evade string detection (branch
  protection is the backstop); gh-merge evidence is the CURRENT session/branch
  proxy — a PR from another branch may be blocked despite that branch having
  been reviewed elsewhere (remedy: human merge, the intentional escape hatch).
- False-block discipline: mutating set excludes `pull`/`reset`; all new denies
  honor the human-only bypass and fail open on infra errors.
