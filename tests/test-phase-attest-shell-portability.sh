#!/usr/bin/env bash
# test-phase-attest-shell-portability.sh
#
# phase-attest.sh is sourced BY THE MODEL in its Bash turn — and that shell is
# not necessarily bash. On macOS it is zsh, where `${BASH_SOURCE[0]}` is EMPTY:
# the self-location on line 14 then resolved to `dirname ""` = `.` = the CWD,
# `[ -f "$CWD/session-token.sh" ]` failed, session-token.sh was never sourced,
# `resolve_own_session_token` stayed undefined, and `_phase_attest_token` fell
# through to the shared last-writer-wins singleton — silently making the
# own-session-first fix of #151/#156 INERT on the exact path it was written for.
#
# Measured live: an attestation landed in a concurrent conversation's file while
# the same code resolved correctly under `bash -c`. The whole suite runs under
# bash, so nothing caught it.
#
# These tests exercise the lib under EVERY shell the model might source it from.
# Bash 3.2 compatible (the harness); the subject runs under zsh too.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-phase-attest-shell-portability.sh ==="

LIB="${PROJECT_ROOT}/hooks/lib/phase-attest.sh"
assert_file_exists "phase-attest.sh exists" "${LIB}"

# Synthetic HOME: an own-session transcript for conv-OWN, and a singleton that
# names a DIFFERENT conversation. A correct resolution returns session-conv-OWN;
# a fallback to the singleton returns session-FOREIGN. The two are
# distinguishable, so this asserts the fix, not merely that a token came back.
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/phase-attest-shell.XXXXXX")" || exit 1
trap 'rm -rf "${TMP_HOME}"' EXIT
mkdir -p "${TMP_HOME}/.claude/projects/proj"
: > "${TMP_HOME}/.claude/projects/proj/conv-OWN.jsonl"
printf 'session-FOREIGN' > "${TMP_HOME}/.claude/.skill-session-token"

# Run from a directory that is NOT hooks/lib, so a CWD-relative self-location
# cannot accidentally succeed. This mirrors the real invocation: the model
# sources the lib by absolute path while sitting in the repo root.
run_in_shell() {
    # $1 = shell binary
    ( cd "${PROJECT_ROOT}" && HOME="${TMP_HOME}" CLAUDE_CODE_SESSION_ID="conv-OWN" \
        "$1" -c ". \"${LIB}\" 2>/dev/null; _phase_attest_token" 2>/dev/null )
}

# --- bash control: this always passed, which is why the bug hid ---
BASH_TOK="$(run_in_shell /bin/bash)"
assert_equals "bash: resolves own-session token (control)" "session-conv-OWN" "${BASH_TOK}"

# --- zsh: the model's actual Bash-tool shell on macOS ---
if command -v zsh >/dev/null 2>&1; then
    ZSH_TOK="$(run_in_shell "$(command -v zsh)")"
    assert_equals "zsh: resolves own-session token (not the singleton)" \
        "session-conv-OWN" "${ZSH_TOK}"

    # Name the failure mode explicitly: a silent singleton fallback is the exact
    # regression, so assert we did not merely get *some* token back.
    if [ "${ZSH_TOK}" = "session-FOREIGN" ]; then
        echo "  (zsh fell back to the singleton — session-token.sh was never sourced)"
    fi

    # sh (dash/bash-as-sh) is the other plausible non-bash sourcing shell.
    if [ -x /bin/sh ]; then
        SH_TOK="$(run_in_shell /bin/sh)"
        assert_equals "sh: resolves own-session token" "session-conv-OWN" "${SH_TOK}"
    fi
else
    # Honest degradation: report loudly rather than silently passing. zsh is the
    # shell the bug was found in, so its absence means this file proves little.
    echo "  SKIP: zsh not installed — the zsh leg (the one that caught the bug) did not run"
fi

print_summary
exit $?
