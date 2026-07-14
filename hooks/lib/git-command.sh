#!/bin/bash
# git-command.sh — predicate: does a shell command actually INVOKE a git write
# (push/commit), vs merely mention the phrase as an argument/string? Sourced by
# openspec-guard.sh. Bash 3.2 compatible. No side effects. Fail-open by design:
# a parse it cannot handle returns 1 (not a write) — callers that need
# fail-CLOSED behavior keep a substring fallback.

# Split a command into segments on UNQUOTED ; | & boundaries (covers ; | && ||).
# Quote-aware: operators inside '...' or "..." are literal, not boundaries. Emits
# one segment per line. Backslash-escaping is not interpreted (rare here; a stray
# escaped quote at worst mis-splits toward a false negative, the safe direction).
_gc_split_segments() {
    local _s="$1" _seg="" _sq=0 _dq=0 _i=0 _n _c _out=""
    _n=${#_s}
    while [ "${_i}" -lt "${_n}" ]; do
        _c="${_s:${_i}:1}"
        if [ "${_sq}" -eq 1 ]; then
            [ "${_c}" = "'" ] && _sq=0
            _seg="${_seg}${_c}"; _i=$((_i+1)); continue
        fi
        if [ "${_dq}" -eq 1 ]; then
            [ "${_c}" = '"' ] && _dq=0
            _seg="${_seg}${_c}"; _i=$((_i+1)); continue
        fi
        case "${_c}" in
            "'") _sq=1; _seg="${_seg}${_c}" ;;
            '"') _dq=1; _seg="${_seg}${_c}" ;;
            ';'|'|'|'&') _out="${_out}${_seg}
"; _seg="" ;;
            *) _seg="${_seg}${_c}" ;;
        esac
        _i=$((_i+1))
    done
    printf '%s\n' "${_out}${_seg}"
}

# _gc_segment_git_sub <segment>
#   Echoes the git subcommand when the segment's first real token (after
#   `env`/VAR=val prefixes) is git or */git; echoes nothing otherwise.
#   Extracted from command_invokes_git_write — semantics unchanged.
_gc_segment_git_sub() {
    local _gc_t
    # shellcheck disable=SC2086
    set -- $1
    # Unwrap leading subshell/brace group openers so `(git push)` or
    # `{ git push` cannot hide the invocation from the gate.
    # PAIRED: command_invokes_gh_merge carries a structural copy of this
    # unwrap (it collects two words instead of echoing one) — update both.
    while [ "$#" -gt 0 ]; do
        case "$1" in
            '('|'{') shift ;;
            '('*|'{'*)
                _gc_t="$1"
                while :; do
                    case "${_gc_t}" in
                        '('*) _gc_t="${_gc_t#\(}" ;;
                        '{'*) _gc_t="${_gc_t#\{}" ;;
                        *) break ;;
                    esac
                done
                shift
                set -- "${_gc_t}" "$@"
                break ;;
            *) break ;;
        esac
    done
    while [ "$#" -gt 0 ]; do
        case "$1" in
            env) shift ;;
            [A-Za-z_]*=*) shift ;;
            *) break ;;
        esac
    done
    [ "$#" -gt 0 ] || return 0
    case "$1" in
        git|*/git) shift ;;
        *) return 0 ;;
    esac
    # Skip git global flags to reach the subcommand.
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -C|-c|--git-dir|--work-tree|--namespace)
                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
            -*) shift ;;
            *)
                # Strip trailing group closers: in `(git push)` the closer
                # glues onto the final token, yielding `push)` — no git
                # subcommand contains ) or }, so stripping is always safe.
                _gc_t="$1"
                while :; do
                    case "${_gc_t}" in
                        *')') _gc_t="${_gc_t%\)}" ;;
                        *'}') _gc_t="${_gc_t%\}}" ;;
                        *) break ;;
                    esac
                done
                printf '%s' "${_gc_t}"
                return 0 ;;
        esac
    done
    return 0
}

# command_invokes_git_write <command> [subcommands]
#   subcommands: space-separated, default "push commit".
#   Returns 0 if any ; | && || -separated segment's first real token is git
#   (or */git) whose first non-flag argument is one of <subcommands>.
command_invokes_git_write() {
    local _gc_cmd _gc_want _gc_segs _gc_oldifs _gc_seg _gc_sub _gc_w
    _gc_cmd="$1"
    _gc_want="${2:-push commit}"
    _gc_segs="$(_gc_split_segments "${_gc_cmd}")"
    _gc_oldifs="$IFS"
    IFS='
'
    for _gc_seg in ${_gc_segs}; do
        IFS="${_gc_oldifs}"
        _gc_sub="$(_gc_segment_git_sub "${_gc_seg}")"
        if [ -n "${_gc_sub}" ]; then
            for _gc_w in ${_gc_want}; do
                if [ "${_gc_sub}" = "${_gc_w}" ]; then
                    IFS="${_gc_oldifs}"
                    return 0
                fi
            done
        fi
        IFS='
'
    done
    IFS="${_gc_oldifs}"
    return 1
}

# command_invokes_gh_merge <command>
#   Returns 0 if any segment actually invokes a PR merge via gh:
#     - `gh [flags] pr [flags] merge ...` (any flag order, incl. -R/--repo)
#     - `gh api ...` naming the REST pull-merge path (pulls/…/merge) or the
#       GraphQL mergePullRequest mutation.
#   Phrase mentions inside quotes of NON-gh segments never match (segment's
#   first real token must be gh). `gh pr create` never matches.
command_invokes_gh_merge() {
    local _gc_segs _gc_oldifs _gc_seg _gc_w1 _gc_w2 _gc_t
    _gc_segs="$(_gc_split_segments "$1")"
    _gc_oldifs="$IFS"
    IFS='
'
    for _gc_seg in ${_gc_segs}; do
        IFS="${_gc_oldifs}"
        # shellcheck disable=SC2086
        set -- ${_gc_seg}
        # Unwrap leading group openers (see _gc_segment_git_sub).
        while [ "$#" -gt 0 ]; do
            case "$1" in
                '('|'{') shift ;;
                '('*|'{'*)
                    _gc_t="$1"
                    while :; do
                        case "${_gc_t}" in
                            '('*) _gc_t="${_gc_t#\(}" ;;
                            '{'*) _gc_t="${_gc_t#\{}" ;;
                            *) break ;;
                        esac
                    done
                    shift
                    set -- "${_gc_t}" "$@"
                    break ;;
                *) break ;;
            esac
        done
        while [ "$#" -gt 0 ]; do
            case "$1" in
                env) shift ;;
                [A-Za-z_]*=*) shift ;;
                *) break ;;
            esac
        done
        if [ "$#" -gt 0 ]; then
            case "$1" in
                gh|*/gh)
                    shift
                    # Collect the first two non-flag words, skipping
                    # value-taking global flags in any position.
                    _gc_w1=""; _gc_w2=""
                    while [ "$#" -gt 0 ]; do
                        case "$1" in
                            -R|--repo|--hostname)
                                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                            -*) shift ;;
                            *)
                                # Strip trailing group closers (`(gh pr merge)`
                                # glues `)` onto the last collected word).
                                _gc_t="$1"
                                while :; do
                                    case "${_gc_t}" in
                                        *')') _gc_t="${_gc_t%\)}" ;;
                                        *'}') _gc_t="${_gc_t%\}}" ;;
                                        *) break ;;
                                    esac
                                done
                                if [ -z "${_gc_w1}" ]; then _gc_w1="${_gc_t}"
                                elif [ -z "${_gc_w2}" ]; then _gc_w2="${_gc_t}"; break
                                fi
                                shift ;;
                        esac
                    done
                    if [ "${_gc_w1}" = "pr" ] && [ "${_gc_w2}" = "merge" ]; then
                        IFS="${_gc_oldifs}"; return 0
                    fi
                    if [ "${_gc_w1}" = "api" ]; then
                        # REST pull-merge is a WRITE only as PUT — a bare
                        # `gh api …/pulls/N/merge` is the merge-STATUS read
                        # (review round 2: over-gating a read breeds evasion).
                        case "${_gc_seg}" in
                            *pulls/*/merge*)
                                case "${_gc_seg}" in
                                    *PUT*) IFS="${_gc_oldifs}"; return 0 ;;
                                esac ;;
                        esac
                        case "${_gc_seg}" in
                            *mergePullRequest*)
                                IFS="${_gc_oldifs}"; return 0 ;;
                        esac
                    fi
                    ;;
            esac
        fi
        IFS='
'
    done
    IFS="${_gc_oldifs}"
    return 1
}

# command_git_mutate_before_push <command>
#   Returns 0 when a content-mutating git subcommand (commit merge cherry-pick
#   rebase revert am) is invoked in a segment ORDERED BEFORE a `git push`
#   segment of the same command. The push gate evaluates PRE-EXEC state, so no
#   evidence can cover a commit created inline — such compounds must be split.
#   `pull` and `reset` are deliberately excluded (false-block discipline; see
#   openspec/changes archive gate-gh-merge-and-compound-push design).
command_git_mutate_before_push() {
    local _gc_segs _gc_oldifs _gc_seg _gc_sub _gc_seen
    _gc_segs="$(_gc_split_segments "$1")"
    _gc_seen=0
    _gc_oldifs="$IFS"
    IFS='
'
    for _gc_seg in ${_gc_segs}; do
        IFS="${_gc_oldifs}"
        _gc_sub="$(_gc_segment_git_sub "${_gc_seg}")"
        case "${_gc_sub}" in
            commit|merge|cherry-pick|rebase|revert|am) _gc_seen=1 ;;
            push)
                if [ "${_gc_seen}" -eq 1 ]; then
                    IFS="${_gc_oldifs}"; return 0
                fi ;;
        esac
        IFS='
'
    done
    IFS="${_gc_oldifs}"
    return 1
}
