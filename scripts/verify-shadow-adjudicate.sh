#!/bin/bash
# verify-shadow-adjudicate.sh — label VERIFY measured-verdict shadow episodes and
# report the corpus against the pre-registered decision rule. Issue #301.
#
# DIAGNOSTIC ONLY. Never sourced by hooks/openspec-guard.sh, deliberately
# EXCLUDED from _GATE_ENFORCE_LIBS, writes no gate state, emits no gate decision,
# and its output MUST NOT be wired into an enforcement decision. It reports
# whether the rule's clauses hold; flipping the leg to deny is a separate change
# made by the repo owner.
#
# The registration in openspec/changes/verify-measured-verdict/design.md
# ("Re-registration 2026-10-02") is an INPUT here, not something this script
# may redefine: the floor, the definition of a false block, the episode
# definition, the diversity clause and both deadlines come from that file.
#
# WHY IT SHIPS WITH THE WRITER. #239's REVIEW corpus reached its floor on
# 2026-09-03 and nobody could see it for three weeks because no reader existed.
#
# THE RULE, in one paragraph. Only episodes containing a WOULD-BLOCK record
# count; `cannot_check` is reported and never counted. Every would-block episode
# must be labelled by a HUMAN as a true catch. One confirmed false block means
# the rule cannot be met under this predicate version. The floor is the one the
# REVIEW and IMPLEMENT legs use — a one-sided 95% Clopper-Pearson upper bound
# under 10%, which at zero false blocks is n=29 — and the band is computed by
# the shared hooks/lib/shadow-corpus.sh, never re-derived here.
#
# Labels append to a SIDECAR. The shadow log is NEVER mutated.
#
# Bash 3.2. Never `set -e`. Never reads stdin.
set -u

# --- pre-registered constants (openspec/changes/verify-measured-verdict/design.md) ---
FLOOR_EPISODES=29
FLOOR_REPOS=2
BACKSTOP_MIN=3
BACKSTOP_DATE=2026-12-31
FINAL_DATE=2027-03-31
EPISODE_WINDOW_SEC=1800
ALPHA=0.05
DENY_P=0.10
ADVISORY_P=0.20

SHADOW_LOG="${VERIFY_SHADOW_LOG:-$HOME/.claude/.push-verify-shadow.jsonl}"
ADJ_LOG="${VERIFY_ADJUDICATION_LOG:-$HOME/.claude/.push-verify-adjudication.jsonl}"

_ROOT="$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." 2>/dev/null && pwd)"

# Predicate version DERIVED FROM THE PRODUCER; the literal is only the fallback
# for a checkout where the lib is absent. An independent pin is a silent corpus
# blackout the day the producer bumps (the IMPLEMENT pair did exactly that).
REQUIRED_PREDICATE_VERSION=2
_vs_lib="${_ROOT}/hooks/lib/verify-shadow.sh"
if [ -f "${_vs_lib}" ]; then
    # shellcheck disable=SC1090
    . "${_vs_lib}" 2>/dev/null || true
    case "${VERIFY_SHADOW_PREDICATE_VERSION:-}" in
        ''|*[!0-9]*) : ;;
        *) REQUIRED_PREDICATE_VERSION="${VERIFY_SHADOW_PREDICATE_VERSION}" ;;
    esac
fi

# The band rule, episode grouping and the ISO->epoch prelude are single-sourced
# with the other two legs. REFUSE to run without them rather than re-derive.
_sc_lib="${_ROOT}/hooks/lib/shadow-corpus.sh"
if [ -f "${_sc_lib}" ]; then
    # shellcheck disable=SC1090
    . "${_sc_lib}" 2>/dev/null || true
fi
if ! command -v shadow_group_episodes >/dev/null 2>&1 || ! command -v shadow_band >/dev/null 2>&1 \
   || [ -z "${SHADOW_AWK_EPOCH:-}" ]; then
    echo "error: hooks/lib/shadow-corpus.sh did not load (looked at ${_sc_lib})." >&2
    echo "       Refusing to report counts computed by a local fallback." >&2
    exit 2
fi

_ISO_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'
_T=""    # per-invocation scratch dir, set by _build
_NOW=""

_count() { grep -c . | tr -d '[:space:]'; }

# _claimant -> human | agent. Biased toward "agent": this leg governs AGENT
# pushes, so the subject has a live incentive to grade its own gate. Same marker
# the sibling readers use; deliberately no tty check (it fires on any pipe). The
# mitigation is not that a forged label is impossible — the sidecar is an
# agent-writable file — it is that forging one takes a deliberate lie about
# provenance.
_claimant() {
    if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then echo agent; return; fi
    case "$(ps -o comm= -p "$PPID" 2>/dev/null)" in *claude*) echo agent; return ;; esac
    echo human
}

_set_now() {
    _NOW="${VERIFY_SHADOW_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)}"
    if ! printf '%s' "${_NOW}" | grep -q "${_ISO_RE}"; then
        echo "error: could not determine the current time as ISO-8601 UTC (got '${_NOW}')." >&2
        return 3
    fi
    return 0
}

# _corpus_state -> none | unreadable | ok. "Exists but cannot be read" must
# never render as "empty": the counts below end in pipelines whose status is
# discarded.
_corpus_state() {
    if [ ! -e "${SHADOW_LOG}" ]; then echo none; return; fi
    if [ ! -f "${SHADOW_LOG}" ] || [ ! -r "${SHADOW_LOG}" ]; then echo unreadable; return; fi
    grep -c . "${SHADOW_LOG}" >/dev/null 2>&1
    # grep -c exits 1 for "no matching lines" (a legitimately empty file);
    # above 1 is a read error and must not be reported as zero.
    if [ "$?" -gt 1 ]; then echo unreadable; return; fi
    echo ok
}

# _build — derive, into ${_T}:
#   rec.tsv    <repo-key> <branch> <token> <ts> <record_id> <classification>
#              (adjudicable version, known classification only)
#   eps.tsv    shared grouper output: <eid> <repo> <branch> <token> <ids_csv>
#   lab.tsv    <record_id> <verdict>   LATEST in-window HUMAN label per record
#   state.tsv  <eid> <repo> <branch> <token> <ids_csv> <state> <anchor_ts> <class>
#              state: true_catch | false_block | unresolved | cannot_check
#
# Every jq reader is `-R` + `fromjson?`, so one malformed line is skipped and
# counted rather than aborting the read.
#
# The repo key is repo_id (normalised origin), falling back to the recorded
# path: the diversity clause counts repositories, and two worktrees of one
# repository are one.
_build() {
    _T="$(mktemp -d "${TMPDIR:-/tmp}/verify-shadow.XXXXXX")" || return 1
    # shellcheck disable=SC2064
    trap "rm -rf '${_T}'" EXIT
    : > "${_T}/rec.tsv"; : > "${_T}/eps.tsv"; : > "${_T}/lab.tsv"; : > "${_T}/state.tsv"
    [ "$(_corpus_state)" = "ok" ] || return 0

    jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" '
        fromjson? // empty | objects | select(.predicate_version == $pv)
        | select(.classification == "explained_ladder"
              or .classification == "unexplained"
              or .classification == "cannot_check")
        | [ (if ((.repo_id // "") | tostring) != "" then (.repo_id | tostring)
             else ((.repo // "") | tostring) end),
            ((.branch // "") | tostring), ((.session_token // "") | tostring),
            ((.ts // "") | tostring), ((.record_id // "") | tostring),
            .classification ] | @tsv' "${SHADOW_LOG}" 2>/dev/null > "${_T}/rec.tsv"

    cut -f1-5 "${_T}/rec.tsv" | shadow_group_episodes "${EPISODE_WINDOW_SEC}" > "${_T}/eps.tsv"

    # LATEST HUMAN label per record, and only one made inside the window. The
    # sidecar is append-only, so the last matching row is the most recent and a
    # correction supersedes what it corrects. Agent-claimed rows are not read at
    # all: resolving over every row would let an agent row displace a human
    # false_block.
    if [ -f "${ADJ_LOG}" ] && [ -r "${ADJ_LOG}" ]; then
        jq -R -r 'fromjson? // empty | objects | select(.claimant == "human")
                  | [((.record_id // "") | tostring), ((.verdict // "") | tostring), ((.ts // "") | tostring)] | @tsv' \
            "${ADJ_LOG}" 2>/dev/null \
        | awk -F'\t' -v fin="${FINAL_DATE}T23:59:59Z" "${SHADOW_AWK_EPOCH}"'
            { e = iso_epoch($3); if (e < 0 || e > iso_epoch(fin)) next
              if (!($1 in v)) order[++n] = $1
              v[$1] = $2 }
            END { for (i = 1; i <= n; i++) print order[i] "\t" v[order[i]] }' > "${_T}/lab.tsv"
    fi

    # Episode state. An episode COUNTS iff it holds a would-block record
    # (explained_ladder or unexplained); cannot_check records neither qualify nor
    # clear one. Within a counted episode, over its would-block records only:
    #   any human false_block             -> false_block
    #   else any record without a human
    #        true_catch (none, or unknown) -> unresolved
    #   else                               -> true_catch
    # Order never decides. A repeated record_id is worst-wins on class.
    awk -F'\t' '
        FILENAME == ARGV[1] { lab[$1] = $2; next }
        FILENAME == ARGV[2] {
            if ($5 in cls) {
                if ($6 == "unexplained" || cls[$5] == "unexplained") cls[$5] = "unexplained"
                else if ($6 == "explained_ladder" || cls[$5] == "explained_ladder") cls[$5] = "explained_ladder"
            } else { cls[$5] = $6; ts[$5] = $4 }
            next
        }
        {
            k = split($5, ids, ","); wb = 0; fb = 0; unres = 0; c = "cannot_check"
            for (i = 1; i <= k; i++) {
                x = cls[ids[i]]
                if (x != "unexplained" && x != "explained_ladder") continue
                wb = 1
                if (x == "unexplained") c = "unexplained"; else if (c != "unexplained") c = "explained_ladder"
                l = lab[ids[i]]
                if (l == "false_block") fb = 1
                else if (l != "true_catch") unres = 1
            }
            st = "cannot_check"
            if (wb) st = (fb ? "false_block" : (unres ? "unresolved" : "true_catch"))
            print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" st "\t" ts[$1] "\t" c
        }' "${_T}/lab.tsv" "${_T}/rec.tsv" "${_T}/eps.tsv" > "${_T}/state.tsv"
    return 0
}

# _uncountable — prints the blocking total and, on stdout before it, one line
# per kind. Anything this reader could not place may be the false block, so
# while any exists "zero false blocks" is not a measurement.
_report_uncountable() {
    local _lines _parsed _unparsed _other _badver _unknown _badts _norid _dup _adjbad=0 _agentrows=0 _late=0 _tot
    _lines="$(grep -c . "${SHADOW_LOG}" 2>/dev/null | tr -d '[:space:]')"
    _parsed="$(jq -R -r 'fromjson? // empty | objects | 1' "${SHADOW_LOG}" 2>/dev/null | _count)"
    _unparsed=$(( ${_lines:-0} - ${_parsed:-0} ))
    # A WHOLE-NUMBER other version is a legitimate band written under a
    # different fire condition: reported, not pooled, not a blocker. Anything
    # else in that field ("2" as a string, null, absent, nan, 1.5) is a record
    # of unknown provenance and blocks like any other this reader cannot place.
    _other="$(jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
        'fromjson? // empty | objects | select((.predicate_version | type) == "number" and (.predicate_version == (.predicate_version | floor)) and .predicate_version != $pv) | 1' "${SHADOW_LOG}" 2>/dev/null | _count)"
    _badver="$(jq -R -r \
        'fromjson? // empty | objects | select(((.predicate_version | type) == "number" and (.predicate_version == (.predicate_version | floor))) | not) | 1' "${SHADOW_LOG}" 2>/dev/null | _count)"
    _unknown="$(jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" '
        fromjson? // empty | objects | select(.predicate_version == $pv)
        | select((.classification == "explained_ladder" or .classification == "unexplained"
                  or .classification == "cannot_check") | not) | 1' "${SHADOW_LOG}" 2>/dev/null | _count)"
    # The SAME test the shared grouper applies (iso_epoch < 0 is dropped), not a
    # shape check: a pre-1970 ts is well formed and still leaves the count.
    _badts="$(awk -F'\t' "${SHADOW_AWK_EPOCH}"'iso_epoch($4) < 0 { n++ } END { print n+0 }' "${_T}/rec.tsv")"
    # An id must be a plain token: the episode list is comma-joined by the
    # grouper and re-split here, so an id holding "," resolves to no record.
    _norid="$(awk -F'\t' '$5 !~ /^[A-Za-z0-9_-]+$/ { n++ } END { print n+0 }' "${_T}/rec.tsv")"
    _dup="$(awk -F'\t' '{ if ($5 in s) n++; s[$5] = 1 } END { print n+0 }' "${_T}/rec.tsv")"
    if [ -f "${ADJ_LOG}" ]; then
        if [ ! -r "${ADJ_LOG}" ]; then
            _adjbad=1
            echo "ERROR: the label sidecar ${ADJ_LOG} exists but is NOT READABLE."
        else
            _adjbad=$(( $(grep -c . "${ADJ_LOG}" 2>/dev/null | tr -d '[:space:]') - $(jq -R -r 'fromjson? // empty | objects | 1' "${ADJ_LOG}" 2>/dev/null | _count) ))
            _agentrows="$(jq -R -r 'fromjson? // empty | objects | select(.claimant != "human") | 1' "${ADJ_LOG}" 2>/dev/null | _count)"
            _late="$(jq -R -r 'fromjson? // empty | objects | select(.claimant == "human") | (.ts // "") | tostring' "${ADJ_LOG}" 2>/dev/null \
                     | awk -v fin="${FINAL_DATE}T23:59:59Z" "${SHADOW_AWK_EPOCH}"'{ e = iso_epoch($0); if (e < 0 || e > iso_epoch(fin)) n++ } END { print n+0 }')"
        fi
    fi

    echo "records : ${_lines:-0} line(s), ${_parsed:-0} parsed, ${_unparsed} unparseable"
    [ "${_other:-0}" -gt 0 ] && {
        echo "EXCLUDED — other-predicate : ${_other} record(s)"
        echo "  Written under a different fire condition; never pooled with version ${REQUIRED_PREDICATE_VERSION}."
    }
    [ "${_unknown:-0}" -gt 0 ] && echo "EXCLUDED — unknown classification : ${_unknown} record(s)"
    [ "${_badts:-0}" -gt 0 ]   && echo "EXCLUDED — unparseable ts : ${_badts} record(s)"
    [ "${_norid:-0}" -gt 0 ]   && echo "EXCLUDED — no usable record_id : ${_norid} record(s)"
    [ "${_badver:-0}" -gt 0 ]  && echo "EXCLUDED — malformed predicate_version : ${_badver} record(s)"
    [ "${_dup:-0}" -gt 0 ]     && echo "DUPLICATE record_id : ${_dup} record(s) share an id with another; counted worst-wins"
    [ "${_adjbad:-0}" -gt 0 ]  && echo "SIDECAR — unparseable label line(s) : ${_adjbad}"
    [ "${_agentrows:-0}" -gt 0 ] && echo "labels  : ${_agentrows} agent-claimed row(s) ignored — only a human label resolves an episode"
    [ "${_late:-0}" -gt 0 ]    && echo "labels  : ${_late} human row(s) ignored — no usable ts, or made after ${FINAL_DATE}"
    _tot=$(( ${_unparsed:-0} + ${_unknown:-0} + ${_badts:-0} + ${_norid:-0} + ${_badver:-0} + ${_dup:-0} + ${_adjbad:-0} ))
    if [ "${_tot}" -gt 0 ]; then
        echo "UNCOUNTABLE : ${_tot} line(s)/record(s) above could not be placed."
        echo "  Any of them may be a false block or hide one, so the decision rule is"
        echo "  reported NOT MET until each is accounted for by hand."
    fi
    _UNCOUNTED="${_tot}"
    return 0
}

cmd_status() {
    local _cs _sum _n=0 _fb=0 _unres=0 _tc=0 _cc=0 _repos=0 _first=-1 _nby=0 _late=0 _unx=0 _exp=0
    local _c1=UNMET _c2=UNMET _c3=UNMET _c4=UNMET _null="" _band=""
    _UNCOUNTED=0
    _set_now || return 3

    echo "=== VERIFY measured-verdict shadow corpus (leg: push, #301) ==="
    echo "corpus  : ${SHADOW_LOG}"
    echo "sidecar : ${ADJ_LOG}"
    echo "as of   : ${_NOW}"
    echo "adjudicable predicate_version: ${REQUIRED_PREDICATE_VERSION}"
    echo "review  : repo owner, fortnightly from 2026-10-12"

    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required. No claim is made about the corpus."
        return 3
    fi
    _cs="$(_corpus_state)"
    if [ "${_cs}" = "unreadable" ]; then
        echo "ERROR: ${SHADOW_LOG} exists but is NOT READABLE."
        echo "  No claim is made about its contents. This is not an empty corpus."
        return 3
    fi
    _build || { echo "ERROR: could not create a scratch directory. No claim is made."; return 3; }
    if [ "${_cs}" = "none" ]; then
        echo "(no corpus yet — the leg has recorded nothing on this machine)"
    else
        _report_uncountable
    fi

    # n, diversity and both deadlines are counted over WOULD-BLOCK episodes whose
    # first record falls inside the window. An episode that begins after the
    # final deadline is reported and never counted, so late arrivals cannot
    # reopen a closed window.
    _sum="$(awk -F'\t' -v dl="${BACKSTOP_DATE}T23:59:59Z" -v fin="${FINAL_DATE}T23:59:59Z" "${SHADOW_AWK_EPOCH}"'
        BEGIN { first = -1 }
        {
            e = iso_epoch($7)
            if ($6 == "cannot_check") { cc++; next }
            if (e > iso_epoch(fin)) { late++; next }
            n++; st[$6]++; cl[$8]++
            if ($6 == "true_catch" && !($2 in seen)) { seen[$2] = 1; nrepos++ }
            if (first < 0 || e < first) first = e
            if (e <= iso_epoch(dl)) nby++
        }
        END { printf "%d %d %d %d %d %d %d %d %d %d %d\n", n + 0, st["false_block"] + 0, st["unresolved"] + 0,
                  st["true_catch"] + 0, cc + 0, nrepos + 0, first, nby + 0, late + 0,
                  cl["unexplained"] + 0, cl["explained_ladder"] + 0 }' "${_T}/state.tsv")"
    # Eleven numeric, never-empty fields: a space-split read cannot shift columns.
    read -r _n _fb _unres _tc _cc _repos _first _nby _late _unx _exp <<EOF
${_sum}
EOF
    case "${_n}${_fb}${_unres}${_tc}${_cc}${_repos}${_nby}${_late}${_unx}${_exp}" in
        ''|*[!0-9]*) echo "ERROR: the episode summary could not be computed. No claim is made."; return 3 ;;
    esac

    echo
    echo "would-block episodes : n=${_n}   (30-minute anchored window over repo, branch, session_token)"
    echo "  by class  : unexplained=${_unx}   explained_ladder=${_exp}"
    echo "  by label  : true_catch=${_tc}   false_block=${_fb}   unresolved=${_unres}"
    echo "  repos=${_repos}   (distinct repositories among human-confirmed true catches)"
    echo "not counted : cannot_check=${_cc} episode(s) — the leg could not look; never evidence either way"
    [ "${_late}" -gt 0 ] && echo "not counted : ${_late} episode(s) began after ${FINAL_DATE}"
    if [ "${_n}" -gt 0 ] && [ "${_first}" -ge 0 ]; then
        echo "  accrual : $(awk -v n="${_n}" -v f="${_first}" -v now="${_NOW}" "${SHADOW_AWK_EPOCH}"'
            BEGIN { d = (iso_epoch(now) - f) / 86400
                    if (d > 0) printf "%.3f episodes/day over %.1f day(s) since the first episode", n / d, d
                    else printf "n/a (no elapsed time since the first episode)" }')"
    fi
    # Informational, and from the SHARED rule: at zero false blocks DENY first
    # holds at n=29, which is where FLOOR_EPISODES comes from.
    _band="$(ALPHA="${ALPHA}" DENY_P="${DENY_P}" ADVISORY_P="${ADVISORY_P}" shadow_band "${_fb}" "$(( _tc + _fb ))" 2>/dev/null)"
    echo "  band (human-labelled only, k=${_fb} of $(( _tc + _fb ))) : ${_band:-INSUFFICIENT}"

    [ "${_n}" -ge "${FLOOR_EPISODES}" ] && _c1=MET
    # Clauses 2 and 3 are vacuous on an empty corpus; "zero of zero" is no
    # measurement and is not reported as met.
    if [ "${_n}" -gt 0 ] && [ "${_fb}" -eq 0 ]; then _c2=MET; fi
    if [ "${_n}" -gt 0 ] && [ "${_unres}" -eq 0 ]; then _c3=MET; fi
    [ "${_repos}" -ge "${FLOOR_REPOS}" ] && _c4=MET

    echo
    echo "decision rule (ALL must hold to flip the leg to deny):"
    echo "  [${_c1}] 1. n >= ${FLOOR_EPISODES} would-block episodes"
    echo "  [${_c2}] 2. zero false-block episodes"
    echo "  [${_c3}] 3. zero unresolved episodes (every one human-labelled a true catch)"
    echo "  [${_c4}] 4. true catches span >= ${FLOOR_REPOS} distinct repos"

    echo
    if [ "${_nby}" -ge "${BACKSTOP_MIN}" ]; then
        echo "starvation check : CLEARED — ${_nby} episode(s) by ${BACKSTOP_DATE} (needed ${BACKSTOP_MIN})"
    elif [ "${_NOW%%T*}" \> "${BACKSTOP_DATE}" ]; then
        _null="Only ${_nby} would-block episode(s) by ${BACKSTOP_DATE} (needed ${BACKSTOP_MIN})."
        echo "starvation check : CLOSED — ${_null}"
    else
        echo "starvation check : OPEN — ${_nby} of ${BACKSTOP_MIN} episode(s) needed by ${BACKSTOP_DATE}"
    fi
    if [ "${_NOW%%T*}" \> "${FINAL_DATE}" ]; then
        echo "final deadline   : PASSED — ${FINAL_DATE}"
    else
        echo "final deadline   : ${FINAL_DATE} — any unmet clause then closes the window as a null result"
    fi

    echo
    if [ "${_c1}${_c2}${_c3}${_c4}" = "METMETMETMET" ] && [ "${_UNCOUNTED:-0}" -eq 0 ] && [ -z "${_null}" ]; then
        echo "verdict  : DECISION RULE MET. Flipping the leg to deny is a separate change made"
        echo "           by the repo owner; this reader authorises nothing by itself. That"
        echo "           change must first pass an installation smoke test of the leg."
    elif [ -n "${_null}" ]; then
        echo "verdict  : WINDOW CLOSED — NULL RESULT. ${_null}"
        echo "           The leg stays advisory by decision, not by inertia. No re-dating."
    elif [ "${_NOW%%T*}" \> "${FINAL_DATE}" ]; then
        echo "verdict  : WINDOW CLOSED — NULL RESULT. The rule was not met by ${FINAL_DATE}."
        echo "           The leg stays advisory by decision, not by inertia. No re-dating."
    elif [ "${_fb}" -gt 0 ]; then
        echo "verdict  : DECISION RULE NOT MET — FALSE BLOCK CONFIRMED (${_fb} episode(s))."
        echo "           The rule requires zero across the whole corpus, so it cannot be met"
        echo "           under predicate_version ${REQUIRED_PREDICATE_VERSION}. Fix the leg and bump the version."
    else
        echo "verdict  : DECISION RULE NOT MET — the leg stays advisory."
        if [ "${_c1}${_c2}${_c3}${_c4}" = "METMETMETMET" ]; then
            echo "           All four clauses read met, but ${_UNCOUNTED} uncountable record(s) block the rule."
        fi
    fi
    return 0
}

_definition() {
    cat <<DEF
TRUE CATCH  : the advisory's remedy — re-run the gate through
              Skill(auto-claude-skills:project-verification), which records
              measured exit codes — was reachable in that repo at that time and
              was the right thing to ask for. "The gate failed and has to be
              fixed first" is still a true catch.
FALSE BLOCK : the agent could not have proceeded by that remedy (the script
              refuses this repo, or there is no gate to run), or the advisory
              named the wrong remedy. The human bypass existing does NOT make a
              block a true catch.
unknown     : you cannot tell from the evidence. It keeps the episode unresolved.
DEF
}

# cmd_next — the oldest unresolved would-block episode, with its evidence.
cmd_next() {
    local _row _eid _ids _id
    _set_now || return 3
    command -v jq >/dev/null 2>&1 || { echo "jq required — cannot read the corpus."; return 3; }
    case "$(_corpus_state)" in
        none)       echo "no shadow log at ${SHADOW_LOG} — nothing outstanding."; return 0 ;;
        unreadable) echo "ERROR: ${SHADOW_LOG} exists but is NOT READABLE."; return 3 ;;
    esac
    _build || return 3
    _row="$(awk -F'\t' '$6 == "unresolved"' "${_T}/state.tsv" | LC_ALL=C sort -t "$(printf '\t')" -k7,7 | head -1)"
    if [ -z "${_row}" ]; then
        # "nothing to label" and "everything is labelled" are different states.
        if [ "$(awk -F'\t' '$6 != "cannot_check"' "${_T}/state.tsv" | _count)" -eq 0 ]; then
            echo "no would-block episodes of predicate_version ${REQUIRED_PREDICATE_VERSION} — nothing to label."
        else
            echo "every would-block episode carries a human label."
        fi
        return 0
    fi
    _eid="$(printf '%s' "${_row}" | cut -f1)"
    _ids="$(printf '%s' "${_row}" | cut -f5)"
    echo "episode    : ${_eid}"
    echo "repository : $(printf '%s' "${_row}" | cut -f2)"
    echo "branch     : $(printf '%s' "${_row}" | cut -f3)"
    echo "first seen : $(printf '%s' "${_row}" | cut -f7)"
    echo "records    :"
    for _id in $(printf '%s' "${_ids}" | tr ',' ' '); do
        jq -R -r --arg id "${_id}" '
            fromjson? // empty | objects | select(.record_id == $id)
            | "  \(.record_id)  \(.ts)  \(.classification)/\(.reason)  source=\(.discovery_source // "")  gate=\(.gate_declaration // "not recorded")  material=\(.material_source)  head=\((.head_sha // "")[0:12])\n    transcript: \(.transcript_path // "")"' \
            "${SHADOW_LOG}" 2>/dev/null | head -2
    done
    echo
    _definition
    echo
    echo "  $0 --adjudicate ${_eid} --verdict true_catch|false_block|unknown [--reason '...']"
    echo "  (one label covers every would-block record in the episode)"
    return 0
}

# cmd_adjudicate <record_id> <verdict> <reason> — label the EPISODE containing
# that record: one sidecar row per would-block record in it. A record joining
# the episode afterwards is unlabelled, so the episode reads unresolved again —
# a label never covers evidence the labeller did not see.
cmd_adjudicate() {
    local _rid="${1:-}" _verdict="${2:-}" _reason="${3:-}" _row _eid _ids _id _claim _tty _wrote=0
    case "${_verdict}" in
        true_catch|false_block|unknown) ;;
        *) echo "error: --verdict must be true_catch, false_block, or unknown" >&2; return 1 ;;
    esac
    case "${_rid}" in
        ''|*[!A-Za-z0-9_-]*) echo "error: --adjudicate needs a record id" >&2; return 1 ;;
    esac
    _set_now || return 3
    command -v jq >/dev/null 2>&1 || { echo "error: jq required" >&2; return 1; }
    [ "$(_corpus_state)" = "ok" ] || { echo "error: no readable shadow log at ${SHADOW_LOG}" >&2; return 1; }
    _build || return 3
    _row="$(awk -F'\t' -v id="${_rid}" '{ k = split($5, a, ","); for (i = 1; i <= k; i++) if (a[i] == id) { print; exit } }' "${_T}/state.tsv")"
    if [ -z "${_row}" ]; then
        echo "error: no adjudicable record '${_rid}' in ${SHADOW_LOG}." >&2
        echo "       Only predicate_version ${REQUIRED_PREDICATE_VERSION} records can be labelled; others were" >&2
        echo "       written under a different fire condition and are never pooled." >&2
        return 1
    fi
    if [ "$(printf '%s' "${_row}" | cut -f6)" = "cannot_check" ]; then
        echo "error: that episode holds only cannot_check records. It is never counted, so" >&2
        echo "       there is nothing to label." >&2
        return 1
    fi
    _eid="$(printf '%s' "${_row}" | cut -f1)"
    _ids="$(printf '%s' "${_row}" | cut -f5)"
    if [ ! -f "${ADJ_LOG}" ]; then
        ( umask 077; : > "${ADJ_LOG}" ) 2>/dev/null || { echo "error: cannot write ${ADJ_LOG}" >&2; return 1; }
    fi
    chmod 600 "${ADJ_LOG}" 2>/dev/null
    _claim="$(_claimant)"
    # `tty` prints "not a tty" to STDOUT and ALSO exits 1; branch on the status.
    if _tty="$(tty 2>/dev/null)"; then :; else _tty="not-a-tty"; fi
    for _id in $(printf '%s' "${_ids}" | tr ',' ' '); do
        # Would-block records only: a cannot_check record in the same episode
        # is not evidence and gets no label.
        awk -F'\t' -v id="${_id}" '$5 == id && ($6 == "unexplained" || $6 == "explained_ladder") { f = 1 } END { exit !f }' \
            "${_T}/rec.tsv" || continue
        jq -cn --arg rid "${_id}" --arg eid "${_eid}" --arg ts "${_NOW}" --arg v "${_verdict}" \
               --arg r "${_reason}" --arg c "${_claim}" --arg u "${USER:-unknown}" --arg tty "${_tty}" \
               --arg corpus "${SHADOW_LOG}" --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
               --arg par "$(ps -o comm= -p "$PPID" 2>/dev/null || echo unknown)" \
               --arg agentenv "$([ -n "${CLAUDECODE:-}" ] && echo present || echo absent)" \
           '{schema_version:1, leg:"verify", predicate_version:$pv, record_id:$rid, episode_id:$eid,
             ts:$ts, verdict:$v, reason:$r, claimant:$c, corpus:$corpus,
             provenance:{user:$u, tty:$tty, parent:$par, agent_env:$agentenv}}' \
           >> "${ADJ_LOG}" 2>/dev/null || { echo "error: append to ${ADJ_LOG} failed" >&2; return 1; }
        _wrote=$(( _wrote + 1 ))
    done
    echo "recorded: episode ${_eid}  ${_verdict}  (${_wrote} record(s), ${_claim}-claimed)"
    if [ "${_claim}" = "agent" ]; then
        echo "note: AGENT-CLAIMED — ignored by --status until a human re-labels the episode."
    fi
    return 0
}

_usage() {
    cat <<USAGE
usage: $0 [--status]
       $0 --next
       $0 --adjudicate <record_id> --verdict true_catch|false_block|unknown [--reason <text>]

  --status      would-block episodes, labels, accrual, repo diversity, both
                deadlines, and which clauses of the decision rule are unmet
  --next        the oldest unresolved would-block episode and how to label it
  --adjudicate  label the episode containing <record_id>

Diagnostic only. Labels go to a sidecar; the shadow log is never mutated.
The registration in openspec/changes/verify-measured-verdict/design.md is the
authority for every number printed here.
USAGE
}

_CMD="status"; _RID=""; _VERDICT=""; _REASON=""
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
    [ $# -gt 0 ] && shift
done
case "${_CMD}" in
    status)     cmd_status; exit $? ;;
    next)       cmd_next; exit $? ;;
    adjudicate) cmd_adjudicate "${_RID}" "${_VERDICT}" "${_REASON}"; exit $? ;;
esac
