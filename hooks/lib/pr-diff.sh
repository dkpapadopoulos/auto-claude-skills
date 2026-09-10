#!/bin/bash
# pr-diff.sh — resolve the file list of the PR a merge command targets.
#
# BASH-ONLY: pr_ref_from_command relies on unquoted word-splitting + `set -f`
# over the raw command text; under zsh it returns empty for every input, so a
# future model-side caller (model Bash turns run zsh) would silently degrade
# every merge to "unresolved" rather than erroring. Source from bash only.
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

# `_gc_redir_kind_var` (git-command.sh) classifies a word as a shell redirection.
# Borrowed rather than reimplemented: that helper is STRUCTURAL (an optional
# `{name}` fd, an optional `&`, an optional digit run, then `<` or `>`), and this
# predicate family has been bypassed repeatedly by hand-written lists of
# redirection spellings that were complete until they were not.
#
# openspec-guard.sh already sources git-command.sh before this file, so the
# common case defines nothing new; the source is a fallback for a direct caller
# (the tests) and is skipped when the function is already present. Guarded per
# CLAUDE.md's #137 form: a `[ -f ]` test proves existence, not that the source
# succeeded, so availability is decided by `command -v` afterwards.
#
# DEGRADATION IS TODAY'S BEHAVIOUR, NOT A NEW FAILURE: with the helper absent,
# `_prd_redir_ok` stays false, no word is skipped, and a redirection operand is
# counted as a ref candidate exactly as it was before this change — i.e. an
# ambiguous command resolves to nothing. Advisory path, so that is a lost
# measurement, never a gate decision (this lib is deliberately excluded from
# _GATE_ENFORCE_LIBS).
_prd_redir_ok=false
if command -v _gc_redir_kind_var >/dev/null 2>&1; then
    _prd_redir_ok=true
else
    _prd_lib_dir=""
    if [ -n "${BASH_SOURCE:-}" ]; then
        _prd_lib_dir=$(dirname "${BASH_SOURCE}") || _prd_lib_dir=""
    fi
    if [ -n "${_prd_lib_dir}" ] && [ -f "${_prd_lib_dir}/git-command.sh" ]; then
        . "${_prd_lib_dir}/git-command.sh" 2>/dev/null || true
        command -v _gc_redir_kind_var >/dev/null 2>&1 && _prd_redir_ok=true
    fi
    unset _prd_lib_dir
fi

# pr_ref_from_command <command> -> bare PR number, or nothing
pr_ref_from_command() {
    local _cmd="${1:-}" _cand="" _tok _seen_merge="" _restore_glob=1 _ndigit=0
    local _skip_next=""
    case "${_cmd}" in
        *pulls/*/merge*)
            # gh api repos/o/r/pulls/7/merge
            _cand="${_cmd#*pulls/}"; _cand="${_cand%%/merge*}"
            ;;
        *"pr"*"merge"*)
            # First bare token STRICTLY AFTER the literal `merge` subcommand
            # token that is digit-leading. `_seen_merge` GATES the digit test
            # itself -- a digit-leading token before `merge` (e.g. an
            # `--org 42` value) must never be mistaken for the PR ref.
            #
            # Globbing is disabled (set -f) for the scan and explicitly
            # restored right after: this is scanning command TEXT via an
            # unquoted `for tok in $cmd`, not expanding filenames -- a bare
            # `*` token in the command text must stay a literal asterisk,
            # never expand against the caller's cwd.
            #
            # NOTE: this loop deliberately does NOT run inside a `$(...)`
            # command substitution. Bash 3.2 (macOS /bin/bash) fails to
            # parse a `case`/`esac` block nested inside `$(...)` -- the `)`
            # terminating a case pattern is misread as closing the command
            # substitution's parens, corrupting the captured output. Verified
            # directly against `/bin/bash --version` 3.2.57(1)-release;
            # backticks and case-outside-$(...) are unaffected. Do not
            # reintroduce a `case` inside `$(...)` in this file.
            case $- in *f*) _restore_glob=0 ;; esac
            set -f
            for _tok in ${_cmd}; do
                # A SHELL REDIRECTION IS NOT A REF. `2>&1` is digit-leading, so
                # before this it counted as a second candidate and the ambiguity
                # guard below returned nothing -- which is why every one of the
                # 14 gh-merge shadow records ever written says "unresolved".
                # A `bare` operator (`>`, `2>`, `<<<`) takes the NEXT word as its
                # target, so that word is a filename and must be skipped too.
                if [ -n "${_skip_next}" ]; then _skip_next=""; continue; fi
                if [ "${_prd_redir_ok}" = "true" ] && _gc_redir_kind_var "${_tok}"; then
                    [ "${_GC_REDIR}" = "bare" ] && _skip_next=1
                    continue
                fi
                if [ -z "${_seen_merge}" ]; then
                    case "${_tok}" in
                        merge) _seen_merge=1 ;;
                    esac
                    continue
                fi
                # AMBIGUITY: do NOT break on the first digit-leading token —
                # count them all. This scanner splits raw command TEXT and
                # cannot tell a flag's value from a positional, so
                #   gh pr merge --title "PR 42 notes" 99
                # yields both `42` and `99`. Breaking early returned 42: a real
                # but UNRELATED PR, recorded as diff_base:"pr:42" while PR 99
                # was merged. For a corpus whose purpose is stating what each
                # event was measured against, a plausible wrong label is worse
                # than none — "unresolved" is a known-unknown an adjudicator can
                # exclude; "pr:42" is a lie they cannot detect. Two or more
                # candidates ⇒ ambiguous ⇒ return nothing.
                case "${_tok}" in
                    [0-9]*) _ndigit=$((_ndigit + 1)); _cand="${_tok}" ;;
                esac
            done
            if [ "${_ndigit}" -gt 1 ]; then _cand=""; fi
            [ "${_restore_glob}" = 1 ] && set +f
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
#
# Bounded by PR_DIFF_GH_TIMEOUT seconds. macOS /bin/bash has no GNU `timeout`
# (only `gtimeout` via coreutils, which cannot be required), so this backgrounds
# `gh`, races it against a watchdog subshell that kills it after the deadline,
# and blocks on `wait` (not a kill -0 poll loop -- a background job that has
# already exited but not yet been reaped is a zombie, and `kill -0` on a
# zombie still succeeds, so a poll loop keyed on `kill -0` would misdetect a
# fast, already-finished `gh` as still running and stall for the FULL
# timeout). This runs from a PreToolUse hook path (Tasks 2-3) that must
# return promptly even if gh hangs (network stall, interactive auth prompt);
# every path here returns empty, never blocks past the deadline, never errors.
pr_changed_files() {
    local _ref="${1:-}" _repo="${2:-}" _out _gh_pid _watchdog_pid _outfile _timeout
    case "${_ref}" in ""|*[!0-9]*) return 0 ;; esac
    command -v gh >/dev/null 2>&1 || return 0

    _timeout="${PR_DIFF_GH_TIMEOUT}"
    case "${_timeout}" in ''|*[!0-9]*) _timeout=10 ;; esac

    _outfile="$(mktemp "${TMPDIR:-/tmp}/prdiff-out.XXXXXX" 2>/dev/null)" || return 0

    (
        cd "${_repo}" 2>/dev/null || exit 0
        exec gh pr view "${_ref}" --json files --jq '.files[].path' >"${_outfile}" 2>/dev/null
    ) &
    _gh_pid=$!

    # Watchdog: after _timeout seconds, kill the gh process if it's still
    # running. Cancelled below once the primary wait returns, so it never
    # outlives this function on the (common) fast path.
    ( sleep "${_timeout}"; kill "${_gh_pid}" 2>/dev/null ) &
    _watchdog_pid=$!

    wait "${_gh_pid}" 2>/dev/null

    kill "${_watchdog_pid}" 2>/dev/null
    wait "${_watchdog_pid}" 2>/dev/null

    _out="$(cat "${_outfile}" 2>/dev/null)"
    rm -f "${_outfile}"
    printf '%s' "${_out}"
    return 0
}
