#!/bin/bash
# git-command.sh — predicate: does a shell command actually INVOKE a git write
# (push/commit), vs merely mention the phrase as an argument/string? Sourced by
# openspec-guard.sh. Bash 3.2 compatible. No side effects. Fail-open by design:
# a parse it cannot handle returns 1 (not a write) — callers that need
# fail-CLOSED behavior keep a substring fallback.

# command_invokes_git_write <command> [subcommands]
#   subcommands: space-separated, default "push commit".
#   Returns 0 if any ; | && || -separated segment's first real token is git
#   (or */git) whose first non-flag argument is one of <subcommands>.
command_invokes_git_write() {
    _gc_cmd="$1"
    _gc_want="${2:-push commit}"
    # One segment per line: split on && || ; |
    _gc_segs="$(printf '%s' "${_gc_cmd}" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/[;|]/\
/g')"
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
