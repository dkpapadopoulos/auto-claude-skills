#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-detection.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pgd-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"
_TOK="session-t"
# REVIEW+VERIFY in chain, completed empty, no ledger, no verdict => a real push
# hits the fail-closed gate and DENIES. A non-write command must exit before that.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' \
    > "$HOME/.claude/.skill-composition-state-${_TOK}"

_run() {
    jq -n --arg tp "$_TPATH" --arg c "$1" \
      '{"transcript_path":$tp,"tool_input":{"command":$c}}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null
}

# (a) Read-only command that merely mentions the phrase -> NO deny.
out="$(_run 'grep -nE "git push|deny" hooks/openspec-guard.sh')"
assert_not_contains "grep with phrase is not gated" '"deny"' "${out:-}"

# (b) echo mentioning the phrase -> NO deny.
out="$(_run 'echo "reminder: git push later"')"
assert_not_contains "echo with phrase is not gated" '"deny"' "${out:-}"

# (c) A real push with no evidence -> DENY (gate still fires).
out="$(_run 'git push origin HEAD')"
assert_contains "real push is gated" '"deny"' "${out:-<empty>}"

# (d) A real push via -C global flag -> DENY.
out="$(_run 'git -C /tmp/x push -u origin feature/y')"
assert_contains "push with -C is gated" '"deny"' "${out:-<empty>}"

# (e) Guard-level: a bare paren-wrapped push must reach the gate (real-world
#     impact of the trailing-closer fix — pre-fix this was silently allowed).
out="$(_run '(git push)')"
assert_contains "bare paren-wrapped push is gated" '"deny"' "${out:-<empty>}"

# Pre-filter: a large command with no "git" substring is not gated (and returns fast).
_big_nogit="echo $(printf 'x%.0s' $(seq 1 6000))"
out="$(_run "${_big_nogit}")"
assert_not_contains "large non-git command not gated" '"deny"' "${out:-}"

# Length cap: a >4096-char command that IS a real push still denies (substring fallback, fail-closed).
_big_push="git push origin HEAD # $(printf 'y%.0s' $(seq 1 4200))"
out="$(_run "${_big_push}")"
assert_contains "oversized real push still gated (fallback)" '"deny"' "${out:-<empty>}"

# --- Predicate units: gh-merge + compound mutate-then-push (audit F2) -------
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/git-command.sh"

_assert_pred() { # <desc> <expected 0|1> <fn> <cmd>
    local _rc=0
    "$3" "$4" >/dev/null 2>&1 || _rc=1
    assert_equals "$1" "$2" "${_rc}"
}

# command_invokes_gh_merge — MATCH (expect 0)
_assert_pred "gh pr merge (bare)"                 0 command_invokes_gh_merge 'gh pr merge'
_assert_pred "gh pr merge with number+auto"       0 command_invokes_gh_merge 'gh pr merge 123 --auto'
_assert_pred "gh -R repo pr merge"                0 command_invokes_gh_merge 'gh -R o/r pr merge 5'
_assert_pred "gh pr merge squash delete-branch"   0 command_invokes_gh_merge 'gh pr merge --squash --delete-branch'
_assert_pred "gh api REST pull merge"             0 command_invokes_gh_merge 'gh api -X PUT repos/o/r/pulls/5/merge'
_assert_pred "gh api graphql mergePullRequest"    0 command_invokes_gh_merge "gh api graphql -f query='mutation { mergePullRequest(input: {}) }'"
_assert_pred "gh merge after other segment"       0 command_invokes_gh_merge 'git fetch origin && gh pr merge 7'
# command_invokes_gh_merge — NO MATCH (expect 1)
_assert_pred "gh pr create mentioning merge"      1 command_invokes_gh_merge 'gh pr create --title "gh pr merge fix"'
_assert_pred "gh pr view"                         1 command_invokes_gh_merge 'gh pr view 5'
_assert_pred "echo phrase"                        1 command_invokes_gh_merge 'echo "gh pr merge"'
_assert_pred "git commit msg mentioning phrase"   1 command_invokes_gh_merge 'git commit -m "gh pr merge"'
_assert_pred "gh pr list piped to grep merge"     1 command_invokes_gh_merge 'gh pr list | grep merge'
_assert_pred "gh api unrelated endpoint"          1 command_invokes_gh_merge 'gh api repos/o/r/pulls/5/comments'

# command_git_mutate_before_push — MATCH (expect 0)
_assert_pred "commit && push"                     0 command_git_mutate_before_push 'git commit -m x && git push'
_assert_pred "add; commit; push"                  0 command_git_mutate_before_push 'git add -A; git commit -m x; git push origin HEAD'
_assert_pred "checkout+merge+push"                0 command_git_mutate_before_push 'git checkout main && git merge f && git push'
_assert_pred "rebase && push"                     0 command_git_mutate_before_push 'git rebase main && git push'
# command_git_mutate_before_push — NO MATCH (expect 1)
_assert_pred "plain push"                         1 command_git_mutate_before_push 'git push origin HEAD'
_assert_pred "pull && push (excluded set)"        1 command_git_mutate_before_push 'git pull && git push'
_assert_pred "push before commit"                 1 command_git_mutate_before_push 'git push && git commit -m x'
_assert_pred "quoted phrase only"                 1 command_git_mutate_before_push 'echo "git commit && git push"'

# Grouped forms: subshell/brace wrapping must not hide the invocation — a
# bare `(git push)` would otherwise evade the milestone gate entirely.
_assert_pred "paren-wrapped push detected"        0 command_invokes_git_write '(git push origin HEAD)'
_assert_pred "brace-group push detected"          0 command_invokes_git_write '{ git push origin HEAD; }'
_assert_pred "paren-wrapped gh merge detected"    0 command_invokes_gh_merge '(gh pr merge 5)'
_assert_pred "paren commit then push (compound)"  0 command_git_mutate_before_push '(git commit -m x) && git push'
_assert_pred "brace group commit;push (compound)" 0 command_git_mutate_before_push '{ git commit -m x; git push; }'
_assert_pred "quoted paren phrase still ignored"  1 command_invokes_git_write "echo '(git push)'"
# Trailing-closer forms: the closer glues onto the FINAL token when the
# subcommand (or its last arg) is last — review round 2 caught bare forms
# evading while the args-carrying test above stayed green.
_assert_pred "bare paren-wrapped push detected"   0 command_invokes_git_write '(git push)'
_assert_pred "cd-subdir paren push detected"      0 command_invokes_git_write '(cd sub && git push)'
_assert_pred "bare paren gh merge detected"       0 command_invokes_gh_merge '(gh pr merge)'
_assert_pred "fully-parenthesized compound"       0 command_git_mutate_before_push '(git commit -am x && git push)'
# gh api merge-status GET is a READ — must not be gated; PUT forms are writes.
_assert_pred "gh api GET merge-status not gated"  1 command_invokes_gh_merge 'gh api repos/o/r/pulls/5/merge'
_assert_pred "gh api --method PUT merge gated"    0 command_invokes_gh_merge 'gh api --method PUT repos/o/r/pulls/5/merge'

# Refactor guard: existing write-detection semantics must be unchanged.
_assert_pred "git push still detected"            0 command_invokes_git_write 'git push origin HEAD'
_assert_pred "git -C push still detected"         0 command_invokes_git_write 'git -C /tmp/x push'
_assert_pred "phrase-in-echo still not detected"  1 command_invokes_git_write 'echo "git push"'

# --- issue #155: newline inside a QUOTED argument is not a command boundary ---
# _gc_split_segments is quote-aware for ; | & but emits segments newline-delimited,
# and callers iterate with IFS=$'\n'. A newline inside quotes therefore survived the
# quote-aware scan and became a boundary anyway, so a multi-line quoted payload with
# a git-write-shaped LINE was classified as a real push. Measured in production: 5
# of 26 deny records were `node .../codex-companion.mjs "<multi-line prompt>"`
# invocations that push nothing (one of them deny:routing-governance, a push-only leg).
_MLQ='node /x/codex.mjs task "review this
git push origin main
and tell me why"'
_assert_pred "newline in quoted arg is not a boundary"   1 command_invokes_git_write "${_MLQ}"
_MLQ_SQ="node /x/codex.mjs task 'steps:
git push origin main
done'"
_assert_pred "newline in single-quoted arg either"       1 command_invokes_git_write "${_MLQ_SQ}"
# NOTE: a "quoted multi-line is not mutate-then-push" assertion was deliberately
# NOT added here. It passes on UNFIXED code for an unrelated reason — the final
# segment is `git push"` and _gc_segment_git_sub strips trailing )/} but not `"`,
# so the sub is `push"` != `push`. It would exert zero regression pressure while
# reading as coverage. Review caught it; the real guarantee is the e2e block below.

# ...but a REAL newline-separated compound (outside quotes) MUST still be detected —
# newline is a legitimate shell command separator; this is the other side of the fix.
_REAL='cd /tmp/x
git push origin HEAD'
_assert_pred "unquoted newline compound still detected"  0 command_invokes_git_write "${_REAL}"
_REAL_MUT='git commit -am x
git push'
_assert_pred "unquoted newline mutate-then-push caught"  0 command_git_mutate_before_push "${_REAL_MUT}"

# --- #155 follow-up: UNBALANCED-quote parses must never under-detect ----------
# Making newline a boundary inside the quote scanner made that scanner's quote
# state load-bearing for multi-line commands. Its model diverges from the
# shell's: it does not interpret backslash escapes, `#` comments, or heredoc
# bodies. An apostrophe in any of those leaves it falsely "inside a quote", the
# newline is consumed literally, and a following REAL push never becomes its own
# segment -> gate bypass. bash genuinely executes the push in every case below.
# The scanner must report the unbalanced parse so callers fail CLOSED.
# The lib predicates are DOCUMENTED fail-open and still miss these (they have no
# backslash/comment/heredoc model). The guarantee lives one layer up: the guard's
# _gc_precise rejects an unbalanced parse and drops to its fail-CLOSED substring
# path, so the push is still DENIED end-to-end. Assert the balance predicate at
# the lib layer and the deny at the guard layer.
_UB_COMMENT="# don't forget
git push origin HEAD"
_UB_ESC="echo it\\'s
git push origin HEAD"
_UB_HEREDOC="cat <<EOF
it's here
EOF
git push origin HEAD"

# Balance predicate: #155 payloads stay BALANCED (precise path preserved);
# bypass payloads are UNBALANCED (force the fail-closed fallback).
_assert_pred "quoted-newline payload parses balanced"    0 command_parse_balanced "${_MLQ}"
_assert_pred "awk-style single quotes parse balanced"    0 command_parse_balanced "awk '{print \$1}' f"
_assert_pred "nested quotes parse balanced"              0 command_parse_balanced "echo \"a 'b' c\""
_assert_pred "apostrophe comment parses unbalanced"      1 command_parse_balanced "${_UB_COMMENT}"
_assert_pred "heredoc apostrophe parses unbalanced"      1 command_parse_balanced "${_UB_HEREDOC}"

# END-TO-END: unbalanced-quote payloads carrying a real push must still DENY.
out="$(_run "${_UB_COMMENT}")"
assert_contains "apostrophe-comment push still denied" '"deny"' "${out:-<empty>}"
out="$(_run "${_UB_ESC}")"
assert_contains "escaped-quote push still denied"      '"deny"' "${out:-<empty>}"
out="$(_run "${_UB_HEREDOC}")"
assert_contains "heredoc-apostrophe push still denied" '"deny"' "${out:-<empty>}"
# ...and the #155 false-block payload must still be ALLOWED (fix not undone).
out="$(_run "${_MLQ}")"
assert_not_contains "quoted-newline payload still allowed" '"deny"' "${out:-}"

export HOME="$_OLDHOME"
print_summary
exit $?
