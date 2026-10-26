# agent-team-review — §4a reproduction worktree

Read at SKILL.md §4a before running any reproduction by pairing. The isolation rule stays in SKILL.md. Moved verbatim from SKILL.md.

```bash
WT="$(mktemp -d)"; git worktree add --detach "$WT" {head_sha}
# {head_sha} is the review range's head — the tree the reviewers actually read.
# Committed work needs nothing further; the sha already carries it.
#
# UNCOMMITTED work must be carried across, or a bare checkout of the sha
# adjudicates the PARENT state and "fails to reproduce" every finding about it.
# Diff against HEAD, NOT against {base_sha}: base..head is already IN the sha,
# so applying that would re-apply committed changes on top of themselves and
# fail (or worse, half-apply).
git diff HEAD | git -C "$WT" apply          # tracked, uncommitted
# Untracked files are in NEITHER the diff nor the sha, so list AND copy any the
# finding depends on — discovering them is not carrying them, and a missing one
# makes the finding "fail to reproduce" for a reason unrelated to the claim:
#   git ls-files --others --exclude-standard | while IFS= read -r f; do
#     mkdir -p "$WT/$(dirname "$f")"; cp "$f" "$WT/$f"; done
...
git worktree remove --force "$WT"   # reap it, like §3 reaps reviewer worktrees
```
