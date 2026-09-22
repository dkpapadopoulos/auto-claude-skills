## PR Review: serena-nudge.sh — extend to Bash tool + single-jq-fork optimization

**Summary**

This PR does two things: (1) extends the hook's tool-name gate from `Grep`-only to `Grep|Bash` so pattern-based nudges fire when agents search via `grep`/`rg`/`ag` through the Bash tool (the population that went dark after #124 wired the hook to every Bash call but the hook's inner gate still required `tool_name == "Grep"`), and (2) collapses three separate jq field reads into a single `join("^_")` parse, eliminating two extra forks per Bash invocation for every serena user. The logic is sound, the fail-open invariant is preserved, and the PR is mergeable as-is.

---

**What passes ✅**

- No `set -e`; `trap 'exit 0' ERR` is intact — hook is fail-open throughout.
- No hardcoded secrets, tokens, PII, or private hostnames.
- File name (`serena-nudge.sh`) stays kebab-case.
- Bash 3.2 compat: `$'\x1f'` ANSI-C quoting, `%%`/`#*` parameter expansion, and `case` are all 3.2-clean. No `declare -A` or other Bash 4+ constructs.
- jq absence handled correctly: when jq is unavailable, `_TOOL_NAME=""` → `case` falls to `*) exit 0 ;;` (line 56-57). Fail-open. ✅
- Field separator `\x1f` (US) used for multi-field extraction from jq; documented with the reason `@tsv` and newline encoding are unsuitable.
- Second jq fork for `_CACHE` read (line 63) is necessarily separate (different input source); `|| true` keeps it out of the ERR trap path. ✅
- The `set -- ${_CMD}` unquoted word-split path (line 99) is intentional and correct — the `# shellcheck disable=SC2086` is appropriate.
- `shift; shift 2>/dev/null || break` at line 105: first `shift` is always safe (loop condition guarantees `$# ≥ 1`); second `shift` failure is caught by `|| break`. ✅
- No writes to `~/.claude/.skill-*-state-*`; concurrent-session safety unaffected.
- Telemetry token is hashed (sha256, 12-char hex); raw token not persisted. ✅
- `case` gate improvement (lines 55-58) is cleaner and more idiomatic than the old `[ "${_TOOL_NAME}" = "Grep" ] || exit 0`.
- The Bash extractor deliberately fails silently for unrecognised shapes (pipelines, variable-expanded patterns, xargs) rather than emitting a wrong nudge. Correct posture for advisory-only output.

---

**Blocking issues 🚫**

None.

---

**Recommendations 💡**

- **hooks/serena-nudge.sh:206 — telemetry `detail` field is now inaccurate for the Bash path.** The hardcoded `grep_extension` was correct when only `Grep` calls reached this point, but now Bash-originated nudges also record `grep_extension`. The whole motivation for this PR is that the Bash channel was unmeasured; if the `detail` field can't distinguish the two, the telemetry can't confirm the new path is actually firing. A minimal fix: use `${_TOOL_NAME}_grep` or emit `bash_grep` vs `native_grep` depending on `_TOOL_NAME`. Non-blocking because the nudge itself is correct and advisory-only.

- **hooks/serena-nudge.sh:18 — comment says "(PR review)".** Per repo style ("Don't reference the current task, fix, or callers — those belong in the PR description and rot"), the parenthetical `(PR review)` should be dropped. The surrounding explanation of why a single jq fork matters is genuinely non-obvious and worth keeping; the task reference isn't.
