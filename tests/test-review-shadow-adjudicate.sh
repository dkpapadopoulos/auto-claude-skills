#!/usr/bin/env bash
# test-review-shadow-adjudicate.sh — the REVIEW leg's corpus reader (#239).
#
# The instrument the pre-registration in openspec/changes/review-verdict/design.md
# always needed and never had: the corpus reached its n=29 floor on 2026-09-03
# and nothing could read it, so the leg stayed advisory by inertia rather than
# by decision.
#
# Every cell here exists because the failure it pins is one this repo has
# already shipped once on the IMPLEMENT leg: a reader pinning its own version
# literal (silent corpus blackout), a tab-split dropping empty fields (episodes
# vanish from the denominator), a counter loop in a subshell (summary reports a
# pass that did not happen), and Wilson substituted for exact Clopper-Pearson.
#
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUT="${PROJECT_ROOT}/scripts/review-shadow-adjudicate.sh"
WRITER="${PROJECT_ROOT}/hooks/lib/review-shadow.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-review-shadow-adjudicate.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required for this test" >&2; exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rsa-XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT INT TERM

# Adjudicable version, read from the PRODUCER exactly as the reader does. The
# test must not hardcode it, or a producer bump makes every fixture unadjudicable
# and the whole suite silently degrades to testing the exclusion path.
PV="$( ( . "${WRITER}" 2>/dev/null; printf '%s' "${REVIEW_SHADOW_PREDICATE_VERSION:-}" ) )"
if [ -z "${PV}" ]; then
    echo "error: could not read REVIEW_SHADOW_PREDICATE_VERSION from the writer" >&2; exit 2
fi

# _rec <log> <id> <ts> <repo> <branch> <token> <reason> [pv]
_rec() {
    jq -cn --arg id "$2" --arg ts "$3" --arg repo "$4" --arg br "$5" \
           --arg tok "$6" --arg rs "$7" --argjson pv "${8:-${PV}}" \
      '{schema_version:2,predicate_version:$pv,record_id:$id,ts:$ts,
        repo:$repo,branch:$br,head_sha:"deadbeef",session_token:$tok,
        action:"push",would_block:true,reason:$rs,transcript_path:""}' >> "$1"
}
_run() { REVIEW_SHADOW_LOG="$1" REVIEW_ADJUDICATION_LOG="$2" /bin/bash "${SUT}" "${@:3}" 2>&1; }

# ---------------------------------------------------------------------------
# 1. Diagnostic-only posture. This script must never be able to influence a
#    gate: no permissionDecision, no gate state, never sourced by the guard,
#    never in _GATE_ENFORCE_LIBS.
# ---------------------------------------------------------------------------
_L="${TMP}/a.jsonl"; _A="${TMP}/a-adj.jsonl"; : > "${_L}"
_rec "${_L}" r1 "2026-09-10T10:00:00Z" /repo/x main tok-1 absent
_out="$(_run "${_L}" "${_A}" --status)"
case "${_out}" in
    *permissionDecision*) _record_fail "status emits no permissionDecision" "found one in output" ;;
    *) _record_pass "status emits no permissionDecision" ;;
esac
if grep -q 'review-shadow-adjudicate' "${GUARD}" 2>/dev/null; then
    _record_fail "guard does not reference the adjudicator" "openspec-guard.sh mentions it"
else
    _record_pass "guard does not reference the adjudicator"
fi
if grep -n '_GATE_ENFORCE_LIBS' "${PROJECT_ROOT}"/hooks/*.sh 2>/dev/null | grep -q 'shadow-corpus\|review-shadow-adjudicate'; then
    _record_fail "adjudicator/shared lib are NOT gate-enforcement libs" "found in _GATE_ENFORCE_LIBS"
else
    _record_pass "adjudicator/shared lib are NOT gate-enforcement libs"
fi

# ---------------------------------------------------------------------------
# 2. The reader DERIVES its required version from the producer. An independent
#    pin is a silent corpus blackout: the IMPLEMENT pair reported "episodes 0"
#    with live records counted unpoolable, which reads exactly like an empty
#    corpus, on the one instrument that must never fake that state.
# ---------------------------------------------------------------------------
_derived="$(_run "${_L}" "${_A}" --status | sed -n 's/^adjudicable predicate_version: //p')"
assert_equals "reader's required version == producer's constant" "${PV}" "${_derived}"

# That cell ALONE is vacuous and a mutation said so: the reader's no-lib
# fallback literal currently equals the producer's constant, so deleting the
# derivation entirely leaves it green. Proving derivation requires MOVING the
# producer, not merely reading it. Copy the tree, bump the writer's constant to
# a value the fallback cannot produce, and see whether the reader follows.
_FAKE="${TMP}/fakeroot"
mkdir -p "${_FAKE}/scripts" "${_FAKE}/hooks/lib"
cp "${SUT}" "${_FAKE}/scripts/" 2>/dev/null
cp "${PROJECT_ROOT}/hooks/lib/shadow-corpus.sh" "${_FAKE}/hooks/lib/" 2>/dev/null
_BUMPED=$(( PV + 7 ))
sed "s/^REVIEW_SHADOW_PREDICATE_VERSION=.*/REVIEW_SHADOW_PREDICATE_VERSION=${_BUMPED}/" \
    "${WRITER}" > "${_FAKE}/hooks/lib/review-shadow.sh" 2>/dev/null
if grep -q "^REVIEW_SHADOW_PREDICATE_VERSION=${_BUMPED}$" "${_FAKE}/hooks/lib/review-shadow.sh" 2>/dev/null; then
    _record_pass "producer-bump fixture built (writer says ${_BUMPED})"
else
    _record_fail "producer-bump fixture built" "sed did not bump the constant -- the next cell is vacuous"
fi
_followed="$(REVIEW_SHADOW_LOG="${_L}" REVIEW_ADJUDICATION_LOG="${_A}" \
    /bin/bash "${_FAKE}/scripts/review-shadow-adjudicate.sh" --status 2>&1 \
    | sed -n 's/^adjudicable predicate_version: //p')"
assert_equals "reader FOLLOWS a producer bump (derivation is live, not a coincidence)" \
    "${_BUMPED}" "${_followed}"

# And with the writer absent it must fall back to its own literal rather than
# to an empty string -- an empty required version silently matches nothing and
# reports an empty corpus.
rm -f "${_FAKE}/hooks/lib/review-shadow.sh"
_fallback="$(REVIEW_SHADOW_LOG="${_L}" REVIEW_ADJUDICATION_LOG="${_A}" \
    /bin/bash "${_FAKE}/scripts/review-shadow-adjudicate.sh" --status 2>&1 \
    | sed -n 's/^adjudicable predicate_version: //p')"
case "${_fallback}" in
    ''|*[!0-9]*) _record_fail "writer absent: reader falls back to a NUMERIC literal" "got '${_fallback}'" ;;
    *) _record_pass "writer absent: reader falls back to a numeric literal (${_fallback})" ;;
esac

# ---------------------------------------------------------------------------
# 3. Other-predicate records are REPORTED, never silently dropped. This is the
#    cell that matters most: the live corpus is entirely other-predicate, and a
#    reader that prints "0 episodes" without saying why is indistinguishable
#    from one reporting an empty corpus.
# ---------------------------------------------------------------------------
_L2="${TMP}/b.jsonl"; _A2="${TMP}/b-adj.jsonl"; : > "${_L2}"
_rec "${_L2}" o1 "2026-08-28T10:00:00Z" /repo/x main tok-1 absent 1
_rec "${_L2}" o2 "2026-08-28T11:00:00Z" /repo/x main tok-1 absent 1
_out2="$(_run "${_L2}" "${_A2}" --status)"
case "${_out2}" in
    *"EXCLUDED — other-predicate : 2 record(s)"*)
        _record_pass "other-predicate records are reported with a count" ;;
    *) _record_fail "other-predicate records are reported with a count" "got: ${_out2}" ;;
esac
case "${_out2}" in
    *"records : 2 line(s)"*) _record_pass "the excluded records are still counted as present" ;;
    *) _record_fail "the excluded records are still counted as present" "got: ${_out2}" ;;
esac
# CONTROL: a corpus with NO other-predicate records must NOT print the banner.
# Without this the cell above is satisfied by a banner that always prints, and
# "199 records excluded" would read the same on a corpus with none.
case "${_out}" in
    *"EXCLUDED — other-predicate"*)
        _record_fail "CONTROL: no exclusion banner when every record is current" "banner printed anyway" ;;
    *) _record_pass "CONTROL: no exclusion banner when every record is current" ;;
esac

# --next must distinguish "nothing countable" from "work done".
_outn="$(_run "${_L2}" "${_A2}" --next)"
case "${_outn}" in
    *"nothing is countable"*) _record_pass "--next says nothing is countable, not 'all labelled'" ;;
    *) _record_fail "--next says nothing is countable, not 'all labelled'" "got: ${_outn}" ;;
esac
# ...and refuses to adjudicate one.
_outa="$(_run "${_L2}" "${_A2}" --adjudicate o1 --verdict true_catch)"
case "${_outa}" in
    *"only v${PV} is adjudicable"*) _record_pass "adjudicating an other-predicate record is refused" ;;
    *) _record_fail "adjudicating an other-predicate record is refused" "got: ${_outa}" ;;
esac

# ---------------------------------------------------------------------------
# 3b. A MIXED corpus -- the state this change creates on every existing machine
#     the moment it ships, since 199 live records are of the older predicate and
#     every new one is current. The two counts come from independent jq passes
#     over the same file, so this is the cell that proves they partition rather
#     than overlap or leak.
# ---------------------------------------------------------------------------
_LM="${TMP}/mixed.jsonl"; _AM="${TMP}/mixed-adj.jsonl"; : > "${_LM}"
_rec "${_LM}" m1 "2026-08-28T10:00:00Z" /repo/x main tok-1 absent 1
_rec "${_LM}" m2 "2026-08-28T11:00:00Z" /repo/x main tok-1 absent 1
_rec "${_LM}" m3 "2026-09-20T10:00:00Z" /repo/x main tok-9 absent
_rec "${_LM}" m4 "2026-09-20T12:00:00Z" /repo/y main tok-9 not-clean
_outm="$(_run "${_LM}" "${_AM}" --status)"
case "${_outm}" in
    *"EXCLUDED — other-predicate : 2 record(s)"*)
        _record_pass "mixed corpus: exactly the 2 older records are excluded" ;;
    *) _record_fail "mixed corpus: exactly the 2 older records are excluded" "got: ${_outm}" ;;
esac
_epsm="$(printf '%s' "${_outm}" | sed -n 's/^episodes (adjudicable) : \([0-9]*\).*/\1/p')"
assert_equals "mixed corpus: only the current records form episodes" "2" "${_epsm}"
case "${_outm}" in
    *"records : 4 line(s), 4 parsed"*)
        _record_pass "mixed corpus: all 4 records are still reported as present" ;;
    *) _record_fail "mixed corpus: all 4 records are still reported as present" "got: ${_outm}" ;;
esac
# ...and --next offers a CURRENT record, never one of the excluded ones.
_outmn="$(_run "${_LM}" "${_AM}" --next)"
case "${_outmn}" in
    *"record_id : m3"*) _record_pass "mixed corpus: --next offers the oldest CURRENT record" ;;
    *) _record_fail "mixed corpus: --next offers the oldest CURRENT record" "got: ${_outmn}" ;;
esac

# ---------------------------------------------------------------------------
# 4. Episode grouping: the anchored 30-minute window, and an EMPTY branch must
#    survive. Tab is IFS whitespace, so a bash `read` collapses the empty field
#    and shifts every later column -- the episode then vanishes from the
#    denominator with no exclusion row.
# ---------------------------------------------------------------------------
_L3="${TMP}/c.jsonl"; _A3="${TMP}/c-adj.jsonl"; : > "${_L3}"
# One episode: three records inside 30 min of the FIRST.
_rec "${_L3}" e1 "2026-09-10T10:00:00Z" /repo/x main tok-1 absent
_rec "${_L3}" e2 "2026-09-10T10:20:00Z" /repo/x main tok-1 absent
_rec "${_L3}" e3 "2026-09-10T10:29:00Z" /repo/x main tok-1 absent
# A second episode: past the window FROM THE ANCHOR (a rolling gap would chain).
_rec "${_L3}" e4 "2026-09-10T10:45:00Z" /repo/x main tok-1 absent
# A third, with an EMPTY branch.
_rec "${_L3}" e5 "2026-09-10T12:00:00Z" /repo/y "" tok-2 absent
_eps="$(_run "${_L3}" "${_A3}" --status | sed -n 's/^episodes (adjudicable) : \([0-9]*\).*/\1/p')"
assert_equals "anchored window groups 3+1 and keeps the empty-branch record" "3" "${_eps}"

# The count alone does NOT detect the IFS trap, and a mutation said so:
# re-splitting the tab-delimited episode rows with a bash `read` still yields
# three iterations, because the collapse shifts the COLUMNS rather than losing
# the row. What is lost is `_ids` -- so the episode can never be matched to an
# adjudication and silently leaves the DENOMINATOR while still being reported.
# Assert the consequence: an empty-branch episode must be adjudicable and must
# enter the rate.
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_L3}" REVIEW_ADJUDICATION_LOG="${_A3}" \
    /bin/bash "${SUT}" --adjudicate e5 --verdict true_catch ) >/dev/null 2>&1
_n_empty="$(_run "${_L3}" "${_A3}" --status | sed -n 's/^rate (human-confirmed only) : k=[0-9]* false blocks of n=\([0-9]*\).*/\1/p')"
assert_equals "an EMPTY-branch episode still reaches the denominator" "1" "${_n_empty}"

# ---------------------------------------------------------------------------
# 5. Only HUMAN-confirmed episodes enter the rate. This leg governs agent
#    pushes, so a self-graded clean rate is the one thing that must not count.
#    The test runs the adjudicator with the agent markers set and then unset.
# ---------------------------------------------------------------------------
_L4="${TMP}/d.jsonl"; _A4="${TMP}/d-adj.jsonl"; : > "${_L4}"; : > "${_A4}"
_rec "${_L4}" f1 "2026-09-10T10:00:00Z" /repo/x main tok-1 absent
CLAUDECODE=1 REVIEW_SHADOW_LOG="${_L4}" REVIEW_ADJUDICATION_LOG="${_A4}" \
    /bin/bash "${SUT}" --adjudicate f1 --verdict true_catch >/dev/null 2>&1
_n_agent="$(_run "${_L4}" "${_A4}" --status | sed -n 's/^rate (human-confirmed only) : k=[0-9]* false blocks of n=\([0-9]*\).*/\1/p')"
assert_equals "an agent-claimed adjudication does NOT enter the denominator" "0" "${_n_agent}"
_ag="$(_run "${_L4}" "${_A4}" --status | sed -n 's/.*agent-claimed, excluded: \([0-9]*\).*/\1/p')"
assert_equals "...and is reported as excluded rather than dropped" "1" "${_ag}"

( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_L4}" REVIEW_ADJUDICATION_LOG="${_A4}" \
    /bin/bash "${SUT}" --adjudicate f1 --verdict true_catch ) >/dev/null 2>&1
_n_human="$(_run "${_L4}" "${_A4}" --status | sed -n 's/^rate (human-confirmed only) : k=[0-9]* false blocks of n=\([0-9]*\).*/\1/p')"
assert_equals "a human-claimed adjudication DOES enter the denominator" "1" "${_n_human}"

# ---------------------------------------------------------------------------
# 6. The LATEST adjudication per record wins. Folding over all rows makes a
#    correction a silent no-op -- the earlier verdict keeps winning while the
#    tool prints success, permanently poisoning a rate that gates a deny-flip.
# ---------------------------------------------------------------------------
_L5="${TMP}/e.jsonl"; _A5="${TMP}/e-adj.jsonl"; : > "${_L5}"; : > "${_A5}"
_rec "${_L5}" g1 "2026-09-10T10:00:00Z" /repo/x main tok-1 absent
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_L5}" REVIEW_ADJUDICATION_LOG="${_A5}" /bin/bash "${SUT}" --adjudicate g1 --verdict false_block
  REVIEW_SHADOW_LOG="${_L5}" REVIEW_ADJUDICATION_LOG="${_A5}" /bin/bash "${SUT}" --adjudicate g1 --verdict true_catch ) >/dev/null 2>&1
_k="$(_run "${_L5}" "${_A5}" --status | sed -n 's/^rate (human-confirmed only) : k=\([0-9]*\).*/\1/p')"
assert_equals "a correcting re-adjudication supersedes the earlier verdict" "0" "${_k}"

# ---------------------------------------------------------------------------
# 7. The shadow log is NEVER mutated by any command.
# ---------------------------------------------------------------------------
_before="$(cksum < "${_L5}")"
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_L5}" REVIEW_ADJUDICATION_LOG="${_A5}" /bin/bash "${SUT}" --adjudicate g1 --verdict unknown
  REVIEW_SHADOW_LOG="${_L5}" REVIEW_ADJUDICATION_LOG="${_A5}" /bin/bash "${SUT}" --status
  REVIEW_SHADOW_LOG="${_L5}" REVIEW_ADJUDICATION_LOG="${_A5}" /bin/bash "${SUT}" --next ) >/dev/null 2>&1
assert_equals "the shadow log is byte-identical after adjudicate/status/next" \
    "${_before}" "$(cksum < "${_L5}")"

# ---------------------------------------------------------------------------
# 8. An adjudication naming a record absent from this corpus is WARNED about.
#    REVIEW_SHADOW_LOG can name an alternate corpus; a sidecar carried across
#    two of them otherwise attaches labels to records it cannot see.
# ---------------------------------------------------------------------------
_L6="${TMP}/f.jsonl"; _A6="${TMP}/f-adj.jsonl"; : > "${_L6}"
_rec "${_L6}" h1 "2026-09-10T10:00:00Z" /repo/x main tok-1 absent
jq -cn '{schema_version:1,leg:"review",record_id:"NOT-IN-CORPUS",ts:"2026-09-10T10:00:00Z",
         verdict:"true_catch",reason:"",claimant:"human",corpus:"/other/log"}' > "${_A6}"
_out6="$(_run "${_L6}" "${_A6}" --status)"
case "${_out6}" in
    *"name a record_id absent from this corpus"*)
        _record_pass "an orphaned adjudication is warned about" ;;
    *) _record_fail "an orphaned adjudication is warned about" "got: ${_out6}" ;;
esac

# CONTROL: an adjudication naming a record that IS present must not warn.
# A warning that always fires carries no information, and every other cell in
# this file adjudicates real records without asserting the warning's absence --
# so nothing else would catch it.
: > "${_A6}"
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_L6}" REVIEW_ADJUDICATION_LOG="${_A6}" \
    /bin/bash "${SUT}" --adjudicate h1 --verdict true_catch ) >/dev/null 2>&1
_out6b="$(_run "${_L6}" "${_A6}" --status)"
case "${_out6b}" in
    *"name a record_id absent from this corpus"*)
        _record_fail "CONTROL: a present record_id does NOT warn" "warned anyway: ${_out6b}" ;;
    *) _record_pass "CONTROL: a present record_id does NOT warn" ;;
esac

# ---------------------------------------------------------------------------
# 9. The band is EXACT Clopper-Pearson. Wilson is anti-conservative and calls
#    8/23 ADVISORY-ONLY where exact says NARROWED -- pinned so a future
#    "simplification" to a normal approximation cannot pass.
# ---------------------------------------------------------------------------
. "${PROJECT_ROOT}/hooks/lib/shadow-corpus.sh" 2>/dev/null
ALPHA=0.05 DENY_P=0.10 ADVISORY_P=0.20
assert_equals "exact CP: 8/23 is NARROWED (Wilson would say ADVISORY-ONLY)" \
    "NARROWED" "$(shadow_band 8 23)"
assert_equals "exact CP: 0/29 is DENY (the pre-registered floor)" \
    "DENY" "$(shadow_band 0 29)"
assert_equals "exact CP: 0/28 is NOT yet DENY" \
    "NARROWED" "$(shadow_band 0 28)"
assert_equals "exact CP: n=0 is INSUFFICIENT, never a band" \
    "INSUFFICIENT" "$(shadow_band 0 0)"

# ---------------------------------------------------------------------------
# 10. The floor message must say the denominator is ADJUDICATED episodes, not
#     recorded ones. "n=29 recorded" is the misreading that would clear a
#     deny-flip on zero evidence -- zero adjudications is not zero false blocks.
# ---------------------------------------------------------------------------
_L7="${TMP}/g.jsonl"; _A7="${TMP}/g-adj.jsonl"; : > "${_L7}"
_i=0
while [ "${_i}" -lt 40 ]; do
    _rec "${_L7}" "z${_i}" "2026-09-10T$(printf '%02d' $(( _i / 4 + 1 ))):$(printf '%02d' $(( (_i % 4) * 15 ))):00Z" \
        "/repo/r${_i}" "b${_i}" "tok-${_i}" absent
    _i=$(( _i + 1 ))
done
_out7="$(_run "${_L7}" "${_A7}" --status)"
case "${_out7}" in
    *"FLOOR NOT MET: the denominator is human-ADJUDICATED episodes"*)
        _record_pass "40 unadjudicated episodes do NOT satisfy the n=29 floor" ;;
    *) _record_fail "40 unadjudicated episodes do NOT satisfy the n=29 floor" "got: ${_out7}" ;;
esac

print_summary
