#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-coverage-adequacy.sh ==="

CAC="${PROJECT_ROOT}/skills/project-verification/scripts/coverage-adequacy-check.sh"
assert_file_exists "coverage-adequacy-check.sh exists" "${CAC}"

# _changed_lines: added lines get new-file line numbers; deletions do not advance.
diff_in="$(printf '%s\n' \
  '--- a/src/foo.py' \
  '+++ b/src/foo.py' \
  '@@ -1,3 +1,4 @@' \
  ' import os' \
  '+def added():' \
  '+    return 1' \
  ' x = 1')"
out_cl="$(printf '%s' "${diff_in}" | COVERAGE_ADEQUACY_MODE=changed-lines bash "${CAC}" 2>/dev/null)"
assert_contains "added def line 2 reported" "src/foo.py	2" "${out_cl}"
assert_contains "added return line 3 reported" "src/foo.py	3" "${out_cl}"
assert_not_contains "context line not reported" "src/foo.py	4" "${out_cl}"

# --- lcov lookup ---
mkdir -p "${PROJECT_ROOT}/tests/fixtures/coverage"
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/sample.lcov" <<'LCOV'
SF:/repo/src/foo.py
DA:2,0
DA:3,5
DA:4,1
end_of_record
LCOV
lc="$(COVERAGE_ADEQUACY_MODE=lcov-hits COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/sample.lcov" bash "${CAC}" </dev/null 2>/dev/null)"
assert_contains "lcov line 2 hits 0"  "/repo/src/foo.py	2	0" "${lc}"
assert_contains "lcov line 3 hits 5"  "/repo/src/foo.py	3	5" "${lc}"

# --- verdict: suspect when changed lines uncovered ---
diff3="$(printf '%s\n' \
  '--- a/src/foo.py' '+++ b/src/foo.py' '@@ -1,1 +1,3 @@' \
  ' import os' '+def added():' '+    return 1')"
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/foo-uncovered.lcov" <<'LCOV'
SF:src/foo.py
DA:2,0
DA:3,0
end_of_record
LCOV
v_susp="$(printf '%s' "${diff3}" | COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/foo-uncovered.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "uncovered changed lines are suspect" "suspect" "${v_susp}"
assert_contains "suspect cites the uncovered line" "src/foo.py:2" "${v_susp}"

# --- verdict: clean when changed lines covered above floor ---
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/foo-covered.lcov" <<'LCOV'
SF:src/foo.py
DA:2,3
DA:3,3
end_of_record
LCOV
v_clean="$(printf '%s' "${diff3}" | COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/foo-covered.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "covered changed lines are clean" "clean" "${v_clean}"

# --- verdict: unverified when no artifact ---
v_unv="$(printf '%s' "${diff3}" | COVERAGE_ADEQUACY_LCOV="/nonexistent.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "no artifact is unverified" "unverified" "${v_unv}"

# --- verdict: unverified when changed lines have no coverage overlap (all non-code) ---
diff_docs="$(printf '%s\n' '--- a/README.md' '+++ b/README.md' '@@ -1,0 +1,1 @@' '+new docs line')"
v_noov="$(printf '%s' "${diff_docs}" | COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/foo-covered.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "no coverable overlap is unverified" "unverified" "${v_noov}"

# --- deletion does not inflate new-file line numbers (Task-1 path regression) ---
diff_del="$(printf '%s\n' '--- a/src/foo.py' '+++ b/src/foo.py' '@@ -1,3 +1,2 @@' ' import os' '-old_line = 1' '+new_line = 2')"
out_del="$(printf '%s' "${diff_del}" | COVERAGE_ADEQUACY_MODE=changed-lines bash "${CAC}" 2>/dev/null)"
assert_contains "added line after deletion is line 2" "src/foo.py	2" "${out_del}"
assert_not_contains "deletion did not inflate to line 3" "src/foo.py	3" "${out_del}"

# --- cobertura/coverage.py XML support (Task 4) ---
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/sample-cobertura.xml" <<'XML'
<coverage><packages><package><classes>
<class filename="src/foo.py"><lines>
<line number="2" hits="0"/><line number="3" hits="4"/>
</lines></class></classes></package></packages></coverage>
XML
xh="$(COVERAGE_ADEQUACY_MODE=cobertura-hits COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/sample-cobertura.xml" bash "${CAC}" </dev/null 2>/dev/null)"
assert_contains "cobertura line 2 hits 0" "src/foo.py	2	0" "${xh}"
assert_contains "cobertura line 3 hits 4" "src/foo.py	3	4" "${xh}"

# end-to-end: xml artifact drives verdict
v_xml="$(printf '%s' "${diff3}" | COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/sample-cobertura.xml" bash "${CAC}" 2>/dev/null)"
assert_contains "xml uncovered line 2 is suspect" "suspect" "${v_xml}"

# --- absolute SF path must suffix-match a relative diff path (load-bearing join branch) ---
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/foo-abs.lcov" <<'LCOV'
SF:/repo/src/foo.py
DA:2,3
DA:3,3
end_of_record
LCOV
v_abs="$(printf '%s' "${diff3}" | COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/foo-abs.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "absolute SF path suffix-matches relative diff path" "clean" "${v_abs}"

# --- unrelated path must NOT spuriously suffix-match => unverified ---
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/other.lcov" <<'LCOV'
SF:other/notsrc/foo.py
DA:2,3
DA:3,3
end_of_record
LCOV
v_nomatch="$(printf '%s' "${diff3}" | COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/other.lcov" bash "${CAC}" 2>/dev/null)"
assert_contains "non-suffix path does not match (unverified)" "unverified" "${v_nomatch}"

# --- compact cobertura: two <line> on one physical line must each emit exactly once ---
cat > "${PROJECT_ROOT}/tests/fixtures/coverage/compact-cobertura.xml" <<'XML'
<coverage><packages><package><classes><class filename="src/bar.py"><lines><line number="2" hits="0"/><line number="3" hits="4"/></lines></class></classes></package></packages></coverage>
XML
ch="$(COVERAGE_ADEQUACY_MODE=cobertura-hits COVERAGE_ADEQUACY_LCOV="${PROJECT_ROOT}/tests/fixtures/coverage/compact-cobertura.xml" bash "${CAC}" </dev/null 2>/dev/null)"
count_l2="$(printf '%s\n' "${ch}" | grep -c 'src/bar.py	2	0')"
assert_equals "compact cobertura line 2 emitted exactly once" "1" "${count_l2}"
count_l3="$(printf '%s\n' "${ch}" | grep -c 'src/bar.py	3	4')"
assert_equals "compact cobertura line 3 emitted exactly once" "1" "${count_l3}"

print_summary
exit $?
