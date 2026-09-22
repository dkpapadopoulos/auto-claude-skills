#!/usr/bin/env bash
# tests/test-miner-staleness.sh — #138
#
# A proposal whose intervention target was already removed wastes the human gate
# and skews the kill counter — which is the miner's own decommission signal, so a
# stale presentation does not merely cost a review, it corrupts the instrument
# that decides whether the miner should exist.
#
# Measured in the miner's first run: 1 of 2 presented proposals was stale (#125,
# whose target had been removed by PR #34).
#
# IT RECURRED WHILE THIS WAS UNIMPLEMENTED, which is why the fix is a gate and
# not a reminder in prose. A 2026-09-19 proposal (#266) cited a live divergence
# that had been REPAIRED hours after filing, and the metric it prescribed
# produced a false positive on the only case it named. Neither was visible
# without re-checking at HEAD.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

MINE="${PROJECT_ROOT}/skills/improvement-miner/scripts/mine-evidence.sh"

_probe() { /bin/bash "${MINE}" target-at-head "$@" >/dev/null 2>&1; echo $?; }

test_probe_exists() {
    if [ -r "${MINE}" ] && grep -q 'target-at-head)' "${MINE}"; then
        _record_pass "mine-evidence.sh exposes target-at-head"
    else
        _record_fail "mine-evidence.sh exposes target-at-head" \
            "not found — every cell below would be vacuous"
    fi
}

test_present_target_passes() {
    local rc; rc="$(_probe "${MINE}")"
    [ "${rc}" = "0" ] && _record_pass "an existing target returns 0" \
        || _record_fail "an existing target returns 0" "got ${rc}"
}

test_absent_target_is_stale() {
    local rc; rc="$(_probe "${PROJECT_ROOT}/hooks/removed-by-some-old-pr.sh")"
    [ "${rc}" = "1" ] && _record_pass "an absent target returns 1 (stale)" \
        || _record_fail "an absent target returns 1 (stale)" "got ${rc}"
}

test_absent_anchor_is_stale() {
    # The #125 shape: the FILE survives but the cited phrase is gone. Checking
    # only for the file would have passed #125 through.
    local rc; rc="$(_probe "${MINE}" 'a phrase that is certainly not in this script')"
    [ "${rc}" = "1" ] && _record_pass "a surviving file with a vanished anchor returns 1" \
        || _record_fail "a surviving file with a vanished anchor returns 1" "got ${rc}"
}

test_present_anchor_passes() {
    # Paired control: without it, a probe that returned 1 for everything would
    # score perfectly on the two cells above.
    local rc; rc="$(_probe "${MINE}" 'target-at-head')"
    [ "${rc}" = "0" ] && _record_pass "a surviving anchor returns 0" \
        || _record_fail "a surviving anchor returns 0" "got ${rc}"
}

test_cannot_check_is_distinct() {
    # An unreadable path and an absent target are different states, and only the
    # second justifies withholding a proposal. Collapsing them would let an
    # infrastructure failure silently suppress real candidates.
    local rc; rc="$(_probe)"
    [ "${rc}" = "2" ] && _record_pass "no path given returns 2 (cannot-check), not 1" \
        || _record_fail "no path given returns 2 (cannot-check), not 1" "got ${rc}"
}

test_select_withholds_stale() {
    local out
    out="$(printf '%s' '[{"fp":"aaaa","grade":"A","meta":false,"end_user":true,"contract_complete":true,"target_at_head":false},{"fp":"bbbb","grade":"A","meta":false,"end_user":true,"contract_complete":true,"target_at_head":true}]' | /bin/bash "${MINE}" select 2>/dev/null)"
    if printf '%s' "${out}" | jq -e '[.presented[].fp] == ["bbbb"] and ([.withheld[] | select(.reason=="stale") | .fp] == ["aaaa"])' >/dev/null 2>&1; then
        _record_pass "select withholds the stale candidate and presents the live one"
    else
        _record_fail "select withholds the stale candidate" "got: ${out}"
    fi
}

test_staleness_only_withholds() {
    # The no-regression clause: staleness may withhold, never promote. A
    # candidate the meta cap already excluded must not reappear because it
    # happens to carry target_at_head.
    local out n
    out="$(printf '%s' '[{"fp":"m1","grade":"A","meta":true,"contract_complete":true,"target_at_head":true},{"fp":"m2","grade":"A","meta":true,"contract_complete":true,"target_at_head":true},{"fp":"m3","grade":"A","meta":true,"contract_complete":true,"target_at_head":true}]' | /bin/bash "${MINE}" select 2>/dev/null)"
    n="$(printf '%s' "${out}" | jq '[.presented[]] | length' 2>/dev/null)"
    if [ "${n}" = "2" ] && printf '%s' "${out}" | jq -e '[.withheld[] | select(.reason=="meta_cap")] | length == 1' >/dev/null 2>&1; then
        _record_pass "the meta cap still binds (staleness withholds, never promotes)"
    else
        _record_fail "the meta cap still binds" "presented ${n}, expected 2; out: ${out}"
    fi
}

test_probe_exists
test_present_target_passes
test_absent_target_is_stale
test_absent_anchor_is_stale
test_present_anchor_passes
test_cannot_check_is_distinct
test_select_withholds_stale
test_staleness_only_withholds

print_summary
