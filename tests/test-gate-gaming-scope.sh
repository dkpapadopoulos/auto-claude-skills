#!/usr/bin/env bash
# test-gate-gaming-scope.sh — which files the gate-gaming check is shown (#332).
#
# The check is a text match over a diff. Its caller used to pick the diff by a
# name glob ('*test*' '*spec*'), which also selects evidence bundles under docs/
# and every OpenSpec document. A skip decorator inside a string in such a file
# made the verdict `suspect`, and routing governance then denied every agent push
# with a remedy that could never succeed.
#
# A repository may now DECLARE the paths in `.verify.yml` (`gate_gaming_paths:`).
# The declaration is read from the merge-base, never from the branch; a branch that
# changes it is recorded suspect; and a declaration that cannot be applied leaves the
# check unverified instead of falling back to the glob.
#
# Every cell here drives the REAL scripts/verify-and-record.sh in a scratch
# repository and reads the verdict it wrote. Piping a diff straight into
# gate-gaming-check.sh would prove nothing: the scope is chosen by the caller, so
# such a cell passes whether or not the scoping works.
#
#   A*  no declaration at the base: today's behaviour, unchanged (incl. the #332 hit)
#   B*  declaration at the base: the RED CONTROL (a real marker on a real test is
#       still suspect) and the #332 shape (clean). Same repo, same marker text,
#       same caller; only the path differs.
#   C*  a branch that edits its own declaration is still judged by the base's
#   D*  a declaration at the base that cannot be applied: unverified, never a fallback
#   F*  a branch that CHANGES the declaration is suspect, unless it only adds paths
#   S*  odd bases: a symlinked .verify.yml, CRLF, no .verify.yml at all
#   E   an INVENTORY of this repository's declaration against the files its gate is
#       known to run. It is a tripwire, not a proof of coverage (see K1).
#   G*  the PUSH GATE's decision, end to end, over the same verdicts
#   K*  KNOWN LIMITS, measured and pinned so nobody mistakes them for coverage
#   M*  mutations of the writer, each of which must flip a named cell

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-gate-gaming-scope.sh ==="

VAR="${REPO_ROOT}/scripts/verify-and-record.sh"
GGC="${REPO_ROOT}/skills/project-verification/scripts/gate-gaming-check.sh"
GUARD="${REPO_ROOT}/hooks/openspec-guard.sh"
FIX332="${REPO_ROOT}/tests/fixtures/gate-gaming-scope/issue-332/test_hidden_runner.py"
P332="docs/plans/2026-10-04-frontier-ablation/harness/test_hidden_runner.py"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available — gate-gaming scope cells NOT run"; exit 0
fi

setup_test_env
export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"   # the writer resolves the checker and its libs from here
unset SKILL_SESSION_TOKEN
# The guard derives its token from the transcript basename ("t" -> session-t); the
# writer is pointed at the same token so both read one artifact.
TOK="session-t"
TPATH="${TEST_HOME}/t.jsonl"; touch "${TPATH}"
printf '%s' "${TOK}" > "${TEST_HOME}/.claude/.skill-session-token"
ARTIFACT="${TEST_HOME}/.claude/.skill-project-verified-${TOK}"

DECL_TESTS='gate_gaming_paths:\n  - tests/\n'

# mkbase <name> <text appended to .verify.yml, %b-expanded>
# A repository on main holding a real test file, a declared gate and a routing
# surface, then a branch `feat`. Leaves the shell inside it.
mkbase() {
    _R="${TEST_TMPDIR}/$1"
    mkdir -p "${_R}/tests" "${_R}/docs" "${_R}/config" "${_R}/skills/demo" && cd "${_R}" || return 1
    git init -q -b main . && git config user.email t@t && git config user.name t
    printf '%s\n' 'import unittest' '' 'class Calc(unittest.TestCase):' \
        '    def test_add(self):' '        self.assertEqual(1 + 1, 2)' > tests/test_calc.py
    printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n%b' "$2" > .verify.yml
    echo notes > docs/README.md
    echo '{}' > config/default-triggers.json
    echo one > skills/demo/SKILL.md
    # An assertion file the name glob does NOT select (no "test" or "spec" in its path).
    mkdir -p checks && printf '%s\n' 'def check():' '    assert 1 + 1 == 2' > checks/validate.py
    git add . && git commit -qm base && git checkout -q -b feat
}
VY_HEAD='substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n'
# set_decl <declaration text, %b-expanded> — rewrite .verify.yml on the branch and commit it.
set_decl() { printf '%b%b' "${VY_HEAD}" "$1" > .verify.yml; git add -A && git commit -qm "edit the declaration"; }

# A REAL skip marker on a REAL test: the decorator sits on a test method, in a
# file under the declared path.
add_real_skip() {
    printf '%s\n' 'import unittest' '' 'class Calc(unittest.TestCase):' \
        '    @unittest.skip("later")' \
        '    def test_add(self):' '        self.assertEqual(1 + 1, 2)' > tests/test_calc.py
    git add -A && git commit -qm "skip a test"
}
# The #332 shape: the reported file, at its reported path.
add_332_shape() {
    mkdir -p "$(dirname "${P332}")" && cp "${FIX332}" "${P332}"
    git add -A && git commit -qm "add the experiment grader's own test"
}
touch_routing() { echo two > skills/demo/SKILL.md; git add -A && git commit -qm "routing change"; }

run_var() { rm -f "${ARTIFACT}"; SKILL_SESSION_TOKEN="${TOK}" /bin/bash "${1:-${VAR}}" > "${TEST_TMPDIR}/var.out" 2>&1; }
gg()    { jq -r '.gate_gaming_status // "<absent>"' "${ARTIFACT}" 2>/dev/null || echo "<no artifact>"; }
scope() { jq -r '.gate_gaming_scope // "<absent>"'  "${ARTIFACT}" 2>/dev/null || echo "<no artifact>"; }
paths() { jq -c '.gate_gaming_paths // "<absent>"'  "${ARTIFACT}" 2>/dev/null || echo "<no artifact>"; }
change() { jq -r '.gate_gaming_scope_change // "<absent>"' "${ARTIFACT}" 2>/dev/null || echo "<no artifact>"; }

assert_file_exists "the reported file's fixture copy exists" "${FIX332}"

# The declaration parser, LIFTED from the writer and never re-typed, for the two cells
# that need to read a declaration the way the writer does (S1's precondition and E).
_parser="$(sed -n '/^_gg_declared_scope()/,/^}/p' "${VAR}")"
if [ -n "${_parser}" ]; then
    eval "${_parser}"
    _record_pass "the scope parser can be lifted from the writer"
else
    _record_fail "the scope parser can be lifted from the writer" "no _gg_declared_scope() in ${VAR}"
    _gg_declared_scope() { echo "<parser missing>"; }
fi

# --- A: no declaration at the base --------------------------------------------------
echo "== A: no declaration — today's behaviour =="
mkbase a1 '' && add_real_skip && run_var
assert_equals "A1 control: a real skip marker on a real test is suspect" "suspect" "$(gg)"
assert_equals "A1: the scope is recorded as the default glob" "default" "$(scope)"
assert_equals "A1: and so are its paths" '["*test*","*spec*",".verify.yml"]' "$(paths)"

mkbase a2 '' && add_332_shape
# PRECONDITION for every later "clean" on this shape: the detector's text match DOES
# fire on the reported file. Without it, a fixture that stopped matching would turn
# B2 green for a reason unrelated to scoping.
assert_equals "A2 precondition: the checker itself flags the reported file's diff" "suspect" \
    "$(git -c diff.mnemonicPrefix=false -c diff.noprefix=false diff main...HEAD -- docs/ | /bin/bash "${GGC}" 2>/dev/null | head -1)"
run_var
assert_equals "A2: with no declaration the #332 shape is still suspect (no change for installers)" "suspect" "$(gg)"

mkbase a3 '' && run_var
assert_equals "A3 control: an untouched branch is clean" "clean" "$(gg)"

# A check that did not run had no scope. Recording "default" for it would describe a
# diff nobody read.
mkdir -p "${TEST_TMPDIR}/a4" && cd "${TEST_TMPDIR}/a4" || exit 1
git init -q -b trunk . && git config user.email t@t && git config user.name t   # no mainline ref => no base
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n%b' "${DECL_TESTS}" > .verify.yml
mkdir tests && echo x > tests/t.txt && git add . && git commit -qm base && run_var
assert_equals "A4: with no resolvable base the check is unverified" "unverified" "$(gg)"
assert_equals "A4: and so is its scope" "unverified" "$(scope)"
assert_equals "A4: with no paths recorded" '[]' "$(paths)"

# --- B: declaration at the base -----------------------------------------------------
echo "== B: declaration at the base =="
mkbase b1 "${DECL_TESTS}" && add_real_skip && run_var
assert_equals "B1 RED CONTROL: a real skip marker on a real test is still suspect" "suspect" "$(gg)"
assert_equals "B1: the scope is recorded as declared" "declared" "$(scope)"
assert_equals "B1: with the declared paths, plus .verify.yml" '["tests/",".verify.yml"]' "$(paths)"

mkbase b2 "${DECL_TESTS}" && add_332_shape && run_var
assert_equals "B2: the #332 shape, outside the declared paths, is clean" "clean" "$(gg)"
assert_equals "B2: under a declared scope" "declared" "$(scope)"

mkbase b3 "${DECL_TESTS}" && add_332_shape && add_real_skip && run_var
assert_equals "B3: the #332 shape does not hide a real marker on the same branch" "suspect" "$(gg)"
assert_equals "B3: under a declared scope" "declared" "$(scope)"

mkbase b4 "${DECL_TESTS}"
printf '%s\n' 'import unittest' '' 'class Calc(unittest.TestCase):' \
    '    def test_add(self):' '        pass' > tests/test_calc.py
git add -A && git commit -qm "drop the assertion" && run_var
assert_equals "B4: a removed assertion under the declared paths is suspect" "suspect" "$(gg)"
assert_equals "B4: under a declared scope" "declared" "$(scope)"

mkbase b5 "${DECL_TESTS}"
printf 'substrate: local\ncommands:\n  - name: lint\n    run: echo ok\n%b' "${DECL_TESTS}" > .verify.yml
git add -A && git commit -qm "replace the tests gate" && run_var
assert_equals "B5: removing a gate entry from .verify.yml is suspect under a declared scope" "suspect" "$(gg)"
assert_equals "B5: under a declared scope" "declared" "$(scope)"
assert_equals "B5: and the declaration itself did not change" "none" "$(change)"

mkbase b6 "${DECL_TESTS}"
git mv tests/test_calc.py docs/test_calc.py && git commit -qm "move a test out of the declared paths" && run_var
assert_equals "B6: moving a test file out of the declared paths is suspect (its assertions leave the scope)" "suspect" "$(gg)"
assert_equals "B6: under a declared scope" "declared" "$(scope)"

# The declaration must not disturb the gate-command parser that shares the file.
_R="${TEST_TMPDIR}/b7"; mkdir -p "${_R}/tests" && cd "${_R}" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
printf '%s\n' 'def test_a():' '    assert True' > tests/test_a.py
printf 'substrate: local\ngate_gaming_paths:\n  # everything the runner collects\n  - tests/test_*.py\n\n  - docs/README.md\ncommands:\n  - name: tests\n    run: echo ok\n  - name: lint\n    run: exit 4\n' > .verify.yml
mkdir docs && echo notes > docs/README.md
git add . && git commit -qm base && git checkout -q -b feat
printf '%s\n' 'import pytest' '@pytest.mark.skip(reason="flaky")' 'def test_a():' '    assert True' > tests/test_a.py
git add -A && git commit -qm skip && run_var
assert_equals "B7: comments, blank lines and a glob are accepted" '["tests/test_*.py","docs/README.md",".verify.yml"]' "$(paths)"
assert_equals "B7: a real marker under a glob entry is suspect" "suspect" "$(gg)"
assert_equals "B7: the gate commands still parse beside the declaration (passed)" '["tests"]' "$(jq -c '.passed' "${ARTIFACT}" 2>/dev/null)"
assert_equals "B7: the gate commands still parse beside the declaration (failed)" '["lint"]' "$(jq -c '.failed' "${ARTIFACT}" 2>/dev/null)"

# --- C: a branch cannot change the scope it is judged by ----------------------------
echo "== C: self-exemption attempts =="
mkbase c1 ''
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\ngate_gaming_paths:\n  - docs/\n' > .verify.yml
git add -A && git commit -qm "declare a scope that leaves the tests out" && add_real_skip && run_var
assert_equals "C1: a declaration ADDED on the branch is not honoured" "default" "$(scope)"
assert_equals "C1: so the real marker it tried to leave out is suspect" "suspect" "$(gg)"

mkbase c2 "${DECL_TESTS}"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\ngate_gaming_paths:\n  - docs/\n' > .verify.yml
git add -A && git commit -qm "re-point the declared scope away from the tests" && add_real_skip && run_var
assert_equals "C2: a declaration NARROWED on the branch is not honoured" '["tests/",".verify.yml"]' "$(paths)"
assert_equals "C2: so the real marker is suspect" "suspect" "$(gg)"

mkbase c3 "${DECL_TESTS}" && add_real_skip
# Left in the working tree, not committed: the writer runs in this tree.
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\ngate_gaming_paths:\n  - docs/\n' > .verify.yml
run_var
assert_equals "C3: nor is an UNCOMMITTED edit to the declaration" '["tests/",".verify.yml"]' "$(paths)"
assert_equals "C3: so the real marker is suspect" "suspect" "$(gg)"

mkbase c4 "${DECL_TESTS}" && add_real_skip
printf '%b%b' "${VY_HEAD}" 'gate_gaming_paths:\n  - docs/\n' > .verify.yml && git add .verify.yml   # staged, not committed
run_var
assert_equals "C4: nor is a STAGED edit to the declaration" '["tests/",".verify.yml"]' "$(paths)"
assert_equals "C4: so the real marker is suspect" "suspect" "$(gg)"

# --- D: a declaration at the base that cannot be applied ------------------------------
# The check is left UNVERIFIED. It must not fall back to the name glob: Dn0-Dn2 below
# show the glob can be NARROWER than what was declared, so a fallback would read clean
# over a file the repository asked to have checked.
echo "== D: an unusable declaration at the base leaves the check unverified =="
while IFS='|' read -r _label _decl; do
    [ -n "${_label}" ] || continue
    mkbase "d-${_label}" "${_decl}" && add_real_skip && run_var
    assert_equals "D ${_label}: the scope is recorded as unusable" "unusable" "$(scope)"
    assert_equals "D ${_label}: the check is unverified, never clean" "unverified" "$(gg)"
    assert_equals "D ${_label}: and lands in could_not_verify[]" '["gate-gaming-check"]' "$(jq -c '.could_not_verify' "${ARTIFACT}" 2>/dev/null)"
    assert_contains "D ${_label}: and the writer says why" "UNUSABLE" "$(cat "${TEST_TMPDIR}/var.out")"
done <<'EOF'
exclude-magic|gate_gaming_paths:\n  - docs/\n  - :(exclude)tests/\n
short-exclude|gate_gaming_paths:\n  - docs/\n  - :!tests/\n
matches-nothing|gate_gaming_paths:\n  - test/\n
one-of-two-matches-nothing|gate_gaming_paths:\n  - docs/\n  - nope/\n
inline-list|gate_gaming_paths: [docs/]\n
empty-list|gate_gaming_paths:\n
parent-dir|gate_gaming_paths:\n  - ../outside/\n
absolute|gate_gaming_paths:\n  - /etc/\n
quoted|gate_gaming_paths:\n  - "docs/"\n
leading-dash|gate_gaming_paths:\n  - --no-index\n
with-space|gate_gaming_paths:\n  - docs/ tests/\n
declared-twice|gate_gaming_paths:\n  - docs/\ngate_gaming_paths:\n  - docs/\n
indented-junk|gate_gaming_paths:\n  - docs/\n    nested: yes\n
EOF

# Why not fall back. checks/validate.py carries an assertion and has neither "test" nor
# "spec" in its path. Every D cell above puts its marker in tests/test_calc.py, which the
# glob also selects, so none of them could tell a fallback from a refusal; these can.
drop_check() { printf '%s\n' 'def check():' '    pass' > checks/validate.py; git add -A && git commit -qm "drop the check's assertion"; }
mkbase dn0 '' && drop_check && run_var
assert_equals "Dn0 precondition: the name glob does not see this file (clean)" "clean" "$(gg)"
mkbase dn1 'gate_gaming_paths:\n  - checks/validate.py\n' && drop_check && run_var
assert_equals "Dn1 control: declared, its removed assertion is suspect" "suspect" "$(gg)"
mkbase dn2 'gate_gaming_paths:\n  - checks/validate.py\n  - nope/\n' && drop_check && run_var
assert_equals "Dn2: declared beside an entry that matches nothing, it is NOT clean" "unverified" "$(gg)"
assert_equals "Dn2: because the scope is unusable, not defaulted" "unusable" "$(scope)"

# --- F: a branch that changes the declaration ----------------------------------------
# Editing the declaration does nothing to the branch that edits it (C*), but it changes
# what every LATER branch is checked against. Without this group, narrowing the scope in
# one change and skipping a test in the next would read clean twice.
echo "== F: changing the declaration is itself suspect =="
DECL_BOTH='gate_gaming_paths:\n  - tests/\n  - docs/\n'
mkbase f1 "${DECL_BOTH}" && set_decl 'gate_gaming_paths:\n  - docs/\n' && run_var
assert_equals "F1: a branch that ONLY narrows the declaration is suspect" "suspect" "$(gg)"
assert_equals "F1: recorded as a change" "changed" "$(change)"
assert_contains "F1: and the writer names both declarations" "changes gate_gaming_paths" "$(cat "${TEST_TMPDIR}/var.out")"

mkbase f2 '' && set_decl "${DECL_TESTS}" && run_var
assert_equals "F2: ADDING a first declaration is suspect (it replaces the name glob)" "suspect" "$(gg)"
assert_equals "F2: recorded as a change" "changed" "$(change)"
assert_equals "F2: and the branch is still judged by the glob" "default" "$(scope)"

mkbase f3 "${DECL_TESTS}" && set_decl '' && run_var
assert_equals "F3: REMOVING the declaration is suspect" "suspect" "$(gg)"

mkbase f4 "${DECL_TESTS}" && set_decl "${DECL_BOTH}" && run_var
assert_equals "F4: a pure widening (no base path lost) is clean" "clean" "$(gg)"
assert_equals "F4: recorded as widened" "widened" "$(change)"

mkbase f5 "${DECL_TESTS}" && set_decl 'gate_gaming_paths:\n  - tests/\n  - nope/\n' && run_var
assert_equals "F5: a declaration made UNUSABLE on the branch is suspect" "suspect" "$(gg)"
assert_contains "F5: and the writer says which entry" "matches no file: nope/" "$(cat "${TEST_TMPDIR}/var.out")"

mkbase f6 "${DECL_BOTH}" && set_decl 'gate_gaming_paths:\n  - tests/test_calc.py\n  - docs/\n' && run_var
assert_equals "F6: replacing an entry with a narrower one is suspect, not a widening" "suspect" "$(gg)"

# The two steps, in order. Step 1 is where the narrowing is caught; step 2 is judged by
# what step 1 put on the mainline. That second half is BY DESIGN and pinned so it is not
# mistaken for protection: the declaration is trusted once a person has merged it.
mkbase f7 "${DECL_BOTH}" && set_decl 'gate_gaming_paths:\n  - docs/\n' && run_var
assert_equals "F7 step 1: the narrowing branch is suspect" "suspect" "$(gg)"
git checkout -q main && git merge -q --ff-only feat && git checkout -q -b feat2 && add_real_skip && run_var
assert_equals "F7 step 2, BY DESIGN: once merged, a later branch is judged by the narrowed scope" "clean" "$(gg)"
assert_equals "F7 step 2: which the verdict records" '["docs/",".verify.yml"]' "$(paths)"

# --- S: odd bases ---------------------------------------------------------------------
echo "== S: a symlinked .verify.yml, CRLF, and no .verify.yml at the base =="
# `git show <rev>:.verify.yml` of a symlink prints the link's TARGET TEXT. A target that
# reads like a declaration must not be honoured as one.
_R="${TEST_TMPDIR}/s1"; mkdir -p "${_R}/tests" "${_R}/docs" && cd "${_R}" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
printf '%s\n' 'import unittest' '' 'class Calc(unittest.TestCase):' \
    '    def test_add(self):' '        self.assertEqual(1 + 1, 2)' > tests/test_calc.py
echo notes > docs/README.md
ln -s "$(printf 'gate_gaming_paths:\n  - docs/')" .verify.yml
git add . && git commit -qm base && git checkout -q -b feat
rm -f .verify.yml && printf '%b' "${VY_HEAD}" > .verify.yml
assert_equals "S1 precondition: the base's .verify.yml is a symlink" "120000" \
    "$(git ls-tree main -- .verify.yml | cut -d' ' -f1)"
assert_equals "S1 precondition: and the writer's own parser reads its target text as a declaration of docs/" "ok docs/" \
    "$(git show main:.verify.yml | _gg_declared_scope | tr '\n' ' ' | sed 's/ $//')"
add_real_skip && run_var
assert_equals "S1: a symlink's target text is not read as a declaration" "default" "$(scope)"
assert_equals "S1: so the real marker is suspect" "suspect" "$(gg)"

# CRLF at the base. (The writer does not run on a CRLF .verify.yml at HEAD — its
# substrate line would not read "local" — so the branch carries the same file with LF.)
_R="${TEST_TMPDIR}/s2"; mkdir -p "${_R}/tests" "${_R}/docs" && cd "${_R}" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t && git config core.autocrlf false
printf '%s\n' 'def test_a():' '    assert True' > tests/test_a.py
printf 'substrate: local\r\ncommands:\r\n  - name: tests\r\n    run: echo ok\r\ngate_gaming_paths:\r\n  - tests/\r\n' > .verify.yml
git add . && git commit -qm base && git checkout -q -b feat
printf '%b%b' "${VY_HEAD}" "${DECL_TESTS}" > .verify.yml && git add -A && git commit -qm "LF" && run_var
assert_equals "S2: a CRLF declaration at the base is read" '["tests/",".verify.yml"]' "$(paths)"
assert_equals "S2: converting the file to LF is not a change to the declaration" "none" "$(change)"
# The status is deliberately not asserted clean: the conversion rewrites every `- name:`
# line, and the checker's gate-entry rule compares names byte for byte, so it reports the
# CR-terminated name as removed. That is the checker, and it predates the declaration.

# No .verify.yml at the base at all: the branch introduces the gate and a declaration.
_R="${TEST_TMPDIR}/s3"; mkdir -p "${_R}/tests" "${_R}/docs" && cd "${_R}" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
printf '%s\n' 'import unittest' '' 'class Calc(unittest.TestCase):' \
    '    def test_add(self):' '        self.assertEqual(1 + 1, 2)' > tests/test_calc.py
echo notes > docs/README.md
git add . && git commit -qm base && git checkout -q -b feat
printf '%b%b' "${VY_HEAD}" 'gate_gaming_paths:\n  - docs/\n' > .verify.yml && add_real_skip && run_var
assert_equals "S3: with no .verify.yml at the base the branch's declaration is not honoured" "default" "$(scope)"
assert_equals "S3: and the real marker is suspect" "suspect" "$(gg)"

# --- E: this repository's own declaration -------------------------------------------
# The declaration is only safe while it covers every file the gate runs. The gate
# here is tests/run-tests.sh, which runs tests/test-*.sh. The parser is LIFTED from
# the writer, never re-typed, so this cell reads the declaration as the writer does.
echo "== E: this repository's declaration covers what its gate runs =="
cd "${REPO_ROOT}" || exit 1
if [ -z "${_parser}" ]; then
    _record_fail "E: the scope parser is available" "it could not be lifted from ${VAR}"
else
    _own="$(_gg_declared_scope < "${REPO_ROOT}/.verify.yml")"
    assert_equals "E: this repository declares a usable scope" "ok" "$(printf '%s\n' "${_own}" | head -1)"
    _decl_paths=()
    while IFS= read -r _p; do [ -n "${_p}" ] && _decl_paths+=("${_p}"); done <<EOF
$(printf '%s\n' "${_own}" | sed 1d)
EOF
    _ran="$(git ls-files -- 'tests/test-*.sh' | grep -c .)"
    if [ "${#_decl_paths[@]}" -gt 0 ]; then
        _covered="$(git ls-files -- "${_decl_paths[@]}" | grep -c -E '^tests/test-[^/]*\.sh$')"
    else
        _covered=0
    fi
    [ "${_ran}" -ge 100 ] && _record_pass "E: population floor (${_ran} gate-run test files)" \
        || _record_fail "E: population floor" "only ${_ran} tests/test-*.sh files found"
    assert_equals "E: every file the gate runs is inside the declared paths" "${_ran}" "${_covered}"

    # tests/test-*.sh is not the whole gate: a test file may hand its assertions to a
    # script elsewhere (tests/test-db-gate-score.sh runs two under scripts/db-gate-race/,
    # found only by reading it). Nothing can list such delegations mechanically, so this
    # is a tripwire on the NAME: a tracked script outside tests/ that is named like a
    # test must be declared, or be listed below with the reason it is not one. docs/ and
    # openspec/ are left out on purpose — the gate never executes a file there, and the
    # #332 report is exactly such a file.
    _NOT_TESTS="scripts/test-shape-scan.py"   # a classifier whose OUTPUT a test asserts on; it asserts nothing itself
    _declared_files="$(git ls-files -- "${_decl_paths[@]}")"
    _named=0
    while IFS= read -r _f; do
        [ -n "${_f}" ] || continue
        _named=$((_named + 1))
        case " ${_NOT_TESTS} " in *" ${_f} "*) continue ;; esac
        if printf '%s\n' "${_declared_files}" | grep -qxF -- "${_f}"; then
            _record_pass "E: ${_f} is named like a test and is declared"
        else
            _record_fail "E: ${_f} is named like a test" "it is neither under gate_gaming_paths nor listed as a known non-test"
        fi
    done <<EOF
$(git ls-files -- '*.sh' '*.py' | grep -v -E '^(tests|docs|openspec)/' | grep -E '(^|/)test[-_][^/]*$')
EOF
    [ "${_named}" -ge 2 ] && _record_pass "E: test-named population floor (${_named} files outside tests/)" \
        || _record_fail "E: test-named population floor" "found ${_named}, expected at least 2"
    for _f in ${_NOT_TESTS}; do
        [ -f "${REPO_ROOT}/${_f}" ] && _record_pass "E: known non-test ${_f} still exists" \
            || _record_fail "E: known non-test ${_f} still exists" "stale entry — remove it from _NOT_TESTS"
    done
    for _f in scripts/db-gate-race/test-score.sh scripts/db-gate-race/validate-corpus.sh; do
        if grep -qF -- "${_f}" "${REPO_ROOT}/tests/test-db-gate-score.sh" 2>/dev/null; then
            if printf '%s\n' "${_declared_files}" | grep -qxF -- "${_f}"; then
                _record_pass "E: ${_f}, run by tests/test-db-gate-score.sh, is declared"
            else
                _record_fail "E: ${_f}, run by tests/test-db-gate-score.sh, is declared" "missing from gate_gaming_paths"
            fi
        else
            _record_fail "E: tests/test-db-gate-score.sh still runs ${_f}" "the delegation moved — re-check the declaration"
        fi
    done
fi

# --- G: the push gate's decision ----------------------------------------------------
# A verdict field nobody reads proves nothing. These drive the REAL openspec-guard.sh
# over the verdict the writer just wrote. BOTH global legs are seeded with invocation
# evidence: measured without it, a suspect verdict is denied first by the global
# fail-closed VERIFY leg (a clean verdict stands in for that evidence, a suspect one
# does not), and every cell below would pass on the wrong check. With it, routing
# governance is the only leg left that reads the verdict, and each deny must name it.
echo "== G: the push gate's decision over the same verdicts =="
jq -nc '["requesting-code-review","verification-before-completion"]' \
    > "${TEST_HOME}/.claude/.skill-invocation-evidence-${TOK}"
_push() {
    jq -nc --arg tp "${TPATH}" --arg c "git push origin HEAD" '{transcript_path:$tp, tool_input:{command:$c}}' \
    | CLAUDE_PLUGIN_ROOT="${REPO_ROOT}" /bin/bash "${GUARD}" 2>/dev/null
}

# An allow is the ABSENCE of a deny, and a guard that failed to run is also silent. So
# each allow cell first asserts the verdict it rests on, and the deny cells around it
# (same repository shape, same session state) show the guard reaching this leg.
mkbase g0 "${DECL_TESTS}" && touch_routing && run_var
assert_equals "G0 precondition: the verdict is clean" "clean" "$(gg)"
out="$(_push)"; _rc=$?
assert_equals "G0: the guard exited 0" "0" "${_rc}"
assert_not_contains "G0 control: a routing change with a clean verdict is allowed" '"deny"' "${out:-<empty>}"

mkbase g1 "${DECL_TESTS}" && touch_routing && add_real_skip && run_var
out="$(_push)"
assert_contains "G1 RED CONTROL: a real skip marker still denies the push" '"deny"' "${out:-<empty>}"
assert_contains "G1: and the denial is routing governance's" "routing governance" "${out:-<empty>}"

mkbase g2 "${DECL_TESTS}" && touch_routing && add_332_shape && run_var
assert_equals "G2 precondition: the verdict is clean" "clean" "$(gg)"
assert_equals "G2 precondition: under a declared scope" "declared" "$(scope)"
out="$(_push)"; _rc=$?
assert_equals "G2: the guard exited 0" "0" "${_rc}"
assert_not_contains "G2: the #332 shape no longer denies the push under a declared scope" '"deny"' "${out:-<empty>}"

mkbase g3 '' && touch_routing && add_332_shape && run_var
out="$(_push)"
assert_contains "G3: with no declaration the #332 shape denies as before" "routing governance" "${out:-<empty>}"

mkbase g4 "${DECL_TESTS}" && touch_routing
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\ngate_gaming_paths:\n  - docs/\n' > .verify.yml
git add -A && git commit -qm "re-point the declared scope" && add_real_skip && run_var
out="$(_push)"
assert_contains "G4: a branch that re-points its own scope and skips a test is still denied" "routing governance" "${out:-<empty>}"

mkbase g5 "${DECL_BOTH}" && touch_routing && set_decl 'gate_gaming_paths:\n  - docs/\n' && run_var
out="$(_push)"
assert_contains "G5: a routing branch that only narrows the declaration is denied" "routing governance" "${out:-<empty>}"

mkbase g6 'gate_gaming_paths:\n  - tests/\n  - nope/\n' && touch_routing && run_var
out="$(_push)"
assert_contains "G6: an unusable declaration at the base denies a routing push (unverified is not clean)" "routing governance" "${out:-<empty>}"

# --- K: known limits ------------------------------------------------------------------
# Each of these reads CLEAN over a real weakening. They are asserted so that the limit
# is on the record with a measurement, and so that closing one of them later shows up as
# a failing cell to be updated on purpose.
echo "== K: KNOWN LIMITS (each reads clean over a real weakening) =="

# K1. A declaration is a claim about where the gate's tests live. A branch can add a
# NEW test file outside the declared paths and pull it into a file inside them. Group E
# cannot see this: it is an inventory of files that already exist.
# What this cell MEASURES is the checker's blindness: the old glob reports the new file's
# marker and the declared scope does not. It does not measure a loss of executed coverage
# — the scratch gate is `echo ok` and runs no test. The import below is the shape a
# unittest loader would collect (a TestCase subclass in the importing module's namespace),
# so the blind spot is reachable; that it is reached is an argument, not a measurement.
k1_wire() {
    printf '%s\n' 'import unittest' '' 'class Extra(unittest.TestCase):' \
        '    @unittest.skip("later")' '    def test_more(self):' '        self.assertEqual(2 + 2, 4)' > docs/test_extra.py
    printf '%s\n' 'import unittest' 'from docs.test_extra import Extra' '' 'class Calc(unittest.TestCase):' \
        '    def test_add(self):' '        self.assertEqual(1 + 1, 2)' > tests/test_calc.py
    git add -A && git commit -qm "add a test outside the declared paths and import it"
}
mkbase k1a '' && k1_wire && run_var
assert_equals "K1 control: under the name glob the new file's marker is reported" "suspect" "$(gg)"
mkbase k1b "${DECL_TESTS}" && k1_wire && run_var
assert_equals "K1 KNOWN LIMIT: under a declared scope it is not reported" "clean" "$(gg)"

# K2. The base is resolved from local refs. Whoever can move the mainline ref chooses
# the base, and with it the declaration. K2a is the ceiling that predates this change
# (the diff empties under the name glob too); K2b is the same primitive reaching a
# narrowed declaration at an intermediate commit.
mkbase k2a '' && add_real_skip && git branch -f main HEAD && run_var
assert_equals "K2a KNOWN LIMIT, pre-existing: with the mainline ref moved to HEAD the diff is empty" "clean" "$(gg)"
mkbase k2b "${DECL_BOTH}" && set_decl 'gate_gaming_paths:\n  - docs/\n' && git branch -f main HEAD && add_real_skip && run_var
assert_equals "K2b KNOWN LIMIT: with the mainline ref moved onto a narrowing commit, a later marker is unseen" "clean" "$(gg)"
assert_equals "K2b: the verdict records the scope it was judged by" '["docs/",".verify.yml"]' "$(paths)"

# --- M: mutations of the writer -----------------------------------------------------
# Each mutant is the real writer with ONE thing changed; CLAUDE_PLUGIN_ROOT still
# points at the real checkout, so nothing else moves. `cmp` proves the edit landed —
# "the mutant behaves differently" is equally true of a sed that matched nothing.
echo "== M: mutations =="
_mutant() {   # <name> <sed expression> -> path of the mutated writer, or empty
    local m="${TEST_TMPDIR}/mutant-$1.sh"
    sed "$2" "${VAR}" > "${m}"
    if cmp -s "${VAR}" "${m}"; then echo ""; else echo "${m}"; fi
}

# M1: read the declaration from the working tree instead of the base.
M1="$(_mutant worktree-read 's#git -C "\$ROOT" show "\${rev}:.verify.yml" 2>/dev/null#cat "\$ROOT/.verify.yml" 2>/dev/null#')"
if [ -z "${M1}" ]; then
    _record_fail "M1: the base-read mutation applies" "sed changed nothing"
else
    mkbase m1 "${DECL_TESTS}"
    printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\ngate_gaming_paths:\n  - docs/\n' > .verify.yml
    git add -A && git commit -qm "re-point the declared scope" && add_real_skip && run_var "${M1}"
    assert_equals "M1: reading the declaration from the branch lets C2's marker through (so C2 holds the base read)" "clean" "$(gg)"
fi

# M2: drop .verify.yml from a declared scope.
M2="$(_mutant drop-verify-yml 's#GG_PATHS=("\${_gg_paths\[@\]}" ".verify.yml")#GG_PATHS=("\${_gg_paths[@]}")#')"
if [ -z "${M2}" ]; then
    _record_fail "M2: the drop-.verify.yml mutation applies" "sed changed nothing"
else
    mkbase m2 "${DECL_TESTS}"
    printf 'substrate: local\ncommands:\n  - name: lint\n    run: echo ok\n%b' "${DECL_TESTS}" > .verify.yml
    git add -A && git commit -qm "replace the tests gate" && run_var "${M2}"
    assert_equals "M2: without .verify.yml in a declared scope B5's gate removal reads clean (so B5 holds it)" "clean" "$(gg)"
fi

# M3: accept a declared path that matches nothing at the base.
M3="$(_mutant no-match-check 's#git -C "\$ROOT" diff --name-only "\$empty" "\$rev" -- "\$p" 2>/dev/null#echo present#')"
if [ -z "${M3}" ]; then
    _record_fail "M3: the matches-nothing mutation applies" "sed changed nothing"
else
    mkbase m3 'gate_gaming_paths:\n  - test/\n' && add_real_skip && run_var "${M3}"
    assert_equals "M3: honouring a path that matches nothing blinds the check (so D matches-nothing holds it)" "clean" "$(gg)"
fi

# M4: accept any entry text, pathspec magic included.
M4="$(_mutant no-entry-validation 's#if (p !~ "^\[A-Za-z0-9._/\*-\]+\$" || p ~ "^\[-/\]" || p ~ "(^|/)\[.\]\[.\](/|\$)") {#if (0) {#')"
if [ -z "${M4}" ]; then
    _record_fail "M4: the entry-validation mutation applies" "sed changed nothing"
else
    mkbase m4 'gate_gaming_paths:\n  - docs/\n  - :(exclude)tests/\n' && add_real_skip && run_var "${M4}"
    assert_equals "M4: honouring an exclude entry hides the real marker (so D exclude-magic holds the validation)" "clean" "$(gg)"
fi

# M5: stop recording a changed declaration as suspect.
M5="$(_mutant no-change-rule 's#\[ "\$GG_STATUS" = "clean" \] && GG_STATUS="suspect"#:#')"
if [ -z "${M5}" ]; then
    _record_fail "M5: the change-rule mutation applies" "sed changed nothing"
else
    mkbase m5 "${DECL_BOTH}" && set_decl 'gate_gaming_paths:\n  - docs/\n' && run_var "${M5}"
    assert_equals "M5: without the change rule a narrowing-only branch reads clean (so F1 holds it)" "clean" "$(gg)"
fi

# M6: read a symlinked .verify.yml at the base as if it were a file.
M6="$(_mutant no-mode-check 's#\*) echo "none"; return 0 ;;#"skip-mode-check") ;;#')"
if [ -z "${M6}" ]; then
    _record_fail "M6: the mode-check mutation applies" "sed changed nothing"
else
    _R="${TEST_TMPDIR}/m6"; mkdir -p "${_R}/tests" "${_R}/docs" && cd "${_R}" || exit 1
    git init -q -b main . && git config user.email t@t && git config user.name t
    printf '%s\n' 'def test_a():' '    assert True' > tests/test_a.py
    echo notes > docs/README.md
    ln -s "$(printf 'gate_gaming_paths:\n  - docs/')" .verify.yml
    git add . && git commit -qm base && git checkout -q -b feat
    rm -f .verify.yml && printf '%b' "${VY_HEAD}" > .verify.yml && git add -A && git commit -qm "a real gate file" && run_var "${M6}"
    assert_equals "M6: without the mode check the symlink's target text becomes the scope (so S1 holds it)" "declared" "$(scope)"
fi

# M7: fall back to the name glob when the base's declaration cannot be applied.
M7="$(_mutant fallback 's#GG_SCOPE="unusable"; _gg_run=false#GG_SCOPE="default"#')"
if [ -z "${M7}" ]; then
    _record_fail "M7: the fallback mutation applies" "sed changed nothing"
else
    mkbase m7 'gate_gaming_paths:\n  - checks/validate.py\n  - nope/\n' && drop_check && run_var "${M7}"
    assert_equals "M7: a fallback reads clean over the declared check's removed assertion (so Dn2 holds the refusal)" "clean" "$(gg)"
fi

cd "${REPO_ROOT}" || true
teardown_test_env
print_summary
