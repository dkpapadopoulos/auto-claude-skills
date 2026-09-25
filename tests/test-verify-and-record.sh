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
printf 'session-vartest' > "${TEST_HOME}/.claude/.skill-session-token"   # restore: T12-T15 rebound it

echo "== T16 (issue #181): a run that straddles a commit is recorded as unverifiable =="
# The gate's sha was read AFTER the gate loop, so a commit landing mid-run was
# silently adopted: the verdict named a commit whose tree no gate ever ran
# against, and the push gate's ancestor acceptance then covered it. Simulate the
# window with a gate command that commits in the fixture repo mid-run.
R16="$(mkrepo "${TEST_TMPDIR}/r16")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: git commit -q --allow-empty -m mid-run; echo ok\n' > "${R16}/.verify.yml"
_PRE_SHA="$(git -C "${R16}" rev-parse HEAD)"
rm -f "${ARTIFACT}"
( cd "${R16}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
_POST_SHA="$(git -C "${R16}" rev-parse HEAD)"
[ "${_PRE_SHA}" != "${_POST_SHA}" ] && _record_pass "fixture genuinely straddled a commit (precondition)" \
    || _record_fail "fixture genuinely straddled a commit (precondition)" "HEAD did not move; the case proves nothing"
# Guards the negative assertion below from passing vacuously on a missing artifact.
assert_file_exists "straddled run still WRITES a verdict (recording is the script's job)" "${ARTIFACT}"
assert_equals "straddled run recorded in could_not_verify[]" "true" \
    "$(jq -r '((.could_not_verify // []) | index("gate-run-straddled-commit")) != null' "${ARTIFACT}")"
assert_equals "sha names the TESTED (pre-gate) commit, not the mid-run one" "${_PRE_SHA}" "$(jq -r '.sha' "${ARTIFACT}")"
# End-to-end consumer assertion: the real predicate the push gate keys on, not a
# re-derivation of it in the test. Guarded first — an unsourceable lib would make
# the NEGATIVE assertion below pass on exit 127 rather than on the predicate.
if ( . "${REPO_ROOT}/hooks/lib/verdict.sh" >/dev/null 2>&1; command -v verdict_is_clean >/dev/null 2>&1 ); then
    _record_pass "verdict.sh sourced and verdict_is_clean is defined (guards the negatives below)"
else
    _record_fail "verdict.sh sourced and verdict_is_clean is defined (guards the negatives below)" \
        "lib unsourceable — every verdict_is_clean negative below would pass on exit 127"
fi
if ( . "${REPO_ROOT}/hooks/lib/verdict.sh" >/dev/null 2>&1; verdict_is_clean session-vartest ); then
    _record_fail "straddled verdict does not satisfy verdict_is_clean" "verdict_is_clean accepted a straddled run"
else
    _record_pass "straddled verdict does not satisfy verdict_is_clean"
fi

echo "== T17 (issue #181): an ordinary run stays clean and HEAD-bound =="
# The control for T16: nothing about the non-straddled path may change, or the
# fix would trade a silent mislabel for a routine false block.
R17="$(mkrepo "${TEST_TMPDIR}/r17")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n' > "${R17}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R17}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_equals "unstraddled run still binds to HEAD" "$(git -C "${R17}" rev-parse HEAD)" "$(jq -r '.sha' "${ARTIFACT}")"
assert_equals "unstraddled run records nothing unverifiable" '[]' "$(jq -c '.could_not_verify' "${ARTIFACT}")"
assert_equals "clean worktree recorded as not dirty" "false" "$(jq -r '.worktree_dirty' "${ARTIFACT}")"
if ( . "${REPO_ROOT}/hooks/lib/verdict.sh" >/dev/null 2>&1; verdict_is_clean session-vartest ); then
    _record_pass "unstraddled verdict still satisfies verdict_is_clean"
else
    _record_fail "unstraddled verdict still satisfies verdict_is_clean" "the fix false-blocks an ordinary run"
fi

echo "== T18 (issue #181): a dirty worktree is disclosed but never gates =="
# A clean sha on a dirty tree has the same "tested something else" problem, so
# the record must say so — but verifying uncommitted work and committing
# afterwards is a supported workflow, so it must NOT reach could_not_verify[].
R18="$(mkrepo "${TEST_TMPDIR}/r18")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok\n' > "${R18}/.verify.yml"
echo modified > "${R18}/f.txt"                     # tracked file, uncommitted
rm -f "${ARTIFACT}"
( cd "${R18}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_equals "modified tracked file recorded as worktree_dirty" "true" "$(jq -r '.worktree_dirty' "${ARTIFACT}")"
assert_equals "dirty worktree adds nothing to could_not_verify[]" '[]' "$(jq -c '.could_not_verify' "${ARTIFACT}")"
if ( . "${REPO_ROOT}/hooks/lib/verdict.sh" >/dev/null 2>&1; verdict_is_clean session-vartest ); then
    _record_pass "dirty worktree keeps the verdict clean (advisory only)"
else
    _record_fail "dirty worktree keeps the verdict clean (advisory only)" "worktree_dirty was deny-wired"
fi

echo "== T19 (issue #181): untracked files alone are not 'dirty', and are not a straddle =="
# worktree_dirty is tracked-files-only, so an untracked file present at gate
# start does not set it. The second assertion is the one that pins D3: a gate
# that WRITES an untracked artifact must not be read as a straddle — that is
# exactly why the straddle predicate is HEAD-sha-only rather than status-based.
R19="$(mkrepo "${TEST_TMPDIR}/r19")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: echo ok > build-artifact.tmp\n' > "${R19}/.verify.yml"
echo scratch > "${R19}/untracked.txt"
rm -f "${ARTIFACT}"
( cd "${R19}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_equals "untracked-only worktree is not dirty" "false" "$(jq -r '.worktree_dirty' "${ARTIFACT}")"
assert_equals "gate-created untracked artifact is not a straddle" '[]' "$(jq -c '.could_not_verify' "${ARTIFACT}")"

echo "== T20 (issue #181): a straddled run whose gate FAILED is no longer authoritative at HEAD =="
# The one case where the fix changes an ENFORCEMENT outcome, so it gets a
# contract pin rather than being left implicit. Pre-fix, a failing straddled run
# recorded the mid-run commit, so verdict_sha_is_head was TRUE and
# verify-hardening denied a push at that HEAD — on the strength of a failure
# measured against a different tree. Post-fix the sha is the pre-gate commit, so
# the failure is authoritative only for the commit it was measured at (the repo's
# stated rule; an ancestor-FAIL blocking a fixed HEAD was a real false block).
# The run is NOT laundered: it stays in failed[] and could_not_verify[], so
# routing-governance and deploy-gate both still reject it.
R20="$(mkrepo "${TEST_TMPDIR}/r20")"
printf 'substrate: local\ncommands:\n  - name: tests\n    run: git commit -q --allow-empty -m mid-run; exit 3\n' > "${R20}/.verify.yml"
_R20_PRE="$(git -C "${R20}" rev-parse HEAD)"
rm -f "${ARTIFACT}"
( cd "${R20}" && /bin/bash "${VAR}" >/dev/null 2>&1 )
assert_equals "straddled failure is still recorded as a failure" '["tests"]' "$(jq -c '.failed' "${ARTIFACT}")"
assert_equals "straddled failure also recorded as unverifiable" "true" \
    "$(jq -r '((.could_not_verify // []) | index("gate-run-straddled-commit")) != null' "${ARTIFACT}")"
assert_equals "straddled failure binds to the commit it was MEASURED at" "${_R20_PRE}" "$(jq -r '.sha' "${ARTIFACT}")"
if ( cd "${R20}" && . "${REPO_ROOT}/hooks/lib/verdict.sh" >/dev/null 2>&1; verdict_sha_is_head session-vartest "${R20}" ); then
    _record_fail "straddled failure is not authoritative for the untested HEAD" \
        "verdict_sha_is_head true — verify-hardening would deny on a failure measured against another tree"
else
    _record_pass "straddled failure is not authoritative for the untested HEAD"
fi
if ( cd "${R20}" && . "${REPO_ROOT}/hooks/lib/verdict.sh" >/dev/null 2>&1; verdict_is_clean session-vartest ); then
    _record_fail "straddled failure is never laundered to clean" "verdict_is_clean accepted a failing straddled run"
else
    _record_pass "straddled failure is never laundered to clean"
fi

# --- T21-T24: explicit-commands mode (#295 step 1) ---------------------------
# Separates the two jobs the script conflates: WHICH commands are the gate
# (judgment, caller) from RUN THEM AND RECORD WHAT HAPPENED (mechanical, script).
# Today a repo with no .verify.yml gets neither, so SKILL.md has the MODEL
# hand-author the JSON and the artifact records belief instead of execution.
R21="$(mkrepo "${TEST_HOME}/r21")"
rm -f "${R21}/.verify.yml" "${ARTIFACT}"
( cd "${R21}" && /bin/bash "${VAR}" --name unit --run "true" ) >/dev/null 2>&1
if [ -f "${ARTIFACT}" ]; then
    _record_pass "explicit mode writes a verdict when no .verify.yml exists"
    assert_equals "passing command lands in passed[]" "true" "$(jq -r '((.passed // []) | index("unit")) != null' "${ARTIFACT}")"
    assert_equals "explicit mode stamps the deterministic writer" "verify-and-record.sh" "$(jq -r '.writer // ""' "${ARTIFACT}")"
    # The SCRIPT owns provenance. A caller-supplied rung would let explicit mode
    # impersonate verify-yml and imply a declaration that does not exist.
    assert_equals "provenance is script-owned and says explicit" "explicit" "$(jq -r '.discovery_source // ""' "${ARTIFACT}")"
else
    for _t in "explicit mode writes a verdict when no .verify.yml exists" "passing command lands in passed[]" \
              "explicit mode stamps the deterministic writer" "provenance is script-owned and says explicit"; do
        _record_fail "${_t}" "no artifact written"
    done
fi

# T22: the honesty property — a FAILING explicit command is never laundered.
R22="$(mkrepo "${TEST_HOME}/r22")"
rm -f "${R22}/.verify.yml" "${ARTIFACT}"
( cd "${R22}" && /bin/bash "${VAR}" --name unit --run "false" ) >/dev/null 2>&1
if [ -f "${ARTIFACT}" ]; then
    assert_equals "failing explicit command lands in failed[]" "true" "$(jq -r '((.failed // []) | index("unit")) != null' "${ARTIFACT}")"
    if ( cd "${R22}" && . "${REPO_ROOT}/hooks/lib/verdict.sh" >/dev/null 2>&1; verdict_is_clean session-vartest ); then
        _record_fail "a failing explicit command is never laundered to clean" "verdict_is_clean accepted a failing run"
    else
        _record_pass "a failing explicit command is never laundered to clean"
    fi
else
    _record_fail "failing explicit command lands in failed[]" "no artifact"
    _record_fail "a failing explicit command is never laundered to clean" "no artifact"
fi

# T23: explicit args MUST NOT bypass a declared gate. Otherwise the mode becomes
# a way to substitute a narrower check for the repo's own contract.
R23="$(mkrepo "${TEST_HOME}/r23")"
printf 'substrate: local\ncommands:\n  - name: real\n    run: false\n' > "${R23}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R23}" && /bin/bash "${VAR}" --name lint --run "true" ) >/dev/null 2>&1
_r23_rc=$?
# Assert REFUSAL, not just "lint absent". The weaker assertion is equally
# satisfied by silently ignoring the explicit args and running the YAML gate,
# which is a different behaviour with a different failure mode.
if [ -f "${ARTIFACT}" ]; then
    _record_fail "explicit args do NOT substitute for a declared gate" "a verdict was written"
elif [ "${_r23_rc}" -eq 0 ]; then
    _record_fail "explicit args do NOT substitute for a declared gate" "refused but exited 0 — callers cannot tell"
else
    _record_pass "explicit args do NOT substitute for a declared gate"
fi

# _refuses <repo> <label> <args...> — the shared refusal contract: NO artifact
# AND a non-zero exit. An artifact-only assertion is equally satisfied by
# "refused but exited 0", which a caller cannot detect.
_refuses() {
    local repo="$1" lbl="$2"; shift 2
    rm -f "${ARTIFACT}"
    ( cd "${repo}" && /bin/bash "${VAR}" "$@" ) >/dev/null 2>&1
    local rc=$?
    if [ -f "${ARTIFACT}" ]; then
        _record_fail "${lbl}" "a verdict was written"
    elif [ "${rc}" -eq 0 ]; then
        _record_fail "${lbl}" "refused but exited 0 — callers cannot tell"
    else
        _record_pass "${lbl}"
    fi
}

# T24: refuse rather than silently transform. The command transport is
# \x1f-delimited and read LINE-wise, and names are comma-split at serialization,
# so a multiline run or a comma in a name would corrupt the record.
R24="$(mkrepo "${TEST_HOME}/r24")"
rm -f "${R24}/.verify.yml"
_refuses "${R24}" "a multiline run is refused, not silently split" --name unit --run "$(printf 'true\nfalse')"
_refuses "${R24}" "a comma in a name is refused, not silently split" --name "a,b" --run "true"
_refuses "${R24}" "a name with no run is refused" --name unit
# A DANGLING name after a valid pair is the case the trailing check uniquely
# catches: EXPLICIT_PAIRS is non-empty here, so the "no commands given" guard
# does not fire and the run would silently drop the second declared check —
# under-gating toward a false clean. Without this cell the trailing check is
# untested (mutation-verified: deleting it failed nothing).
rm -f "${ARTIFACT}"
( cd "${R24}" && /bin/bash "${VAR}" --name unit --run "true" --name dropped ) >/dev/null 2>&1
if [ -f "${ARTIFACT}" ]; then
    _record_fail "a dangling name after a valid pair is refused" "artifact written; the second check silently vanished"
else
    _record_pass "a dangling name after a valid pair is refused"
fi

# --- T25: refusals found in review of the first cut ---------------------------
R25="$(mkrepo "${TEST_HOME}/r25")"
rm -f "${R25}/.verify.yml"
# P1. The transport is read LINE-wise, so a newline in a name splits one declared
# check across two records — in one of TWO shapes, and only the second is a false
# clean. Measured against the pre-fix script, so do not merge these:
#   "a\nb"  -> could_not_verify=[a], failed=[b]. A CORRUPT record, not clean.
#   bare \n  -> both records nameless, both SKIPPED, `false` never runs, and the
#              empty arrays satisfy verdict_is_clean. THAT is the false clean.
_refuses "${R25}" "a newline in a name is refused (corrupts the record)" --name "$(printf 'a\nb')" --run "false"
_refuses "${R25}" "a bare-newline name is refused (else: FALSE CLEAN)"   --name $'\n' --run "false"
# US is the other transport-corrupting byte, in either field.
_refuses "${R25}" "US in a name is refused"    --name "$(printf 'a\037b')" --run "false"
_refuses "${R25}" "US in a command is refused" --name a --run "$(printf 'fal\037se')"
# I2. `eval " "` exits 0, so a whitespace-only command records PASS having run
# nothing — the degenerate shape the non-empty guard exists to stop, which a
# bare -n test walks straight past. The line is drawn at "not entirely
# whitespace"; this deliberately does NOT validate command CONTENT.
_refuses "${R25}" "a whitespace-only command is refused" --name unit --run " "
_refuses "${R25}" "a tab-only command is refused"        --name unit --run "$(printf '\t')"
# P2a: "" doubled as BOTH "no pending name" and "an explicitly empty name", so a
# trailing --name "" passed the dangling check and its declared check vanished.
# B1. This is the ONLY new guard that survived deletion with zero failing cells,
# and it is the silent-drop class: with it gone, `--name lint --name tests --run
# true` records tests, drops lint, and reports CLEAN. The trailing-dangling cell
# exercises a DIFFERENT guard (the one after the loop), and the duplicate cell
# passes complete pairs, so neither reaches this one.
_refuses "${R25}" "a second --name before the first has a --run is refused" --name lint --name tests --run "true"
_refuses "${R25}" "a trailing empty name is refused"                   --name unit --run "true" --name ""
# Duplicate names produce a duplicated entry in passed[]/failed[] that no reader
# can attribute back to a command.
_refuses "${R25}" "a duplicate name is refused"                        --name a --run "true" --name a --run "true"
# R2 has no caller flag at all — assert the override attempt is rejected, rather
# than only asserting the default stamp (which cannot detect an override route).
_refuses "${R25}" "there is no caller flag for provenance"             --name a --run "true" --discovery-source verify-yml

# P2b: R1 must key on EXISTENCE, not regular-file-ness. A directory or dangling
# symlink at .verify.yml is a declared-gate location the caller cannot measure,
# and must not silently fall through to explicit mode.
R26="$(mkrepo "${TEST_HOME}/r26")"
rm -rf "${R26}/.verify.yml"; mkdir -p "${R26}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R26}" && /bin/bash "${VAR}" --name a --run "true" ) >/dev/null 2>&1
if [ -f "${ARTIFACT}" ]; then
    _record_fail "a directory at .verify.yml does not fall through to explicit mode" "verdict written"
else
    _record_pass "a directory at .verify.yml does not fall through to explicit mode"
fi
rm -rf "${R26}/.verify.yml"; ln -s /nonexistent-target "${R26}/.verify.yml"
rm -f "${ARTIFACT}"
( cd "${R26}" && /bin/bash "${VAR}" --name a --run "true" ) >/dev/null 2>&1
if [ -f "${ARTIFACT}" ]; then
    _record_fail "a dangling .verify.yml symlink does not fall through" "verdict written"
else
    _record_pass "a dangling .verify.yml symlink does not fall through"
fi

# T27: a SUCCESSFUL multi-pair run. Every other multi-pair cell exercises a
# REFUSAL, so replacing rather than appending EXPLICIT_PAIRS would escape all of
# them — the surviving pair would just be the last one, and a refusal still
# refuses.
R27="$(mkrepo "${TEST_HOME}/r27")"
rm -f "${R27}/.verify.yml" "${ARTIFACT}"
( cd "${R27}" && /bin/bash "${VAR}" --name alpha --run "true" --name beta --run "false" ) >/dev/null 2>&1
if [ -f "${ARTIFACT}" ]; then
    assert_equals "multi-pair: the passing check is recorded" "true" "$(jq -r '((.passed // []) | index("alpha")) != null' "${ARTIFACT}")"
    assert_equals "multi-pair: the failing check is recorded" "true" "$(jq -r '((.failed // []) | index("beta")) != null' "${ARTIFACT}")"
    assert_equals "multi-pair: BOTH ran, neither dropped" "2" "$(jq -r '((.passed // [])|length) + ((.failed // [])|length) + ((.could_not_verify // [])|length)' "${ARTIFACT}")"
else
    for _t in "multi-pair: the passing check is recorded" "multi-pair: the failing check is recorded" "multi-pair: BOTH ran, neither dropped"; do
        _record_fail "${_t}" "no artifact written"
    done
fi

cd "${REPO_ROOT}" || true
teardown_test_env
print_summary
