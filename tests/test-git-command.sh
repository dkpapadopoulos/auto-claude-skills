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

print_summary
exit $?
