# Plan: gate-gh-merge-and-compound-push (3 TDD tasks, audit F2)

Branch: `fix/gate-gh-merge-and-compound-push` (off main @ ebdaf53).
Spec: `openspec/changes/gate-gh-merge-and-compound-push/` (committed).

## Task 1 — RED: detector + guard regressions

Detector units (`tests/test-push-gate-detection.sh`):
- [ ] `command_invokes_gh_merge` MATCHES: `gh pr merge`, `gh pr merge 123 --auto`,
      `gh -R o/r pr merge 5`, `gh pr merge --squash --delete-branch`,
      `gh api -X PUT repos/o/r/pulls/5/merge`, `gh api graphql -f query='mutation { mergePullRequest(...) }'`.
- [ ] NO-MATCH: `gh pr create --title "gh pr merge fix"`, `gh pr view 5`,
      `echo "gh pr merge"`, `git commit -m "gh pr merge"`, `gh pr list | grep merge`.
- [ ] `command_git_mutate_before_push` MATCHES: `git commit -m x && git push`,
      `git add -A; git commit -m x; git push origin HEAD`,
      `git checkout main && git merge f && git push`, `git rebase main && git push`.
- [ ] NO-MATCH: `git push origin HEAD`, `git pull && git push`,
      `git push && git commit -m x` (push first), `echo "git commit && git push"`.
- [ ] `command_invokes_git_write` existing assertions untouched and green
      (byte-compatible refactor onto `_gc_segment_git_sub`).

Guard behavior (`tests/test-push-gate-failclosed.sh` additions):
- [ ] `gh pr merge 123` with empty evidence → deny naming missing milestone(s).
- [ ] `gh pr merge 123` with ledger REVIEW+VERIFY + clean verdict → no deny.
- [ ] `gh pr create ...` → never denied (any evidence state).
- [ ] `git commit -m x && git push` with FULL clean evidence → deny with
      separate-command remedy (spec scenario: evidence cannot cover compound).
- [ ] Plain `git push` same state → compound rule silent.
- [ ] Exported ACSM_SKIP_PUSH_GATE=1 bypasses the gh-merge and compound denies.

## Task 2 — GREEN: implement

- [ ] `hooks/lib/git-command.sh`: extract `_gc_segment_git_sub`; rewrite
      `command_invokes_git_write` on it (semantics identical); add
      `command_invokes_gh_merge` + `command_git_mutate_before_push`.
- [ ] `hooks/openspec-guard.sh`: pre-filter `*git*|*gh*`; fast-path OR-in
      gh-merge (substring fallback: `"gh pr merge"`, `mergePullRequest`,
      `pulls/`+`/merge`); `_gc_is_outbound`; `_GATE_ACTION` in messages;
      compound deny first in body; routing gate stays push-only.
- [ ] `/bin/bash -n` both files; Task 1 green; affected suites green.

## Task 3 — Docs + full verification

- [ ] CLAUDE.md push-gate bullet: gh-merge coverage, compound rule, branch
      protection as per-PR backstop, gh-merge proxy-evidence limitation.
- [ ] CHANGELOG `[Unreleased]` Added entry.
- [ ] Full suite `bash tests/run-tests.sh < /dev/null` green; fresh verdict at
      HEAD (routing paths touched); push as separate command.
