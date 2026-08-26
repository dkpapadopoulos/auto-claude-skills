#!/bin/bash
# reviewer-shadow.sh — append one adjudicable shadow record per consultation of
# the ADVISORY reviewer-evidence leg in hooks/openspec-guard.sh.
#
# WHY IT EXISTS: that leg sets no _DECISION, so a would-advise is
# indistinguishable from a satisfied check in ~/.claude/.push-gate-invocation-log
# (which records the gate's DECISION, and the decision is identical either way).
# This JSONL is the corpus the pre-registered deny-flip is decided on — n=29
# independent episodes OR 2026-11-30, whichever comes first; see
# openspec/changes/reviewer-dispatch-and-evidence/design.md, Pre-registration,
# for the population, the episode collapse rule, the labels and the bands.
#
# DIAGNOSTIC ONLY. Every path returns 0, nothing reaches stdout, and no gate
# state is read or written — so this lib is deliberately EXCLUDED from
# _GATE_ENFORCE_LIBS, the same posture as hooks/lib/implement-shadow.sh and
# scripts/push-gate-capture.sh.
#
# predicate_version is load-bearing: BUMP it when the leg's predicate changes,
# and NEVER pool records across versions when computing a rate.
#
# Raw command text is never written here; transcript_path is the adjudication
# pointer, which keeps the secret posture identical to the IMPLEMENT recorder.
#
# Bash 3.2 compatible. No associative arrays, no quoted operands in $(( )).

REVIEWER_SHADOW_SCHEMA_VERSION=1
REVIEWER_SHADOW_PREDICATE_VERSION=1

# _reviewer_shadow_enum <value> <allowed...> — print <value> if it is one of
# <allowed>, else "unknown". Never errors, never returns non-zero.
#
# Out-of-vocabulary input degrades to "unknown" rather than being written
# through: a value the adjudicator does not recognise is data it cannot segment
# on, and silently minting a NEW category from a caller typo would split the
# corpus without anyone noticing. "unknown" is already a category adjudication
# has to handle.
_reviewer_shadow_enum() {
    local _v="${1:-}" _a
    shift 2>/dev/null || true
    for _a in "$@"; do
        if [ "${_v}" = "${_a}" ]; then
            printf '%s' "${_v}"
            return 0
        fi
    done
    printf 'unknown'
    return 0
}

# reviewer_shadow_record <action> <repo> <session_token> <transcript_path> \
#                        <evidence_present> <evidence_sha> <credited_by> \
#                        <is_error_field>
#
#   action            push | gh-merge
#
#   evidence_present  present | stale | missing | cannot_check
#
#     NOT A BOOLEAN, and collapsing it into one is the single change that would
#     silently destroy this measurement. `reviewer-ran` is SHA-bound (design
#     D8), and the steady-state loop is review -> fix -> commit -> push, so the
#     bound SHA trails HEAD almost immediately and `stale` becomes the ROUTINE
#     outcome once the recorder is populated. Folded into `present` the corpus
#     reports near-perfect compliance and the flip clears on a rate that was
#     never measured; folded into `missing` it reports near-total
#     non-compliance and the flip is denied on the same non-measurement. The
#     question the deny-flip actually turns on — whether the stale variant
#     should stay advisory permanently — is answerable ONLY if the three states
#     are distinct in the record.
#
#     `cannot_check` is the fourth value and is not optional either. The leg has
#     two un-checkable exits (branch-ledger lib unavailable; no ledger key
#     resolves for this branch) where nothing at all is known about whether a
#     reviewer ran. Recording those as `missing` would count an infrastructure
#     failure as evidence of non-compliance — the direction that biases the
#     pre-registered rate TOWARD clearing the flip, which is exactly the defect
#     hooks/lib/implement-shadow.sh's impl_evidence_detail exists to prevent.
#
#   credited_by       literal | subagent-driven-development |
#                     agent-team-execution | agent-team-review | unknown
#
#     Which skill credited the REVIEW milestone. design.md D7 records that
#     whether the review-embedding proxy flows emit a VISIBLE reviewer at all is
#     UNKNOWN, so proxy-credited episodes must be segmentable or the flip is
#     decided on pooled, unreadable data. The branch ledger stores every proxy
#     under the canonical `requesting-code-review` name, so attribution comes
#     from the session-local invocation-evidence array; `unknown` when that file
#     is absent (e.g. cross-session, ledger-only evidence) is an honest answer,
#     not a failure.
#
#   is_error_field    present | absent | unknown
#
#     Whether `.tool_response.is_error` was PRESENT on the credited Agent
#     return. The recorder credits on `.tool_response.is_error // false`, so an
#     ABSENT field still credits; if `Agent` omits the field, crashed reviewers
#     credit `reviewer-ran` and the corpus overstates compliance in the
#     direction that clears the flip. Recording present-vs-absent makes that
#     assumption measurable from the corpus itself instead of from a
#     settings-editing probe (design.md, Pre-registration, blocking
#     precondition). Do NOT drop this as redundant.
#
#     SHIPPED: the only vantage point that can observe the field is
#     hooks/reviewer-evidence-hook.sh, which sees the Agent payload. It writes
#     a sidecar next to the ledger record, one line after branch_ledger_record,
#     and openspec-guard.sh::_reviewer_is_error_field reads it — so this
#     carries real `present`/`absent` data, not a placeholder `unknown`.
#
#     It records per CREDITED return only. An errored return exits the
#     recorder (`[ "${_IS_ERROR}" = "true" ] && exit 0`) before the credit and
#     the sidecar write, so there is no episode for it to describe — that is
#     correct, not a gap. `unknown` still appears for records predating the
#     write, or when the ledger directory itself cannot be resolved.
#
#     If the sidecar-write site in hooks/reviewer-evidence-hook.sh is ever
#     expanded — written in more cases, or at a different point — BUMP
#     schema_version in the same commit. Records written before the expansion
#     carry a different meaning for is_error_field, and without a version
#     boundary a pooled corpus cannot separate them. This is the #133 sidecar
#     precedent: a new observation surface gets a version bump so the earlier
#     records stay segmentable.
#
# Always returns 0. Compact JSONL (jq -cn) because this is a line format.
reviewer_shadow_record() {
    command -v jq >/dev/null 2>&1 || return 0
    local _act="${1:-unknown}" _repo="${2:-}" _tok="${3:-}" _tp="${4:-}"
    local _ep="${5:-unknown}" _esha="${6:-}" _by="${7:-unknown}" _ief="${8:-unknown}"
    local _log _dir _ts _nonce _rid _branch _head
    _ep="$(_reviewer_shadow_enum "${_ep}" present stale missing cannot_check)"
    _by="$(_reviewer_shadow_enum "${_by}" literal subagent-driven-development agent-team-execution agent-team-review)"
    _ief="$(_reviewer_shadow_enum "${_ief}" present absent)"
    _log="${REVIEWER_SHADOW_LOG:-${HOME}/.claude/.reviewer-evidence-shadow.jsonl}"
    _dir="$(dirname "${_log}" 2>/dev/null)" || return 0
    [ -d "${_dir}" ] || mkdir -p "${_dir}" 2>/dev/null || return 0
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || return 0
    [ -n "${_ts}" ] || return 0
    # Nonce keeps record_id unique when ts, pid, token and action all repeat.
    _nonce="${RANDOM:-0}${RANDOM:-0}$$"
    # If BOTH shasum and cksum are absent the pipeline's stdout is empty, _rid
    # ends up empty and the event is silently skipped — the same deliberate
    # fail-open posture as every other path here, matching implement-shadow.sh.
    _rid="$(printf '%s|%s|%s|%s|%s' "${_ts}" "$$" "${_tok}" "${_act}" "${_nonce}" \
        | { shasum -a 256 2>/dev/null || cksum; } | tr -dc 'a-f0-9' | cut -c1-16)"
    [ -n "${_rid}" ] || return 0
    _branch="$(git -C "${_repo:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || _branch=""
    _head="$(git -C "${_repo:-.}" rev-parse HEAD 2>/dev/null)" || _head=""
    # Secure the file BEFORE the first write, like the capture log.
    : >> "${_log}" 2>/dev/null || return 0
    chmod 0600 "${_log}" 2>/dev/null || true
    jq -cn \
        --argjson sv "${REVIEWER_SHADOW_SCHEMA_VERSION}" \
        --argjson pv "${REVIEWER_SHADOW_PREDICATE_VERSION}" \
        --arg rid "${_rid}" --arg ts "${_ts}" --arg act "${_act}" \
        --arg repo "${_repo}" --arg branch "${_branch}" --arg head "${_head}" \
        --arg tok "${_tok}" --arg tp "${_tp}" \
        --arg ep "${_ep}" --arg esha "${_esha}" --arg by "${_by}" --arg ief "${_ief}" \
        '{schema_version:$sv,record_id:$rid,ts:$ts,predicate_version:$pv,
          gate:"push-reviewer-evidence",action:$act,
          repo:$repo,branch:$branch,head_sha:$head,
          review_credited:true,evidence_present:$ep,evidence_sha:$esha,
          review_credited_by:$by,is_error_field:$ief,
          session_token:$tok,transcript_path:$tp}' \
        >> "${_log}" 2>/dev/null || return 0
    return 0
}
