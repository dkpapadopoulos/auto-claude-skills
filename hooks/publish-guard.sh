#!/bin/bash
# publish-guard.sh — denies gh publications carrying private memory text (#174).
# PreToolUse (Bash matcher). Separate from openspec-guard.sh on purpose: the
# push gate's fail-open ERR trap and lib-sourcing order are load-bearing.
#
# Detection is FAIL-CLOSED (a match always denies). Inability to check is
# FAIL-OPEN and announced (absent corpus, missing jq, unreadable body).

trap 'exit 0' ERR

_INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

_COMMAND="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0
case "${_COMMAND}" in *gh*) ;; *) exit 0 ;; esac

_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -f "${_ROOT}/hooks/lib/git-command.sh" ] || exit 0
. "${_ROOT}/hooks/lib/git-command.sh" 2>/dev/null || exit 0
command -v command_invokes_gh_publish >/dev/null 2>&1 || exit 0
command -v gh_publish_body_files      >/dev/null 2>&1 || exit 0

command_invokes_gh_publish "${_COMMAND}" || exit 0

_ENGINE="${_ROOT}/scripts/memory-leak-check.sh"
[ -f "${_ENGINE}" ] || exit 0

# Announced degradation: when no corpus resolves there is nothing to leak, but
# silence would be indistinguishable from a clean check. Probe once, on the
# publish path only, so ordinary Bash calls stay quiet.
_MEMPROBE="$(/bin/bash "${_ENGINE}" /dev/null 2>&1 >/dev/null)"
case "${_MEMPROBE}" in
    *"no memory corpus"*)
        jq -n --arg msg "publish-guard: could not check — no local memory corpus resolved for this repo. Allowing (nothing to leak)." \
            '{"systemMessage":$msg}'
        exit 0 ;;
esac

_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pubguard.XXXXXXXX")" || exit 0
trap 'rm -rf "${_TMP}"' EXIT

_FINDINGS=""
_UNCHECKED=""

_check() {  # _check <file> <label>
    local _out _rc
    if [ ! -r "$1" ]; then
        _UNCHECKED="${_UNCHECKED}${_UNCHECKED:+; }$2 unreadable"
        return 0
    fi
    _out="$(/bin/bash "${_ENGINE}" "$1" 2>/dev/null)"
    _rc=$?
    case "${_rc}" in
        1) _FINDINGS="${_FINDINGS}${_FINDINGS:+
}${_out}" ;;
        0) : ;;
        *) _UNCHECKED="${_UNCHECKED}${_UNCHECKED:+; }$2 engine exit ${_rc}" ;;
    esac
}

# 1. The whole command string. This is what covers an inline `--body` without
#    parsing it — strictly conservative, since a 16-word private run cannot
#    appear among flags and paths unless it IS the body.
printf '%s\n' "${_COMMAND}" > "${_TMP}/cmd"
_check "${_TMP}/cmd" "command"

# 2. Each --body-file. Iterated through a pipe-free redirect so _FINDINGS
#    survives: `... | while read` would run the loop in a SUBSHELL and every
#    finding would be discarded.
gh_publish_body_files "${_COMMAND}" > "${_TMP}/files" 2>/dev/null || : > "${_TMP}/files"
_N=0
while IFS= read -r _bf; do
    [ -n "${_bf}" ] || continue
    _N=$((_N + 1))
    _check "${_bf}" "body-file ${_N}"
done < "${_TMP}/files"

if [ -n "${_FINDINGS}" ]; then
    _MSG="PUBLICATION BLOCKED (#174): this publication reproduces private local-memory text verbatim, and the tracker is public.

${_FINDINGS}

Cite the evidence as memory/<file>.md:<line> instead of quoting it. The citation is auditable by anyone holding the corpus, and publishes no private text."
    jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
    exit 0
fi

if [ -n "${_UNCHECKED}" ]; then
    jq -n --arg msg "publish-guard: could not check this body for private-memory text (${_UNCHECKED}) — allowing, but the #174 leak gate did not run." \
        '{"systemMessage":$msg}'
fi
exit 0
