#!/usr/bin/env bash
# test-phase-attest-shell-portability.sh
#
# phase-attest.sh and session-token.sh are sourced BY THE MODEL in its Bash
# turn, and that shell is not necessarily bash — on macOS it is zsh. The whole
# rest of the suite runs under bash, which hid three separate defects:
#
#   1. `${BASH_SOURCE[0]}` is EMPTY in zsh, so phase-attest's self-location
#      resolved to the CWD, session-token.sh was never sourced,
#      resolve_own_session_token stayed undefined, and _phase_attest_token fell
#      back to the shared singleton — making the own-session-first fixes of
#      #151/#156 INERT on the path they were written for. Found live: an
#      attestation landed in a concurrent conversation's file.
#   2. zsh treats an unmatched glob as a FATAL error that unwinds the enclosing
#      function, so resolve_own_session_token's transcript probe skipped its
#      own singleton fallback and returned EMPTY on a miss.
#   3. zsh does not word-split unquoted scalars, so `for ex in $LIST` iterated
#      ONCE over the whole string and the gating-milestone lock accepted every
#      milestone it exists to refuse.
#
# Every assertion therefore runs in EVERY available shell. Bash legs are kept
# as controls: they passed throughout, which is precisely the problem.
#
# Harness is Bash 3.2; the subjects run under bash, zsh, sh and dash.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-phase-attest-shell-portability.sh ==="

ATTEST_LIB="${PROJECT_ROOT}/hooks/lib/phase-attest.sh"
TOKEN_LIB="${PROJECT_ROOT}/hooks/lib/session-token.sh"
assert_file_exists "phase-attest.sh exists" "${ATTEST_LIB}"
assert_file_exists "session-token.sh exists" "${TOKEN_LIB}"

# Build the shell list. bash is the control and always present; the others are
# added when installed. Note macOS /bin/sh IS bash 3.2, so it is a duplicate
# control rather than a POSIX-sh leg — dash is the real POSIX leg.
SHELLS="/bin/bash"
for _cand in "$(command -v zsh 2>/dev/null)" "$(command -v dash 2>/dev/null)" /bin/sh; do
    [ -n "${_cand}" ] && [ -x "${_cand}" ] && SHELLS="${SHELLS} ${_cand}"
done

# zsh is the shell the bugs were found in. Its absence must be loud, not a
# quietly-passing file — the runner only reports per-file pass/fail.
ZSH_BIN="$(command -v zsh 2>/dev/null || true)"
if [ -z "${ZSH_BIN}" ]; then
    echo "  WARNING: zsh not installed — the leg that caught every bug in this file did NOT run."
    echo "           Treat this file's result as unproven on this machine."
fi

# Synthetic HOME: an own-session transcript for conv-OWN plus a singleton naming
# a DIFFERENT conversation, so a correct resolution (session-conv-OWN) and a
# silent singleton fallback (session-FOREIGN) are distinguishable.
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/phase-attest-shell.XXXXXX")" || exit 1
trap 'rm -rf "${TMP_HOME}"' EXIT
mkdir -p "${TMP_HOME}/.claude/projects/proj"
: > "${TMP_HOME}/.claude/projects/proj/conv-OWN.jsonl"
printf 'session-FOREIGN' > "${TMP_HOME}/.claude/.skill-session-token"

# Always run from a directory that is NOT hooks/lib, so a CWD-relative
# self-location cannot accidentally succeed — this mirrors the real invocation.
in_shell() {
    # $1 = shell, $2 = script body, $3 = CLAUDE_CODE_SESSION_ID (optional)
    ( cd "${PROJECT_ROOT}" && HOME="${TMP_HOME}" CLAUDE_CODE_SESSION_ID="${3-conv-OWN}" \
        "$1" -c "$2" 2>/dev/null )
}

# Can this shell tell a sourced file its own path? Probed with a SEPARATE
# one-line file, so this measures shell semantics, not the lib under test —
# otherwise the expectation would be tautological. bash exposes BASH_SOURCE,
# zsh sets $0 to the sourced path; dash offers neither ($0 stays "dash"), which
# is the documented "degrade to the singleton" case, not a bug to assert away.
PROBE="${TMP_HOME}/probe-self.sh"
printf 'printf %%s "${BASH_SOURCE:-$0}"\n' > "${PROBE}"
shell_can_self_locate() {
    case "$( "$1" -c ". '${PROBE}'" 2>/dev/null )" in
        */probe-self.sh) return 0 ;;
        *) return 1 ;;
    esac
}

for SH in ${SHELLS}; do
    NAME="$(basename "${SH}")"
    [ "${SH}" = "/bin/sh" ] && NAME="sh"

    if shell_can_self_locate "${SH}"; then
        # (1) self-location works => the resolver is actually defined
        OUT="$(in_shell "${SH}" ". '${ATTEST_LIB}'; command -v resolve_own_session_token >/dev/null 2>&1 && echo DEFINED || echo UNDEFINED")"
        assert_equals "${NAME}: phase-attest finds and sources session-token.sh" "DEFINED" "${OUT}"

        # (2) own-session-first, not the singleton
        OUT="$(in_shell "${SH}" ". '${ATTEST_LIB}'; _phase_attest_token")"
        assert_equals "${NAME}: resolves own-session token, not the singleton" "session-conv-OWN" "${OUT}"
    else
        # Documented degradation: no self-location => singleton, and crucially
        # the lib must still LOAD (a `Bad substitution` here would take
        # phase_attest and phase_attested down entirely instead of degrading).
        OUT="$(in_shell "${SH}" ". '${ATTEST_LIB}'; command -v phase_attest >/dev/null 2>&1 && echo LOADED || echo DIED")"
        assert_equals "${NAME}: lib still loads without self-location" "LOADED" "${OUT}"

        OUT="$(in_shell "${SH}" ". '${ATTEST_LIB}'; _phase_attest_token")"
        assert_equals "${NAME}: degrades to the singleton (documented)" "session-FOREIGN" "${OUT}"
    fi

    # (3) DEGRADATION: no transcript for the id => singleton, never empty.
    #     zsh NOMATCH made this return empty, which is worse than a scatter.
    OUT="$(in_shell "${SH}" ". '${TOKEN_LIB}'; resolve_own_session_token" "no-such-id")"
    assert_equals "${NAME}: unmatched transcript degrades to the singleton" "session-FOREIGN" "${OUT}"

    # (4) gating-milestone lock: writer half must REFUSE and return non-zero
    OUT="$(in_shell "${SH}" ". '${ATTEST_LIB}'; phase_attest requesting-code-review 'should be refused' >/dev/null 2>&1; echo rc=\$?")"
    assert_equals "${NAME}: writer refuses a gating milestone" "rc=1" "${OUT}"

    # (5) gating-milestone lock: reader half must not honor one either.
    # Honest accounting: this leg is NOT red against the pre-fix lib — with no
    # attest file present, the broken zsh loop fell through to the jq `has()`
    # check, which returned 1 anyway. It is a contract pin on the reader half of
    # the two independent locks, not evidence the reader was broken.
    OUT="$(in_shell "${SH}" ". '${ATTEST_LIB}'; phase_attested session-conv-OWN verification-before-completion >/dev/null 2>&1; echo rc=\$?")"
    assert_equals "${NAME}: reader rejects a gating milestone" "rc=1" "${OUT}"

    # (6) a NON-gating step is still attestable (the lock must not over-refuse)
    OUT="$(in_shell "${SH}" ". '${ATTEST_LIB}'; phase_attest executing-plans 'legitimate skip' >/dev/null 2>&1; echo rc=\$?")"
    assert_equals "${NAME}: non-gating step is still attestable" "rc=0" "${OUT}"
    rm -f "${TMP_HOME}/.claude/.skill-phase-attest-session-conv-OWN"
done

# A lone copy with no sibling lib must degrade to the singleton and must NOT
# reach into the CWD for one — the CWD-derived source was a proven
# arbitrary-code-execution path (a planted ./session-token.sh gets executed).
LONE="$(mktemp -d "${TMPDIR:-/tmp}/phase-attest-lone.XXXXXX")"
cp "${ATTEST_LIB}" "${LONE}/phase-attest.sh"
mkdir -p "${LONE}/planted-cwd"
printf 'echo HOSTILE-SOURCED\n' > "${LONE}/planted-cwd/session-token.sh"
if [ -n "${ZSH_BIN}" ]; then
    OUT="$( cd "${LONE}/planted-cwd" && HOME="${TMP_HOME}" PATH="${LONE}:${PATH}" \
        "${ZSH_BIN}" -c '. phase-attest.sh; echo "tok=$(_phase_attest_token)"' 2>/dev/null )"
    assert_not_contains "bare-name \$0 never sources a CWD-planted lib" "HOSTILE-SOURCED" "${OUT}"
    assert_contains "lone lib degrades to the singleton" "tok=session-FOREIGN" "${OUT}"
fi
rm -rf "${LONE}"

print_summary
exit $?
