#!/usr/bin/env bash
# test-verify-and-record.sh — deterministic verdict writer.
# Red-first core: a FAILING declared gate must be recorded as failed:[name],
# never laundered to clean. Everything runs in fixture repos under an
# isolated HOME so no real verdict artifact is touched.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

VAR="${REPO_ROOT}/scripts/verify-and-record.sh"

setup_test_env
export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"   # script resolves gate-gaming-check from the plugin root
# The script honors an inherited SKILL_SESSION_TOKEN over the token file (#122),
# and the project-verification skill tells callers to pass exactly that (#51) —
# so running this suite from inside such a verification run redirected every
# verdict away from $ARTIFACT and failed 20 asserts. T11 sets it per-invocation.
unset SKILL_SESSION_TOKEN
printf 'session-vartest' > "${TEST_HOME}/.claude/.skill-session-token"
ARTIFACT="${TEST_HOME}/.claude/.skill-project-verified-session-vartest"

# mkrepo <dir> — init a fixture repo on main with one commit; echoes resolved root
mkrepo() {
    mkdir -p "$1" && cd "$1" || return 1
    git init -q -b main . && git config user.email t@t && git config user.name t
    echo x > f.txt && git add . && git commit -qm base
    git rev-parse --show-toplevel
}

echo "== script exists and parses (bash 3.2) =="
assert_file_exists "script exists at scripts/verify-and-record.sh" "${VAR}"
/bin/bash -n "${VAR}" 2>/dev/null && _record_pass "parses under /bin/bash" \
    || _record_fail "parses under /bin/bash" "syntax error or missing"

echo "== T1 (red core): failing gate recorded as failed, never clean =="
R1="$(mkrepo "${TEST_TMPDIR}/r1")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: exit 3\n' > "${R1}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R1}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
rc=$?
assert_equals "script exits 0 when a FAILING verdict was recorded" "0" "${rc}"
assert_file_exists "failing verdict artifact written" "${ARTIFACT}"
assert_equals "failing command lands in failed[]" '["tests"]' "$(jq -c '.failed' "${ARTIFACT}")"
assert_equals "failing verdict has empty passed[]" '[]' "$(jq -c '.passed' "${ARTIFACT}")"

echo "== T2: passing gate — clean, sha-bound, measured =="
R2="$(mkrepo "${TEST_TMPDIR}/r2")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n' > "${R2}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R2}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_equals "passing command lands in passed[]" '["tests"]' "$(jq -c '.passed' "${ARTIFACT}")"
assert_equals "no failures" '[]' "$(jq -c '.failed' "${ARTIFACT}")"
assert_equals "nothing unverifiable" '[]' "$(jq -c '.could_not_verify' "${ARTIFACT}")"
# empty review diff (single commit, merge-base HEAD main = HEAD) => checker prints clean
assert_equals "gate-gaming measured clean" "clean" "$(jq -r '.gate_gaming_status' "${ARTIFACT}")"
assert_equals "sha binds to the TARGET repo HEAD" "$(cd "${R2}" && git rev-parse HEAD)" "$(jq -r '.sha' "${ARTIFACT}")"
assert_equals "writer provenance field present" "verify-and-record.sh" "$(jq -r '.writer' "${ARTIFACT}")"
assert_equals "substrate recorded" "local" "$(jq -r '.substrate' "${ARTIFACT}")"

echo "== T3: unrunnable command (127) is could_not_verify, never a pass =="
R3="$(mkrepo "${TEST_TMPDIR}/r3")"
printf 'substrate: local\ncommands:\n  - name: types\n    run: definitely-not-a-cmd-xyz --check\n' > "${R3}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R3}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_equals "127 command in could_not_verify[]" '["types"]' "$(jq -c '.could_not_verify' "${ARTIFACT}")"
assert_equals "127 command not in passed[]" '[]' "$(jq -c '.passed' "${ARTIFACT}")"

echo "== T4: no .verify.yml — refuse, write nothing =="
R4="$(mkrepo "${TEST_TMPDIR}/r4")"
rm -f "${ARTIFACT}"
( cd "${R4}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
rc=$?
[ "${rc}" -ne 0 ] && _record_pass "non-zero exit without .verify.yml" \
    || _record_fail "non-zero exit without .verify.yml" "got exit 0"
[ ! -f "${ARTIFACT}" ] && _record_pass "no verdict written without a declared gate" \
    || _record_fail "no verdict written without a declared gate" "artifact exists"

echo "== T5: non-local substrate — refuse, write nothing =="
R5="$(mkrepo "${TEST_TMPDIR}/r5")"
printf 'substrate: docker\ncommands:\n  - name: tests\n    run: echo ok\n' > "${R5}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R5}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
rc=$?
[ "${rc}" -ne 0 ] && _record_pass "non-zero exit on non-local substrate" \
    || _record_fail "non-zero exit on non-local substrate" "got exit 0"
[ ! -f "${ARTIFACT}" ] && _record_pass "no verdict written on non-local substrate" \
    || _record_fail "no verdict written on non-local substrate" "artifact exists"

echo "== T6: multiple commands — mixed results recorded per-command =="
R6="$(mkrepo "${TEST_TMPDIR}/r6")"
printf 'substrate: local\ncommands:\n  - name: lint\n    run: echo ok\n  - name: tests\n    run: exit 1\n' > "${R6}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R6}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_equals "mixed run: lint passed" '["lint"]' "$(jq -c '.passed' "${ARTIFACT}")"
assert_equals "mixed run: tests failed" '["tests"]' "$(jq -c '.failed' "${ARTIFACT}")"

echo "== T7: unrunnable gate-gaming check — unverified, never clean =="
R7="$(mkrepo "${TEST_TMPDIR}/r7")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n' > "${R7}/.verify.yml"
rm -f "${ARTIFACT}"
mkdir -p "${TEST_TMPDIR}/emptyplugin"
( cd "${R7}" && CLAUDE_PLUGIN_ROOT="${TEST_TMPDIR}/emptyplugin" /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_equals "missing checker => gate_gaming unverified" "unverified" "$(jq -r '.gate_gaming_status' "${ARTIFACT}")"
assert_equals "missing checker lands in could_not_verify[]" '["gate-gaming-check"]' "$(jq -c '.could_not_verify' "${ARTIFACT}")"

echo "== T8: unresolvable diff base — unverified, never clean =="
mkdir -p "${TEST_TMPDIR}/r8" && cd "${TEST_TMPDIR}/r8" || exit 1
git init -q -b trunk . && git config user.email t@t && git config user.name t
echo x > f.txt && git add . && git commit -qm base   # no main/master, no upstream
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n' > .verify.yml
rm -f "${ARTIFACT}"
/bin/bash "${VAR}" >/dev/null 2>&1
assert_equals "no mainline base => gate_gaming unverified" "unverified" "$(jq -r '.gate_gaming_status' "${ARTIFACT}")"

echo "== T9: declared name without run: — could_not_verify, not dropped =="
R9="$(mkrepo "${TEST_TMPDIR}/r9")"
printf 'substrate: local\ncommands:\n  - name: lint\n  - name: tests\n    run: echo ok\n' > "${R9}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R9}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_equals "run-less name lands in could_not_verify[]" '["lint"]' "$(jq -c '.could_not_verify' "${ARTIFACT}")"
assert_equals "paired command still measured" '["tests"]' "$(jq -c '.passed' "${ARTIFACT}")"

echo "== T10 (issue #122): token captured BEFORE the gate loop — mid-run rewrite doesn't rebind =="
# A concurrent session rebinds the shared singleton mid-suite. Simulate that with
# a gate command that overwrites ~/.claude/.skill-session-token, then verify the
# verdict still lands under the START-of-run token, not the sibling's.
R10="$(mkrepo "${TEST_TMPDIR}/r10")"
SIBLING_ARTIFACT="${TEST_HOME}/.claude/.skill-project-verified-session-sibling"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: printf session-sibling > "%s/.claude/.skill-session-token"; echo ok\n' "${TEST_HOME}" > "${R10}/.verify.yml"
printf 'session-vartest' > "${TEST_HOME}/.claude/.skill-session-token"   # start-of-run token
rm -f "${ARTIFACT}" "${SIBLING_ARTIFACT}"
( cd "${R10}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_file_exists "verdict binds to START-of-run token despite mid-run rewrite" "${ARTIFACT}"
[ ! -f "${SIBLING_ARTIFACT}" ] && _record_pass "no verdict leaked under the sibling (mid-run) token" \
    || _record_fail "no verdict leaked under the sibling (mid-run) token" "verdict written to sibling-token artifact"
printf 'session-vartest' > "${TEST_HOME}/.claude/.skill-session-token"   # restore for any later cases

echo "== T11 (issue #122): explicit SKILL_SESSION_TOKEN env overrides the token file =="
R11="$(mkrepo "${TEST_TMPDIR}/r11")"
EXPLICIT_ARTIFACT="${TEST_HOME}/.claude/.skill-project-verified-payload-tok"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n' > "${R11}/.verify.yml"
printf 'file-token' > "${TEST_HOME}/.claude/.skill-session-token"
rm -f "${EXPLICIT_ARTIFACT}" "${TEST_HOME}/.claude/.skill-project-verified-file-token"
( cd "${R11}" && SKILL_SESSION_TOKEN=payload-tok /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_file_exists "explicit env token binds the verdict" "${EXPLICIT_ARTIFACT}"
[ ! -f "${TEST_HOME}/.claude/.skill-project-verified-file-token" ] && _record_pass "file token ignored when env token given" \
    || _record_fail "file token ignored when env token given" "verdict written under the file token"
printf 'session-vartest' > "${TEST_HOME}/.claude/.skill-session-token"   # restore

echo "== T12 (issue #156): own-session token beats the shared singleton =="
# The singleton is last-writer-wins across concurrent sessions, so a verdict
# bound to it lands under a FOREIGN conversation's token. The push gate reads
# payload-first, finds nothing under its own token, and can then only be
# rescued by the cross-token bridge — which is EXACT-HEAD only, silently
# downgrading the own-token ancestor acceptance the routing-governance leg
# depends on. CLAUDE_CODE_SESSION_ID names this conversation and equals the
# transcript basename readers derive their token from.
_OWN_ID="var-own-11111111"
_OWN_ARTIFACT="${TEST_HOME}/.claude/.skill-project-verified-session-${_OWN_ID}"
_SINGLETON_ARTIFACT="${TEST_HOME}/.claude/.skill-project-verified-session-foreign"
R12="$(mkrepo "${TEST_TMPDIR}/r12")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n' > "${R12}/.verify.yml"
mkdir -p "${TEST_HOME}/.claude/projects/-var-proj"
: > "${TEST_HOME}/.claude/projects/-var-proj/${_OWN_ID}.jsonl"
printf 'session-foreign' > "${TEST_HOME}/.claude/.skill-session-token"
rm -f "${_OWN_ARTIFACT}" "${_SINGLETON_ARTIFACT}"
( cd "${R12}" && CLAUDE_CODE_SESSION_ID="${_OWN_ID}" /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_file_exists "verdict binds to the OWN session token" "${_OWN_ARTIFACT}"
[ ! -f "${_SINGLETON_ARTIFACT}" ] && _record_pass "verdict did NOT scatter into the foreign singleton token" \
    || _record_fail "verdict did NOT scatter into the foreign singleton token" "verdict written under the singleton"

echo "== T13 (issue #156): unverifiable / unsafe / absent session id falls back to the singleton =="
# A session id with no transcript on disk is stale, foreign, or injected —
# it must never bind a verdict. Same degradation for a path-unsafe id and for
# no id at all (pre-fix behaviour, unchanged).
rm -f "${_SINGLETON_ARTIFACT}"
( cd "${R12}" && CLAUDE_CODE_SESSION_ID="var-nosuch-22222222" /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_file_exists "session id with no transcript falls back to the singleton" "${_SINGLETON_ARTIFACT}"

rm -f "${_SINGLETON_ARTIFACT}"
( cd "${R12}" && CLAUDE_CODE_SESSION_ID="../../evil" /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_file_exists "path-unsafe session id falls back to the singleton" "${_SINGLETON_ARTIFACT}"
[ ! -f "${TEST_HOME}/evil" ] && [ ! -f "${TEST_HOME}/.claude/projects/evil" ] \
    && _record_pass "path-unsafe session id escaped no file out of ~/.claude" \
    || _record_fail "path-unsafe session id escaped no file out of ~/.claude" "artifact written outside ~/.claude"

rm -f "${_SINGLETON_ARTIFACT}"
( cd "${R12}" && env -u CLAUDE_CODE_SESSION_ID /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_file_exists "absent session id falls back to the singleton" "${_SINGLETON_ARTIFACT}"

echo "== T14 (issue #156): SKILL_SESSION_TOKEN still outranks the own-session id =="
# The explicit override is the #122 contract and must stay highest precedence.
_T14_ARTIFACT="${TEST_HOME}/.claude/.skill-project-verified-explicit-tok"
rm -f "${_T14_ARTIFACT}" "${_OWN_ARTIFACT}" "${_SINGLETON_ARTIFACT}"
( cd "${R12}" && CLAUDE_CODE_SESSION_ID="${_OWN_ID}" SKILL_SESSION_TOKEN=explicit-tok /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_file_exists "explicit env token outranks the own-session id" "${_T14_ARTIFACT}"
[ ! -f "${_OWN_ARTIFACT}" ] && _record_pass "own-session id ignored when an explicit token is given" \
    || _record_fail "own-session id ignored when an explicit token is given" "verdict written under the derived token"

echo "== T15 (issue #156): missing session-token.sh degrades to the singleton =="
# session-token.sh owns the token FORMAT; without it the script must fall back
# to the singleton, never to a locally re-derived shape that could drift.
_LONE_ROOT="${TEST_TMPDIR}/lone-plugin"
mkdir -p "${_LONE_ROOT}/hooks/lib"
rm -f "${_OWN_ARTIFACT}" "${_SINGLETON_ARTIFACT}"
( cd "${R12}" && CLAUDE_PLUGIN_ROOT="${_LONE_ROOT}" CLAUDE_CODE_SESSION_ID="${_OWN_ID}" /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_file_exists "missing session-token.sh degrades to the singleton" "${_SINGLETON_ARTIFACT}"
[ ! -f "${_OWN_ARTIFACT}" ] && _record_pass "no locally re-derived token shape when the lib is absent" \
    || _record_fail "no locally re-derived token shape when the lib is absent" "verdict written under a re-derived token"

rm -rf "${TEST_HOME}/.claude/projects"
printf 'session-vartest' > "${TEST_HOME}/.claude/.skill-session-token"   # restore

cd "${REPO_ROOT}" || true
teardown_test_env
print_summary
