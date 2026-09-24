#!/usr/bin/env bash
# tests/test-placement-check-content.sh — #264
#
# A control that exists is not a control that applies. Measured 2026-09-18: a
# control written for a correctly-identified residual risk hashed ONE designated
# element of an artifact against a frozen fixture, while the risk lived in a
# DIFFERENT region of the same file. An artifact carrying a real account
# identifier in a visible table passed and exited 0; two further bypasses
# followed. Nine tasks of red-first testing and mutation verification ran past
# it, because every cell varied the contents of the inspected element and
# nothing probed outside it. The rigor was real and entirely inside the wrong
# boundary — and the sensitive data happened to be absent from the machine, so
# the placement was unfalsifiable rather than merely unverified.
#
# This file asserts skills/agent-safety-review/SKILL.md carries the mechanical
# check. It is a content test by necessity: whether a reviewer actually performs
# the comparison is behavioural, and #264's A/B contract covers that with an
# eval pack at variance 5. Presence is the deterministic floor, the same bar
# tests/test-skill-anatomy.sh sets.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

SKILL="${PROJECT_ROOT}/skills/agent-safety-review/SKILL.md"

_has() { grep -qi -- "$1" "${SKILL}"; }
_line_of() { grep -ni -- "$1" "${SKILL}" | head -1 | cut -d: -f1; }

test_skill_is_readable() {
    if [ -r "${SKILL}" ]; then
        _record_pass "skills/agent-safety-review/SKILL.md is readable"
    else
        _record_fail "skills/agent-safety-review/SKILL.md is readable" \
            "missing — every cell below would be vacuous"
    fi
}

test_threat_and_control_regions_are_written_separately() {
    # Writing one sentence about "the control covers the risk" is the state
    # that already failed. The two regions have to be named independently
    # before they can be compared.
    if _has 'threat region' && _has 'control region'; then
        _record_pass "the step names a threat region and a control region separately"
    else
        _record_fail "the step names both regions separately" \
            "a single combined sentence asserts the overlap instead of checking it"
    fi
}

test_control_region_is_what_it_reads_not_what_it_is_called() {
    # The measured failure: the control's NAME described the whole artifact
    # while it read one element of it.
    if _has 'what it reads' || _has 'actually.*inspect'; then
        _record_pass "the control region is defined by what the control reads"
    else
        _record_fail "the control region is defined by what it reads" \
            "defining it by intent or name re-certifies the exact control that failed"
    fi
}

test_overlap_must_be_stated_explicitly() {
    # "State whether they overlap" is not enough: the direction matters (the
    # control's region must CONTAIN the threat's, not merely touch it), and so
    # does the consequence of a miss.
    if _has 'contains region 1' && _has 'the control does not apply'; then
        _record_pass "the step requires containment and names the consequence of a miss"
    else
        _record_fail "the step requires containment and names the consequence" \
            "without the direction and the consequence, two regions are listed side by side and nothing follows"
    fi
}

test_not_looked_at_question_is_present() {
    if _has 'does this check NOT look at'; then
        _record_pass "the skill asks what the check does NOT look at"
    else
        _record_fail "the skill asks what the check does NOT look at" \
            "\"does it work?\" only ever tests the region already inspected"
    fi
}

test_not_looked_at_is_asked_before_does_it_work() {
    # Ordering is the mechanism. Asked second, it is a postscript to a
    # conclusion already reached.
    local n w
    n="$(_line_of 'does this check NOT look at')"
    w="$(_line_of 'does this check work')"
    if [ -n "${n}" ] && [ -n "${w}" ] && [ "${n}" -lt "${w}" ]; then
        _record_pass "the NOT-look-at question is ordered before \"does this check work?\""
    else
        _record_fail "the NOT-look-at question comes first" \
            "not-look-at at line ${n:-none}, does-it-work at ${w:-none} — asked second it changes no decision"
    fi
}

test_unvalidated_against_clause_exists() {
    if _has 'unvalidated-against'; then
        _record_pass "the skill defines an unvalidated-against disposition"
    else
        _record_fail "the skill defines an unvalidated-against disposition" \
            "with no vocabulary for it, an unexercisable threat is reported as holding"
    fi
}

test_unvalidated_is_not_reportable_as_holding() {
    # The whole cost of the measured incident was that "the controls stay as
    # designed" silently became "the controls hold".
    if _has 'not.*report it as holding' || _has 'Absent evidence is not evidence of absence'; then
        _record_pass "an unvalidated control may not be reported as holding"
    else
        _record_fail "an unvalidated control may not be reported as holding" \
            "naming the state without forbidding the claim leaves the false all-clear available"
    fi
}

test_output_template_carries_the_fields() {
    # A step with no artifact fields is advice: nothing in the produced risk
    # assessment would be missing if it were skipped.
    if _has 'Threat region:' && _has 'Control region:' && _has 'Not looked at:'; then
        _record_pass "the risk-assessment template carries the placement fields"
    else
        _record_fail "the risk-assessment template carries the placement fields" \
            "without output fields the step leaves no trace and cannot be seen to be skipped"
    fi
}

test_step_is_ordered_between_mitigation_and_risk_assessment() {
    # Placed after the assessment is produced, the check cannot change it.
    local mit place assess
    mit="$(_line_of '^## Step 3: Recommend Mitigation')"
    place="$(_line_of '^## Step 3b: Placement check')"
    assess="$(_line_of '^## Step 4: Produce Risk Assessment')"
    if [ -n "${mit}" ] && [ -n "${place}" ] && [ -n "${assess}" ] \
       && [ "${mit}" -lt "${place}" ] && [ "${place}" -lt "${assess}" ]; then
        _record_pass "the placement check runs after mitigation and before the assessment"
    else
        _record_fail "the placement check is ordered between mitigation and assessment" \
            "mitigation ${mit:-none}, placement ${place:-none}, assessment ${assess:-none}"
    fi
}

test_no_control_means_unmitigated_not_silence() {
    # PR review: the template block read as unconditional, which invites
    # boilerplate "N/A" rows on assessments where no control was discussed.
    # Scoping it is right — but the escape must be CLOSED, or "claim no
    # control" becomes the way to skip the step. A risk with no claimed control
    # is reported UNMITIGATED, and silence is explicitly not the third option.
    if _has 'no control to place' && _has 'unmitigated' && _has 'Saying\s*$' ; then
        _record_pass "a risk with no claimed control is reported unmitigated, not silently"
    elif _has 'no control to place' && _has 'reported as \*\*unmitigated\*\*'; then
        _record_pass "a risk with no claimed control is reported unmitigated, not silently"
    else
        _record_fail "a risk with no claimed control is reported unmitigated" \
            "without this, scoping the block to claimed controls makes 'claim nothing' the way to skip the check"
    fi
}

test_skill_is_readable
test_no_control_means_unmitigated_not_silence
test_threat_and_control_regions_are_written_separately
test_control_region_is_what_it_reads_not_what_it_is_called
test_overlap_must_be_stated_explicitly
test_not_looked_at_question_is_present
test_not_looked_at_is_asked_before_does_it_work
test_unvalidated_against_clause_exists
test_unvalidated_is_not_reportable_as_holding
test_output_template_carries_the_fields
test_step_is_ordered_between_mitigation_and_risk_assessment

print_summary
