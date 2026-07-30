#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-git-command.sh ==="

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/git-command.sh"

# _yes desc cmd [subs] : expect the predicate returns 0 (is a git write)
_yes() { if command_invokes_git_write "$2" ${3:-}; then _record_pass "$1"; else _record_fail "$1" "expected git-write: $2"; fi; }
# _no  desc cmd [subs] : expect returns 1 (not a git write)
_no()  { if command_invokes_git_write "$2" ${3:-}; then _record_fail "$1" "unexpected git-write: $2"; else _record_pass "$1"; fi; }

# Real invocations -> yes
_yes "plain push"                 "git push origin HEAD"
_yes "plain commit"               "git commit -m msg"
_yes "push with -C global flag"   "git -C /repo push -u origin feature/x"
_yes "env-prefixed commit"        "GIT_AUTHOR_NAME=x git commit -m msg"
_yes "env keyword prefix"         "env GIT_PAGER=cat git push"
_yes "chained after cd"           "cd /repo && git push"
_yes "absolute git path"          "/usr/bin/git push"

# Phrase-as-argument / read-only -> no
_no  "grep mentioning the phrase" 'grep -nE "git push|deny" hooks/openspec-guard.sh'
_no  "echo mentioning the phrase" 'echo "run git push later"'
_no  "comment only"               '# git push placeholder'
_no  "unrelated git read"         "git status"
_no  "git log is not a write"     "git log --oneline -3"

# Subcommand filter: restrict to push only
_yes "commit matches default set" "git commit -m x"
_no  "commit excluded when asking push-only" "git commit -m x" "push"

# Quote-aware: operator INSIDE quotes is not a boundary -> phrase-as-argument stays FALSE
_no  "semicolon inside dquotes"   'echo "note; git push "'
_no  "pipe inside dquotes"        'echo "msg| git push "'
_no  "semicolon inside squotes"   "printf 'log; git commit '"
# Real chained commands still detected (no regression)
_yes "chained with && still true" "cd /repo && git push origin x"
_yes "real cmd then piped grep"   "git commit -m x | tee log"

# --- gh publish predicates (#174) -------------------------------------------
_pub() { command_invokes_gh_publish "$1" && echo yes || echo no; }

assert_equals "gh issue create is a publish" "yes" "$(_pub 'gh issue create --title t --body-file /tmp/b.md')"
assert_equals "gh issue comment is a publish" "yes" "$(_pub 'gh issue comment 12 --body-file /tmp/b.md')"
assert_equals "gh issue edit is a publish"    "yes" "$(_pub 'gh issue edit 12 --body-file /tmp/b.md')"
assert_equals "gh pr create is a publish"     "yes" "$(_pub 'gh pr create --body hello')"
assert_equals "gh pr comment is a publish"    "yes" "$(_pub 'gh pr comment 3 -b hi')"
assert_equals "gh pr merge is NOT a publish"  "no"  "$(_pub 'gh pr merge 3 --squash')"
assert_equals "gh issue list is NOT a publish" "no" "$(_pub 'gh issue list --limit 5')"
assert_equals "git push is NOT a publish"     "no"  "$(_pub 'git push origin main')"
assert_equals "echo mentioning gh is NOT a publish" "no" "$(_pub 'echo "gh issue create later"')"
assert_equals "publish in a compound segment is detected" "yes" \
    "$(_pub 'cd /tmp && gh issue create --body-file b.md')"

# body-file extraction
assert_equals "body-file path is captured" "/tmp/b.md" \
    "$(gh_publish_body_files 'gh issue create --title t --body-file /tmp/b.md')"
assert_equals "-F short form is captured" "/tmp/x.md" \
    "$(gh_publish_body_files 'gh issue create -F /tmp/x.md')"
assert_equals "quoted path is unquoted" "/tmp/b.md" \
    "$(gh_publish_body_files 'gh issue create --body-file "/tmp/b.md"')"
assert_equals "--body-file=path form is captured" "/tmp/e.md" \
    "$(gh_publish_body_files 'gh issue create --body-file=/tmp/e.md')"
assert_equals "inline --body yields no file (scanned via the command string)" "" \
    "$(gh_publish_body_files 'gh pr comment 3 --body "hello world"')"
assert_equals "non-publish yields nothing" "" \
    "$(gh_publish_body_files 'gh issue list')"

# --- Critical 1: glued-paren wrap; Critical 2: gh global flags ---
# Paren-wrapped gh commands (glued token `(gh` from single segment)
assert_equals "paren-wrapped gh issue create detected" "yes" \
    "$(_pub '(gh issue create --body-file /tmp/b.md)')"
assert_equals "brace-wrapped gh issue create detected" "yes" \
    "$(_pub '{ gh issue create --body-file /tmp/b.md; }')"
assert_equals "paren-wrapped gh comment detected" "yes" \
    "$(_pub '(gh issue comment 5 --body-file /tmp/b.md)')"

# Paren-wrapped with body-file extraction
assert_equals "paren-wrapped extraction" "/tmp/b.md" \
    "$(gh_publish_body_files '(gh issue create --body-file /tmp/b.md)')"
assert_equals "brace-wrapped extraction" "/tmp/e.md" \
    "$(gh_publish_body_files '{ gh issue create --body-file=/tmp/e.md; }')"

# gh global flags before noun/verb
assert_equals "gh --repo before issue create" "yes" \
    "$(_pub 'gh --repo owner/repo issue create --body-file /tmp/b.md')"
assert_equals "gh -R before issue comment" "yes" \
    "$(_pub 'gh -R owner/repo issue comment 5 --body-file /tmp/b.md')"
assert_equals "gh --hostname before pr create" "yes" \
    "$(_pub 'gh --hostname github.com pr create --body-file /tmp/b.md')"

# Global flags with body-file extraction
assert_equals "extract with --repo prefix" "/tmp/b.md" \
    "$(gh_publish_body_files 'gh --repo owner/repo issue create --body-file /tmp/b.md')"
assert_equals "extract with -R prefix" "/tmp/f.md" \
    "$(gh_publish_body_files 'gh -R o/r issue comment 5 --body-file /tmp/f.md')"

# Controls: these should NOT match
assert_equals "paren-wrapped gh issue list NOT a publish" "no" \
    "$(_pub '(gh issue list --limit 5)')"
assert_equals "gh --repo before pr merge NOT a publish" "no" \
    "$(_pub 'gh --repo owner/repo pr merge 3 --squash')"

# --- Important: trailing-closer strip must be opener-counted ---
# Paths can legitimately end in ) or }; strip only consumed openers' closers
assert_equals "path with paren preserved (no wrap)" "/tmp/report(v2)" \
    "$(gh_publish_body_files 'gh issue create --body-file /tmp/report(v2)')"
assert_equals "path with brace preserved (no wrap)" "/tmp/set{a}" \
    "$(gh_publish_body_files 'gh issue create --body-file /tmp/set{a}')"
assert_equals "paren-wrapped path: one opener consumed, one closer stripped" "/tmp/b.md" \
    "$(gh_publish_body_files '(gh issue create --body-file /tmp/b.md)')"
assert_equals "double-paren-wrapped path: two openers, two closers stripped" "/tmp/b.md" \
    "$(gh_publish_body_files '((gh issue create --body-file /tmp/b.md))')"
assert_equals "wrapped path with paren in name: one opener, one closer stripped" "/tmp/report(v2)" \
    "$(gh_publish_body_files '(gh issue create --body-file /tmp/report(v2))')"

# --- gh api publish predicates (issue #174 gap: gh api was unguarded) ------
# `gh api` defaults to POST when fields are supplied with no explicit
# --method, so a bare `-f body=...` against an issues/comments/pulls write
# endpoint is a publish exactly like an explicit --method POST/PATCH.
assert_equals "gh api issues create with fields (implicit POST) is a publish" "yes" \
    "$(_pub 'gh api repos/o/r/issues -f body=leaky text here')"
assert_equals "gh api issue comment with --method POST before endpoint is a publish" "yes" \
    "$(_pub 'gh api --method POST repos/o/r/issues/1/comments -f body=leaky text')"
assert_equals "gh api pr comments with --method PATCH is a publish" "yes" \
    "$(_pub 'gh api repos/o/r/pulls/3/comments --method PATCH -f body=leaky')"
assert_equals "gh api pulls creation with fields is a publish" "yes" \
    "$(_pub 'gh api repos/o/r/pulls -f title=t -f body=leaky')"
assert_equals "gh api -X POST short form is a publish" "yes" \
    "$(_pub 'gh api repos/o/r/issues -X POST -f body=leaky')"

# Controls: merge endpoint / graphql mergePullRequest must NEVER become a
# publish here — that is command_invokes_gh_merge's territory, and this
# predicate must not overlap it.
assert_equals "gh api pulls merge PUT is NOT a publish" "no" \
    "$(_pub 'gh api repos/o/r/pulls/3/merge --method PUT')"
# PUT isn't in the write-method set, so the above passes even with the
# `*/pulls/*/merge` exclusion deleted -- it proves nothing about the
# exclusion itself. --method POST *is* in the write set, so this one only
# stays "no" because the exclusion fires first; delete the exclusion line
# and this assertion goes red (mutation-verified).
assert_equals "gh api pulls merge with --method POST is still NOT a publish" "no" \
    "$(_pub 'gh api --method POST repos/o/r/pulls/3/merge')"
assert_equals "gh api graphql mergePullRequest is NOT a publish" "no" \
    "$(_pub 'gh api graphql -f query=mergePullRequest')"

# A bare read (no --method, no fields) sends no body at all, so it is
# deliberately NOT treated as a publish -- same over-gating-breeds-evasion
# discipline as command_invokes_gh_merge's bare-merge-status-read exclusion.
assert_equals "gh api issues read with no fields/method is NOT a publish (bare GET)" "no" \
    "$(_pub 'gh api repos/o/r/issues')"

# --- gh api body-FILE extraction (issue #174 round: I1) ---------------------
# --input <path> and -f/-F/--field/--raw-field name=@<path> carry the body in
# a file gh reads directly, exactly like --body-file for issue/pr. Before this
# fix, gh_publish_body_files emitted NOTHING for any `api` verb, so these
# files were never scanned and never announced -- a silent unchecked publish.
assert_equals "gh api --input path is captured" "/tmp/pg-body.md" \
    "$(gh_publish_body_files 'gh api repos/o/r/issues --method POST --input /tmp/pg-body.md')"
assert_equals "gh api -F name=@path is captured" "/tmp/pg-body.md" \
    "$(gh_publish_body_files 'gh api repos/o/r/issues -X POST -F body=@/tmp/pg-body.md')"
assert_equals "gh api -f name=@path is captured" "/tmp/pg-body.md" \
    "$(gh_publish_body_files 'gh api repos/o/r/issues -f body=@/tmp/pg-body.md')"
assert_equals "gh api --input=path form is captured" "/tmp/pg-body.md" \
    "$(gh_publish_body_files 'gh api repos/o/r/issues --input=/tmp/pg-body.md')"
assert_equals "gh api merge endpoint --input is NOT captured" "" \
    "$(gh_publish_body_files 'gh api repos/o/r/pulls/3/merge --input /tmp/x.md')"
assert_equals "gh api inline field value (no @) yields no file" "" \
    "$(gh_publish_body_files 'gh api repos/o/r/issues -f body=inline')"
assert_equals "gh api graphql -F name=@path is NOT captured (not an issue/pr endpoint)" "" \
    "$(gh_publish_body_files 'gh api graphql -F query=@/tmp/q.gql')"

print_summary
exit $?
