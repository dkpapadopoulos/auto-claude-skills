#!/bin/bash
# shadow-adjudicate.sh — label IMPLEMENT-leg shadow records (the Stage C1 corpus)
# and report the pre-registered false-block rate over independent episodes.
#
# DIAGNOSTIC ONLY. Never sourced by hooks/openspec-guard.sh, deliberately
# EXCLUDED from _GATE_ENFORCE_LIBS, writes no gate state, and its output MUST
# NOT be wired into an enforcement decision — the guard is the only decider.
#
# The pre-registration in openspec/changes/implement-shadow-event/design.md is an
# INPUT here, not something this script may redefine: the bands, the n=29 floor,
# the >=2-repo diversity requirement and the episode denominator all come from
# that file.
#
# Bash 3.2. Never `set -e`. Never reads stdin.
set -u

REQUIRED_PREDICATE_VERSION=2
FLOOR_EPISODES=29
FLOOR_REPOS=2
EPISODE_WINDOW_SEC=1800
ALPHA=0.05
DENY_P=0.10
ADVISORY_P=0.20

SHADOW_LOG="${IMPLEMENT_SHADOW_LOG:-$HOME/.claude/.push-implement-shadow.jsonl}"
ADJ_LOG="${IMPLEMENT_ADJUDICATION_LOG:-$HOME/.claude/.push-implement-adjudication.jsonl}"

# _band <k> <n> -> DENY | ADVISORY-ONLY | NARROWED | INSUFFICIENT
#
# Exact Clopper-Pearson, stated as a direct CDF comparison so no interval
# inversion is needed (the binomial CDF is monotone in p):
#   DENY          <=> P(X <= k | n, 0.10) <  alpha
#   ADVISORY-ONLY <=> P(X >= k | n, 0.20) <= alpha
# Do NOT substitute a normal approximation: Wilson is anti-conservative in the
# tail and calls 8/23 ADVISORY-ONLY where exact says NARROWED (a pinned test).
_band() {
    awk -v k="${1:-0}" -v n="${2:-0}" -v a="${ALPHA}" \
        -v dp="${DENY_P}" -v ap="${ADVISORY_P}" '
    function tail(kk, nn, p, mode,   i, t, s) {
        # mode "le": sum_{i<=kk}   mode "ge": sum_{i>=kk}
        # Term recurrence rather than factorials, so large n cannot overflow.
        s = 0; t = (1 - p) ^ nn
        for (i = 0; i <= nn; i++) {
            if (mode == "le" && i <= kk) s += t
            if (mode == "ge" && i >= kk) s += t
            if (i < nn) t = t * (nn - i) / (i + 1) * p / (1 - p)
        }
        return s
    }
    BEGIN {
        if (n < 1) { print "INSUFFICIENT"; exit }
        if (tail(k, n, dp, "le") <  a) { print "DENY";          exit }
        if (tail(k, n, ap, "ge") <= a) { print "ADVISORY-ONLY"; exit }
        print "NARROWED"
    }'
}

# _iso_epoch <iso8601-utc> -> epoch seconds, or -1 if unparseable.
# Implemented in awk rather than via `date`, because `date -d` (GNU) and
# `date -j -f` (BSD/macOS) are mutually incompatible and this must run on both.
_iso_epoch() {
    awk -v s="${1:-}" '
    function days_from_civil(y, m, d,   era, yoe, doy, doe) {
        if (m <= 2) y = y - 1
        era = int((y >= 0 ? y : y - 399) / 400)
        yoe = y - era * 400
        doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return era * 146097 + doe - 719468
    }
    BEGIN {
        if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) { print -1; exit }
        y  = substr(s,1,4)+0;  mo = substr(s,6,2)+0;  d  = substr(s,9,2)+0
        hh = substr(s,12,2)+0; mi = substr(s,15,2)+0; ss = substr(s,18,2)+0
        print days_from_civil(y, mo, d) * 86400 + hh * 3600 + mi * 60 + ss
    }'
}

# _episodes — group v2 shadow records into independent episodes.
# One TAB-separated line per episode:
#   <episode_id> <repo> <branch> <session_token> <record_ids_csv>
# Membership: same (repo, branch, session_token) AND ts within
# EPISODE_WINDOW_SEC of the episode's FIRST record — anchored, not rolling.
# A rolling gap would chain a whole day of intermittent pushes into one episode
# and drive the denominator below the real number of decision points.
_episodes() {
    [ -f "${SHADOW_LOG}" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" '
        select(.predicate_version == $pv)
        | [.repo, .branch, .session_token, .ts, .record_id] | @tsv
      ' "${SHADOW_LOG}" 2>/dev/null \
    | while IFS="$(printf '\t')" read -r _repo _branch _tok _ts _rid; do
          [ -z "${_rid:-}" ] && continue
          printf '%s\t%s\t%s\t%s\t%s\n' "$_repo" "$_branch" "$_tok" "$(_iso_epoch "$_ts")" "$_rid"
      done \
    | sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3 -k4,4n \
    | awk -F'\t' -v w="${EPISODE_WINDOW_SEC}" '
        {
          key = $1 "\001" $2 "\001" $3
          if (NR == 1 || key != prev_key || ($4 - anchor) > w) {
            if (NR > 1) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids
            eid = $5; erepo = $1; ebranch = $2; etok = $3; ids = $5
            anchor = $4; prev_key = key
          } else {
            ids = ids "," $5
          }
        }
        END { if (NR > 0) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids }'
}

# _claimant -> human | agent
# Deliberately biased toward "agent": a human using `!` inside a session is
# misclassified and pays one re-confirmation, whereas an agent's self-label
# counted silently would corrupt the rate. This leg governs agent pushes, so the
# subject has a live incentive to grade its own gate.
# All three signals are forgeable — the output says human-CLAIMED, never verified.
_claimant() {
    if [ -n "${CLAUDECODE:-}" ]; then echo agent; return; fi
    if [ ! -t 1 ]; then echo agent; return; fi
    case "$(ps -o comm= -p "$PPID" 2>/dev/null)" in *claude*) echo agent; return;; esac
    echo human
}

_record_field() { # _record_field <record_id> <field>
    jq -r --arg id "${1:-}" --arg f "${2:-}" \
       'select(.record_id == $id) | .[$f] // empty' "${SHADOW_LOG}" 2>/dev/null | head -1
}

cmd_adjudicate() {
    local _rid="${1:-}" _verdict="${2:-}" _reason="${3:-}" _pv _ts _claim
    case "${_verdict}" in
        true_catch|false_block|unknown) ;;
        *) echo "error: --verdict must be true_catch, false_block, or unknown" >&2; return 1;;
    esac
    [ -f "${SHADOW_LOG}" ] || { echo "error: no shadow log at ${SHADOW_LOG}" >&2; return 1; }
    command -v jq >/dev/null 2>&1 || { echo "error: jq required" >&2; return 1; }
    _pv="$(_record_field "${_rid}" predicate_version)"
    [ -z "${_pv}" ] && { echo "error: no record '${_rid}' in ${SHADOW_LOG}" >&2; return 1; }
    if [ "${_pv}" != "${REQUIRED_PREDICATE_VERSION}" ]; then
        echo "error: record '${_rid}' is predicate_version ${_pv}; only v${REQUIRED_PREDICATE_VERSION} is adjudicable." >&2
        echo "       v1 measured a different subject for merges and MUST NOT be pooled with v2." >&2
        return 1
    fi
    if [ ! -f "${ADJ_LOG}" ]; then
        : > "${ADJ_LOG}" 2>/dev/null || { echo "error: cannot write ${ADJ_LOG}" >&2; return 1; }
    fi
    chmod 600 "${ADJ_LOG}" 2>/dev/null
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    _claim="$(_claimant)"
    jq -cn --arg rid "${_rid}" --arg ts "${_ts}" --arg v "${_verdict}" \
           --arg r "${_reason}" --arg c "${_claim}" \
           --arg u "${USER:-unknown}" --arg tty "$(tty 2>/dev/null || echo not-a-tty)" \
           --arg par "$(ps -o comm= -p "$PPID" 2>/dev/null || echo unknown)" \
           --arg head "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
           --arg agentenv "$([ -n "${CLAUDECODE:-}" ] && echo present || echo absent)" \
       '{schema_version:1,record_id:$rid,ts:$ts,verdict:$v,reason:$r,claimant:$c,
         provenance:{user:$u,tty:$tty,parent:$par,repo_head:$head,agent_env:$agentenv}}' \
       >> "${ADJ_LOG}" 2>/dev/null || { echo "error: append to ${ADJ_LOG} failed" >&2; return 1; }
    echo "recorded: ${_rid}  ${_verdict}  (${_claim}-claimed)"
    [ "${_claim}" = "agent" ] && \
        echo "note: agent-claimed — excluded from the rate until a human re-confirms."
    echo "label: HUMAN-CLAIMED, not human-verified."
    return 0
}

_usage() {
    cat <<'HELP'
shadow-adjudicate.sh — label IMPLEMENT-leg shadow records and report the rate.

  --next                       show the oldest unadjudicated record + how to label it
  <record_id> --verdict <v> --reason "<why>"
                               record a verdict: true_catch | false_block | unknown
  --status                     episodes, exclusions, rate, band, distance to floor

Diagnostic only. Exits 0 for observational commands. Never wire the output of
--status into an enforcement decision: the push gate is the only decider.
HELP
}

# Allow tests to source the helpers without executing a command. `return` is
# valid here only because this branch is reached solely via `. script --source-only`;
# the 2>/dev/null covers the executed case, where the case below runs instead.
case "${1:-}" in
    --source-only) return 0 2>/dev/null ;;
    --next)        cmd_next; exit $? ;;
    --status)      cmd_status; exit $? ;;
    -h|--help)     _usage; exit 0 ;;
    "")            _usage; exit 1 ;;
    *)
        _RID="$1"; shift
        _V=""; _R=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --verdict) _V="${2:-}"; shift 2 ;;
                --reason)  _R="${2:-}"; shift 2 ;;
                *) echo "error: unexpected argument '$1'" >&2; exit 1 ;;
            esac
        done
        cmd_adjudicate "${_RID}" "${_V}" "${_R}"; exit $?
        ;;
esac
