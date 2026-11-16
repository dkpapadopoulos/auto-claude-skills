#!/usr/bin/env bash
# test-verify-receipt.sh — the receipt rendered from a recorded verdict.
# Every verdict here is written by the REAL scripts/verify-and-record.sh in a
# fixture repo under an isolated HOME; the few cells that need a state the
# writer cannot produce on demand edit a real artifact with jq and say so.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

VAR="${REPO_ROOT}/scripts/verify-and-record.sh"
RCPT="${REPO_ROOT}/scripts/verify-receipt.sh"

setup_test_env
export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"
# Both outrank the token file in the writer and the reader, so an inherited
# value would send every verdict away from $ARTIFACT.
unset SKILL_SESSION_TOKEN CLAUDE_CODE_SESSION_ID
printf 'session-rcpt' > "${TEST_HOME}/.claude/.skill-session-token"
ARTIFACT="${TEST_HOME}/.claude/.skill-project-verified-session-rcpt"

# mkrepo <dir> — fixture repo on main with one commit; echoes its root
mkrepo() {
    mkdir -p "$1" && cd "$1" || return 1
    git init -q -b main . && git config user.email t@t && git config user.name t
    echo x > f.txt && git add . && git commit -qm base
    git rev-parse --show-toplevel
}
# record <repo> <writer args…> — run the real writer
record() { local r="$1"; shift; ( cd "$r" && /bin/bash "${VAR}" "$@" >/dev/null 2>&1 < /dev/null ); }
# render <dir> — sets OUT, ERR, RC
render() {
    OUT="$( cd "$1" && /bin/bash "${RCPT}" 2>"${TEST_TMPDIR}/err" < /dev/null )"; RC=$?
    ERR="$(cat "${TEST_TMPDIR}/err")"
}
# edit_artifact <jq filter> — rewrite the real artifact in place
edit_artifact() { jq "$1" "${ARTIFACT}" > "${ARTIFACT}.e" && mv "${ARTIFACT}.e" "${ARTIFACT}"; }
# line_of <fixed string> — first line number of it in OUT, or 0
line_of() { local n; n="$(printf '%s\n' "${OUT}" | grep -nF -- "$1" | head -1 | cut -d: -f1)"; printf '%s' "${n:-0}"; }
assert_empty() { [ -z "$2" ] && _record_pass "$1" || _record_fail "$1" "expected empty, got: '$2'"; }

echo "== R0: script exists and parses (bash 3.2) =="
assert_file_exists "script exists at scripts/verify-receipt.sh" "${RCPT}"
/bin/bash -n "${RCPT}" 2>/dev/null && _record_pass "parses under /bin/bash" \
    || _record_fail "parses under /bin/bash" "syntax error or missing"

echo "== R1: clean measured verdict at HEAD =="
R1="$(mkrepo "${TEST_TMPDIR}/r1")"
rm -f "${ARTIFACT}"
record "${R1}" --name unit --run true --name lint --run true
H1="$(git -C "${R1}" rev-parse HEAD)"
render "${R1}"
assert_equals "clean verdict: exit 0" "0" "${RC}"
assert_equals "first line is the marker with the full sha and result=pass" \
    "<!-- acs-verify-receipt v1 sha=${H1} result=pass -->" "$(printf '%s\n' "${OUT}" | head -1)"
assert_contains "heading says PASS" "### Local verification: PASS" "${OUT}"
assert_contains "unit listed as passed" "| unit | passed |" "${OUT}"
assert_contains "lint listed as passed" "| lint | passed |" "${OUT}"
assert_contains "commit named in full" "- Commit: \`${H1}\`" "${OUT}"
assert_contains "provenance says explicit" "(explicit)" "${OUT}"
assert_contains "gate-gaming status shown" "- Gate-gaming check: clean" "${OUT}"
assert_contains "says it is not CI" "not CI" "${OUT}"
assert_contains "recorded time is the artifact's ts" "- Recorded: $(jq -r '.ts' "${ARTIFACT}") " "${OUT}"

echo "== R2: a failing verdict is rendered, failed first =="
R2="$(mkrepo "${TEST_TMPDIR}/r2")"
rm -f "${ARTIFACT}"
record "${R2}" --name unit --run true --name e2e --run 'exit 3'
render "${R2}"
assert_equals "failing verdict: exit 0 (a receipt was rendered)" "0" "${RC}"
assert_contains "marker carries result=fail" " result=fail -->" "$(printf '%s\n' "${OUT}" | head -1)"
assert_contains "heading says FAIL" "### Local verification: FAIL" "${OUT}"
assert_contains "e2e named as FAILED" "| e2e | FAILED |" "${OUT}"
assert_contains "unit still listed as passed" "| unit | passed |" "${OUT}"
_lf="$(line_of '| e2e | FAILED |')"; _lp="$(line_of '| unit | passed |')"
[ "${_lf}" -gt 0 ] && [ "${_lf}" -lt "${_lp}" ] && _record_pass "failed row precedes passed row" \
    || _record_fail "failed row precedes passed row" "failed at ${_lf}, passed at ${_lp}"

echo "== R3: a check that could not run =="
R3="$(mkrepo "${TEST_TMPDIR}/r3")"
rm -f "${ARTIFACT}"
record "${R3}" --name types --run definitely-not-a-cmd-xyz
render "${R3}"
assert_equals "could-not-run verdict: exit 0" "0" "${RC}"
assert_contains "marker carries result=could-not-verify" " result=could-not-verify -->" "$(printf '%s\n' "${OUT}" | head -1)"
assert_contains "heading says COULD NOT VERIFY" "### Local verification: COULD NOT VERIFY" "${OUT}"
assert_contains "types named as could not run" "| types | could not run |" "${OUT}"

echo "== R4: HEAD moved after verification =="
R4="$(mkrepo "${TEST_TMPDIR}/r4")"
rm -f "${ARTIFACT}"
record "${R4}" --name unit --run true
V4="$(git -C "${R4}" rev-parse HEAD)"
git -C "${R4}" commit --allow-empty -qm next
N4="$(git -C "${R4}" rev-parse HEAD)"
render "${R4}"
assert_equals "moved HEAD: exit 1" "1" "${RC}"
assert_empty "moved HEAD: stdout empty" "${OUT}"
assert_contains "moved HEAD: stderr names the verified sha" "${V4}" "${ERR}"
assert_contains "moved HEAD: stderr names the current sha" "${N4}" "${ERR}"

echo "== R5: verdict measured on a dirty tree =="
R5="$(mkrepo "${TEST_TMPDIR}/r5")"
rm -f "${ARTIFACT}"
echo y >> "${R5}/f.txt"
record "${R5}" --name unit --run true
assert_equals "precondition: the writer recorded a dirty tree" "true" "$(jq -r '.worktree_dirty' "${ARTIFACT}" 2>/dev/null)"
render "${R5}"
assert_equals "dirty tree: exit 1" "1" "${RC}"
assert_empty "dirty tree: stdout empty" "${OUT}"
assert_contains "dirty tree: stderr says uncommitted" "uncommitted" "${ERR}"

echo "== R6: no verdict recorded — refuse, write nothing =="
R6="$(mkrepo "${TEST_TMPDIR}/r6")"
rm -f "${ARTIFACT}"
_before="$(ls -A "${TEST_HOME}/.claude")"
render "${R6}"
assert_equals "no verdict: exit 1" "1" "${RC}"
assert_empty "no verdict: stdout empty" "${OUT}"
assert_not_empty "no verdict: reason on stderr" "${ERR}"
assert_equals "no verdict: nothing written under ~/.claude" "${_before}" "$(ls -A "${TEST_HOME}/.claude")"

echo "== R7: a verdict that was not measured =="
R7="$(mkrepo "${TEST_TMPDIR}/r7")"
rm -f "${ARTIFACT}"
record "${R7}" --name unit --run true
# The writer stamps only verify-yml|explicit; a ladder value exists only on a
# hand-authored record, so it is set on a real artifact here.
edit_artifact '.discovery_source = "claude-md-commands"'
render "${R7}"
assert_equals "ladder verdict: exit 1" "1" "${RC}"
assert_empty "ladder verdict: stdout empty" "${OUT}"
assert_contains "ladder verdict: stderr says not measured" "not measured" "${ERR}"

echo "== R8: a verdict the writer did not write =="
rm -f "${ARTIFACT}"
record "${R7}" --name unit --run true
edit_artifact '.writer = "by-hand"'   # the writer never stamps another name
render "${R7}"
assert_equals "foreign writer: exit 1" "1" "${RC}"
assert_empty "foreign writer: stdout empty" "${OUT}"

echo "== R9: an artifact holding two documents =="
rm -f "${ARTIFACT}"
record "${R7}" --name unit --run 'exit 1'
printf '%s\n' '{"gate_gaming_status":"clean","failed":[]}' >> "${ARTIFACT}"
render "${R7}"
assert_equals "two documents: exit 3" "3" "${RC}"
assert_empty "two documents: stdout empty" "${OUT}"

echo "== R10: not a git repo =="
mkdir -p "${TEST_TMPDIR}/norepo"
OUT="$( cd "${TEST_TMPDIR}/norepo" && GIT_CEILING_DIRECTORIES="${TEST_TMPDIR}" /bin/bash "${RCPT}" 2>/dev/null < /dev/null )"; RC=$?
assert_equals "outside a repo: exit 3" "3" "${RC}"
assert_empty "outside a repo: stdout empty" "${OUT}"

echo "== R11: jq unavailable =="
rm -f "${ARTIFACT}"
record "${R1}" --name unit --run true
# A private bin with the tools the script needs and no jq. /usr/bin is left out
# on purpose: macOS ships /usr/bin/jq.
_NOJQ="${TEST_TMPDIR}/nojq-bin"; mkdir -p "${_NOJQ}"
for _t in git dirname cat grep sed tr head; do
    _p="$(command -v "${_t}")" && ln -sf "${_p}" "${_NOJQ}/${_t}"
done
if PATH="${_NOJQ}" /bin/bash -c 'command -v jq' >/dev/null 2>&1; then
    _record_fail "jq-less PATH really lacks jq" "jq still resolvable"
else
    _record_pass "jq-less PATH really lacks jq"
fi
PATH="${_NOJQ}" /bin/bash -c 'command -v git' >/dev/null 2>&1 && _record_pass "jq-less PATH still has git" \
    || _record_fail "jq-less PATH still has git" "git not resolvable"
OUT="$( cd "${R1}" && PATH="${_NOJQ}" /bin/bash "${RCPT}" 2>/dev/null < /dev/null )"; RC=$?
assert_equals "no jq: exit 3" "3" "${RC}"
assert_empty "no jq: stdout empty" "${OUT}"

echo "== R12: run from a subdirectory =="
mkdir -p "${R1}/sub"
render "${R1}/sub"
assert_equals "subdirectory: exit 0" "0" "${RC}"
assert_equals "subdirectory: same marker as from the root" \
    "<!-- acs-verify-receipt v1 sha=${H1} result=pass -->" "$(printf '%s\n' "${OUT}" | head -1)"

echo "== R13: takes no arguments =="
OUT="$( cd "${R1}" && /bin/bash "${RCPT}" --help 2>/dev/null < /dev/null )"; RC=$?
assert_equals "an argument: exit 3" "3" "${RC}"
assert_empty "an argument: stdout empty" "${OUT}"

cd "${REPO_ROOT}" || true
teardown_test_env
print_summary
