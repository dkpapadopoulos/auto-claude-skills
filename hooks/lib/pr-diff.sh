#!/bin/bash
# pr-diff.sh — resolve the file list of the PR a merge command targets.
#
# ADVISORY-PATH ONLY. Never influences a gate decision; every failure returns
# empty. Deliberately NOT in _GATE_ENFORCE_LIBS (same posture as
# implement-shadow.sh and push-gate-capture.sh).
#
# WHY THIS EXISTS: _diff_touches_material_source uses the branch-local
# merge-base(mainline,HEAD)..HEAD delta. For `gh pr merge <other>` that
# describes the invoking session's branch, not the PR being merged — see
# openspec/changes/merge-pr-diff-subject/design.md.
#
# SECURITY BOUNDARY: the command is model-authored text. pr_ref_from_command
# returns ONLY a bare integer; anything else yields empty. Without that, a
# crafted command could inject `--repo other/org` or a flag into the gh call.
# The ref is always passed to gh as a single argument, never interpolated.

PR_DIFF_GH_TIMEOUT="${PR_DIFF_GH_TIMEOUT:-10}"

# pr_ref_from_command <command> -> bare PR number, or nothing
pr_ref_from_command() {
    local _cmd="${1:-}" _tok _prev="" _cand=""
    case "${_cmd}" in
        *pulls/*/merge*)
            # gh api repos/o/r/pulls/7/merge
            _cand="${_cmd#*pulls/}"; _cand="${_cand%%/merge*}"
            ;;
        *"pr"*"merge"*)
            # First bare token after `merge` that is all digits. Flags and their
            # values are skipped by the digit test itself.
            for _tok in ${_cmd}; do
                case "${_prev}" in merge|merge*) : ;; esac
                _prev="${_tok}"
                case "${_tok}" in
                    [0-9]*) _cand="${_tok}"; break ;;
                esac
            done
            ;;
        *) return 0 ;;
    esac
    # THE boundary: bare integer only.
    case "${_cand}" in
        ""|*[!0-9]*) return 0 ;;
        *) printf '%s' "${_cand}" ;;
    esac
}

# pr_changed_files <ref> <repo> -> newline-separated paths, or nothing
pr_changed_files() {
    local _ref="${1:-}" _repo="${2:-}" _out
    case "${_ref}" in ""|*[!0-9]*) return 0 ;; esac
    command -v gh >/dev/null 2>&1 || return 0
    _out="$( cd "${_repo}" 2>/dev/null && \
        gh pr view "${_ref}" --json files --jq '.files[].path' 2>/dev/null )" || return 0
    printf '%s' "${_out}"
    return 0
}
