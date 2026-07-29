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

print_summary
exit $?
