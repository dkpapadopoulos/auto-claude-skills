#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-pr-diff.sh ==="

. "${PROJECT_ROOT}/hooks/lib/pr-diff.sh"

# --- ref extraction -------------------------------------------------------
assert_equals "plain merge with number"      "7" "$(pr_ref_from_command 'gh pr merge 7 --squash')"
assert_equals "number after flags"           "7" "$(pr_ref_from_command 'gh pr merge --squash 7')"
assert_equals "rest api merge path"          "7" "$(pr_ref_from_command 'gh api repos/o/r/pulls/7/merge')"
assert_equals "delete-branch flag ignored"  "12" "$(pr_ref_from_command 'gh pr merge 12 --squash --delete-branch')"

# Fix round 1, IMPORTANT 1a: a digit-leading token BEFORE the literal `merge`
# token (e.g. a flag value like `--org 42`) must never be mistaken for the PR
# ref -- the loop must gate the digit test on having seen `merge` first.
assert_equals "digit-leading token before merge is not the ref" "7" \
    "$(pr_ref_from_command 'gh --org 42 pr merge --squash 7')"

# Fix round 1, IMPORTANT 1b: the token loop uses an unquoted `for tok in $cmd`,
# which performs pathname expansion as well as word-splitting -- a bare `*`
# token in the command text must stay a literal asterisk, never expand
# against files in the caller's cwd.
_GLOBTEST_DIR="$(mktemp -d /tmp/prdiff-globtest-XXXXXX)"
( cd "${_GLOBTEST_DIR}" && mkdir 42 && touch 99 )
assert_equals "unquoted loop token is not glob-expanded" "999" \
    "$(cd "${_GLOBTEST_DIR}" && pr_ref_from_command 'gh pr merge * 999')"
rm -rf "${_GLOBTEST_DIR}"

# --- SECURITY: a non-integer token must never be returned ----------------
# The command is model-authored. Returning anything but a bare integer would let
# a crafted command inject flags (e.g. --repo other/org) into the gh call.
assert_equals "flag in ref position rejected"   "" "$(pr_ref_from_command 'gh pr merge --repo other/org --squash')"
assert_equals "path-shaped ref rejected"        "" "$(pr_ref_from_command 'gh pr merge ../../etc/passwd')"
assert_equals "semicolon injection rejected"    "" "$(pr_ref_from_command 'gh pr merge 7;rm -rf /')"
assert_equals "graphql node id not a number"    "" "$(pr_ref_from_command 'gh api graphql -f query=mergePullRequest')"
assert_equals "bare merge has no explicit ref"  "" "$(pr_ref_from_command 'gh pr merge')"

# --- AMBIGUITY: prefer no answer over a confidently wrong one -------------
# This scanner splits raw command TEXT; it cannot tell a flag's value from a
# positional. `gh pr merge --title "PR 42 notes" 99` used to return 42 — a real
# but UNRELATED PR — so the record would read diff_base:"pr:42" while PR 99 was
# merged. In a corpus whose whole purpose is stating what each event was
# measured against, a plausible wrong label is strictly worse than "unresolved":
# unresolved is a known-unknown an adjudicator can exclude, pr:42 is a lie they
# cannot detect. So when MORE THAN ONE digit-leading token follows `merge`, the
# reference is ambiguous and we return nothing.
assert_equals "ambiguous ref (number in --title) rejected"  "" \
    "$(pr_ref_from_command 'gh pr merge --title "PR 42 notes" 99')"
assert_equals "ambiguous ref (number in --body) rejected"   "" \
    "$(pr_ref_from_command 'gh pr merge --body "fixes 7" 99')"
assert_equals "ambiguous ref (two positionals) rejected"    "" \
    "$(pr_ref_from_command 'gh pr merge 42 99')"
# ...and the unambiguous cases must be untouched by that rule.
assert_equals "single ref with trailing flags still works" "12" \
    "$(pr_ref_from_command 'gh pr merge 12 --squash --delete-branch')"
assert_equals "numeric flag BEFORE merge still ignored"     "7" \
    "$(pr_ref_from_command 'gh --org 42 pr merge --squash 7')"
assert_equals "a push is not a merge"           "" "$(pr_ref_from_command 'git push origin HEAD')"

# --- fetch: hermetic, gh is stubbed; NO test may hit the network ---------
_STUB="$(mktemp -d /tmp/prdiff-stub-XXXXXX)"
cat > "${_STUB}/gh" <<'STUB'
#!/bin/bash
# Emulates: gh pr view <n> --json files --jq '.files[].path'
for a in "$@"; do case "$a" in 404) exit 1 ;; esac; done
printf 'src/app.py\ndocs/readme.md\n'
STUB
chmod +x "${_STUB}/gh"

_out="$(PATH="${_STUB}:$PATH" pr_changed_files 7 "$PWD")"
assert_contains "fetch returns the PR's paths" "src/app.py" "${_out}"
assert_equals   "unknown PR yields nothing"  "" "$(PATH="${_STUB}:$PATH" pr_changed_files 404 "$PWD")"

# gh absent entirely -> empty, never an error
_EMPTY="$(mktemp -d /tmp/prdiff-empty-XXXXXX)"
assert_equals "gh absent yields nothing" "" "$(PATH="${_EMPTY}" pr_changed_files 7 "$PWD" 2>/dev/null)"

# A rejected ref must never reach the subprocess: the stub records its argv.
cat > "${_STUB}/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${PRDIFF_ARGV_LOG}"
printf 'src/app.py\n'
STUB
chmod +x "${_STUB}/gh"
export PRDIFF_ARGV_LOG="${_STUB}/argv.log"; : > "${PRDIFF_ARGV_LOG}"
# Fix round 1, IMPORTANT 2: this input is deliberately chosen so the loop DOES
# capture a candidate ("7;rm", since the loop's [0-9]* test only checks a
# token's first character) before the final all-digits boundary strips it.
# `gh pr merge --repo other/org` (the original input here) never exercises
# the final boundary case at all -- the loop's own digit test already yields
# an empty candidate for it, so a mutation that deletes the final boundary
# case still passes trivially (mutation-proved: see task-1-report.md "Fix
# round 1"). The direct assert_equals below on `_bad` is the load-bearing
# check -- it fails if the final boundary case is removed. The argv-log
# assertion after it is a secondary, defense-in-depth confirmation.
_bad="$(pr_ref_from_command 'gh pr merge 7;rm -rf / --squash')"
assert_equals "captured-but-non-integer candidate is rejected" "" "${_bad}"
[ -n "${_bad}" ] && PATH="${_STUB}:$PATH" pr_changed_files "${_bad}" "$PWD" >/dev/null
assert_equals "rejected ref never reaches gh" "0" "$(wc -l < "${PRDIFF_ARGV_LOG}" | tr -d ' ')"

# --- timeout: a hanging gh must not block indefinitely --------------------
# Fix round 1, IMPORTANT 3: PR_DIFF_GH_TIMEOUT must actually bound the gh
# call. Use a short override (not the 10s default) to keep this test fast.
_STUB_SLOW="$(mktemp -d /tmp/prdiff-slow-XXXXXX)"
cat > "${_STUB_SLOW}/gh" <<'STUB'
#!/bin/bash
sleep 5
printf 'src/app.py\n'
STUB
chmod +x "${_STUB_SLOW}/gh"
SECONDS=0
_out="$(PATH="${_STUB_SLOW}:$PATH" PR_DIFF_GH_TIMEOUT=1 pr_changed_files 7 "$PWD")"
_elapsed="${SECONDS}"
assert_equals "slow gh is cut off, yields empty (not the eventual output)" "" "${_out}"
assert_equals "slow gh is cut off promptly, not left to hang" "1" \
    "$( [ "${_elapsed}" -le 3 ] && echo 1 || echo 0 )"
rm -rf "${_STUB_SLOW}"

rm -rf "${_STUB}" "${_EMPTY}"
print_summary
exit $?
