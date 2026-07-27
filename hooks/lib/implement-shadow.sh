#!/bin/bash
# implement-shadow.sh — append one adjudicable shadow record per IMPLEMENT
# would-block event, so the deny-flip's push-replay backtest has a corpus.
#
# DIAGNOSTIC ONLY. It never influences a gate decision and fails open on every
# error path, so it is deliberately NOT in _GATE_ENFORCE_LIBS (same posture as
# scripts/push-gate-capture.sh).
#
# predicate_version is load-bearing: when the IMPLEMENT predicate changes, bump
# it, and NEVER pool records across versions when computing a rate. See
# openspec/changes/implement-shadow-event/design.md for the pre-registered
# false-block definition and decision rule.
#
# Raw command text is never written here — the transcript_path pointer is the
# adjudication surface, which keeps the secret posture identical to capture.

IMPLEMENT_SHADOW_SCHEMA_VERSION=1
IMPLEMENT_SHADOW_PREDICATE_VERSION=1

# implement_shadow_record <action> <repo> <session_token> <transcript_path> <evidence_kind>
#   action: push | gh-merge
#   evidence_kind: which evidence classes were tried and missed (e.g. "none")
# Always returns 0. Compact JSONL (jq -cn) because this is a line format.
implement_shadow_record() {
    command -v jq >/dev/null 2>&1 || return 0
    local _act="${1:-unknown}" _repo="${2:-}" _tok="${3:-}" _tp="${4:-}" _ev="${5:-none}"
    local _log _dir _ts _nonce _rid _branch _head
    _log="${IMPLEMENT_SHADOW_LOG:-${HOME}/.claude/.push-implement-shadow.jsonl}"
    _dir="$(dirname "${_log}" 2>/dev/null)" || return 0
    [ -d "${_dir}" ] || mkdir -p "${_dir}" 2>/dev/null || return 0
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || return 0
    [ -n "${_ts}" ] || return 0
    # Nonce keeps record_id unique when ts, pid and token all repeat.
    _nonce="${RANDOM:-0}${RANDOM:-0}$$"
    _rid="$(printf '%s|%s|%s|%s|%s' "${_ts}" "$$" "${_tok}" "${_act}" "${_nonce}" \
        | { shasum -a 256 2>/dev/null || cksum; } | tr -dc 'a-f0-9' | cut -c1-16)"
    [ -n "${_rid}" ] || return 0
    _branch="$(git -C "${_repo}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || _branch=""
    _head="$(git -C "${_repo}" rev-parse HEAD 2>/dev/null)" || _head=""
    : >> "${_log}" 2>/dev/null || return 0
    chmod 0600 "${_log}" 2>/dev/null || true
    jq -cn \
        --argjson sv "${IMPLEMENT_SHADOW_SCHEMA_VERSION}" \
        --argjson pv "${IMPLEMENT_SHADOW_PREDICATE_VERSION}" \
        --arg rid "${_rid}" --arg ts "${_ts}" --arg act "${_act}" \
        --arg repo "${_repo}" --arg branch "${_branch}" --arg head "${_head}" \
        --arg tok "${_tok}" --arg tp "${_tp}" --arg ev "${_ev}" \
        '{schema_version:$sv,record_id:$rid,ts:$ts,predicate_version:$pv,
          gate:"push-implement",would_block:true,action:$act,
          repo:$repo,branch:$branch,head_sha:$head,
          impl_in_chain:true,material_source:true,impl_evidence_kind:$ev,
          session_token:$tok,transcript_path:$tp}' \
        >> "${_log}" 2>/dev/null || return 0
    return 0
}
