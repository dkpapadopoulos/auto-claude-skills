#!/usr/bin/env bash
# credited-skills.sh — the one list of skills whose invocation or return is
# credited as REVIEW evidence, the one coverage rule that says whether a
# reviewed sha still covers a subject commit, and the one reader of the
# branch ledger's `reviewer-returned` milestone for credit (allowlist arm only).
#
# Consumers: the routing typed-slash lib, the completion hook, the push guard,
# phase-evidence.sh and gate-status.sh. Gate-enforcement lib: a failure to load
# NARROWS credit (callers fall back to a hardcoded four-name list or credit
# nothing), it never widens it. Not model-sourced. Constants and functions only,
# sources nothing, `set -u` clean (the activation hook runs `set -uo pipefail`).
# Bash 3.2.

CREDITED_REVIEW_SKILLS="requesting-code-review subagent-driven-development agent-team-execution agent-team-review code-review review-pr security-review"

# credited_review_skill <name> — 0 iff the name, minus any plugin prefix, is
# credited. Empty or empty-bare names are never credited. A case, never a for
# over the scalar (zsh does not word-split it).
credited_review_skill() {
    local _bare="${1:-}"
    # Reject anything outside the plugin:name charset (whitespace included), so
    # a multi-token string cannot match an adjacent list entry.
    case "${_bare}" in *[!A-Za-z0-9._:-]*) return 1 ;; esac
    _bare="${_bare##*:}"
    [ -n "${_bare}" ] || return 1
    case " ${CREDITED_REVIEW_SKILLS} " in
        *" ${_bare} "*) return 0 ;;
    esac
    return 1
}

# credited_review_builtin <name> — 0 iff exactly a built-in review command
# (these have no registry entry, so they are credited bare only).
credited_review_builtin() {
    case "${1:-}" in
        code-review|security-review) return 0 ;;
    esac
    return 1
}

# review_sha_covers <sha> <subj_root> <subj_rev>
#   0 covered   — <sha> is an ancestor of <subj_rev> and no material source
#                 file differs between them
#   1 uncovered — not an ancestor, or a material source file changed
#   2 cannot check — malformed sha, unknown commit, bad root or any git failure
# Prints nothing. The docs exclusion is identical to _names_touch_material_source
# (openspec-guard.sh) and staleness_delta_is_docs: docs/*, openspec/*, *.md.
review_sha_covers() {
    local _sha="${1:-}" _root="${2:-}" _rev="${3:-}" _names _f _rc
    case "${_sha}" in
        ''|*[!0-9a-f]*) return 2 ;;
    esac
    [ "${#_sha}" -ge 7 ] && [ "${#_sha}" -le 40 ] || return 2
    [ -n "${_root}" ] && [ -n "${_rev}" ] || return 2
    git -C "${_root}" merge-base --is-ancestor "${_sha}" "${_rev}" >/dev/null 2>&1
    _rc=$?
    [ "${_rc}" -eq 0 ] || { [ "${_rc}" -eq 1 ] && return 1; return 2; }
    _names="$(git -C "${_root}" diff --no-renames --name-only "${_sha}" "${_rev}" -- 2>/dev/null)" || return 2
    while IFS= read -r _f; do
        [ -n "${_f}" ] || continue
        case "${_f}" in docs/*|openspec/*|*.md) continue ;; *) return 1 ;; esac
    done <<EOF
${_names}
EOF
    return 0
}

# review_reviewer_returned_sha <ledger_root>
#   Prints the reviewed sha and returns 0 iff the branch ledger keyed from
#   <ledger_root> holds a `reviewer-returned` milestone tagged `arm=allowlist`
#   (the reviewer was matched by the allowlisted subagent_type arm, not the
#   description word) whose sha is 7-40 lowercase hex. Returns 1 and prints
#   nothing otherwise: an empty root, branch-ledger.sh not loaded
#   (branch_ledger_sha_tag undefined — this lib sources nothing), no milestone,
#   an untagged pre-arm milestone, `arm=description`, or a sha of `unknown` or
#   `-` (dispatch-time commit not known; never a later HEAD).
# The sha and the arm come from ONE read under ONE key derivation
# (branch_ledger_sha_tag). Reading them separately can pair one record's
# `arm=allowlist` with a concurrently written `arm=description` record's sha.
review_reviewer_returned_sha() {
    local _lroot="${1:-}" _st _tag _sha
    [ -n "${_lroot}" ] || return 1
    command -v branch_ledger_sha_tag >/dev/null 2>&1 || return 1
    _st="$(branch_ledger_sha_tag reviewer-returned "${_lroot}" 2>/dev/null)" || return 1
    case "${_st}" in *" "*) ;; *) return 1 ;; esac
    _sha="${_st%% *}"
    _tag="${_st#* }"
    [ "${_tag}" = "arm=allowlist" ] || return 1
    case "${_sha}" in
        ''|*[!0-9a-f]*) return 1 ;;
    esac
    [ "${#_sha}" -ge 7 ] && [ "${#_sha}" -le 40 ] || return 1
    printf '%s' "${_sha}"
}

# review_reviewer_covers <ledger_root> <subj_root> <subj_rev>
#   Prints the reviewed sha and returns 0 iff review_reviewer_returned_sha
#   succeeds AND review_sha_covers says that sha covers <subj_rev> in
#   <subj_root>. Returns 1 and prints nothing otherwise — uncovered and
#   cannot-check alike; a caller that must tell them apart calls
#   review_sha_covers itself. The ledger root and the subject root are separate
#   on purpose: ledger reads stay on the process-derived root (the writer keys on
#   ITS cwd+branch), while coverage is measured against the command's subject.
# Must stay the LAST definition in this file (pinned by tests/test-reviewer-arm.sh).
review_reviewer_covers() {
    local _lroot="${1:-}" _sroot="${2:-}" _srev="${3:-}" _sha
    _sha="$(review_reviewer_returned_sha "${_lroot}")" || return 1
    review_sha_covers "${_sha}" "${_sroot}" "${_srev}" || return 1
    printf '%s' "${_sha}"
}
