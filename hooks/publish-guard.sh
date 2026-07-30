#!/bin/bash
# publish-guard.sh — denies gh publications carrying private memory text (#174).
# PreToolUse (Bash matcher). Separate from openspec-guard.sh on purpose: the
# push gate's fail-open ERR trap and lib-sourcing order are load-bearing.
#
# Detection is FAIL-CLOSED (a match always denies). Inability to check is
# FAIL-OPEN and ANNOUNCED — absent corpus, missing jq, missing/unsourceable
# git-command.sh (or its functions undefined after sourcing), missing engine,
# mktemp failure, unreadable body — never silently (#174 round 1).

trap 'exit 0' ERR

# jq-free emitter: some inability-to-check paths fire before jq is confirmed
# available (or while sourcing may have failed), so they cannot build JSON
# with jq. $1 MUST be a fixed literal string this file controls — never
# runtime data (a path, the command, matched text) — printf does no JSON
# escaping, so anything else would be an injection risk.
_announce() {
    printf '{"systemMessage":"publish-guard: could not check for private-memory text (%s) — allowing, but the #174 leak gate did NOT run."}\n' "$1"
}

_INPUT="$(cat)"

# Cheap pre-filter, no jq required: the overwhelming majority of Bash calls
# never mention "gh" at all, so they exit here, silently, even if jq itself
# is broken below. This does not replace the precise jq-based filter further
# down — it only bounds how often the jq-unavailable announce can fire.
case "${_INPUT}" in *gh*) ;; *) exit 0 ;; esac

if ! command -v jq >/dev/null 2>&1; then
    _announce "jq unavailable"
    exit 0
fi

_COMMAND="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0
case "${_COMMAND}" in *gh*) ;; *) exit 0 ;; esac

_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ ! -f "${_ROOT}/hooks/lib/git-command.sh" ]; then
    _announce "git-command.sh unavailable"
    exit 0
fi
if ! . "${_ROOT}/hooks/lib/git-command.sh" 2>/dev/null; then
    _announce "git-command.sh unavailable"
    exit 0
fi
if ! command -v command_invokes_gh_publish >/dev/null 2>&1 || ! command -v gh_publish_body_files >/dev/null 2>&1; then
    _announce "git-command.sh unavailable"
    exit 0
fi

command_invokes_gh_publish "${_COMMAND}" || exit 0

_ENGINE="${_ROOT}/scripts/memory-leak-check.sh"
if [ ! -f "${_ENGINE}" ]; then
    _announce "leak engine unavailable"
    exit 0
fi

# Announced degradation: when no corpus resolves there is nothing to leak, but
# silence would be indistinguishable from a clean check. Probe once, on the
# publish path only, so ordinary Bash calls stay quiet.
# `|| _MEMPROBE=""` keeps this assignment's own exit status 0 regardless of
# the engine's — a broken TMPDIR (etc.) would otherwise trip the blanket ERR
# trap right here and exit silently, before the properly-announced `_TMP`
# mktemp guard a few lines down ever runs (issue #174 round, M4).
# `2>&1 >/dev/null` is stderr-only capture, and the order is deliberate: the
# engine writes its diagnostics (the "no memory corpus" notice this case
# matches) to >&2, while stdout carries LEAK findings we do not want here.
# Reversing to `>/dev/null 2>&1` would discard both and the probe would never
# match — do not "tidy" it.
_MEMPROBE="$(/bin/bash "${_ENGINE}" /dev/null 2>&1 >/dev/null)" || _MEMPROBE=""
case "${_MEMPROBE}" in
    *"no memory corpus"*)
        jq -n --arg msg "publish-guard: could not check — no local memory corpus resolved for this repo. Allowing (nothing to leak)." \
            '{"systemMessage":$msg}'
        exit 0 ;;
esac

if ! _TMP="$(mktemp -d "${TMPDIR:-/tmp}/pubguard.XXXXXXXX")"; then
    _announce "no temp dir"
    exit 0
fi
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

# Structural backstop (issue #174 round): command_invokes_gh_publish already
# confirmed (above) this command IS a publication. If the resolver just above
# found ZERO body files, yet the command string still carries a token that
# names a body FILE, that is exactly the "cannot check" case the Global
# Constraint requires be ANNOUNCED, not passed silently — a catch-all for
# this resolver's known shapes AND any future flag/order gh_publish_body_files
# doesn't yet parse.
if [ "${_N}" -eq 0 ]; then
    case "${_COMMAND}" in
        *--input*|*=@*|*--body-file*|*-F*)
            _UNCHECKED="${_UNCHECKED}${_UNCHECKED:+; }body-file token present but no file resolved" ;;
    esac
fi

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
