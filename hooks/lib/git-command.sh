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
        # Word-split the segment with default IFS.
        # shellcheck disable=SC2086
        set -- ${_gc_seg}
        # Strip leading `env` and VAR=val assignment prefixes.
        while [ "$#" -gt 0 ]; do
            case "$1" in
                env) shift ;;
                [A-Za-z_]*=*) shift ;;
                *) break ;;
            esac
        done
        if [ "$#" -gt 0 ]; then
            case "$1" in
                git|*/git)
                    shift
                    # Skip git global flags to reach the subcommand.
                    _gc_sub=""
                    while [ "$#" -gt 0 ]; do
                        case "$1" in
                            -C|-c|--git-dir|--work-tree|--namespace)
                                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                            -*) shift ;;
                            *) _gc_sub="$1"; break ;;
                        esac
                    done
                    for _gc_w in ${_gc_want}; do
                        if [ "${_gc_sub}" = "${_gc_w}" ]; then
                            IFS="${_gc_oldifs}"
                            return 0
                        fi
                    done
                    ;;
            esac
        fi
        IFS='
'
    done
    IFS="${_gc_oldifs}"
    return 1
}
