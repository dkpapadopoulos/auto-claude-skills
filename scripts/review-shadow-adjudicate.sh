#!/bin/bash
# review-shadow-adjudicate.sh — label REVIEW-leg shadow records and report the
# pre-registered false-block rate over independent episodes.
#
# DIAGNOSTIC ONLY. Never sourced by hooks/openspec-guard.sh, deliberately
# EXCLUDED from _GATE_ENFORCE_LIBS, writes no gate state, emits no
# permissionDecision, and its output MUST NOT be wired into an enforcement
# decision — the guard is the only decider.
#
# The pre-registration in openspec/changes/review-verdict/design.md is an INPUT
# here, not something this script may redefine: the bands, the n=29 floor, the
# >=2-repo diversity requirement, the episode denominator and the definition of
# `false_block` all come from that file.
#
# Adjudications append to a SIDECAR. The shadow log is NEVER mutated.
#
# Bash 3.2. Never `set -e`. Never reads stdin.
set -u

# --- pre-registered constants (openspec/changes/review-verdict/design.md) ---
FLOOR_EPISODES=29
FLOOR_REPOS=2
EPISODE_WINDOW_SEC=1800
ALPHA=0.05
DENY_P=0.10
ADVISORY_P=0.20

SHADOW_LOG="${REVIEW_SHADOW_LOG:-$HOME/.claude/.push-review-shadow.jsonl}"
ADJ_LOG="${REVIEW_ADJUDICATION_LOG:-$HOME/.claude/.push-review-adjudication.jsonl}"

_ROOT="$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." 2>/dev/null && pwd)"

# Adjudicable predicate version, DERIVED FROM THE PRODUCER. The literal below is
# only the fallback for a checkout where the lib is absent. Pinning it
# independently is a silent corpus blackout: when #219 bumped the IMPLEMENT
# producer while its reader stayed behind, `--status` reported 0 episodes with
# live records counted "unpoolable" — indistinguishable from an empty corpus, on
# the one instrument that must never fake that state.
REQUIRED_PREDICATE_VERSION=2
_rs_lib="${_ROOT}/hooks/lib/review-shadow.sh"
if [ -f "${_rs_lib}" ]; then
    # shellcheck disable=SC1090
    . "${_rs_lib}" 2>/dev/null || true
    case "${REVIEW_SHADOW_PREDICATE_VERSION:-}" in
        ''|*[!0-9]*) : ;;
        *) REQUIRED_PREDICATE_VERSION="${REVIEW_SHADOW_PREDICATE_VERSION}" ;;
    esac
fi

# Shared corpus measurement, single-sourced with the IMPLEMENT adjudicator.
# REFUSE to run without it rather than falling back to a local copy: the
# degraded answer here would be a NUMBER, and an instrument that silently
# reports a rate computed by unknown means is worse than one that stops.
_sc_lib="${_ROOT}/hooks/lib/shadow-corpus.sh"
if [ -f "${_sc_lib}" ]; then
    # shellcheck disable=SC1090
    . "${_sc_lib}" 2>/dev/null || true
fi
if ! command -v shadow_band >/dev/null 2>&1 || ! command -v shadow_group_episodes >/dev/null 2>&1; then
    echo "error: hooks/lib/shadow-corpus.sh did not load (looked at ${_sc_lib})." >&2
    echo "       Refusing to report a rate computed by a local fallback." >&2
    exit 2
fi

# _tsv <jq-projection> — records of the ADJUDICABLE predicate version only.
# `jq` ABORTS on the first parse error, so a single truncated line would
# silently truncate the whole corpus. `-R` + `fromjson?` skips only the bad
# line; unparseable lines are counted and reported by --status.
_tsv() {
    jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
       "fromjson? // empty | select(.predicate_version == \$pv) | ${1} | @tsv" \
       "${SHADOW_LOG}" 2>/dev/null
}

# _legacy_count — records of ANY OTHER predicate version.
#
# These are REPORTED, never silently dropped and never silently counted. The
# live v1 corpus spans two fire conditions under one label: 78aa21e (#219,
# 2026-09-01) moved this leg's material-source and coverage predicates onto the
# resolved subject and bumped implement-shadow.sh while leaving review-shadow.sh
# alone. A timestamp cannot recover which guard wrote a given record, because
# sessions run cached plugin versions. So those records are describable but not
# poolable, and saying so is the whole point of this line.
_legacy_count() {
    jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
       'fromjson? // empty | select(.predicate_version != $pv) | .predicate_version' \
       "${SHADOW_LOG}" 2>/dev/null | grep -c . | tr -d '[:space:]'
}

_episodes() {
    [ -f "${SHADOW_LOG}" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    _tsv '[.repo, .branch, .session_token, .ts, .record_id]' \
    | shadow_group_episodes "${EPISODE_WINDOW_SEC}"
}

# _claimant -> human | agent
# Biased toward "agent": this leg governs AGENT pushes, so the subject has a
# live incentive to grade its own gate. A human misclassified inside a session
# pays one re-confirmation; an agent's self-label counted silently would corrupt
# the rate. Deliberately NO tty check — `[ ! -t 1 ]` fires on any redirect or
# pipe, and since human-claimed episodes are the only countable ones that would
# make the floor unreachable for anyone who pipes, rather than merely costing a
# re-confirmation. The mitigation is not that forgery is impossible; it is that
# a forged clean rate requires a deliberate lie about provenance.
_claimant() {
    if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then echo agent; return; fi
    case "$(ps -o comm= -p "$PPID" 2>/dev/null)" in *claude*) echo agent; return;; esac
    echo human
}

_record_field() { # <record_id> <field>
    jq -r --arg id "${1:-}" --arg f "${2:-}" \
       'select(.record_id == $id) | .[$f] // empty' "${SHADOW_LOG}" 2>/dev/null | head -1
}

_adjudicated_ids() {
    [ -f "${ADJ_LOG}" ] || return 0
    jq -r '.record_id // empty' "${ADJ_LOG}" 2>/dev/null | sort -u
}

cmd_adjudicate() {
    local _rid="${1:-}" _verdict="${2:-}" _reason="${3:-}" _pv _ts _claim _tty
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
        echo "       Records of another predicate version were written by a different fire" >&2
        echo "       condition and MUST NOT be pooled." >&2
        return 1
    fi
    if [ ! -f "${ADJ_LOG}" ]; then
        : > "${ADJ_LOG}" 2>/dev/null || { echo "error: cannot write ${ADJ_LOG}" >&2; return 1; }
    fi
    chmod 600 "${ADJ_LOG}" 2>/dev/null
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    _claim="$(_claimant)"
    # `tty` prints "not a tty" to STDOUT and ALSO exits 1, so `$(tty || echo X)`
    # captures BOTH strings. Branch on the exit status instead.
    if _tty="$(tty 2>/dev/null)"; then :; else _tty="not-a-tty"; fi
    jq -cn --arg rid "${_rid}" --arg ts "${_ts}" --arg v "${_verdict}" \
           --arg r "${_reason}" --arg c "${_claim}" \
           --arg u "${USER:-unknown}" --arg tty "${_tty}" \
           --arg corpus "${SHADOW_LOG}" \
           --arg par "$(ps -o comm= -p "$PPID" 2>/dev/null || echo unknown)" \
           --arg head "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
           --arg agentenv "$([ -n "${CLAUDECODE:-}" ] && echo present || echo absent)" \
       '{schema_version:1,leg:"review",record_id:$rid,ts:$ts,verdict:$v,reason:$r,
         claimant:$c,corpus:$corpus,
         provenance:{user:$u,tty:$tty,parent:$par,repo_head:$head,agent_env:$agentenv}}' \
       >> "${ADJ_LOG}" 2>/dev/null || { echo "error: append to ${ADJ_LOG} failed" >&2; return 1; }
    echo "recorded: ${_rid}  ${_verdict}  (${_claim}-claimed)"
    [ "${_claim}" = "agent" ] && \
        echo "note: agent-claimed — excluded from the rate until a human re-confirms."
    echo "label: $(printf '%s' "${_claim}" | tr '[:lower:]' '[:upper:]')-CLAIMED, not human-verified."
    return 0
}

# cmd_next — oldest adjudicable record with no adjudication. Read-only.
cmd_next() {
    local _seen _line _id _row _n_ok _n_legacy
    [ -f "${SHADOW_LOG}" ] || { echo "no shadow log at ${SHADOW_LOG} — nothing outstanding."; return 0; }
    command -v jq >/dev/null 2>&1 || { echo "jq required — cannot read the corpus."; return 0; }
    _seen="$(_adjudicated_ids)"
    _line="$(_tsv 'select((.ts // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
              | select(has("would_block") and ((.would_block|type) == "boolean") and .would_block == true)
              | [.record_id,.ts,.repo,.branch,.action,.reason,.transcript_path]' \
            | sort -t "$(printf '\t')" -k2,2 \
            | while IFS= read -r _row; do
                  _id="$(printf '%s' "${_row}" | cut -f1)"
                  [ -z "${_id}" ] && continue
                  if [ -n "${_seen}" ] && printf '%s\n' "${_seen}" | grep -qxF "${_id}"; then
                      continue
                  fi
                  printf '%s\n' "${_row}"; break
              done)"
    if [ -z "${_line}" ]; then
        # "no adjudicable records exist" and "all of them are adjudicated" are
        # different states and must not share a message: the first means nothing
        # is countable yet, the second means the work is done.
        _n_ok="$(_tsv '[.record_id]' | grep -c . | tr -d '[:space:]')"
        _n_legacy="$(_legacy_count)"
        if [ "${_n_ok:-0}" -eq 0 ]; then
            echo "no predicate_version ${REQUIRED_PREDICATE_VERSION} records yet — nothing is countable."
            if [ "${_n_legacy:-0}" -gt 0 ]; then
                echo "  ${_n_legacy} record(s) of another predicate version are present and are NOT"
                echo "  adjudicable: they were written by a different fire condition. See --status."
            fi
        else
            echo "all ${_n_ok} adjudicable record(s) are labelled."
        fi
        return 0
    fi
    echo "record_id : $(printf '%s' "${_line}" | cut -f1)"
    echo "ts        : $(printf '%s' "${_line}" | cut -f2)"
    echo "repo      : $(printf '%s' "${_line}" | cut -f3)"
    echo "branch    : $(printf '%s' "${_line}" | cut -f4)"
    echo "action    : $(printf '%s' "${_line}" | cut -f5)"
    echo "reason    : $(printf '%s' "${_line}" | cut -f6)"
    echo "transcript: $(printf '%s' "${_line}" | cut -f7)"
    echo
    echo "A would-block resolved by the author actually running a review is a TRUE CATCH."
    echo "It is a FALSE BLOCK only if a real review demonstrably did occur, or the"
    echo "artifact was absent for an infrastructure reason the advisory misnames."
    echo "reason=cannot-check is pre-registered as ALWAYS a false_block."
    echo
    echo "  $0 --adjudicate $(printf '%s' "${_line}" | cut -f1) --verdict true_catch|false_block|unknown [--reason '...']"
    return 0
}

# _episode_verdict <ids_csv> -> two lines: <verdict> <claimant>
#
# Worst-verdict-wins (any false_block wins), with the LATEST adjudication per
# record superseding earlier ones. The sidecar is append-only, so the last
# matching row is the most recent. Folding over ALL rows instead makes a
# correction a silent no-op: re-adjudicating a fat-fingered false_block to
# true_catch would print success while the earlier verdict kept winning,
# permanently poisoning a rate that gates a deny-flip.
_episode_verdict() {
    local _ids="${1:-}" _v="unlabeled" _claim="agent" _has_human=0 _id _rows _latest _rv _rc
    if [ ! -f "${ADJ_LOG}" ]; then printf 'unlabeled\nagent\n'; return; fi
    _rows="$(jq -r '[.record_id,.verdict,.claimant] | @tsv' "${ADJ_LOG}" 2>/dev/null)"
    for _id in $(printf '%s' "${_ids}" | tr ',' ' '); do
        _latest="$(printf '%s\n' "${_rows}" \
                   | awk -F'\t' -v id="${_id}" '$1 == id { v = $2; c = $3 }
                                                END { if (v != "") print v "\t" c }')"
        [ -z "${_latest}" ] && continue
        _rv="$(printf '%s' "${_latest}" | cut -f1)"
        _rc="$(printf '%s' "${_latest}" | cut -f2)"
        [ "${_rc}" = "human" ] && _has_human=1
        case "${_rv}" in
            false_block) _v="false_block" ;;
            unknown)     if [ "${_v}" != "false_block" ]; then _v="unknown"; fi ;;
            true_catch)  if [ "${_v}" = "unlabeled" ];    then _v="true_catch"; fi ;;
        esac
    done
    [ "${_has_human}" -eq 1 ] && _claim="human"
    printf '%s\n%s\n' "${_v}" "${_claim}"
}

# cmd_status — episode-level readout. Observational; always exits 0.
cmd_status() {
    local _tot=0 _lab=0 _fb=0 _tc=0 _unk=0 _agent=0 _unlab=0
    local _repos="" _eid _repo _branch _tok _ids _vc _v _c _nrepos
    local _lines=0 _parsed=0 _unparsed=0 _legacy=0 _orphan=0
    local _band_hdl _den

    echo "=== REVIEW shadow corpus (leg: push/merge REVIEW verdict) ==="
    echo "corpus  : ${SHADOW_LOG}"
    echo "sidecar : ${ADJ_LOG}"
    echo "adjudicable predicate_version: ${REQUIRED_PREDICATE_VERSION}"
    if [ ! -f "${SHADOW_LOG}" ]; then echo "(no corpus yet)"; return 0; fi
    if ! command -v jq >/dev/null 2>&1; then echo "(jq required)"; return 0; fi

    _lines="$(grep -c . "${SHADOW_LOG}" 2>/dev/null | tr -d '[:space:]')"
    _parsed="$(jq -R -r 'fromjson? // empty | .ts // ""' "${SHADOW_LOG}" 2>/dev/null | grep -c . | tr -d '[:space:]')"
    _unparsed=$(( ${_lines:-0} - ${_parsed:-0} ))
    _legacy="$(_legacy_count)"
    echo "records : ${_lines:-0} line(s), ${_parsed:-0} parsed, ${_unparsed} unparseable"

    # The legacy band is REPORTED, with its cause, never silently folded in or
    # silently dropped. Quietly reporting 0 episodes for a live corpus and
    # quietly reporting all of them are the same error facing opposite ways.
    if [ "${_legacy:-0}" -gt 0 ]; then
        echo
        echo "EXCLUDED — other-predicate : ${_legacy} record(s)"
        echo "  Written by a different fire condition and NOT poolable into the rate."
        echo "  78aa21e (#219, 2026-09-01) moved this leg's material-source and coverage"
        echo "  predicates onto the resolved subject and bumped implement-shadow.sh while"
        echo "  leaving review-shadow.sh at predicate_version 1, so v1 records span BOTH"
        echo "  fire conditions under one label. A timestamp cannot recover which guard"
        echo "  wrote a record: sessions run cached plugin versions."
    fi

    # Episode loop MUST stay in the current shell, so the counters survive --
    # hence a heredoc, never a pipe. And it re-splits on \x1f rather than tab:
    # tab is IFS WHITESPACE, so an empty field (an unresolvable branch writes
    # one) collapses and shifts every later column, which silently drops the
    # episode from the denominator.
    while IFS="$(printf '\037')" read -r _eid _repo _branch _tok _ids; do
        [ -z "${_eid}" ] && continue
        _tot=$(( _tot + 1 ))
        case " ${_repos} " in *" ${_repo} "*) ;; *) _repos="${_repos} ${_repo}" ;; esac
        _vc="$(_episode_verdict "${_ids}")"
        _v="$(printf '%s' "${_vc}" | sed -n '1p')"
        _c="$(printf '%s' "${_vc}" | sed -n '2p')"
        case "${_v}" in
            unlabeled) _unlab=$(( _unlab + 1 )) ;;
            *) _lab=$(( _lab + 1 ))
               if [ "${_c}" != "human" ]; then _agent=$(( _agent + 1 ));
               else
                   case "${_v}" in
                       false_block) _fb=$(( _fb + 1 )) ;;
                       true_catch)  _tc=$(( _tc + 1 )) ;;
                       unknown)     _unk=$(( _unk + 1 )) ;;
                   esac
               fi ;;
        esac
    done <<EOF
$(_episodes | tr '\t' '\037')
EOF

    _nrepos=0
    for _repo in ${_repos}; do _nrepos=$(( _nrepos + 1 )); done

    echo
    echo "episodes (adjudicable) : ${_tot}   across ${_nrepos} distinct repo path(s)"
    echo "  unlabeled            : ${_unlab}"
    echo "  labelled             : ${_lab}   (agent-claimed, excluded: ${_agent})"
    echo "  human-confirmed      : false_block=${_fb}  true_catch=${_tc}  unknown=${_unk}"

    # Adjudications naming records this corpus does not contain. Surfaced, not
    # fatal: REVIEW_SHADOW_LOG can name an alternate corpus, and a sidecar
    # carried across two of them would otherwise attach labels invisibly.
    if [ -f "${ADJ_LOG}" ]; then
        _orphan="$(jq -r '.record_id // empty' "${ADJ_LOG}" 2>/dev/null | sort -u \
                   | while IFS= read -r _id; do
                         [ -z "${_id}" ] && continue
                         jq -e --arg i "${_id}" -R 'fromjson? // empty | select(.record_id == $i)' \
                            "${SHADOW_LOG}" >/dev/null 2>&1 || printf 'x\n'
                     done | grep -c . | tr -d '[:space:]')"
        if [ "${_orphan:-0}" -gt 0 ]; then
            echo
            echo "WARNING: ${_orphan} adjudication(s) name a record_id absent from this corpus."
            echo "  A sidecar reused across two different logs labels records it cannot see."
        fi
    fi

    # k/n: ONLY human-confirmed episodes count. Zero adjudications is NOT zero
    # false blocks -- it is no measurement, and reporting it as 0/0 clean is the
    # direction that would clear a deny-flip on no evidence.
    _den=$(( _fb + _tc + _unk ))
    _band_hdl="$(shadow_band "${_fb}" "${_den}")"
    echo
    echo "rate (human-confirmed only) : k=${_fb} false blocks of n=${_den} episode(s)"
    echo "band                        : ${_band_hdl}"
    echo "pre-registered floor        : n>=${FLOOR_EPISODES} at zero false blocks, >=${FLOOR_REPOS} distinct repos"
    if [ "${_den}" -lt "${FLOOR_EPISODES}" ]; then
        echo "FLOOR NOT MET: the denominator is human-ADJUDICATED episodes, not recorded ones."
        echo "  ${_tot} episode(s) are recorded and ${_unlab} are unlabeled. The deny-flip"
        echo "  criterion is NOT established; the leg stays advisory."
    elif [ "${_nrepos}" -lt "${FLOOR_REPOS}" ]; then
        echo "FLOOR NOT MET: diversity — ${_nrepos} repo(s) < ${FLOOR_REPOS}."
    else
        echo "floor met on n and diversity; band above decides."
    fi
    return 0
}

_usage() {
    cat <<USAGE
usage: $0 <command>

  --status                      episode-level readout and the pre-registered band
  --next                        oldest unadjudicated record, with how to label it
  --adjudicate <record_id> --verdict true_catch|false_block|unknown [--reason <text>]

Diagnostic only. Writes to a sidecar; the shadow log is never mutated.
The pre-registration in openspec/changes/review-verdict/design.md is the
authority for the bands, the floor and the definition of false_block.
USAGE
}

_CMD=""; _RID=""; _VERDICT=""; _REASON=""
while [ $# -gt 0 ]; do
    case "$1" in
        --status)     _CMD=status ;;
        --next)       _CMD=next ;;
        --adjudicate) _CMD=adjudicate; shift; _RID="${1:-}" ;;
        --verdict)    shift; _VERDICT="${1:-}" ;;
        --reason)     shift; _REASON="${1:-}" ;;
        -h|--help)    _usage; exit 0 ;;
        *) echo "error: unknown argument '$1'" >&2; _usage >&2; exit 1 ;;
    esac
    shift
done
case "${_CMD}" in
    status)     cmd_status ;;
    next)       cmd_next ;;
    adjudicate) cmd_adjudicate "${_RID}" "${_VERDICT}" "${_REASON}" ;;
    *)          _usage >&2; exit 1 ;;
esac
