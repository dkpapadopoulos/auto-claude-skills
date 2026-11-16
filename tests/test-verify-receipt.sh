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

# --- Disclosure: a PR description can be public, and names are user text ------

echo "== D1/D2: command line, output and local detail never reach the receipt =="
RD="$(mkrepo "${TEST_TMPDIR}/rd")"
rm -f "${ARTIFACT}"
record "${RD}" --name deploy --run 'echo LEAKED-OUTPUT-7731; : --token=SECRET-TOKEN-4242'
assert_contains "precondition: the artifact holds the command line" "SECRET-TOKEN-4242" "$(jq -r '.command' "${ARTIFACT}")"
assert_contains "precondition: the artifact holds the output" "LEAKED-OUTPUT-7731" "$(jq -r '.output_excerpt' "${ARTIFACT}")"
render "${RD}"
assert_equals "secret-bearing verdict still renders" "0" "${RC}"
assert_contains "the check itself is listed" "| deploy | passed |" "${OUT}"
assert_not_contains "command line is not in the receipt" "SECRET-TOKEN-4242" "${OUT}"
assert_not_contains "command output is not in the receipt" "LEAKED-OUTPUT-7731" "${OUT}"
assert_not_contains "home directory is not in the receipt" "${TEST_HOME}" "${OUT}"
assert_not_contains "session token is not in the receipt" "session-rcpt" "${OUT}"
assert_not_contains "artifact name is not in the receipt" ".skill-project-verified" "${OUT}"

echo "== D3: a check name that is not a plain label is counted, not shown =="
rm -f "${ARTIFACT}"
record "${RD}" --name 'x --> @everyone' --run true --name ok --run true
assert_equals "precondition: the writer accepted the name" '["x --> @everyone","ok"]' "$(jq -c '.passed' "${ARTIFACT}")"
render "${RD}"
assert_equals "hostile name: exit 0" "0" "${RC}"
assert_not_contains "hostile name is not printed" "@everyone" "${OUT}"
assert_equals "the only comment terminator is the marker's" "1" "$(printf '%s\n' "${OUT}" | grep -c -- '-->')"
assert_contains "hostile name is counted" "| (1 check(s) with a name that is not a plain label) | passed |" "${OUT}"
assert_contains "plain name beside it still listed" "| ok | passed |" "${OUT}"

echo "== D4: a failed check with a table-breaking name still reads as FAILED =="
rm -f "${ARTIFACT}"
record "${RD}" --name 'a | b' --run 'exit 1'
render "${RD}"
assert_contains "marker carries result=fail" " result=fail -->" "$(printf '%s\n' "${OUT}" | head -1)"
assert_not_contains "pipe-bearing name is not printed" "a | b" "${OUT}"
assert_contains "it is counted under FAILED" "| (1 check(s) with a name that is not a plain label) | FAILED |" "${OUT}"

echo "== D5/D6: recorded free text is not echoed =="
rm -f "${ARTIFACT}"
record "${RD}" --name unit --run true
# The writer records a status word and an ISO timestamp; anything else means the
# file was edited after it was written, which is what these two cells model.
edit_artifact '.gate_gaming_status = "clean -->\n@x"'
render "${RD}"
assert_equals "edited status: still renders" "0" "${RC}"
assert_contains "edited status reads unrecognised" "- Gate-gaming check: unrecognised" "${OUT}"
assert_not_contains "edited status text is not printed" "@x" "${OUT}"
rm -f "${ARTIFACT}"
record "${RD}" --name unit --run true
edit_artifact '.ts = "yesterday <b>"'
render "${RD}"
assert_contains "edited ts reads unknown" "- Recorded: unknown by" "${OUT}"
assert_not_contains "edited ts text is not printed" "<b>" "${OUT}"

echo "== D6b: a trailing newline does not pass the shape check =="
rm -f "${ARTIFACT}"
record "${RD}" --name unit --run true
edit_artifact '.gate_gaming_status = "clean\n"'   # jq's $ matches before it
render "${RD}"
assert_contains "status with a trailing newline reads unrecognised" "- Gate-gaming check: unrecognised" "${OUT}"

echo "== D6c: a failed entry that is not a string is still a failure =="
rm -f "${ARTIFACT}"
record "${RD}" --name unit --run true
edit_artifact '.failed = [7]'   # not writable by the writer; an edited record
render "${RD}"
assert_contains "non-string failed entry: result=fail" " result=fail -->" "$(printf '%s\n' "${OUT}" | head -1)"
assert_contains "non-string failed entry is counted" "| (1 check(s) with a name that is not a plain label) | FAILED |" "${OUT}"

echo "== D7: a suspect gate-gaming status =="
rm -f "${ARTIFACT}"
record "${RD}" --name unit --run true
# A real suspect needs a mainline base and a weakened test in the diff;
# tests/test-gate-gaming-scope.sh owns that path. Set on a real artifact here.
edit_artifact '.gate_gaming_status = "suspect"'
render "${RD}"
assert_contains "marker carries result=suspect" " result=suspect -->" "$(printf '%s\n' "${OUT}" | head -1)"
assert_contains "heading says SUSPECT" "### Local verification: SUSPECT" "${OUT}"
assert_contains "status line says suspect" "- Gate-gaming check: suspect" "${OUT}"

echo "== D8/D9: which session's verdict is rendered =="
OTHER="${TEST_HOME}/.claude/.skill-project-verified-session-other"
rm -f "${ARTIFACT}" "${OTHER}"
( cd "${RD}" && SKILL_SESSION_TOKEN=session-other /bin/bash "${VAR}" --name unit --run 'exit 1' >/dev/null 2>&1 < /dev/null )
assert_file_exists "precondition: sibling verdict written" "${OTHER}"
render "${RD}"
assert_equals "sibling-only verdict at HEAD: rendered" "0" "${RC}"
assert_contains "sibling-only: the sibling's failure is shown" " result=fail -->" "$(printf '%s\n' "${OUT}" | head -1)"
# Own verdict at the exact commit wins without a sibling scan
# (verdict_resolve_token leg 1, the precedence the push gate uses). Pinned as
# observed: this session's receipt describes this session's run.
record "${RD}" --name unit --run true
render "${RD}"
assert_contains "own verdict at HEAD is the one rendered" " result=pass -->" "$(printf '%s\n' "${OUT}" | head -1)"
rm -f "${OTHER}"

# --- The writer names the command, and the named command works as pasted -----

PFX="receipt for a PR description: "
# writer_out <repo> <plugin root> <writer args…> — sets WOUT (the writer's stdout)
writer_out() {
    local r="$1" pr="$2"; shift 2
    WOUT="$( cd "$r" && CLAUDE_PLUGIN_ROOT="$pr" /bin/bash "${pr}/scripts/verify-and-record.sh" "$@" 2>/dev/null < /dev/null )"
    WLAST="$(printf '%s\n' "${WOUT}" | tail -1)"
}

echo "== W1/W2: a renderable verdict ends by naming the command, and it runs =="
RW="$(mkrepo "${TEST_TMPDIR}/rw")"
rm -f "${ARTIFACT}"
writer_out "${RW}" "${REPO_ROOT}" --name unit --run true
assert_equals "last line names the receipt command, single-quoted and absolute" \
    "${PFX}bash '${REPO_ROOT}/scripts/verify-receipt.sh'" "${WLAST}"
_cmd="${WLAST#"${PFX}"}"
OUT="$( cd "${RW}" && env -u CLAUDE_PLUGIN_ROOT /bin/bash -c "${_cmd}" 2>/dev/null < /dev/null )"; RC=$?
assert_equals "the named command, pasted, exits 0" "0" "${RC}"
assert_contains "the named command, pasted, prints the receipt" "<!-- acs-verify-receipt v1 sha=" "$(printf '%s\n' "${OUT}" | head -1)"

echo "== W3: a dirty-tree verdict names no command =="
rm -f "${ARTIFACT}"
echo y >> "${RW}/f.txt"
writer_out "${RW}" "${REPO_ROOT}" --name unit --run true
assert_contains "precondition: the verdict was written" "verdict written:" "${WOUT}"
assert_not_contains "dirty tree: the receipt command is not named" "verify-receipt" "${WOUT}"
git -C "${RW}" checkout -q -- f.txt

echo "== W3b: a run that straddled a commit names no command =="
RS="$(mkrepo "${TEST_TMPDIR}/rs")"
rm -f "${ARTIFACT}"
writer_out "${RS}" "${REPO_ROOT}" --name unit --run 'git commit --allow-empty -qm mid'
assert_contains "precondition: the straddle was recorded" "gate-run-straddled-commit" "$(jq -c '.could_not_verify' "${ARTIFACT}")"
assert_not_contains "straddled run: the receipt command is not named" "verify-receipt" "${WOUT}"

echo "== W4: a failing verdict on a clean tree still names it =="
rm -f "${ARTIFACT}"
writer_out "${RW}" "${REPO_ROOT}" --name unit --run 'exit 1'
assert_contains "failing verdict: command named" "${PFX}bash '" "${WLAST}"

echo "== W5: a plugin path with a space, a quote and a substitution pastes safely =="
PL="${TEST_TMPDIR}/pl ug'in\$(touch PWN)"
mkdir -p "${PL}/hooks" "${PL}/skills/project-verification"
cp -R "${REPO_ROOT}/scripts" "${PL}/scripts"
cp -R "${REPO_ROOT}/hooks/lib" "${PL}/hooks/lib"
cp -R "${REPO_ROOT}/skills/project-verification/scripts" "${PL}/skills/project-verification/scripts"
rm -f "${ARTIFACT}"
writer_out "${RW}" "${PL}" --name unit --run true
assert_contains "odd path: command named" "${PFX}bash '" "${WLAST}"
_cmd="${WLAST#"${PFX}"}"
OUT="$( cd "${RW}" && env -u CLAUDE_PLUGIN_ROOT /bin/bash -c "${_cmd}" 2>/dev/null < /dev/null )"; RC=$?
assert_equals "odd path: pasted under bash, exits 0" "0" "${RC}"
assert_contains "odd path: pasted under bash, prints the receipt" "<!-- acs-verify-receipt v1 sha=" "${OUT}"
if command -v zsh >/dev/null 2>&1; then
    OUT="$( cd "${RW}" && env -u CLAUDE_PLUGIN_ROOT zsh -f -c "${_cmd}" 2>/dev/null < /dev/null )"; RC=$?
    assert_equals "odd path: pasted under zsh, exits 0" "0" "${RC}"
    assert_contains "odd path: pasted under zsh, prints the receipt" "<!-- acs-verify-receipt v1 sha=" "${OUT}"
else
    _record_pass "odd path: zsh not installed, bash half only"
fi
[ ! -e "${RW}/PWN" ] && _record_pass "odd path: the substitution in the path never ran" \
    || _record_fail "odd path: the substitution in the path never ran" "PWN was created"

echo "== W6: a declared .verify.yml gate =="
RY="$(mkrepo "${TEST_TMPDIR}/ry")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n' > "${RY}/.verify.yml"
git -C "${RY}" add .verify.yml && git -C "${RY}" commit -qm gate
rm -f "${ARTIFACT}"
writer_out "${RY}" "${REPO_ROOT}"
assert_contains "declared gate: command named" "${PFX}bash '" "${WLAST}"
render "${RY}"
assert_equals "declared gate: receipt rendered" "0" "${RC}"
assert_contains "declared gate: provenance says verify-yml" "(verify-yml)" "${OUT}"
assert_contains "declared gate: the check is listed" "| tests | passed |" "${OUT}"

# --- Review findings: the receipt may never read better than the gate's reader -

echo "== F1: pass needs a clean gate-gaming status and at least one check =="
RF="$(mkrepo "${TEST_TMPDIR}/rf")"
# fresh — a real clean verdict for RF under the own token
fresh() { rm -f "${ARTIFACT}"; record "${RF}" --name unit --run true; }
fresh; edit_artifact '.gate_gaming_status = "unverified"'   # the writer pairs this with a could_not_verify entry
render "${RF}"
assert_equals "unverified status: rendered" "0" "${RC}"
assert_contains "unverified status is not a pass" " result=could-not-verify -->" "$(printf '%s\n' "${OUT}" | head -1)"
assert_contains "unverified status is shown" "- Gate-gaming check: unverified" "${OUT}"
fresh; edit_artifact 'del(.gate_gaming_status)'
render "${RF}"
assert_contains "missing status is not a pass" " result=could-not-verify -->" "$(printf '%s\n' "${OUT}" | head -1)"
fresh; edit_artifact '.passed = []'   # the writer refuses an empty gate
render "${RF}"
assert_contains "zero checks is not a pass" " result=could-not-verify -->" "$(printf '%s\n' "${OUT}" | head -1)"
assert_contains "zero checks says so" "| (no checks recorded) | - |" "${OUT}"

echo "== F2: a record whose fields are the wrong type is not rendered =="
# verdict_has_test_failure reads a string or object in .failed as a failure, so
# rendering these as an empty list printed PASS over a verdict the push gate
# reads as failing. None is writable by the writer.
for _edit in '.failed = "unit"' '.failed = {"a":1}' '.could_not_verify = "x"' '.passed = null' '.worktree_dirty = "true"' 'del(.worktree_dirty)'; do
    fresh; edit_artifact "${_edit}"
    render "${RF}"
    assert_equals "malformed (${_edit}): exit 3" "3" "${RC}"
    assert_empty "malformed (${_edit}): stdout empty" "${OUT}"
done

echo "== F3: provenance is printed as a fixed word =="
fresh; edit_artifact '.discovery_source = "explicit\n"'   # passes the lib's case after $( ) strips the newline
render "${RF}"
assert_contains "provenance stays on one line" "\`verify-and-record.sh\` (explicit)" "${OUT}"

echo "== F4: a sibling session's could-not-verify verdict at HEAD is found =="
rm -f "${ARTIFACT}" "${OTHER}"
( cd "${RF}" && SKILL_SESSION_TOKEN=session-other /bin/bash "${VAR}" --name types --run definitely-not-a-cmd-xyz >/dev/null 2>&1 < /dev/null )
assert_equals "precondition: sibling recorded could-not-verify" '["types"]' "$(jq -c '.could_not_verify' "${OTHER}" 2>/dev/null)"
render "${RF}"
assert_equals "sibling could-not-verify: rendered" "0" "${RC}"
assert_contains "sibling could-not-verify: result" " result=could-not-verify -->" "$(printf '%s\n' "${OUT}" | head -1)"
# Two siblings at the commit, one failing: the failing one is rendered.
( cd "${RF}" && SKILL_SESSION_TOKEN=session-third /bin/bash "${VAR}" --name unit --run 'exit 1' >/dev/null 2>&1 < /dev/null )
render "${RF}"
assert_contains "among siblings a failing verdict is the one rendered" " result=fail -->" "$(printf '%s\n' "${OUT}" | head -1)"
# A sibling's hand-written record at the commit is not picked up.
rm -f "${OTHER}" "${TEST_HOME}/.claude/.skill-project-verified-session-third"
( cd "${RF}" && SKILL_SESSION_TOKEN=session-other /bin/bash "${VAR}" --name unit --run true >/dev/null 2>&1 < /dev/null )
jq '.discovery_source = "heuristic:make"' "${OTHER}" > "${OTHER}.e" && mv "${OTHER}.e" "${OTHER}"
render "${RF}"
assert_equals "sibling hand-written record: no receipt" "1" "${RC}"
assert_empty "sibling hand-written record: stdout empty" "${OUT}"
rm -f "${OTHER}"

echo "== F5: a repo with no commits names no command =="
mkdir -p "${TEST_TMPDIR}/unborn" && git -C "${TEST_TMPDIR}/unborn" init -q -b main .
rm -f "${ARTIFACT}"
writer_out "${TEST_TMPDIR}/unborn" "${REPO_ROOT}" --name unit --run true
assert_contains "precondition: the writer still wrote a verdict" "verdict written:" "${WOUT}"
assert_not_contains "unborn repo: the receipt command is not named" "verify-receipt" "${WOUT}"

# --- The skill tells the agent what the receipt is for -----------------------

echo "== S1-S3: skills/project-verification/SKILL.md =="
SK="${REPO_ROOT}/skills/project-verification/SKILL.md"
SK_OUT="$(sed -n '/^## Output/,$p' "${SK}")"
assert_contains "Output section names the receipt command by plugin root" "bash '<PLUGIN_ROOT>/scripts/verify-receipt.sh'" "${SK_OUT}"
assert_contains "Output section says verbatim" "verbatim" "${SK_OUT}"
assert_contains "Output section says PR description" "PR description" "${SK_OUT}"
assert_contains "Output section forbids a hand-written receipt" "never write one by hand" "${SK_OUT}"
_sk_bytes="$(wc -c < "${SK}" | tr -d ' ')"
[ "${_sk_bytes}" -le 19500 ] && _record_pass "SKILL.md within the 19,500-byte re-attach budget (${_sk_bytes})" \
    || _record_fail "SKILL.md within the 19,500-byte re-attach budget" "${_sk_bytes} bytes"

cd "${REPO_ROOT}" || true
teardown_test_env
print_summary
