#!/usr/bin/env bash
# tests/test-ruling-propagation-content.sh — #265
#
# A ruling that changes a NOT-YET-DISPATCHED task has no propagation path. The
# Mini-Spec is synthesized from the plan; nothing carries a progress ledger into
# the plan. So a ruling recorded in the ledger READS AS DONE and is ABSENT from
# the run — worse than forgetting it, because the record is what stops you
# checking.
#
# Observed twice in one session (2026-09-19). In the first, a ruling that a task
# must gain a capture step that fails on identical outputs never reached the
# brief; three parties each accepted a test that exits 0 on skip because "the
# step existed" — it existed in the ledger. The lesson was written down after
# that instance and still not applied to two rulings three lines above it.
#
# This file asserts the SKILL.md carries the mechanical check. It is a content
# test by necessity: whether a lead actually performs it is behavioural, and
# #265's A/B contract covers that with an eval pack at variance 5. Presence is
# the deterministic floor, the same bar tests/test-skill-anatomy.sh sets.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

SKILL="${PROJECT_ROOT}/skills/agent-team-execution/SKILL.md"

_has() { grep -qi -- "$1" "${SKILL}"; }

test_skill_is_readable() {
    if [ -r "${SKILL}" ]; then
        _record_pass "skills/agent-team-execution/SKILL.md is readable"
    else
        _record_fail "skills/agent-team-execution/SKILL.md is readable" \
            "missing — every cell below would be vacuous"
    fi
}

test_ruling_must_reach_the_dispatch_artifact() {
    if _has 'dispatch artifact'; then
        _record_pass "the skill names the dispatch artifact as the propagation target"
    else
        _record_fail "the skill names the dispatch artifact" \
            "a ruling with no stated target lands in a ledger and never reaches the brief"
    fi
}

test_recording_is_not_sufficient() {
    # The failure mode is precisely that recording FEELS like completing.
    if _has 'step one of two' || _has 'does not propagate'; then
        _record_pass "the skill states that recording alone does not propagate"
    else
        _record_fail "the skill states that recording alone does not propagate" \
            "without this the ledger reads as done, which is the defect"
    fi
}

test_check_is_on_the_text_being_sent() {
    # Checking the RECORD reproduces the bug: the record is what is already
    # wrong. The check has to be on the outgoing dispatch text.
    if _has 'text that will actually be sent' || _has 'text being sent'; then
        _record_pass "the pre-dispatch check is on the text being sent, not the record"
    else
        _record_fail "the pre-dispatch check is on the text being sent" \
            "a check against the record cannot detect a ruling missing from the brief"
    fi
}

test_post_dispatch_path_is_distinguished() {
    # A ruling made AFTER dispatch has a different, already-documented route.
    # Collapsing the two would tell a lead to edit a brief already sent.
    if _has 're-announce' && _has 'shared-contracts.md'; then
        _record_pass "the post-dispatch path is distinguished from the pre-dispatch one"
    else
        _record_fail "the post-dispatch path is distinguished" \
            "the two cases need different handling; conflating them sends a lead to edit a dispatched brief"
    fi
}

test_setup_phase_orders_propagation_before_spawn() {
    # Ordering is the whole mechanism: propagating after spawning is a no-op.
    local prop spawn
    prop="$(grep -n 'Propagate every ruling' "${SKILL}" | head -1 | cut -d: -f1)"
    spawn="$(grep -n 'Spawn specialists' "${SKILL}" | head -1 | cut -d: -f1)"
    if [ -n "${prop}" ] && [ -n "${spawn}" ] && [ "${prop}" -lt "${spawn}" ]; then
        _record_pass "propagation is ordered before specialists are spawned"
    else
        _record_fail "propagation is ordered before spawning" \
            "propagate at line ${prop:-none}, spawn at ${spawn:-none} — after the spawn it is a no-op"
    fi
}

test_skill_is_readable
test_ruling_must_reach_the_dispatch_artifact
test_recording_is_not_sufficient
test_check_is_on_the_text_being_sent
test_post_dispatch_path_is_distinguished
test_setup_phase_orders_propagation_before_spawn

print_summary
