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
# Written NEWEST-FIRST on purpose: --next must sort by ts, and with the file
# already in ts order the sort was unpinned (stripping it changed nothing).
_rec "${_LM}" m4 "2026-09-20T12:00:00Z" /repo/y main tok-9 not-clean
_rec "${_LM}" m3 "2026-09-20T10:00:00Z" /repo/x main tok-9 absent
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
_kn="$(_run "${_L5}" "${_A5}" --status | sed -n 's/^rate (human-confirmed only) : k=\([0-9]*\) false blocks of n=\([0-9]*\).*/\1 \2/p')"
# Asserts n as well as k. With k alone the cell is satisfied by _claimant always
# returning agent, where the episode leaves the rate entirely and k=0 for the
# wrong reason -- green under a mutation it does not name.
assert_equals "a correcting re-adjudication supersedes the earlier verdict (k AND n)" "0 1" "${_kn}"

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

# ---------------------------------------------------------------------------
# 11. The PRE-REGISTERED CONSTANTS are pinned against design.md as a SECOND
#     AUTHORITY, and against literals hardcoded here as a third.
#
#     Measured before this cell existed: `FLOOR_EPISODES 29 -> 1` plus
#     `FLOOR_REPOS 2 -> 1` left the suite 30/30 GREEN, and so did
#     `DENY_P 0.10 -> 0.45` plus `ADVISORY_P 0.20 -> 0.99`. For a change whose
#     entire purpose is to make a pre-registration enforceable, its numbers
#     were the one thing nothing pinned.
#
#     Cell 9 does not cover this and cannot: it sources the lib and sets
#     ALPHA/DENY_P/ADVISORY_P *itself*, so it validates the band FUNCTION while
#     reading none of the script's constants -- a mutation picked from the
#     test's own needles rather than from the invariant.
#
#     Three authorities, because two that can drift together are one: the
#     script, the registration prose, and literals written out here. A floor on
#     the number of checks stops a reworded design.md from silently matching
#     nothing and passing.
# ---------------------------------------------------------------------------
_DESIGN="${PROJECT_ROOT}/openspec/changes/review-verdict/design.md"
_const() { grep -oE "^${1}=[0-9.]+" "${SUT}" 2>/dev/null | head -1 | cut -d= -f2; }
_checked=0

if [ -f "${_DESIGN}" ]; then
    _record_pass "pre-registration design.md is present (second authority)"
else
    _record_fail "pre-registration design.md is present (second authority)" \
        "missing at ${_DESIGN} -- every cell below would be vacuous"
fi

# floor: episodes. design.md says "n = 29 independent episodes"
_d_floor="$(grep -oE 'n = ([0-9]+) independent episodes' "${_DESIGN}" 2>/dev/null | head -1 | grep -oE '[0-9]+')"
assert_equals "design.md states the episode floor (not silently unmatched)" "29" "${_d_floor:-<no match>}"
assert_equals "FLOOR_EPISODES == design.md == 29" "${_d_floor}" "$(_const FLOOR_EPISODES)"
[ -n "${_d_floor}" ] && _checked=$(( _checked + 1 ))

# floor: repo diversity. design.md says ">=2 distinct repos" (unicode >=)
_d_repos="$(grep -oE '≥([0-9]+) distinct repos' "${_DESIGN}" 2>/dev/null | head -1 | grep -oE '[0-9]+')"
assert_equals "design.md states the diversity floor" "2" "${_d_repos:-<no match>}"
assert_equals "FLOOR_REPOS == design.md == 2" "${_d_repos}" "$(_const FLOOR_REPOS)"
[ -n "${_d_repos}" ] && _checked=$(( _checked + 1 ))

# band probabilities, from the two CDF comparisons in the bands clause.
_d_deny="$(grep -oE 'P\(X≤k \| n, ([0-9.]+)\)' "${_DESIGN}" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+')"
assert_equals "design.md states the DENY probability" "0.10" "${_d_deny:-<no match>}"
assert_equals "DENY_P == design.md == 0.10" "${_d_deny}" "$(_const DENY_P)"
[ -n "${_d_deny}" ] && _checked=$(( _checked + 1 ))

_d_adv="$(grep -oE 'P\(X≥k \| n, ([0-9.]+)\)' "${_DESIGN}" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+')"
assert_equals "design.md states the ADVISORY-ONLY probability" "0.20" "${_d_adv:-<no match>}"
assert_equals "ADVISORY_P == design.md == 0.20" "${_d_adv}" "$(_const ADVISORY_P)"
[ -n "${_d_adv}" ] && _checked=$(( _checked + 1 ))

# episode window. design.md says "within 30 minutes"
_d_win="$(grep -oE 'within ([0-9]+) minutes' "${_DESIGN}" 2>/dev/null | head -1 | grep -oE '[0-9]+')"
assert_equals "design.md states the episode window in minutes" "30" "${_d_win:-<no match>}"
if [ -n "${_d_win}" ]; then
    assert_equals "EPISODE_WINDOW_SEC == design.md minutes * 60 == 1800" \
        "$(( _d_win * 60 ))" "$(_const EPISODE_WINDOW_SEC)"
    _checked=$(( _checked + 1 ))
fi

# ALPHA has no prose form to parse; pin it against a literal so a change to it
# is still a red test rather than a silent relaxation.
assert_equals "ALPHA == 0.05" "0.05" "$(_const ALPHA)"

# Floor on the number of constants actually cross-checked. Without this, a
# reworded design.md makes every grep above return empty and the cell degrades
# to comparing "" with "" -- green, and pinning nothing.
if [ "${_checked}" -ge 5 ]; then
    _record_pass "cross-checked ${_checked} pre-registered constants against design.md (>=5)"
else
    _record_fail "cross-checked >=5 pre-registered constants against design.md" \
        "only ${_checked} matched -- design.md wording drifted and these cells are going vacuous"
fi

# ---------------------------------------------------------------------------
# 12. The DIVERSITY branch must be REACHED, and must be counted over the same
#     population as the rate. Measured before the fix: 29 human-adjudicated
#     true_catch episodes in ONE repo plus a single UNLABELED episode in a
#     second printed "floor met on n and diversity" with band DENY -- the
#     instrument certifying the deny-flip on single-repo evidence. No cell
#     reached the branch at all, because none adjudicated 29 episodes.
# ---------------------------------------------------------------------------
_LD="${TMP}/div.jsonl"; _AD="${TMP}/div-adj.jsonl"; : > "${_LD}"; : > "${_AD}"
_i=0
while [ "${_i}" -lt 29 ]; do
    _rec "${_LD}" "d${_i}" "2026-09-$(printf '%02d' $(( _i / 8 + 1 )))T$(printf '%02d' $(( _i % 8 * 3 ))):00:00Z" \
        /repo/alpha "br${_i}" "tokd-${_i}" absent
    _i=$(( _i + 1 ))
done
# One UNLABELED episode in a SECOND repo. It carries no evidence of anything.
_rec "${_LD}" dbeta "2026-09-20T10:00:00Z" /repo/beta main tokd-beta absent
_i=0
while [ "${_i}" -lt 29 ]; do
    ( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
      REVIEW_SHADOW_LOG="${_LD}" REVIEW_ADJUDICATION_LOG="${_AD}" \
        /bin/bash "${SUT}" --adjudicate "d${_i}" --verdict true_catch ) >/dev/null 2>&1
    _i=$(( _i + 1 ))
done
_outd="$(_run "${_LD}" "${_AD}" --status)"
# The rate floor IS met (n=29, k=0) -- so the diversity branch is genuinely
# reached rather than short-circuited by an unmet n.
_nd="$(printf '%s' "${_outd}" | sed -n 's/^rate (human-confirmed only) : k=[0-9]* false blocks of n=\([0-9]*\).*/\1/p')"
assert_equals "diversity branch is REACHED (n floor met at 29)" "29" "${_nd}"
case "${_outd}" in
    *"FLOOR NOT MET: diversity"*)
        _record_pass "an UNLABELED episode in a second repo does NOT satisfy the diversity floor" ;;
    *) _record_fail "an UNLABELED episode in a second repo does NOT satisfy the diversity floor" \
           "got: ${_outd}" ;;
esac
# CONTROL: adjudicate the second repo's episode and the floor must now be met,
# or the cell above would pass simply because diversity can never be satisfied.
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_LD}" REVIEW_ADJUDICATION_LOG="${_AD}" \
    /bin/bash "${SUT}" --adjudicate dbeta --verdict true_catch ) >/dev/null 2>&1
_outd2="$(_run "${_LD}" "${_AD}" --status)"
case "${_outd2}" in
    *"floor met on n and diversity"*)
        _record_pass "CONTROL: adjudicating the second repo DOES satisfy diversity" ;;
    *) _record_fail "CONTROL: adjudicating the second repo DOES satisfy diversity" "got: ${_outd2}" ;;
esac

# ---------------------------------------------------------------------------
# 13. DIVERSITY IS PER REPOSITORY, NOT PER WORKTREE PATH.
#
#     The writer sets `repo` from `git rev-parse --show-toplevel`, which is the
#     WORKTREE path. On the live corpus that is 15 distinct values for 5
#     repositories, so ">=2 distinct repos" was satisfiable by two worktrees of
#     ONE repository -- zero cross-repository evidence, which is the entire
#     purpose of the clause. This repo uses detached worktrees heavily, so it is
#     not hypothetical.
#
#     Real git repositories, because the resolution asks git (origin URL, then
#     --git-common-dir). A fabricated path fixture would prove nothing.
# ---------------------------------------------------------------------------
_WTR="${TMP}/wtrepo"; mkdir -p "${_WTR}"
( cd "${_WTR}"; git init -q -b main; git config user.email t@t; git config user.name t
  git remote add origin https://example.invalid/one.git
  echo a > a; git add -A; git commit -qm a ) >/dev/null 2>&1
_WT2="${TMP}/wtrepo-second"
git -C "${_WTR}" worktree add -q --detach "${_WT2}" main >/dev/null 2>&1

# A genuinely different repository, as the positive control.
_OTHER="${TMP}/otherrepo"; mkdir -p "${_OTHER}"
( cd "${_OTHER}"; git init -q -b main; git config user.email t@t; git config user.name t
  git remote add origin https://example.invalid/two.git
  echo b > b; git add -A; git commit -qm b ) >/dev/null 2>&1

if [ -d "${_WT2}/.git" ] || [ -f "${_WT2}/.git" ]; then
    _record_pass "two-worktree fixture built"
else
    _record_fail "two-worktree fixture built" "no worktree at ${_WT2} -- cells below are vacuous"
fi

_LW="${TMP}/wt.jsonl"; _AW="${TMP}/wt-adj.jsonl"; : > "${_LW}"; : > "${_AW}"
_rec "${_LW}" w1 "2026-09-20T10:00:00Z" "${_WTR}" main tokw-1 absent
_rec "${_LW}" w2 "2026-09-20T12:00:00Z" "${_WT2}" other tokw-2 absent
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_LW}" REVIEW_ADJUDICATION_LOG="${_AW}" /bin/bash "${SUT}" --adjudicate w1 --verdict true_catch
  REVIEW_SHADOW_LOG="${_LW}" REVIEW_ADJUDICATION_LOG="${_AW}" /bin/bash "${SUT}" --adjudicate w2 --verdict true_catch ) >/dev/null 2>&1
_nw="$(_run "${_LW}" "${_AW}" --status | sed -n 's/^episodes (adjudicable) : [0-9]*   across \([0-9]*\) distinct.*/\1/p')"
assert_equals "two WORKTREES of one repository count as ONE repository" "1" "${_nw}"

# CONTROL: a genuinely different repository must still count as a second, or
# the cell above would pass with the count hardwired to 1.
_rec "${_LW}" w3 "2026-09-20T14:00:00Z" "${_OTHER}" main tokw-3 absent
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_LW}" REVIEW_ADJUDICATION_LOG="${_AW}" /bin/bash "${SUT}" --adjudicate w3 --verdict true_catch ) >/dev/null 2>&1
_nw2="$(_run "${_LW}" "${_AW}" --status | sed -n 's/^episodes (adjudicable) : [0-9]*   across \([0-9]*\) distinct.*/\1/p')"
assert_equals "CONTROL: a DIFFERENT repository counts as a second" "2" "${_nw2}"

# A repo path containing a SPACE must count as one repository, not two. The
# first cut accumulated space-separated and counted with an unquoted `for`,
# which read one such path as two and silently INFLATED diversity.
_SPACE="${TMP}/My Projects/spacerepo"; mkdir -p "${_SPACE}"
( cd "${_SPACE}"; git init -q -b main; git config user.email t@t; git config user.name t
  echo c > c; git add -A; git commit -qm c ) >/dev/null 2>&1
_LS="${TMP}/sp.jsonl"; _AS="${TMP}/sp-adj.jsonl"; : > "${_LS}"; : > "${_AS}"
_rec "${_LS}" s1 "2026-09-20T10:00:00Z" "${_SPACE}" main toks-1 absent
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_LS}" REVIEW_ADJUDICATION_LOG="${_AS}" /bin/bash "${SUT}" --adjudicate s1 --verdict true_catch ) >/dev/null 2>&1
_ns="$(_run "${_LS}" "${_AS}" --status | sed -n 's/^episodes (adjudicable) : [0-9]*   across \([0-9]*\) distinct.*/\1/p')"
assert_equals "a repo path containing a SPACE counts as ONE repository" "1" "${_ns}"

git -C "${_WTR}" worktree remove --force "${_WT2}" >/dev/null 2>&1

# ---------------------------------------------------------------------------
# 14. "Exists but cannot be READ" must never render as "empty".
#
#     `-f` says nothing about readability, and the count pipelines end in `tr`,
#     so a permission error is discarded with the pipeline's status. Measured
#     before the fix: a chmod 000 corpus printed "0 line(s), 0 parsed" -- byte
#     for byte what a genuinely empty corpus prints. This instrument exists
#     precisely to stop a live corpus reading as an empty one; failing that on
#     a different input is the same defect wearing a different hat.
#
#     Skipped when running as root, where chmod 000 does not deny reads.
# ---------------------------------------------------------------------------
_LU="${TMP}/unreadable.jsonl"; _AU="${TMP}/unreadable-adj.jsonl"; : > "${_LU}"
_rec "${_LU}" u1 "2026-09-20T10:00:00Z" /repo/x main toku-1 absent
_out_readable="$(_run "${_LU}" "${_AU}" --status)"
case "${_out_readable}" in
    *"records : 1 line(s)"*) _record_pass "CONTROL: a readable 1-record corpus reports 1 line" ;;
    *) _record_fail "CONTROL: a readable 1-record corpus reports 1 line" "got: ${_out_readable}" ;;
esac
chmod 000 "${_LU}" 2>/dev/null
if [ -r "${_LU}" ]; then
    _record_pass "SKIPPED: chmod 000 still readable (running as root?) — unreadable cell not applicable"
else
    _out_unreadable="$(_run "${_LU}" "${_AU}" --status)"
    case "${_out_unreadable}" in
        *"NOT READABLE"*) _record_pass "an unreadable corpus is reported as unreadable, not as empty" ;;
        *) _record_fail "an unreadable corpus is reported as unreadable, not as empty" \
               "got: ${_out_unreadable}" ;;
    esac
    # And it must NOT claim a record count it could not obtain.
    case "${_out_unreadable}" in
        *"records : 0 line(s)"*)
            _record_fail "an unreadable corpus does not report a zero record count" \
                "printed '0 line(s)' — indistinguishable from an empty corpus" ;;
        *) _record_pass "an unreadable corpus does not report a zero record count" ;;
    esac
fi
chmod 644 "${_LU}" 2>/dev/null

# ---------------------------------------------------------------------------
# 15. CORRUPTED INPUT in either log must not silently shrink the measurement.
#
#     jq ABORTS on the first malformed line and returns what it parsed BEFORE
#     the abort. Measured before the fix: one truncated line prepended to a
#     sidecar holding two intact human adjudications took the readout from
#     "k=1 of n=2, NARROWED" to "k=0 of n=0, INSUFFICIENT" with no warning.
#     The POSITION is what makes it dangerous -- a bad line at row 29 of 35
#     keeps rows 1-28, so a real false_block at row 34 vanishes while n>=29
#     survives: k falls and the band CLEARS.
# ---------------------------------------------------------------------------
_LC="${TMP}/corrupt.jsonl"; _AC="${TMP}/corrupt-adj.jsonl"; : > "${_LC}"; : > "${_AC}"
_rec "${_LC}" c1 "2026-09-10T10:00:00Z" /repo/x main tokc-1 absent
_rec "${_LC}" c2 "2026-09-11T10:00:00Z" /repo/y main tokc-2 absent
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_LC}" REVIEW_ADJUDICATION_LOG="${_AC}" /bin/bash "${SUT}" --adjudicate c1 --verdict false_block
  REVIEW_SHADOW_LOG="${_LC}" REVIEW_ADJUDICATION_LOG="${_AC}" /bin/bash "${SUT}" --adjudicate c2 --verdict true_catch ) >/dev/null 2>&1
_rate_before="$(_run "${_LC}" "${_AC}" --status | sed -n 's/^rate (human-confirmed only) : \(.*\)$/\1/p')"
assert_equals "CONTROL: intact sidecar gives the expected rate" "k=1 false blocks of n=2 episode(s)" "${_rate_before}"

# Prepend one truncated line to the SIDECAR -- the log whose corruption moves k.
printf '%s\n' '{"record_id":"trunc","verdict":' > "${TMP}/bad.jsonl"
cat "${_AC}" >> "${TMP}/bad.jsonl"; mv "${TMP}/bad.jsonl" "${_AC}"
_rate_after="$(_run "${_LC}" "${_AC}" --status | sed -n 's/^rate (human-confirmed only) : \(.*\)$/\1/p')"
assert_equals "a truncated SIDECAR line does not discard the adjudications after it" \
    "${_rate_before}" "${_rate_after}"

# And the corruption is ANNOUNCED, not merely survived.
_out_corrupt="$(_run "${_LC}" "${_AC}" --status)"
case "${_out_corrupt}" in
    *"unparseable"*) _record_pass "sidecar corruption is announced" ;;
    *) _record_fail "sidecar corruption is announced" "no unparseable count in: ${_out_corrupt}" ;;
esac

# Same for the CORPUS: a truncated line must not hide records after it from
# --adjudicate, which is the exact workflow the tool prescribes.
printf '%s\n' '{"record_id":"trunc2","ts":' > "${TMP}/bad2.jsonl"
cat "${_LC}" >> "${TMP}/bad2.jsonl"; mv "${TMP}/bad2.jsonl" "${_LC}"
_outadj="$( ( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_LC}" REVIEW_ADJUDICATION_LOG="${_AC}" \
    /bin/bash "${SUT}" --adjudicate c2 --verdict true_catch ) 2>&1 )"
case "${_outadj}" in
    *"no record 'c2'"*) _record_fail "a record after a truncated corpus line is still addressable" \
        "adjudicate asserted the record does not exist: ${_outadj}" ;;
    *) _record_pass "a record after a truncated corpus line is still addressable" ;;
esac

# ---------------------------------------------------------------------------
# 16. --next must not claim the work is done when nothing is OFFERABLE.
#     Measured before the fix: one empty-ts record plus one would_block:false
#     record, sidecar empty, printed "all 2 adjudicable record(s) are labelled"
#     with zero adjudications. `ts:""` is reachable from the producer, not only
#     from fixtures -- review-shadow.sh emits it whenever `date` fails.
# ---------------------------------------------------------------------------
_LN="${TMP}/nooffer.jsonl"; _AN="${TMP}/nooffer-adj.jsonl"; : > "${_LN}"; : > "${_AN}"
jq -cn --argjson pv "${PV}" '{schema_version:2,predicate_version:$pv,record_id:"n1",ts:"",
   repo:"/repo/x",branch:"main",head_sha:"d",session_token:"t",action:"push",
   would_block:true,reason:"absent",transcript_path:""}' >> "${_LN}"
jq -cn --argjson pv "${PV}" '{schema_version:2,predicate_version:$pv,record_id:"n2",
   ts:"2026-09-10T10:00:00Z",repo:"/repo/x",branch:"main",head_sha:"d",session_token:"t",
   action:"push",would_block:false,reason:"absent",transcript_path:""}' >> "${_LN}"
_outn2="$(_run "${_LN}" "${_AN}" --next)"
case "${_outn2}" in
    *"are labelled"*) _record_fail "--next does not say 'all labelled' with zero adjudications" \
        "got: ${_outn2}" ;;
    *) _record_pass "--next does not say 'all labelled' with zero adjudications" ;;
esac
case "${_outn2}" in
    *"excluded from the"*) _record_pass "--next explains WHY nothing is offerable" ;;
    *) _record_fail "--next explains WHY nothing is offerable" "got: ${_outn2}" ;;
esac

# ...and a would_block:false record must not form an episode or feed diversity.
_eps_n="$(_run "${_LN}" "${_AN}" --status | sed -n 's/^episodes (adjudicable) : \([0-9]*\).*/\1/p')"
assert_equals "a would_block:false record does NOT enter the episode population" "0" "${_eps_n}"

# ---------------------------------------------------------------------------
# 17. An AGENT-claimed verdict must not enter the human-confirmed counts.
#     Measured before the fix: one episode with an agent false_block and a
#     human true_catch reported "human-confirmed : false_block=1" and put the
#     agent's verdict into k -- seconds after --adjudicate told the operator
#     that row was excluded.
# ---------------------------------------------------------------------------
_LA="${TMP}/mixed.jsonl"; _AA="${TMP}/mixed-adj.jsonl"; : > "${_LA}"; : > "${_AA}"
_rec "${_LA}" m1 "2026-09-10T10:00:00Z" /repo/x main tokm-1 absent
_rec "${_LA}" m2 "2026-09-10T10:05:00Z" /repo/x main tokm-1 absent
CLAUDECODE=1 REVIEW_SHADOW_LOG="${_LA}" REVIEW_ADJUDICATION_LOG="${_AA}" \
    /bin/bash "${SUT}" --adjudicate m1 --verdict false_block >/dev/null 2>&1
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
  REVIEW_SHADOW_LOG="${_LA}" REVIEW_ADJUDICATION_LOG="${_AA}" \
    /bin/bash "${SUT}" --adjudicate m2 --verdict true_catch ) >/dev/null 2>&1
_km="$(_run "${_LA}" "${_AA}" --status | sed -n 's/^rate (human-confirmed only) : k=\([0-9]*\).*/\1/p')"
assert_equals "an AGENT false_block does not enter k under a human-confirmed header" "0" "${_km}"

# ---------------------------------------------------------------------------
# 18. The EXCLUDED band is described, so the amendment's figures are
#     reproducible by the instrument rather than by hand.
# ---------------------------------------------------------------------------
_LL="${TMP}/legacy.jsonl"; _AL="${TMP}/legacy-adj.jsonl"; : > "${_LL}"
_rec "${_LL}" "" "2026-08-01T10:00:00Z" /repo/old main tokl-1 absent 1
_rec "${_LL}" "" "2026-08-03T10:00:00Z" /repo/old main tokl-2 absent 1
_outl="$(_run "${_LL}" "${_AL}" --status)"
case "${_outl}" in
    *"DESCRIPTIVE ONLY"*) _record_pass "the excluded band is described, not just counted" ;;
    *) _record_fail "the excluded band is described, not just counted" "got: ${_outl}" ;;
esac
_legeps="$(printf '%s' "${_outl}" | sed -n 's/^    episodes \([0-9]*\),.*/\1/p')"
assert_equals "excluded-band episodes are grouped despite having no record_id" "2" "${_legeps}"

# ---------------------------------------------------------------------------
# 19. THE REAL PRODUCER FEEDING THE REAL READER.
#
#     Every other corpus in this file is hand-built by `_rec()`, which RETYPES
#     the field names -- so the producer/consumer contract that is the whole
#     point of this change had no coverage at all. Measured on the committed
#     version: renaming `would_block` to `wouldblock`, or `ts` to `timestamp`,
#     in hooks/lib/review-shadow.sh left BOTH test files fully green, while the
#     real reader answered `all 1 adjudicable record(s) are labelled` for a
#     record nobody had ever adjudicated -- the exact confusion cmd_next's two
#     messages exist to prevent, reached by a different cause than the reader
#     bug fixed alongside it.
#
#     This is the fixture rule this repo already records: a fixture the author
#     invented rather than observed proves only that the code agrees with the
#     author's assumption.
# ---------------------------------------------------------------------------
_RT="${TMP}/roundtrip.jsonl"; _RTA="${TMP}/roundtrip-adj.jsonl"; rm -f "${_RT}" "${_RTA}"
( set -u; . "${WRITER}" 2>/dev/null
  REVIEW_SHADOW_LOG="${_RT}" review_shadow_record "session-rt" "${PROJECT_ROOT}" "absent" "push" "HEAD" ) \
  >/dev/null 2>&1
if [ -s "${_RT}" ]; then
    _record_pass "the real producer wrote a record"
else
    _record_fail "the real producer wrote a record" "nothing at ${_RT} -- cells below are vacuous"
fi

# The reader must SEE it: one adjudicable episode, and --next must OFFER it.
_rt_eps="$(_run "${_RT}" "${_RTA}" --status | sed -n 's/^episodes (adjudicable) : \([0-9]*\).*/\1/p')"
assert_equals "the real reader groups the real producer's record into 1 episode" "1" "${_rt_eps}"

_rt_next="$(_run "${_RT}" "${_RTA}" --next)"
case "${_rt_next}" in
    *"are labelled"*)
        _record_fail "--next OFFERS the real producer's record" \
            "said the work is done for a record never adjudicated: ${_rt_next}" ;;
    *"record_id : "*) _record_pass "--next OFFERS the real producer's record" ;;
    *) _record_fail "--next OFFERS the real producer's record" "got: ${_rt_next}" ;;
esac

# And the id --next prints must be addressable by --adjudicate, which is the
# workflow the tool prescribes.
_rt_id="$(printf '%s' "${_rt_next}" | sed -n 's/^record_id : //p' | head -1)"
if [ -n "${_rt_id}" ]; then
    _rt_adj="$( ( unset CLAUDECODE CLAUDE_CODE_SESSION_ID
      REVIEW_SHADOW_LOG="${_RT}" REVIEW_ADJUDICATION_LOG="${_RTA}" \
        /bin/bash "${SUT}" --adjudicate "${_rt_id}" --verdict true_catch ) 2>&1 )"
    case "${_rt_adj}" in
        *"recorded: ${_rt_id}"*) _record_pass "the producer's record is addressable by --adjudicate" ;;
        *) _record_fail "the producer's record is addressable by --adjudicate" "got: ${_rt_adj}" ;;
    esac
    _rt_n="$(_run "${_RT}" "${_RTA}" --status | sed -n 's/^rate (human-confirmed only) : k=[0-9]* false blocks of n=\([0-9]*\).*/\1/p')"
    assert_equals "the producer's record reaches the denominator end to end" "1" "${_rt_n}"
else
    _record_fail "the producer's record is addressable by --adjudicate" "--next printed no record_id"
fi

# ---------------------------------------------------------------------------
# 20. A record that parses but has an unusable ts must be ACCOUNTED FOR.
#     It is correctly excluded from the grouping -- merging two corrupt records
#     would satisfy (-1)-(-1)=0 <= window and collapse them on a time relation
#     nothing verified -- but excluding it SILENTLY left the denominator short
#     with no row explaining the gap: "2 parsed, 1 episode" and nothing said.
#     That is the shortfall this file's own section 4 forbids for empty
#     branches. `ts:""` is producer-reachable whenever `date` fails.
# ---------------------------------------------------------------------------
_LT="${TMP}/badts.jsonl"; _AT="${TMP}/badts-adj.jsonl"; : > "${_LT}"; : > "${_AT}"
_rec "${_LT}" t1 "2026-09-20T10:00:00Z" /repo/x main tokt-1 absent
jq -cn --argjson pv "${PV}" '{schema_version:2,predicate_version:$pv,record_id:"t2",
   ts:"not-a-timestamp",repo:"/repo/x",branch:"main",head_sha:"d",session_token:"tokt-2",
   action:"push",would_block:true,reason:"absent",transcript_path:""}' >> "${_LT}"
_outt="$(_run "${_LT}" "${_AT}" --status)"
case "${_outt}" in
    *"EXCLUDED — unparseable ts : 1 record"*)
        _record_pass "a malformed-ts record is reported as excluded, not silently dropped" ;;
    *) _record_fail "a malformed-ts record is reported as excluded, not silently dropped" "got: ${_outt}" ;;
esac
assert_equals "...and it does not enter the episode population" "1" \
    "$(printf '%s' "${_outt}" | sed -n 's/^episodes (adjudicable) : \([0-9]*\).*/\1/p')"
# CONTROL: with every ts well-formed the exclusion row must NOT appear.
_LT2="${TMP}/goodts.jsonl"; : > "${_LT2}"
_rec "${_LT2}" g1 "2026-09-20T10:00:00Z" /repo/x main tokg-1 absent
case "$(_run "${_LT2}" "${_AT}" --status)" in
    *"unparseable ts"*) _record_fail "CONTROL: no ts-exclusion row when every ts is valid" "row printed anyway" ;;
    *) _record_pass "CONTROL: no ts-exclusion row when every ts is valid" ;;
esac

# ---------------------------------------------------------------------------
# 21. A malformed LINE in the corpus must not truncate the read. The `-R
#     fromjson?` guards were added throughout, but no fixture contained a
#     malformed line, so the protection was unpinned wherever it was added.
# ---------------------------------------------------------------------------
_LB="${TMP}/badline.jsonl"; _AB="${TMP}/badline-adj.jsonl"; : > "${_LB}"; : > "${_AB}"
_rec "${_LB}" b1 "2026-09-20T10:00:00Z" /repo/x main tokb-1 absent
printf '%s\n' '{"record_id":"broken","ts":' >> "${_LB}"
_rec "${_LB}" b2 "2026-09-20T12:00:00Z" /repo/y main tokb-2 absent
_outb="$(_run "${_LB}" "${_AB}" --status)"
assert_equals "records AFTER a malformed line still form episodes" "2" \
    "$(printf '%s' "${_outb}" | sed -n 's/^episodes (adjudicable) : \([0-9]*\).*/\1/p')"
case "${_outb}" in
    *"1 unparseable"*) _record_pass "the malformed line is counted as unparseable" ;;
    *) _record_fail "the malformed line is counted as unparseable" "got: ${_outb}" ;;
esac

# ---------------------------------------------------------------------------
# 22. shadow_band refuses a degenerate probability rather than emitting awk's
#     division-by-zero output. The recurrence divides by (1 - p), so p == 1 is
#     a division by zero -- measured before the guard, awk printed "division by
#     zero" and the caller got no usable band. Neither pre-registration can
#     reach it, but this is shared code and a future leg's probabilities are
#     not this file's to assume.
# ---------------------------------------------------------------------------
_band_err="$( ( . "${PROJECT_ROOT}/hooks/lib/shadow-corpus.sh" 2>/dev/null
                ALPHA=0.05 DENY_P=1 ADVISORY_P=0.20 shadow_band 0 10 ) 2>&1 )"
case "${_band_err}" in
    *"division by zero"*)
        _record_fail "shadow_band refuses DENY_P=1 instead of dividing by zero" \
            "awk's division-by-zero surfaced: ${_band_err}" ;;
    *"requires 0 <"*) _record_pass "shadow_band refuses DENY_P=1 instead of dividing by zero" ;;
    *) _record_fail "shadow_band refuses DENY_P=1 instead of dividing by zero" "got: ${_band_err}" ;;
esac
# CONTROL: the pre-registered values must still compute a band, or the guard
# would be satisfied by refusing everything.
assert_equals "CONTROL: the pre-registered probabilities still yield a band" "DENY" \
    "$( ( . "${PROJECT_ROOT}/hooks/lib/shadow-corpus.sh" 2>/dev/null
          ALPHA=0.05 DENY_P=0.10 ADVISORY_P=0.20 shadow_band 0 29 ) 2>/dev/null )"

print_summary
