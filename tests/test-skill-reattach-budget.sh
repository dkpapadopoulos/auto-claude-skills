#!/usr/bin/env bash
# test-skill-reattach-budget.sh — every owned SKILL.md fits the post-compaction
# re-attach budget (openspec/changes/skill-reattach-budget).
#
# After a compaction Claude Code re-attaches each invoked skill cut to its first
# 20,000 characters, so anything later in a long SKILL.md is gone for the rest of
# the session. The cut counts characters including a ~110-145-character
# base-directory header and the frontmatter is stripped first, so a file of at
# most 19,500 BYTES (bytes are at least characters) survives whole.
#
# Skills not yet split sit on a pending list whose ceiling is an EQUALITY
# ratchet, like INCIDENT_SKILL_WORD_BASELINE: it must equal the file's current
# byte size. A pending skill that grows fails; one that shrinks fails until its
# ceiling is lowered in the same commit, so slack is never banked for regrowth;
# and one that drops under the budget while still listed fails too, so the list
# cannot outlive the work it tracks.
#
# Every cell below, the real-tree one included, calls the SAME check function;
# the controls only change its inputs (a scratch skills dir, a scratch list).
# Bash 3.2 compatible.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-skill-reattach-budget.sh ==="

REATTACH_BUDGET_BYTES=19500

# One "<skill> <ceiling-bytes>" per line, each ceiling equal to that SKILL.md's
# current `wc -c`. Remove an entry in the same commit that splits the skill;
# lower a ceiling in the same commit that shrinks the skill; never raise one.
REATTACH_PENDING="incident-analysis 83053
alert-hygiene 65670
agent-team-review 47871
runtime-validation 23790"

# Owned skills at the time of writing; the real-tree cell fails below this.
REATTACH_MIN_SKILLS=20

# _reattach_is_ceiling <value> — succeeds only for a count `[ -gt ]` can always
# evaluate: digits only, no leading zero, at most 8 digits. An unbounded count
# (20 digits) makes the comparison error out, and with no `set -e` that error
# falls through as "not over" — a parse failure turned into a silent pass.
_reattach_is_ceiling() {
    case "${1:-}" in
        ''|*[!0-9]*|0*|?????????*) return 1 ;;
    esac
    return 0
}

# _reattach_violations <skills-dir> <pending-list> <min-skills>
#
# Prints one `VIOLATION: ...` line per problem, nothing when clean, and a final
# `CHECKED <n>`. Records nothing itself, so the controls can call it on scratch
# input and assert on exactly what it reports.
_reattach_violations() {
    local _dir="$1" _pending="$2" _min="$3" _f _name _bytes _ceil _n=0 _line _pname _pceil _seen=" "
    # The list is validated before it is used: a ceiling that `[ -gt ]` cannot
    # evaluate makes the comparison error out and fall through as "not over".
    while IFS= read -r _line || [ -n "${_line}" ]; do
        [ -z "${_line}" ] && continue
        _pname="${_line%% *}"
        _pceil="${_line#* }"
        _reattach_is_ceiling "${_pceil}" || \
            echo "VIOLATION: pending entry '${_line}' has no valid byte ceiling"
        # A second line for the same skill would be ignored (the lookup below
        # takes the first), so a stale duplicate could sit in the list unseen.
        case "${_seen}" in
            *" ${_pname} "*) echo "VIOLATION: pending entry '${_pname}' is listed more than once — keep one line" ;;
        esac
        _seen="${_seen}${_pname} "
        [ -f "${_dir}/${_pname}/SKILL.md" ] || \
            echo "VIOLATION: pending entry '${_pname}' names no ${_dir}/${_pname}/SKILL.md — remove it from the pending list"
    done <<EOF
${_pending}
EOF
    for _f in "${_dir}"/*/SKILL.md; do
        [ -f "${_f}" ] || continue
        _n=$((_n + 1))
        _name="$(basename "$(dirname "${_f}")")"
        _bytes="$(wc -c < "${_f}" | tr -d ' ')"
        _ceil="$(printf '%s\n' "${_pending}" | awk -v n="${_name}" '$1 == n { print $2; exit }')"
        _reattach_is_ceiling "${_ceil}" || _ceil=""
        if [ -n "${_ceil}" ]; then
            if [ "${_bytes}" -gt "${_ceil}" ]; then
                echo "VIOLATION: ${_f} is ${_bytes} bytes, over its pending ceiling of ${_ceil} — a pending skill may not grow"
            elif [ "${_bytes}" -le "${REATTACH_BUDGET_BYTES}" ]; then
                echo "VIOLATION: ${_f} is ${_bytes} bytes, within the ${REATTACH_BUDGET_BYTES}-byte budget — remove it from the pending list"
            elif [ "${_bytes}" -lt "${_ceil}" ]; then
                echo "VIOLATION: ${_f} is ${_bytes} bytes, under its pending ceiling of ${_ceil} — lower the ceiling to ${_bytes}"
            fi
        elif [ "${_bytes}" -gt "${REATTACH_BUDGET_BYTES}" ]; then
            echo "VIOLATION: ${_f} is ${_bytes} bytes, over the ${REATTACH_BUDGET_BYTES}-byte re-attach budget"
        fi
    done
    # FLOOR: a glob that matches nothing checks nothing, and would otherwise
    # report a clean pass.
    [ "${_n}" -lt "${_min}" ] && \
        echo "VIOLATION: checked ${_n} SKILL.md files under ${_dir}, floor ${_min} — the glob is not seeing the skills, so a pass would be vacuous"
    echo "CHECKED ${_n}"
}

# _scratch_skill <dir> <name> <bytes> — a SKILL.md of exactly <bytes> bytes,
# built from a real one so the controls exercise real content.
_scratch_skill() {
    mkdir -p "$1/$2"
    {
        cat "${PROJECT_ROOT}/skills/security-scanner/SKILL.md"
        awk 'BEGIN { for (i = 0; i < 200000; i++) printf "x" }'
    } | head -c "$3" > "$1/$2/SKILL.md"
}

_violations_of() { printf '%s\n' "$1" | grep '^VIOLATION: ' || true; }
_checked_of() { printf '%s\n' "$1" | sed -n 's/^CHECKED //p'; }

test_real_tree_fits_budget() {
    local _out _v _n
    _out="$(_reattach_violations "${PROJECT_ROOT}/skills" "${REATTACH_PENDING}" "${REATTACH_MIN_SKILLS}")"
    _v="$(_violations_of "${_out}")"
    _n="$(_checked_of "${_out}")"
    # Gate on the sentinel's PRESENCE: a function that aborted partway prints
    # no violations either, and must not read as clean.
    if case "${_n}" in ''|*[!0-9]*) true ;; *) false ;; esac; then
        _record_fail "owned skills fit the re-attach budget" \
            "the check printed no CHECKED count ('${_n}') — it did not run to its end, so the absence of violations means nothing"
    elif [ -n "${_v}" ]; then
        _record_fail "owned skills fit the re-attach budget (${_n} checked)" "${_v}"
    else
        _record_pass "owned skills fit the re-attach budget (${_n} checked, pending: $(printf '%s\n' "${REATTACH_PENDING}" | awk '{print $1}' | tr '\n' ' '))"
    fi
}

test_control_over_budget_fails_naming_file_and_size() {
    local _d="${TEST_TMPDIR}/over" _out
    _scratch_skill "${_d}" fits 19500
    _scratch_skill "${_d}" too-big 19501
    _out="$(_reattach_violations "${_d}" "" 1)"
    assert_contains "red control: a 19,501-byte non-pending SKILL.md is named with its size" \
        "VIOLATION: ${_d}/too-big/SKILL.md is 19501 bytes, over the 19500-byte re-attach budget" "${_out}"
    assert_not_contains "control: a 19,500-byte SKILL.md is within the budget" \
        "${_d}/fits/SKILL.md" "${_out}"
}

test_control_pending_skill_that_grows_fails() {
    local _d="${TEST_TMPDIR}/grows" _out
    _scratch_skill "${_d}" big-skill 47900
    _out="$(_reattach_violations "${_d}" "big-skill 47871" 1)"
    assert_contains "red control: a pending skill grown past its ceiling fails" \
        "is 47900 bytes, over its pending ceiling of 47871" "${_out}"
}

test_control_pending_skill_that_shrinks_must_lower_ceiling() {
    local _d="${TEST_TMPDIR}/shrinks" _out
    _scratch_skill "${_d}" big-skill 47000
    _out="$(_reattach_violations "${_d}" "big-skill 47871" 1)"
    assert_contains "red control: a pending skill that shrinks fails until its ceiling is lowered" \
        "${_d}/big-skill/SKILL.md is 47000 bytes, under its pending ceiling of 47871 — lower the ceiling to 47000" "${_out}"
}

test_control_shrink_with_ceiling_lowered_passes() {
    local _d="${TEST_TMPDIR}/lowered" _out
    _scratch_skill "${_d}" big-skill 47000
    _scratch_skill "${_d}" other 30000
    _out="$(_reattach_violations "${_d}" "big-skill 47000
other 30000" 1)"
    assert_equals "control: pending skills whose ceilings equal their sizes pass" \
        "" "$(_violations_of "${_out}")"
}

test_control_unbounded_ceiling_fails() {
    local _d="${TEST_TMPDIR}/unbounded" _out _err="${TEST_TMPDIR}/unbounded.err"
    _scratch_skill "${_d}" present 30000
    _out="$(_reattach_violations "${_d}" "present 99999999999999999999" 1 2>"${_err}")"
    assert_contains "red control: a 20-digit ceiling is rejected, not compared" \
        "pending entry 'present 99999999999999999999' has no valid byte ceiling" "${_out}"
    assert_contains "red control: with an unbounded ceiling the skill is held to the budget" \
        "${_d}/present/SKILL.md is 30000 bytes, over the 19500-byte re-attach budget" "${_out}"
    assert_equals "control: no comparison errored on stderr" "" "$(cat "${_err}")"
}

test_control_duplicate_pending_entry_fails() {
    local _d="${TEST_TMPDIR}/dup" _out
    _scratch_skill "${_d}" big 20000
    _out="$(_reattach_violations "${_d}" "big 90000
big 20000" 1)"
    assert_contains "red control: a pending entry listed twice is named" \
        "pending entry 'big' is listed more than once" "${_out}"
}

test_control_pending_skill_under_budget_must_leave_list() {
    local _d="${TEST_TMPDIR}/split" _out
    _scratch_skill "${_d}" was-split 18000
    _out="$(_reattach_violations "${_d}" "was-split 22289" 1)"
    assert_contains "red control: a pending skill now within the budget fails until delisted" \
        "${_d}/was-split/SKILL.md is 18000 bytes, within the 19500-byte budget — remove it from the pending list" "${_out}"
}

test_control_stale_or_malformed_pending_entry_fails() {
    local _d="${TEST_TMPDIR}/stale" _out
    _scratch_skill "${_d}" present 30000
    _out="$(_reattach_violations "${_d}" "present 30000
gone-skill 40000" 1)"
    assert_contains "red control: a pending entry naming no skill fails" \
        "pending entry 'gone-skill' names no" "${_out}"
    _out="$(_reattach_violations "${_d}" "present 3O000" 1)"
    assert_contains "red control: a pending ceiling that is not a count fails" \
        "pending entry 'present 3O000' has no valid byte ceiling" "${_out}"
    assert_contains "red control: with no valid ceiling the skill is held to the budget" \
        "${_d}/present/SKILL.md is 30000 bytes, over the 19500-byte re-attach budget" "${_out}"
}

test_control_empty_glob_fails_the_floor() {
    local _d="${TEST_TMPDIR}/empty" _out
    mkdir -p "${_d}"
    _out="$(_reattach_violations "${_d}" "" "${REATTACH_MIN_SKILLS}")"
    assert_contains "red control: a skills dir the glob finds nothing in fails the floor" \
        "VIOLATION: checked 0 SKILL.md files under ${_d}, floor ${REATTACH_MIN_SKILLS}" "${_out}"
}

setup_test_env

test_real_tree_fits_budget
test_control_over_budget_fails_naming_file_and_size
test_control_pending_skill_that_grows_fails
test_control_pending_skill_that_shrinks_must_lower_ceiling
test_control_shrink_with_ceiling_lowered_passes
test_control_unbounded_ceiling_fails
test_control_duplicate_pending_entry_fails
test_control_pending_skill_under_budget_must_leave_list
test_control_stale_or_malformed_pending_entry_fails
test_control_empty_glob_fails_the_floor

teardown_test_env

print_summary
