#!/bin/bash
# push-resurrect-advisory.sh — PreToolUse on Bash (#368). Advisory only: it
# never denies, and every failure path exits 0 with no output.
#
# Merging a PR on GitHub auto-deletes its head branch. The local branch keeps
# its commits and its upstream config, so a later `git push` of it RECREATES
# the remote branch, and git reports that as `* [new branch]`, which reads as
# routine on a branch pushed before. Observed three times (2026-08-29 once,
# 2026-10-03 twice), each time while follow-up work was being pushed to a branch
# whose PR had just been merged.
#
# Predicate: the branch being pushed WAS on the remote (its upstream is that
# remote branch, or a remote-tracking ref for it exists locally) and the remote
# no longer has it. Only the second half needs the network, and it is asked
# only when the first half holds, so the first push of a new branch makes no
# query at all.
#
# A separate hook rather than a leg of openspec-guard.sh: the guard's ~40 test
# files drive it against the real checkout, so a network-backed leg there would
# make them depend on the remote state of whatever branch the suite runs on —
# the environment coupling #369 removed from another test.

_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Bounded read (#188): a FIFO or socket on fd 0 is not a TTY, and `cat` would
# wait forever for an EOF that never arrives.
_INPUT="$(
    _l=""
    while IFS= read -r -t 2 _l; do printf '%s\n' "${_l}"; _l=""; done
    [ -n "${_l}" ] && printf '%s' "${_l}"
    exit 0
)" || exit 0

# Every Bash call reaches this hook, so leave before any fork when the payload
# cannot be a push.
case "${_INPUT}" in *push*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
_CMD="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "${_CMD}" ] || exit 0

. "${_PLUGIN_ROOT}/hooks/lib/git-command.sh" 2>/dev/null \
    && command -v command_push_subject_is_partial >/dev/null 2>&1 || exit 0

# Segment walk, never a substring scan: `echo 'git push'` is not a push.
command_invokes_git_write "${_CMD}" push || exit 0
# A deletion, --all/--mirror/--tags or several refspecs has no single branch.
command_push_subject_is_partial "${_CMD}" && exit 0

_DIR="$(command_git_subject_dir "${_CMD}")"
[ -n "${_DIR}" ] || _DIR="."
git -C "${_DIR}" rev-parse --git-dir >/dev/null 2>&1 || exit 0

_B="$(command_push_ref "${_CMD}")"
if [ -z "${_B}" ]; then
    _B="$(git -C "${_DIR}" symbolic-ref -q --short HEAD 2>/dev/null)" || exit 0
fi
[ -n "${_B}" ] || exit 0
git -C "${_DIR}" show-ref --verify -q "refs/heads/${_B}" 2>/dev/null || exit 0

_REMOTE="$(git -C "${_DIR}" config "branch.${_B}.remote" 2>/dev/null)"
[ -n "${_REMOTE}" ] || _REMOTE="origin"
[ "${_REMOTE}" != "." ] || exit 0
git -C "${_DIR}" remote get-url "${_REMOTE}" >/dev/null 2>&1 || exit 0

_SEEN=""
if [ "$(git -C "${_DIR}" config "branch.${_B}.merge" 2>/dev/null)" = "refs/heads/${_B}" ] \
    && [ "$(git -C "${_DIR}" config "branch.${_B}.remote" 2>/dev/null)" = "${_REMOTE}" ]; then
    _SEEN="its upstream is ${_REMOTE}/${_B}"
fi
if git -C "${_DIR}" show-ref --verify -q "refs/remotes/${_REMOTE}/${_B}" 2>/dev/null; then
    [ -n "${_SEEN}" ] && _SEEN="${_SEEN}, and " || true
    _SEEN="${_SEEN}a remote-tracking ref ${_REMOTE}/${_B} exists locally"
fi
[ -n "${_SEEN}" ] || exit 0

# Ask the remote, bounded: macOS has no timeout(1). No prompt may block it.
_TMP="$(mktemp -d "${TMPDIR:-/tmp}/acs-resurrect.XXXXXX" 2>/dev/null)" || exit 0
trap 'rm -rf "${_TMP}"' EXIT
(
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" \
        git -C "${_DIR}" ls-remote --heads "${_REMOTE}" "refs/heads/${_B}" \
        > "${_TMP}/out" 2>/dev/null
    echo "$?" > "${_TMP}/rc"
) < /dev/null &
_PID=$!
_LIMIT="${ACS_PUSH_REMOTE_TIMEOUT:-5}"
case "${_LIMIT}" in ''|*[!0-9]*) _LIMIT=5 ;; esac
_I=0
while [ ! -s "${_TMP}/rc" ] && [ "${_I}" -lt $(( _LIMIT * 5 )) ]; do
    sleep 0.2; _I=$(( _I + 1 ))
done

_MSG=""
if [ ! -s "${_TMP}/rc" ]; then
    pkill -P "${_PID}" 2>/dev/null; kill "${_PID}" 2>/dev/null
    _MSG="could not check whether ${_REMOTE}/${_B} still exists (no answer from the remote within ${_LIMIT} s). This branch was pushed there before (${_SEEN}); if its PR has been merged, this push recreates it."
elif [ "$(cat "${_TMP}/rc")" != "0" ]; then
    _MSG="could not check whether ${_REMOTE}/${_B} still exists (git ls-remote failed). This branch was pushed there before (${_SEEN}); if its PR has been merged, this push recreates it."
elif [ ! -s "${_TMP}/out" ]; then
    _Q="'$(printf '%s' "${_B}" | sed "s/'/'\\\\''/g")'"
    _MSG="${_REMOTE}/${_B} no longer exists on the remote, but this branch was there before (${_SEEN}). If its PR was merged, the host deleted the branch and this push will RECREATE it (git reports that as \`* [new branch]\`). Check first: \`gh pr view ${_Q} --json state\`. If it is MERGED, do not push: start a fresh branch from the remote's default branch and cherry-pick only the commits that are not in it (after a squash merge, ancestry says nothing is merged, so compare content). If the branch was deleted on purpose and you mean to recreate it, push as planned."
fi
[ -n "${_MSG}" ] || exit 0

jq -n --arg msg "PUSH (advisory): ${_MSG}" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
exit 0
