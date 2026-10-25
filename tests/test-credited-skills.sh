#!/usr/bin/env bash
# test-credited-skills.sh — hooks/lib/credited-skills.sh single-sources the
# REVIEW-credited skill names and the review-coverage rule (reviewed sha is an
# ancestor of the subject and no material source file changed between them).
# Bash 3.2; real throwaway git repo for the coverage cells; jq not needed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

LIB="${PROJECT_ROOT}/hooks/lib/credited-skills.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
STALE="${PROJECT_ROOT}/hooks/lib/staleness-delta.sh"

echo "=== test-credited-skills.sh ==="

# Lift the exact docs-exclusion `case` pattern text from a file by anchor.
_pattern_of() {
    # $1 file, $2 anchor regex; prints the first `docs/*|...` alternation after it
    ANCHOR_RE="$2" awk '
        $0 ~ ENVIRON["ANCHOR_RE"] { on=1 }
        on && match($0, /docs\/\*\|[^)]*\)/) { print substr($0, RSTART, RLENGTH); exit }
    ' "$1"
}

test_lib_exists() {
    if [ -f "${LIB}" ]; then _record_pass "lib exists"
    else _record_fail "lib exists" "missing ${LIB}"; fi
}

test_c1_credited_names() {
    local n p
    . "${LIB}" 2>/dev/null
    for n in requesting-code-review subagent-driven-development agent-team-execution agent-team-review code-review review-pr security-review; do
        credited_review_skill "$n" 2>/dev/null
        assert_equals "C1 bare ${n} credited" "0" "$?"
    done
    credited_review_skill "superpowers:requesting-code-review" 2>/dev/null
    assert_equals "C1 prefixed requesting-code-review" "0" "$?"
    credited_review_skill "pr-review-toolkit:review-pr" 2>/dev/null
    assert_equals "C1 prefixed review-pr" "0" "$?"
    for p in "x:agent-team-review" "a:b:security-review"; do
        credited_review_skill "$p" 2>/dev/null
        assert_equals "C1 prefixed ${p}" "0" "$?"
    done
}

test_c2_near_misses() {
    local n
    . "${LIB}" 2>/dev/null
    for n in verification-before-completion receiving-code-review code-reviewer review code-review-x xcode-review simplify executing-plans "" "requesting-code-review:" "code-review review-pr" "agent-team-execution agent-team-review" " code-review" "code-review " "Code-Review" "code-review;x"; do
        credited_review_skill "$n" 2>/dev/null
        assert_equals "C2 near-miss '${n}' not credited" "1" "$?"
    done
}

test_c3_builtin() {
    local n
    . "${LIB}" 2>/dev/null
    for n in code-review security-review; do
        credited_review_builtin "$n" 2>/dev/null
        assert_equals "C3 builtin ${n}" "0" "$?"
    done
    for n in superpowers:code-review review-pr requesting-code-review ""; do
        credited_review_builtin "$n" 2>/dev/null
        assert_equals "C3 non-builtin '${n}'" "1" "$?"
    done
}

test_c4_coverage() {
    local R A B C G rc
    . "${LIB}" 2>/dev/null
    R="${TEST_TMPDIR}/repo"
    mkdir -p "$R" && cd "$R" || return
    git init -q -b main . 2>/dev/null || git init -q .
    git config user.email t@t; git config user.name t
    echo base > base.txt; git add base.txt; git commit -q -m base
    git checkout -q -b f
    echo a > src.sh; git add src.sh; git commit -q -m A; A="$(git rev-parse HEAD)"
    mkdir -p docs openspec; echo d > docs/a.md; echo o > openspec/x.txt; echo r > README.md
    git add docs openspec README.md; git commit -q -m B; B="$(git rev-parse HEAD)"
    echo b >> src.sh; git add src.sh; git commit -q -m C; C="$(git rev-parse HEAD)"
    git checkout -q main; git checkout -q -b g
    echo g > g.sh; git add g.sh; git commit -q -m G; G="$(git rev-parse HEAD)"
    git checkout -q f
    cd "$PROJECT_ROOT" || return

    review_sha_covers "$A" "$R" "$B" 2>/dev/null; assert_equals "C4 docs-only delta covered" "0" "$?"
    review_sha_covers "$B" "$R" "$B" 2>/dev/null; assert_equals "C4 same sha covered" "0" "$?"
    review_sha_covers "$A" "$R" "$C" 2>/dev/null; assert_equals "C4 source delta uncovered" "1" "$?"
    review_sha_covers "$G" "$R" "$C" 2>/dev/null; assert_equals "C4 non-ancestor uncovered" "1" "$?"
    review_sha_covers "zzz" "$R" "$C" 2>/dev/null; assert_equals "C4 non-hex sha cannot-check" "2" "$?"
    review_sha_covers "0123456789012345678901234567890123456789" "$R" "$C" 2>/dev/null
    assert_equals "C4 unknown 40-hex cannot-check" "2" "$?"
    review_sha_covers "$A" "/nonexistent" "$C" 2>/dev/null; assert_equals "C4 bad root cannot-check" "2" "$?"
    review_sha_covers "-x" "$R" "$C" 2>/dev/null; assert_equals "C4 option-shaped sha cannot-check" "2" "$?"
    review_sha_covers "$(printf '%s' "$A" | tr a-f A-F)" "$R" "$B" 2>/dev/null
    assert_equals "C4 uppercase sha cannot-check" "2" "$?"
    review_sha_covers "abcdef0" "$R" "$B" 2>/dev/null; assert_equals "C4 unknown short sha cannot-check" "2" "$?"
    review_sha_covers "$A" "$R" "no-such-rev" 2>/dev/null; assert_equals "C4 invalid non-empty rev cannot-check" "2" "$?"
    review_sha_covers "$A" "$R" "--output=/tmp/x" 2>/dev/null; assert_equals "C4 option-shaped rev cannot-check" "2" "$?"
    review_sha_covers "${A%"${A#???????}"}" "$R" "$B" 2>/dev/null; assert_equals "C4 unambiguous 7-char sha covered" "0" "$?"
    rc="$(review_sha_covers "$A" "$R" "$B" 2>&1)"
    assert_equals "C4 prints nothing" "" "$rc"
}

test_c5_parity() {
    local mine g s
    mine="$(_pattern_of "${LIB}" 'review_sha_covers\(\)')"
    g="$(_pattern_of "${GUARD}" '^ *_names_touch_material_source\(\) \{')"
    s="$(_pattern_of "${STALE}" '^staleness_delta_is_docs\(\)')"
    assert_not_empty "C5 lib pattern extracted" "$mine"
    assert_not_empty "C5 guard pattern extracted" "$g"
    assert_equals "C5 lib == guard docs pattern" "$g" "$mine"
    assert_equals "C5 lib == staleness docs pattern" "$s" "$mine"
}

test_c6_nounset() {
    local out
    out="$(bash -u -c ". '${LIB}'; credited_review_skill; credited_review_builtin; review_sha_covers; echo survived" 2>/dev/null </dev/null)"
    assert_contains "C6 set -u survives empty args" "survived" "$out"
}

test_c7_quiet_source() {
    local out rc
    out="$( ( . "${LIB}" ) </dev/null 2>&1 )"; rc=$?
    assert_equals "C7 sourcing prints nothing" "" "$out"
    assert_equals "C7 sourcing exits 0" "0" "$rc"
}

setup_test_env
test_lib_exists
test_c1_credited_names
test_c2_near_misses
test_c3_builtin
test_c4_coverage
test_c5_parity
test_c6_nounset
test_c7_quiet_source
teardown_test_env
assert_test_functions_wired "$0"
print_summary
