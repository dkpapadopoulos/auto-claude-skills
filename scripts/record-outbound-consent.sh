#!/bin/bash
# record-outbound-consent.sh — records that the user affirmatively approved an outbound
# cross-family dispatch. Called by panel / second-opinion / design-debate AFTER the user
# answers the disclosure preview, never before asking.
#
# Resolves the session token internally (writer/reader symmetry) so no caller retypes it.
set -u
_SKILL="${1:-unknown}"
_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "${_ROOT}" ]; then
    _ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || _ROOT=""
fi
_TOKEN=""
# shellcheck source=/dev/null
. "${_ROOT}/hooks/lib/session-token.sh" 2>/dev/null \
    && command -v resolve_own_session_token >/dev/null 2>&1 \
    && _TOKEN="$(resolve_own_session_token 2>/dev/null)" || true
if [ -z "${_TOKEN}" ] && [ -r "${HOME}/.claude/.skill-session-token" ]; then
    _TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)" || _TOKEN=""
fi
if [ -z "${_TOKEN}" ]; then
    echo "record-outbound-consent: no session token resolved; consent NOT recorded" >&2
    exit 1
fi
_OUT="${HOME}/.claude/.skill-outbound-consent-${_TOKEN}"
_TS="$(date +%s)"
umask 077
printf '{"skill":"%s","ts":%s}\n' "${_SKILL}" "${_TS}" > "${_OUT}" || {
    echo "record-outbound-consent: write failed" >&2; exit 1; }
echo "consent recorded for ${_SKILL}"
