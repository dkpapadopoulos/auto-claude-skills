#!/usr/bin/env bash
# test-session-token-strict.sh — resolve_own_session_token_strict never borrows the
# shared singleton.
#
# The egress consent dispatcher reads approval receipts under the resolved token. The
# existing resolve_own_session_token silently falls back to ~/.claude/.skill-session-token,
# which names whichever session wrote last — so a receipt read under it can be ANOTHER
# conversation's approval. The strict variant must print nothing and return 1 instead.
#
# The lib is sourced by the model in its own shell (zsh on macOS), so every cell runs in
# every available shell; bash is kept as the control.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-session-token-strict.sh ==="

LIB="${PROJECT_ROOT}/hooks/lib/session-token.sh"
SHELLS="/bin/bash"
for _cand in "$(command -v zsh 2>/dev/null)" "$(command -v dash 2>/dev/null)"; do
    [ -n "${_cand}" ] && [ -x "${_cand}" ] && SHELLS="${SHELLS} ${_cand}"
done

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/tok-strict.XXXXXX")" || exit 1
trap 'rm -rf "${TMP_HOME}"' EXIT
mkdir -p "${TMP_HOME}/.claude/projects/proj"
: > "${TMP_HOME}/.claude/projects/proj/conv-OWN.jsonl"
printf 'session-FOREIGN' > "${TMP_HOME}/.claude/.skill-session-token"

# $1 shell, $2 function, $3 CLAUDE_CODE_SESSION_ID ("-" = unset). Prints "<out>|<rc>".
run_fn() {
    local _sh="$1" _fn="$2" _id="$3"
    if [ "${_id}" = "-" ]; then
        ( cd "${TMP_HOME}" && env -u CLAUDE_CODE_SESSION_ID HOME="${TMP_HOME}" \
            "${_sh}" -c ". '${LIB}'; ${_fn}; printf '|%s' \$?" 2>/dev/null )
    else
        ( cd "${TMP_HOME}" && HOME="${TMP_HOME}" CLAUDE_CODE_SESSION_ID="${_id}" \
            "${_sh}" -c ". '${LIB}'; ${_fn}; printf '|%s' \$?" 2>/dev/null )
    fi
}

for sh in ${SHELLS}; do
    n="$(basename "${sh}")"
    assert_equals "[${n}] valid id + transcript -> own token, rc 0" \
        "session-conv-OWN|0" "$(run_fn "${sh}" resolve_own_session_token_strict conv-OWN)"
    assert_equals "[${n}] valid id, no transcript -> nothing, rc 1 (singleton NOT used)" \
        "|1" "$(run_fn "${sh}" resolve_own_session_token_strict conv-MISSING)"
    assert_equals "[${n}] id unset -> nothing, rc 1" \
        "|1" "$(run_fn "${sh}" resolve_own_session_token_strict -)"
    assert_equals "[${n}] path-unsafe id -> nothing, rc 1" \
        "|1" "$(run_fn "${sh}" resolve_own_session_token_strict '../proj/conv-OWN')"
    # Control: the non-strict resolver's documented degradation is unchanged.
    assert_equals "[${n}] control: resolve_own_session_token still falls back to the singleton" \
        "session-FOREIGN|0" "$(run_fn "${sh}" resolve_own_session_token conv-MISSING)"
    assert_equals "[${n}] control: resolve_own_session_token still prefers the own token" \
        "session-conv-OWN|0" "$(run_fn "${sh}" resolve_own_session_token conv-OWN)"
done

print_summary
