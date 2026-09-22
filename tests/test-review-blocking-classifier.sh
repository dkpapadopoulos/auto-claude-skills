#!/usr/bin/env bash
# tests/test-review-blocking-classifier.sh — #239
#
# The review workflow posted its review as an ISSUE COMMENT, so
# `record-review-verdict.sh --from-github` — which derives its verdict from
# review STATE — could never see it. Measured across three PRs each carrying a
# substantive review: `gh pr view --json reviews` returned `[]`. The #197
# verdict layer was dark for every CI-reviewed PR.
#
# The fix submits a REAL review for the blocking direction only, which requires
# deciding "did this review block?" from the model's markdown. That is an output
# classifier over another component's prose — the shape that has misfired twice
# in this repo (#127's replay classifier matched compact JSON while the producer
# pretty-printed; #254's deny lint was line-oriented over a declaration-shaped
# language). So:
#
# FIXTURE PROVENANCE IS LABELLED, because it is not uniform:
#   observed-*   harvested VERBATIM from real bot reviews on PRs #281/#284/#286.
#   derived-*    authored from the workflow prompt's own contract, because no
#                blocking review has ever been observed in this repo. They are
#                named apart so nobody later reads them as evidence of what the
#                model actually emits.
#
# The three observed bodies are the reason this file exists: they render the
# SAME section three different ways — `## Blocking issues`, `### Blocking
# issues`, and `**Blocking issues**` — so the obvious `^#+ Blocking issues`
# matcher silently misses one in three.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-review-blocking-classifier.sh ==="

CLS="${PROJECT_ROOT}/scripts/review-blocking-classifier.sh"
FIX="${SCRIPT_DIR}/fixtures/review-blocking-classifier"
WF="${PROJECT_ROOT}/.github/workflows/claude-code-review.yml"

_classify() { /bin/bash "${CLS}" "${FIX}/$1" 2>/dev/null; }

test_preconditions() {
    if [ -r "${CLS}" ] && [ -d "${FIX}" ] && [ -r "${WF}" ]; then
        _record_pass "classifier, fixtures and workflow are present"
    else
        _record_fail "classifier, fixtures and workflow are present" "missing one — cells below vacuous"
    fi
}

test_observed_none_bodies_classify_none() {
    # All three real renderings. A heading-anchored matcher passes two of these
    # and fails the bold one, which is why the anchor is the phrase.
    local f n
    for f in "${FIX}"/observed-none-*.md; do
        n="$(/bin/bash "${CLS}" "${f}" 2>/dev/null)"
        if [ "${n}" = "none" ]; then
            _record_pass "observed $(basename "${f}") => none"
        else
            _record_fail "observed $(basename "${f}") => none" "got '${n}'"
        fi
    done
}

test_all_three_renderings_are_present_in_the_corpus() {
    # The corpus only pins the renderings it contains. If someone replaces the
    # bold-rendered body with another heading one, the interesting case is gone
    # and every cell above still passes.
    local h2 h3 bold
    h2="$(grep -lE '^## Blocking issues'   "${FIX}"/observed-none-*.md 2>/dev/null | wc -l | tr -d ' ')"
    h3="$(grep -lE '^### Blocking issues'  "${FIX}"/observed-none-*.md 2>/dev/null | wc -l | tr -d ' ')"
    bold="$(grep -lE '^\*\*Blocking issues' "${FIX}"/observed-none-*.md 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${h2}" -ge 1 ] && [ "${h3}" -ge 1 ] && [ "${bold}" -ge 1 ]; then
        _record_pass "the observed corpus still covers h2, h3 and bold renderings"
    else
        _record_fail "the observed corpus covers all three renderings" \
            "h2=${h2} h3=${h3} bold=${bold} — a rendering was lost from the corpus"
    fi
}

test_derived_blocking_bodies_classify_blocking() {
    local f n
    for f in "${FIX}"/derived-blocking-*.md; do
        n="$(/bin/bash "${CLS}" "${f}" 2>/dev/null)"
        if [ "${n}" = "blocking" ]; then
            _record_pass "derived $(basename "${f}") => blocking"
        else
            _record_fail "derived $(basename "${f}") => blocking" "got '${n}'"
        fi
    done
}

test_ambiguous_and_absent_classify_unknown() {
    # `unknown` is the whole safety story: the caller comments on it. A
    # classifier that guessed `blocking` here would submit a CHANGES_REQUESTED
    # that can block a human's merge and cannot be deleted, only dismissed.
    assert_equals "a hedged \"none that block merge, but…\" is unknown" \
        "unknown" "$(_classify derived-ambiguous-hedged.md)"
    assert_equals "a review with no blocking section at all is unknown" \
        "unknown" "$(_classify derived-absent-section.md)"
}

test_classifier_never_exits_nonzero() {
    # The workflow reads the ANSWER from stdout. A non-zero exit would be read
    # as "the step failed" and, under `set -e`, would skip posting the review
    # entirely — losing the review to protect against an unclear one.
    local rc
    /bin/bash "${CLS}" "${FIX}/derived-absent-section.md" >/dev/null 2>&1; rc=$?
    assert_equals "an unclassifiable body still exits 0" "0" "${rc}"
    /bin/bash "${CLS}" "${FIX}/definitely-not-here.md" >/dev/null 2>&1; rc=$?
    assert_equals "a missing file still exits 0" "0" "${rc}"
    assert_equals "...and answers unknown" "unknown" "$(/bin/bash "${CLS}" "${FIX}/definitely-not-here.md" 2>/dev/null)"
    /bin/bash "${CLS}" >/dev/null 2>&1; rc=$?
    assert_equals "no argument still exits 0" "0" "${rc}"
}

test_workflow_only_submits_a_review_on_blocking() {
    # THE GOVERNANCE ASSERTION. An automated reviewer must never be able to
    # CLEAR a review gate: that is the same substitution #197 exists to prevent,
    # one layer out. So the workflow may request changes and may comment, and
    # must never approve.
    if grep -q 'gh pr review .*--approve' "${WF}"; then
        _record_fail "the workflow never approves a PR" \
            "found an --approve call; an automated approval would let a bot clear the REVIEW gate"
    else
        _record_pass "the workflow never approves a PR"
    fi
    if grep -q 'gh pr review .*--request-changes' "${WF}"; then
        _record_pass "the workflow submits a real review for the blocking direction"
    else
        _record_fail "the workflow submits a real review for blocking" \
            "without it the verdict layer stays dark for CI-reviewed PRs (#239)"
    fi
    # The classifier must gate that call, not a grep inlined in the YAML.
    if grep -q 'review-blocking-classifier.sh' "${WF}"; then
        _record_pass "the workflow classifies through the tested script"
    else
        _record_fail "the workflow classifies through the tested script" \
            "an inlined matcher in the YAML is untestable and unpinned"
    fi
}

test_unknown_does_not_request_changes() {
    # Structural: the `blocking` arm is the ONLY one that may reach
    # --request-changes. Extract the case block and check the other arm comments.
    local _case
    _case="$(awk '/case "\$_CLASS" in/,/esac/' "${WF}")"
    if printf '%s' "${_case}" | grep -q 'blocking)' \
       && printf '%s' "${_case}" | grep -q 'gh pr comment'; then
        _record_pass "the non-blocking arm comments instead of requesting changes"
    else
        _record_fail "the non-blocking arm comments" \
            "could not find a blocking) arm paired with a comment fallback"
    fi
}

test_fixture_counts_do_not_shrink() {
    assert_equals "3 observed bodies still pinned" "3" \
        "$(ls -1 "${FIX}"/observed-none-*.md 2>/dev/null | wc -l | tr -d ' ')"
    # One of these deliberately carries a bullet and NO file:line. Without it
    # the list-item rule is redundant with the file:line rule and deleting it
    # fails no cell — measured.
    assert_equals "4 derived blocking bodies still pinned" "4" \
        "$(ls -1 "${FIX}"/derived-blocking-*.md 2>/dev/null | wc -l | tr -d ' ')"
}

assert_test_functions_wired "$0"

test_preconditions
test_observed_none_bodies_classify_none
test_all_three_renderings_are_present_in_the_corpus
test_derived_blocking_bodies_classify_blocking
test_ambiguous_and_absent_classify_unknown
test_classifier_never_exits_nonzero
test_workflow_only_submits_a_review_on_blocking
test_unknown_does_not_request_changes
test_fixture_counts_do_not_shrink

print_summary
