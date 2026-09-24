## PR Review: verdict dirty-tree measurement disclosure (#274)

**Summary:** This PR adds advisory disclosure when the push gate accepts a verification verdict that was measured on a dirty working tree. Three commits: the advisory infrastructure in `openspec-guard.sh` + new reader functions in `verdict.sh` (ed56295), a `+k more` remainder fix (6402dc8), and the recording-side fix to capture real path names via `--porcelain -z` instead of git's C-style-quoted output (15807f9). The change is advisory-only — it never gates on `worktree_dirty`, consistent with the existing design. Test coverage is comprehensive. **Mergeable.**

---

### What passes ✅

- **No `set -e`** introduced in any hook. `openspec-guard.sh` retains its `trap 'exit 0' ERR` fail-open semantics throughout.
- **Bash 3.2 compatible.** No associative arrays, no `declare -A`, no `${BASH_SOURCE[0]}`, no quoted `$(( "…" ))` arithmetic. The awk script is POSIX awk.
- **jq optional.** Both `verdict_measured_dirty` and `verdict_dirty_note` gate on `command -v jq` and return 1 on absence. `_note_dirty_verdict` therefore degrades silently when jq is missing — no enforcement to announce the loss of, per the inline comment.
- **Fail-open at every error path.** `verdict_artifact_path` returns 1 on empty token; `[ -f "$f" ] || return 1` guards missing artifacts; the caller's `|| _where=""` handles any non-zero from `verdict_dirty_note`. The function never reaches `_STALE_MSG` on an error.
- **Single writer, both acceptance points.** `_note_dirty_verdict` is called at line 1519 (chain VERIFY leg) and 1633 (routing-governance leg), not inlined at each — directly applying the #166 lesson about the merge-suppression rule diverging at duplicate call sites.
- **Dedup flag wired correctly.** `_DIRTY_NOTED=false` is set in the outer scope before either acceptance point. The function sets it without `local`, so the outer variable is modified. Test section (5) verifies the one-emission property using a state that actually triggers both legs (the prior state only triggered one and was vacuous).
- **Scoped correctly.** `local _where=""` inside `_note_dirty_verdict` prevents pollution. `_DIRTY_NOTED` and `_STALE_MSG` are correctly outer-scope.
- **Advisory-only boundary pinned.** The function appends to `_STALE_MSG` only; it has no `permissionDecision`, no `exit`. Test section (6) asserts a deny still drops the advisory (the #198 boundary).
- **`--porcelain -z` + awk correctly handles renames.** After `tr '\0' '\n'`, a rename entry is two lines: `R  new` then `orig`. The awk `skip { skip=0; next }` on the second entry records only the new path. The test (section 1b) asserts `renamed.txt` is present and `->` is absent.
- **`--porcelain -z` correctly handles special characters.** Backslash, double-quote, UTF-8, and space paths are tested (section 1b) against the real writer. The `-z` output bypasses git's C-style quoting, so `unicode-ü.txt` arrives as itself.
- **`dirty_path_count` is the TRUE total.** `WORKTREE_DIRTY_COUNT` is computed from the full `_WD_PATHS` list before capping; `_WD_PATHS_CAPPED` is the first 20. The truncation note in `verdict_dirty_note` correctly shows `+32 more` for a 37-total / 20-stored fixture and states the cap as a fact about the RECORD. Test section (2) pins the exact strings.
- **Legacy record handled.** `dirty-legacy-no-paths.json` (no `dirty_paths` key) exercises the `(.dirty_paths // []) as $p | if ($p | length) == 0 then ""` early-return. The test asserts an empty note, which the guard branches on to emit the "does not say which paths" variant rather than fabricating a list.
- **`grep -c .`** in `verify-and-record.sh` line 136 is counting non-empty lines — not a regex gotcha; `.` is intentional here (counts any non-empty path line).
- **No hardcoded secrets, tokens, PII, or private hostnames.**
- **Field separators preserved.** `_STALE_MSG` continues to use `; ` as its in-message separator; no `\x1f`/`\x01` fields are touched.
- **`run-tests.sh` auto-discovers** `test-*.sh` by glob; the new `test-verdict-dirty-tree.sh` is picked up without a manual registration.

---

### Blocking issues 🚫

None.

---

### Recommendations 💡

- `assert_not_contains "a rename is not recorded as a pair" "->"` (test-verdict-dirty-tree.sh, section 1b) would give a false pass if a legitimate path happened to contain `->`. It is testing against the old `--porcelain` rendering artifact (`old -> new`), which cannot appear in `-z` output. Consider replacing the negative with `assert_not_contains "old path of rename is not recorded" "to-rename.txt"` — that pins the actual property (old path absent) rather than the absent format string.
- `WORKTREE_DIRTY_COUNT="$(printf '%s' "${_WD_PATHS}" | grep -c . || :)"` (verify-and-record.sh line 136): works correctly, but the `|| :` is redundant when `_WD_PATHS` is non-empty (which it always is at that point, since `WORKTREE_DIRTY=true` is set only when `_WD_PATHS` is non-empty). Not a bug; just slightly noisy.
