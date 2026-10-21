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
#
# Only the FIRST push segment of a compound command is checked, matching
# command_git_subject_dir; `git push origin main && git push origin feat` is
# judged on `main` alone.

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

# SECURITY: the command text is model-authored, and git runs programs that a
# repository's own config names (remote.<name>.uploadpack, core.sshCommand)
# while this hook runs, BEFORE the user approves the command. A directory the
# command names is used only when it is a worktree of the session's own
# repository (same canonical --git-common-dir), the rule openspec-guard.sh
# applies to its subject (#219). Anything else is skipped, never guessed.
_common_dir() {
    local c
    c="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 0
    case "${c}" in '') return 0 ;; /*) ;; *) c="$1/${c}" ;; esac
    ( cd "${c}" 2>/dev/null && pwd -P )
}
_HERE="$(_common_dir .)"
[ -n "${_HERE}" ] || exit 0
_DIR="$(command_git_subject_dir "${_CMD}")"
[ -n "${_DIR}" ] || _DIR="."
if [ "${_DIR}" != "." ] && [ "$(_common_dir "${_DIR}")" != "${_HERE}" ]; then
    exit 0
fi

# The remote and the refspec are the ones the COMMAND names: positional 1 and
# 2 of the push segment, `--repo` standing in for a missing positional 1. The
# word walk follows command_push_ref's, which reports only the refspec's
# source half and so cannot answer "which remote, which destination".
_POS1=""; _POS2=""; _REPO=""
_SEGS="$(_gc_split_segments "${_CMD}")"
_OLDIFS="$IFS"
IFS="${_GC_SEP}"
for _SEG in ${_SEGS}; do
    IFS="${_OLDIFS}"
    if [ "$(_gc_segment_git_sub "${_SEG}")" = "push" ]; then
        # shellcheck disable=SC2086
        set -- ${_SEG}
        while [ "$#" -gt 0 ]; do
            case "$1" in
                '('|'{') shift ;;
                '('*|'{'*) _U="$(_gc_strip_openers "$1")"; shift; set -- "${_U}" "$@"; break ;;
                *) break ;;
            esac
        done
        while [ "$#" -gt 0 ]; do
            case "$1" in env) shift ;; [A-Za-z_]*=*) shift ;; *) break ;; esac
        done
        case "${1:-}" in git|*/git) shift ;; *) IFS="${_GC_SEP}"; continue ;; esac
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -C|-c|--git-dir|--work-tree|--namespace)
                    if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                -*) shift ;;
                *) break ;;
            esac
        done
        [ "$#" -gt 0 ] && shift   # drop `push`
        _N=0
        while [ "$#" -gt 0 ]; do
            _gc_strip_closers_var "$1"
            if _gc_redir_kind_var "${_GC_W}"; then
                if [ "${_GC_REDIR}" = "bare" ] && [ "$#" -ge 2 ]; then shift 2; else shift; fi
                continue
            fi
            # One layer of quotes off, as git-command.sh does for a refspec.
            _a="${_GC_W}"
            _a="${_a%\"}"; _a="${_a#\"}"; _a="${_a%\'}"; _a="${_a#\'}"
            case "${_a}" in
                '') shift ;;
                --repo=*)
                    _REPO="${_a#--repo=}"
                    _REPO="${_REPO%\"}"; _REPO="${_REPO#\"}"; _REPO="${_REPO%\'}"; _REPO="${_REPO#\'}"
                    shift ;;
                --repo)
                    _REPO="${2:-}"
                    _REPO="${_REPO%\"}"; _REPO="${_REPO#\"}"; _REPO="${_REPO%\'}"; _REPO="${_REPO#\'}"
                    if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                -o|--push-option|--receive-pack|--exec)
                    if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                -*) shift ;;
                *)
                    _N=$((_N + 1))
                    [ "${_N}" -eq 1 ] && _POS1="${_a}"
                    [ "${_N}" -eq 2 ] && _POS2="${_a}"
                    shift ;;
            esac
        done
        break
    fi
    IFS="${_GC_SEP}"
done
IFS="${_OLDIFS}"

_CUR="$(git -C "${_DIR}" symbolic-ref -q --short HEAD 2>/dev/null)"
if [ -z "${_POS2}" ]; then
    # No refspec: the current branch, to its upstream's name under
    # push.default=upstream and to its own name otherwise.
    [ -n "${_CUR}" ] || exit 0
    _SRC="${_CUR}"; _DST="${_CUR}"
    if [ "$(git -C "${_DIR}" config push.default 2>/dev/null)" = "upstream" ]; then
        _M="$(git -C "${_DIR}" config "branch.${_CUR}.merge" 2>/dev/null)"
        case "${_M}" in refs/heads/?*) _DST="${_M#refs/heads/}" ;; esac
    fi
else
    _R="${_POS2#+}"
    case "${_R}" in
        *:*) _SRC="${_R%%:*}"; _DST="${_R#*:}" ;;
        *)   _SRC="${_R}"; _DST="" ;;
    esac
    [ "${_SRC}" = "HEAD" ] && _SRC="${_CUR}"
    _SRC="${_SRC#refs/heads/}"
    [ -n "${_DST}" ] || _DST="${_SRC}"
    case "${_DST}" in
        refs/heads/*) _DST="${_DST#refs/heads/}" ;;
        refs/*|HEAD) exit 0 ;;
    esac
fi
[ -n "${_DST}" ] || exit 0

# Remote: as git resolves it — the command's, else the branch's pushRemote,
# remote.pushDefault, its upstream remote, then origin. A URL is not a
# configured remote and has no tracking state to compare, so it is skipped.
_REMOTE="${_POS1:-${_REPO}}"
if [ -z "${_REMOTE}" ] && [ -n "${_SRC}" ]; then
    _REMOTE="$(git -C "${_DIR}" config "branch.${_SRC}.pushRemote" 2>/dev/null)"
fi
[ -n "${_REMOTE}" ] || _REMOTE="$(git -C "${_DIR}" config remote.pushDefault 2>/dev/null)"
if [ -z "${_REMOTE}" ] && [ -n "${_SRC}" ]; then
    _REMOTE="$(git -C "${_DIR}" config "branch.${_SRC}.remote" 2>/dev/null)"
fi
[ -n "${_REMOTE}" ] || _REMOTE="origin"
[ "${_REMOTE}" != "." ] || exit 0
git -C "${_DIR}" remote get-url "${_REMOTE}" >/dev/null 2>&1 || exit 0

# Was the destination on that remote before?
_SEEN=""
if [ -n "${_SRC}" ] \
    && [ "$(git -C "${_DIR}" config "branch.${_SRC}.merge" 2>/dev/null)" = "refs/heads/${_DST}" ] \
    && [ "$(git -C "${_DIR}" config "branch.${_SRC}.remote" 2>/dev/null)" = "${_REMOTE}" ]; then
    _SEEN="the upstream of ${_SRC} is ${_REMOTE}/${_DST}"
fi
if git -C "${_DIR}" show-ref --verify -q "refs/remotes/${_REMOTE}/${_DST}" 2>/dev/null; then
    [ -n "${_SEEN}" ] && _SEEN="${_SEEN}, and " || true
    _SEEN="${_SEEN}a remote-tracking ref ${_REMOTE}/${_DST} exists locally"
fi
[ -n "${_SEEN}" ] || exit 0
_B="${_DST}"

# Ask the remote, bounded: macOS has no timeout(1). No prompt may block it.
_TMP="$(mktemp -d "${TMPDIR:-/tmp}/acs-resurrect.XXXXXX" 2>/dev/null)" || exit 0
trap 'rm -rf "${_TMP}"' EXIT
(
    export GIT_TERMINAL_PROMPT=0
    # Only when the user has configured no ssh of their own: GIT_SSH_COMMAND
    # outranks core.sshCommand, so setting it unconditionally would replace a
    # per-repo identity (`ssh -i <key>`) and authenticate as the wrong account.
    if [ -z "${GIT_SSH_COMMAND:-}" ] && [ -z "${GIT_SSH:-}" ] \
        && [ -z "$(git -C "${_DIR}" config core.sshCommand 2>/dev/null)" ]; then
        export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=4"
    fi
    git -C "${_DIR}" ls-remote --heads "${_REMOTE}" "refs/heads/${_B}" \
        > "${_TMP}/out" 2>/dev/null
    echo "$?" > "${_TMP}/rc"
) < /dev/null 2>/dev/null &
_PID=$!
_LIMIT="${ACS_PUSH_REMOTE_TIMEOUT:-5}"
case "${_LIMIT}" in ''|*[!0-9]*) _LIMIT=5 ;; esac
# hooks.json allows this hook 10 s; past that the harness kills it and the
# advisory is lost without a word.
[ "${#_LIMIT}" -le 1 ] && [ "${_LIMIT}" -le 8 ] || _LIMIT=8
_I=0
while [ ! -s "${_TMP}/rc" ] && [ "${_I}" -lt $(( _LIMIT * 5 )) ]; do
    sleep 0.2; _I=$(( _I + 1 ))
done

_MSG=""
if [ ! -s "${_TMP}/rc" ]; then
    pkill -P "${_PID}" 2>/dev/null; kill "${_PID}" 2>/dev/null
    wait "${_PID}" 2>/dev/null
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
