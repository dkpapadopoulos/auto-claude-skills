#!/bin/bash
# verify-shadow-adjudicate.sh — read the VERIFY measured-verdict shadow corpus
# and report it against the pre-registered decision rule. Issue #301.
#
# DIAGNOSTIC ONLY. Never sourced by hooks/openspec-guard.sh, deliberately
# EXCLUDED from _GATE_ENFORCE_LIBS, writes no gate state and no file at all, and
# its output MUST NOT be wired into an enforcement decision. It reports whether
# the rule's clauses hold; flipping the leg to deny is a separate change made
# by the repo owner.
#
# The pre-registration in openspec/changes/verify-measured-verdict/design.md is
# an INPUT here, not something this script may redefine: the floor, the
# classification vocabulary, the episode definition, the diversity clause and
# the backstop all come from that file.
#
# WHY IT SHIPS WITH THE WRITER. #239's REVIEW corpus reached its floor on
# 2026-09-03 and nobody could see it for three weeks because no reader existed.
#
# Unlike the IMPLEMENT and REVIEW readers this one computes NO rate and NO
# band, and takes no human labels: the rule is a count over classifications the
# leg assigns itself, by design ("Why this is NOT a rate floor").
#
# Bash 3.2. Never `set -e`. Never reads stdin.
set -u

# --- pre-registered constants (openspec/changes/verify-measured-verdict/design.md) ---
FLOOR_EPISODES=5
FLOOR_REPOS=2
BACKSTOP_MIN=3
BACKSTOP_DATE=2026-12-31
EPISODE_WINDOW_SEC=1800

SHADOW_LOG="${VERIFY_SHADOW_LOG:-$HOME/.claude/.push-verify-shadow.jsonl}"

_ROOT="$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." 2>/dev/null && pwd)"

# Predicate version DERIVED FROM THE PRODUCER; the literal is only the fallback
# for a checkout where the lib is absent. An independent pin is a silent corpus
# blackout the day the producer bumps (the IMPLEMENT pair did exactly that).
REQUIRED_PREDICATE_VERSION=1
_vs_lib="${_ROOT}/hooks/lib/verify-shadow.sh"
if [ -f "${_vs_lib}" ]; then
    # shellcheck disable=SC1090
    . "${_vs_lib}" 2>/dev/null || true
    case "${VERIFY_SHADOW_PREDICATE_VERSION:-}" in
        ''|*[!0-9]*) : ;;
        *) REQUIRED_PREDICATE_VERSION="${VERIFY_SHADOW_PREDICATE_VERSION}" ;;
    esac
fi

# Episode grouping and the ISO->epoch prelude are single-sourced with the other
# two legs. REFUSE to run without them rather than re-derive either here.
_sc_lib="${_ROOT}/hooks/lib/shadow-corpus.sh"
if [ -f "${_sc_lib}" ]; then
    # shellcheck disable=SC1090
    . "${_sc_lib}" 2>/dev/null || true
fi
if ! command -v shadow_group_episodes >/dev/null 2>&1 || [ -z "${SHADOW_AWK_EPOCH:-}" ]; then
    echo "error: hooks/lib/shadow-corpus.sh did not load (looked at ${_sc_lib})." >&2
    echo "       Refusing to report counts grouped by a local fallback." >&2
    exit 2
fi

_ISO_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'

# Every reader is `-R` + `fromjson?`: jq ABORTS on the first malformed line and
# returns what it parsed before it, so one truncated line would silently cut the
# corpus at that point — and everything after it would vanish from the count.
#
# _records — adjudicable-version records with a KNOWN classification, as TSV:
#   <repo-key> <branch> <session_token> <ts> <record_id> <classification>
# The repo key is repo_id (origin URL), falling back to the recorded path: the
# diversity clause counts repositories, and two worktrees of one are one.
_records() {
    jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" '
        fromjson? // empty | objects | select(.predicate_version == $pv)
        | select(.classification == "explained_ladder"
              or .classification == "unexplained"
              or .classification == "cannot_check")
        | [ (if ((.repo_id // "") | tostring) != "" then (.repo_id | tostring)
             else ((.repo // "") | tostring) end),
            ((.branch // "") | tostring), ((.session_token // "") | tostring),
            ((.ts // "") | tostring), ((.record_id // "") | tostring),
            .classification ] | @tsv' "${SHADOW_LOG}" 2>/dev/null
}

_count() { grep -c . | tr -d '[:space:]'; }

cmd_status() {
    local _now _lines=0 _lines_rc=0 _parsed=0 _unparsed=0 _other=0 _unknown=0 _badts=0 _norid=0
    local _n=0 _unx=0 _exp=0 _cc=0 _repos=0 _first=-1 _nby=0 _tmp _sum
    local _badver=0 _dup=0 _uncounted=0
    local _c1=UNMET _c2=UNMET _c3=UNMET _c4=UNMET _null=false _have=false

    _now="${VERIFY_SHADOW_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)}"
    if ! printf '%s' "${_now}" | grep -q "${_ISO_RE}"; then
        echo "error: could not determine the current time as ISO-8601 UTC (got '${_now}')." >&2
        return 3
    fi

    echo "=== VERIFY measured-verdict shadow corpus (leg: push, #301) ==="
    echo "corpus  : ${SHADOW_LOG}"
    echo "as of   : ${_now}"
    echo "adjudicable predicate_version: ${REQUIRED_PREDICATE_VERSION}"
    echo "review  : repo owner, fortnightly from 2026-10-12"

    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required. No claim is made about the corpus."
        return 3
    fi

    if [ ! -e "${SHADOW_LOG}" ]; then
        echo "(no corpus yet — the leg has recorded nothing on this machine)"
    elif [ ! -f "${SHADOW_LOG}" ] || [ ! -r "${SHADOW_LOG}" ]; then
        # "exists but cannot be read" must never render as "empty": the counts
        # below end in pipelines whose status is discarded.
        echo "ERROR: ${SHADOW_LOG} exists but is NOT READABLE."
        echo "  No claim is made about its contents. This is not an empty corpus."
        return 3
    else
        _lines="$(grep -c . "${SHADOW_LOG}" 2>/dev/null)"; _lines_rc=$?
        _lines="$(printf '%s' "${_lines}" | tr -d '[:space:]')"
        # grep -c exits 1 for "no matching lines" (a legitimately empty file);
        # above 1 is a read error and must not be reported as zero.
        if [ "${_lines_rc}" -gt 1 ]; then
            echo "ERROR: could not read ${SHADOW_LOG} (grep exit ${_lines_rc}). No claim is made about its contents."
            return 3
        fi
        _have=true
    fi

    if [ "${_have}" = "true" ]; then
        _parsed="$(jq -R -r 'fromjson? // empty | objects | 1' "${SHADOW_LOG}" 2>/dev/null | _count)"
        _unparsed=$(( ${_lines:-0} - ${_parsed:-0} ))
        # A NUMERIC other version is a legitimate band written under a
        # different fire condition: reported, not pooled, and not a blocker.
        # A NON-numeric one ("1" as a string, null, absent) is a malformed
        # record of unknown provenance and is treated like any other record
        # this reader could not place.
        _other="$(jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
            'fromjson? // empty | objects | select((.predicate_version | type) == "number" and .predicate_version != $pv) | 1' "${SHADOW_LOG}" 2>/dev/null | _count)"
        _badver="$(jq -R -r \
            'fromjson? // empty | objects | select((.predicate_version | type) != "number") | 1' "${SHADOW_LOG}" 2>/dev/null | _count)"
        _unknown="$(jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" '
            fromjson? // empty | objects | select(.predicate_version == $pv)
            | select((.classification == "explained_ladder" or .classification == "unexplained"
                      or .classification == "cannot_check") | not) | 1' "${SHADOW_LOG}" 2>/dev/null | _count)"

        _tmp="$(mktemp -d "${TMPDIR:-/tmp}/verify-shadow.XXXXXX")" || { echo "ERROR: mktemp failed."; return 3; }
        # shellcheck disable=SC2064
        trap "rm -rf '${_tmp}'" EXIT
        _records > "${_tmp}/rec.tsv"
        _badts="$(awk -F'\t' -v re="${_ISO_RE}" '$4 !~ re { n++ } END { print n+0 }' "${_tmp}/rec.tsv")"
        _norid="$(awk -F'\t' '$5 == "" { n++ } END { print n+0 }' "${_tmp}/rec.tsv")"
        cut -f1-5 "${_tmp}/rec.tsv" | shadow_group_episodes "${EPISODE_WINDOW_SEC}" > "${_tmp}/eps.tsv"

        # Episode class is WORST-WINS and order-free: any unexplained record
        # makes the episode unexplained, else any explained_ladder, else it is
        # cannot_check. An arrival-order rule would let a later explained
        # record launder an unexplained one.
        _sum="$(awk -F'\t' -v dl="${BACKSTOP_DATE}T23:59:59Z" "${SHADOW_AWK_EPOCH}"'
            FILENAME == ARGV[1] {
                # A repeated record_id is WORST-WINS and COUNTED. Last-wins let
                # an explained record sharing an id overwrite an unexplained
                # one with no exclusion line at all.
                if ($5 in cls) {
                    dup++
                    if ($6 == "unexplained" || cls[$5] == "unexplained") cls[$5] = "unexplained"
                    else if ($6 == "explained_ladder" || cls[$5] == "explained_ladder") cls[$5] = "explained_ladder"
                } else { cls[$5] = $6; ts[$5] = $4 }
                next
            }
            {
                n++
                k = split($5, ids, ",")
                c = "cannot_check"
                for (i = 1; i <= k; i++) {
                    if (cls[ids[i]] == "unexplained") c = "unexplained"
                    else if (cls[ids[i]] == "explained_ladder" && c != "unexplained") c = "explained_ladder"
                }
                cnt[c]++
                if (!($2 in seen)) { seen[$2] = 1; nrepos++ }
                e = iso_epoch(ts[$1])
                if (first < 0 || e < first) first = e
                if (e <= iso_epoch(dl)) nby++
            }
            BEGIN { first = -1 }
            END {
                printf "%d %d %d %d %d %d %d %d\n", n + 0, cnt["unexplained"] + 0,
                    cnt["explained_ladder"] + 0, cnt["cannot_check"] + 0,
                    nrepos + 0, first, nby + 0, dup + 0
            }' "${_tmp}/rec.tsv" "${_tmp}/eps.tsv")"
        # All eight fields are numeric and never empty, so a space-split read
        # cannot shift columns.
        read -r _n _unx _exp _cc _repos _first _nby _dup <<EOF
${_sum}
EOF
        case "${_n}${_unx}${_exp}${_cc}${_repos}${_nby}${_dup}" in
            ''|*[!0-9]*) echo "ERROR: the episode summary could not be computed. No claim is made."; return 3 ;;
        esac

        echo "records : ${_lines:-0} line(s), ${_parsed:-0} parsed, ${_unparsed} unparseable"
        if [ "${_other:-0}" -gt 0 ]; then
            echo "EXCLUDED — other-predicate : ${_other} record(s)"
            echo "  Written under a different fire condition; never pooled with version ${REQUIRED_PREDICATE_VERSION}."
        fi
        if [ "${_unknown:-0}" -gt 0 ]; then
            echo "EXCLUDED — unknown classification : ${_unknown} record(s)"
            echo "  Outside the pre-registered vocabulary, so they cannot be counted in any class."
        fi
        if [ "${_badts:-0}" -gt 0 ]; then
            echo "EXCLUDED — unparseable ts : ${_badts} record(s)"
            echo "  They parse as JSON but cannot be placed in an episode."
        fi
        if [ "${_norid:-0}" -gt 0 ]; then
            echo "EXCLUDED — no record_id : ${_norid} record(s)"
        fi
        if [ "${_badver:-0}" -gt 0 ]; then
            echo "EXCLUDED — malformed predicate_version : ${_badver} record(s)"
        fi
        if [ "${_dup:-0}" -gt 0 ]; then
            echo "DUPLICATE record_id : ${_dup} record(s) share an id with another; counted worst-wins"
        fi
        # Every record this reader could not place might be the unexplained one.
        # While any exist, "zero unexplained" is not a measurement.
        _uncounted=$(( ${_unparsed:-0} + ${_unknown:-0} + ${_badts:-0} + ${_norid:-0} + ${_badver:-0} + ${_dup:-0} ))
        if [ "${_uncounted}" -gt 0 ]; then
            echo "UNCOUNTABLE : ${_uncounted} line(s)/record(s) above could not be placed in any class."
            echo "  Any of them may be an unexplained event, so the decision rule is reported"
            echo "  NOT MET until each is accounted for by hand."
        fi
    fi

    echo
    echo "episodes : n=${_n}   (30-minute anchored window over repo, branch, session_token)"
    echo "  unexplained=${_unx}   explained_ladder=${_exp}   cannot_check=${_cc}"
    echo "  repos=${_repos}   (distinct repositories, keyed on origin URL)"
    if [ "${_n}" -gt 0 ] && [ "${_first}" -ge 0 ]; then
        echo "  accrual : $(awk -v n="${_n}" -v f="${_first}" -v now="${_now}" "${SHADOW_AWK_EPOCH}"'
            BEGIN { d = (iso_epoch(now) - f) / 86400
                    if (d > 0) printf "%.3f episodes/day over %.1f day(s) since the first episode", n / d, d
                    else printf "n/a (no elapsed time since the first episode)" }')"
    fi

    [ "${_n}" -ge "${FLOOR_EPISODES}" ] && _c1=MET
    # Clause 2 is vacuous on an empty corpus; "zero unexplained of zero" is no
    # measurement and is not reported as met.
    if [ "${_n}" -gt 0 ] && [ "${_unx}" -eq 0 ]; then _c2=MET; fi
    [ "${_exp}" -ge 1 ] && _c3=MET
    [ "${_repos}" -ge "${FLOOR_REPOS}" ] && _c4=MET

    echo
    echo "decision rule (ALL must hold to flip the leg to deny):"
    echo "  [${_c1}] 1. n >= ${FLOOR_EPISODES} shadow episodes recorded"
    echo "  [${_c2}] 2. zero unexplained episodes among them"
    echo "  [${_c3}] 3. at least one explained_ladder episode (positive control)"
    echo "  [${_c4}] 4. episodes span >= ${FLOOR_REPOS} distinct repos"

    # Backstop: counted over episodes whose FIRST record is on or before the
    # deadline, so episodes arriving later cannot reopen a closed window.
    echo
    if [ "${_nby}" -ge "${BACKSTOP_MIN}" ]; then
        echo "backstop : CLEARED — ${_nby} episode(s) by ${BACKSTOP_DATE} (needed ${BACKSTOP_MIN})"
    elif [ "${_now%%T*}" \> "${BACKSTOP_DATE}" ]; then
        _null=true
        echo "backstop : CLOSED — NULL RESULT. Only ${_nby} episode(s) by ${BACKSTOP_DATE} (needed ${BACKSTOP_MIN})."
    else
        echo "backstop : OPEN — ${_nby} of ${BACKSTOP_MIN} episode(s) needed by ${BACKSTOP_DATE}"
    fi

    echo
    if [ "${_null}" = "true" ]; then
        echo "verdict  : WINDOW CLOSED — NULL RESULT. The leg stays advisory by decision, not"
        echo "           by inertia. No re-dating; a successor window is a separate registration."
    elif [ "${_c1}${_c2}${_c3}${_c4}" = "METMETMETMET" ] && [ "${_uncounted:-0}" -eq 0 ]; then
        echo "verdict  : DECISION RULE MET. Flipping the leg to deny is a separate change made"
        echo "           by the repo owner; this reader authorises nothing by itself."
    else
        echo "verdict  : DECISION RULE NOT MET — the leg stays advisory."
        if [ "${_c1}${_c2}${_c3}${_c4}" = "METMETMETMET" ]; then
            echo "           All four clauses read met, but ${_uncounted} uncountable record(s) block the rule."
        fi
    fi
    return 0
}

_usage() {
    cat <<USAGE
usage: $0 [--status]

  --status   episode counts, classification split, accrual, repo diversity,
             and which clauses of the pre-registered decision rule are unmet

Diagnostic only; reads the corpus and writes nothing.
The pre-registration in openspec/changes/verify-measured-verdict/design.md is
the authority for every number printed here.
USAGE
}

case "${1:---status}" in
    --status)  cmd_status; exit $? ;;
    -h|--help) _usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; _usage >&2; exit 1 ;;
esac
