#!/usr/bin/env bash
# tests/test-dated-check-audit.sh — #266
#
# When a dated commitment is extended, the new date tends to land in a COMMENT
# while the body's `due:` line — the field the label query reads — keeps the
# superseded date. The query then reports a wrong number, which is worse than no
# number because it is quotable.
#
# THE FIXTURES ARE THE POINT, not belt-and-braces. #266's premise was already
# stale when it was implemented: the single live divergence it cited had been
# repaired hours after filing, so the live set is CLEAN. A live `0` therefore
# demonstrates nothing on its own — it is indistinguishable from an audit that
# silently stopped working. These fixtures are what make a clean live run mean
# "checked and clean".

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

AUDIT="${PROJECT_ROOT}/scripts/dated-check-audit.sh"
FIX="${SCRIPT_DIR}/fixtures/dated-check"

_run_fixtures() { DATED_CHECK_FIXTURES="${FIX}" /bin/bash "${AUDIT}" 2>/dev/null; }

test_audit_is_runnable() {
    if [ -r "${AUDIT}" ] && [ -d "${FIX}" ]; then
        _record_pass "audit script and fixtures are present"
    else
        _record_fail "audit script and fixtures are present" \
            "missing ${AUDIT} or ${FIX} — every cell below would be vacuous"
    fi
}

test_fixture_corpus_is_intact() {
    # A floor equal to the needle count: a shrunken corpus would let the
    # classification cells below pass having checked almost nothing.
    local n; n="$(ls -1 "${FIX}"/*.body 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n}" -ge 7 ]; then
        _record_pass "fixture corpus intact (${n} cases)"
    else
        _record_fail "fixture corpus intact" "found ${n} .body fixtures, expected at least 7"
    fi
}

test_divergences_are_detected() {
    # THE cell that makes a clean live run meaningful.
    local out missing=""
    out="$(_run_fixtures)"
    for id in div-comment-defer div-until div-body-only; do
        printf '%s' "${out}" | grep -q "^${id}	divergent" || missing="${missing} ${id}"
    done
    if [ -z "${missing}" ]; then
        _record_pass "all three divergent fixtures are detected"
    else
        _record_fail "all three divergent fixtures are detected" \
            "not flagged:${missing} — a clean live run would prove nothing"
    fi
}

test_aligned_issues_are_not_flagged() {
    # The paired control. Without it, an audit that flagged everything would
    # score perfectly on the cell above.
    local out wrong=""
    out="$(_run_fixtures)"
    for id in ok-body-matches ok-no-dates-in-comments ok-narrative-date-only; do
        printf '%s' "${out}" | grep -q "^${id}	clean" || wrong="${wrong} ${id}"
    done
    if [ -z "${wrong}" ]; then
        _record_pass "aligned fixtures are not flagged"
    else
        _record_fail "aligned fixtures are not flagged" "wrongly flagged:${wrong}"
    fi
}

test_narrative_date_is_not_a_commitment() {
    # The specific false positive the first two cuts produced, taken from the
    # live issue: "Extended window executed 2026-09-19" reports WHEN something
    # happened; it does not move a deadline. An audit whose purpose is that a
    # wrong number is worse than no number must not manufacture one.
    if _run_fixtures | grep -q '^ok-body-matches	clean'; then
        _record_pass "a narrative date next to 'Extended' is not read as a deferral"
    else
        _record_fail "a narrative date next to 'Extended' is not read as a deferral" \
            "the audit invented a divergence from prose — this is the defect it exists to prevent"
    fi
}

test_unparseable_is_cannot_check_not_clean() {
    # Three outcomes, never two. "Could not check" must not read as "clean".
    local out rc
    out="$(_run_fixtures)"; rc=$?
    if printf '%s' "${out}" | grep -q '^bad-no-due-line	cannot-check' && [ "${rc}" -eq 3 ]; then
        _record_pass "an unparseable body reports cannot-check and exits 3"
    else
        _record_fail "an unparseable body reports cannot-check and exits 3" \
            "exit was ${rc}; a body with no due: line must never be reported clean"
    fi
}

test_adds_no_scheduled_caller() {
    # #182 resolved that lapsed dated commitments are a PRIORITIZATION problem,
    # not a visibility one, and ruled out digests and monitors. This check is
    # run by a person; if it ever acquires a scheduled caller, the finding says
    # to delete it rather than trim it.
    local hits
    hits="$(grep -rl 'dated-check-audit' "${PROJECT_ROOT}/.github/workflows" 2>/dev/null || true)"
    if [ -z "${hits}" ]; then
        _record_pass "no workflow invokes the audit (the #182 finding holds)"
    else
        _record_fail "no workflow invokes the audit" \
            "referenced by:${hits} — #182 rules out scheduled reporting for this class"
    fi
}

test_audit_is_runnable
test_fixture_corpus_is_intact
test_divergences_are_detected
test_aligned_issues_are_not_flagged
test_narrative_date_is_not_a_commitment
test_unparseable_is_cannot_check_not_clean
test_adds_no_scheduled_caller

print_summary
