#!/bin/bash
# test-cozempic-wrapper.sh — hooks/cozempic-wrapper.sh must not pollute stdout.
#
# Every hooks.json registration of this wrapper is a HOOK: `guard --daemon`
# (SessionStart) and three `checkpoint` entries (PostToolUse). Stdout is the
# harness's structured channel for a hook, so a wrapper that passes the child's
# stdout through is a harness-visible side effect on every fire. Measured on a
# machine with cozempic installed: `checkpoint` wrote 26 bytes to stdout and
# 140 to stderr per run, and the `^(Task|Agent)$` matcher fires on every
# subagent dispatch.
#
# STDERR IS DELIBERATELY LEFT ALONE. It is not part of any hook's contract, and
# it is where a genuine failure would surface — silencing it would buy quiet by
# deleting diagnostics, which is the failure mode CLAUDE.md warns about
# repeatedly. Only stdout is suppressed, and only for the non-`doctor` verbs.
#
# `doctor` is the one user-facing verb (it prints the monorepo-subdir hint) and
# MUST keep stdout.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRAPPER="${PROJECT_ROOT}/hooks/cozempic-wrapper.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-cozempic-wrapper.sh ==="

_TMP="$(mktemp -d /tmp/cozwrap-XXXXXX)"
_BIN="${_TMP}/bin"
mkdir -p "${_BIN}"

# A stand-in cozempic that writes to BOTH streams and echoes its argv, so the
# assertions below distinguish "stdout suppressed" from "child never ran".
cat > "${_BIN}/cozempic" <<'FAKE'
#!/bin/bash
echo "  No team state detected."
echo "  Cozempic: local hooks redundant (global hooks active)" >&2
echo "ARGV:$*" >> "${COZWRAP_ARGV_LOG}"
exit 0
FAKE
chmod +x "${_BIN}/cozempic"

_ARGV_LOG="${_TMP}/argv.log"
export COZWRAP_ARGV_LOG="${_ARGV_LOG}"

# $1 = label, $@ = wrapper args. Captures the two streams separately.
_run() {
    _OUT="$(PATH="${_BIN}:$PATH" bash "${WRAPPER}" "$@" 2>"${_TMP}/err" < /dev/null)"
    _ERR="$(cat "${_TMP}/err" 2>/dev/null)"
}

# ---- the hook verbs: stdout silent, child still ran ------------------------
: > "${_ARGV_LOG}"
_run checkpoint
assert_equals "checkpoint writes nothing to stdout" "" "${_OUT}"
if grep -q "ARGV:checkpoint" "${_ARGV_LOG}" 2>/dev/null; then
    _record_pass "checkpoint still execs cozempic (stdout suppressed, not skipped)"
else
    _record_fail "checkpoint still execs cozempic (stdout suppressed, not skipped)" \
        "cozempic was never invoked"
fi

# The distinction that makes the assertion above meaningful: a wrapper that
# simply never ran the child would also produce empty stdout.
case "${_ERR}" in
    *"local hooks redundant"*)
        _record_pass "checkpoint preserves stderr (diagnostics are not silenced)" ;;
    *)  _record_fail "checkpoint preserves stderr (diagnostics are not silenced)" \
            "stderr was: ${_ERR}" ;;
esac

: > "${_ARGV_LOG}"
_run guard --daemon
assert_equals "guard --daemon writes nothing to stdout" "" "${_OUT}"
if grep -q "ARGV:guard --daemon" "${_ARGV_LOG}" 2>/dev/null; then
    _record_pass "guard --daemon passes its flags through"
else
    _record_fail "guard --daemon passes its flags through" \
        "argv log: $(cat "${_ARGV_LOG}" 2>/dev/null)"
fi

# ---- doctor is user-facing and KEEPS stdout --------------------------------
: > "${_ARGV_LOG}"
_run doctor
case "${_OUT}" in
    *"No team state detected"*)
        _record_pass "doctor keeps stdout (it is the user-facing verb)" ;;
    *)  _record_fail "doctor keeps stdout (it is the user-facing verb)" \
            "stdout was: ${_OUT}" ;;
esac

# ---- cozempic absent: still silent, still exit 0 ---------------------------
# The curated PATH keeps /usr/bin:/bin (the wrapper shells out to `dirname`,
# and `bash` itself must resolve) and drops only the fake bin. HOME is moved so
# the wrapper's own ~/.local/bin and ~/Library/Python discovery finds nothing.
_EMPTY="${_TMP}/empty"; mkdir -p "${_EMPTY}"
_NOCOZ_PATH="${_EMPTY}:/usr/bin:/bin"

# Assert the harness ACTUALLY removed cozempic before asserting degradation --
# otherwise a harness that silently still resolves it makes this cell vacuous.
if PATH="${_NOCOZ_PATH}" HOME="${_TMP}" command -v cozempic >/dev/null 2>&1; then
    _record_fail "no-cozempic harness actually removes cozempic" "still resolvable"
else
    _record_pass "no-cozempic harness actually removes cozempic"
fi

_out2="$(PATH="${_NOCOZ_PATH}" HOME="${_TMP}" bash "${WRAPPER}" checkpoint 2>/dev/null < /dev/null; echo "rc=$?")"
assert_equals "absent cozempic degrades silently with exit 0" "rc=0" "${_out2}"

# ---- every hooks.json registration is covered by the rule above ------------
# Pins the population: if a future entry introduces a verb this test does not
# exercise, this assertion fails rather than the gap going unnoticed.
if command -v jq >/dev/null 2>&1; then
    _verbs="$(jq -r '.hooks | to_entries[] | .value[]? | .hooks[]? | .command
                     | select(test("cozempic-wrapper\\.sh"))
                     | sub("^.*cozempic-wrapper\\.sh +"; "")' \
              "${PROJECT_ROOT}/hooks/hooks.json" 2>/dev/null | sort -u | tr '\n' ',')"
    assert_equals "hooks.json invokes only the verbs this test covers" \
        "checkpoint,guard --daemon," "${_verbs}"
else
    _record_pass "hooks.json verb population (skipped: no jq)"
fi

rm -rf "${_TMP}"
print_summary
exit $?
