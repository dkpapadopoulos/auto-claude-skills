#!/bin/bash
# outbound-consent-hook.sh — observes CROSS-FAMILY OUTBOUND DISPATCH and reports
# whether the user's consent was actually recorded for it.
#
# WHY THIS EXISTS: the consent gate for panel / second-opinion / design-debate lives in
# SKILL.md prose ("ask, and wait for an answer"). Prose asks a model to stop; it does not
# make it stop. This hook is the measurement that says how often dispatch happens with no
# recorded consent — the same warn-first posture the IMPLEMENT leg uses, and for the same
# reason: a deny flip should be earned from data, not assumed.
#
# ADVISORY ONLY. It emits `systemMessage` and NEVER a permissionDecision, so it cannot
# block a dispatch and cannot become a bypass. Every inability-to-check is fail-open AND
# announced — an unchecked dispatch must never read as a checked one.

trap 'exit 0' ERR

# Backslash BEFORE quote, or the quote pass doubles the escapes it just added. Every
# caller currently passes a hardcoded ASCII literal, so this changes no output today --
# it caps the blast radius if a future caller interpolates a path or token containing
# " or \, which would otherwise emit invalid JSON that the harness silently drops.
_json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n\r'
}
_announce() {
    printf '{"systemMessage":"outbound-consent: %s"}\n' "$(_json_escape "$1")"
}

_INPUT="$(cat)"

# Cheap pre-filter, jq-free: almost no tool call mentions codex at all.
# Deliberately LOOSE. This is a cheap substring pre-filter whose only job is to let the
# overwhelming majority of tool calls exit before the jq fork. False positives here are
# SAFE and expected -- OPENAI_API_KEY in an env line, a path like codex_settings.yaml --
# they simply fall through to the precise _IS_OUTBOUND test below and exit 0 silently.
# The direction that would be unsafe is a false NEGATIVE: a dispatch shape whose text
# contains none of these words is never examined at all. That is the documented
# ceiling, and it is why the SKILL.md files say coverage is PARTIAL rather than total.
case "${_INPUT}" in *codex*|*Codex*|*CODEX*|*gemini*|*Gemini*|*GEMINI*|*openai*|*OpenAI*|*OPENAI*) ;; *) exit 0 ;; esac

if ! command -v jq >/dev/null 2>&1; then
    _announce "jq unavailable — could NOT check whether consent was recorded for this outbound dispatch."
    exit 0
fi

_TOOL="$(printf '%s' "${_INPUT}" | jq -r '.tool_name // ""' 2>/dev/null)" \
    || { _announce "hook input unparseable — consent NOT checked."; exit 0; }

# Is this actually an outbound cross-family dispatch? Two shapes reach a vendor:
#   (a) the codex-rescue subagent, via Agent/Task
#   (b) a Bash call running the codex CLI or its companion script
_IS_OUTBOUND=false
case "${_TOOL}" in
    Agent|Task)
        _SUB="$(printf '%s' "${_INPUT}" | jq -r '(.tool_input | objects | .subagent_type) // ""' 2>/dev/null)"
        case "${_SUB}" in *codex*|*gemini*|*openai*) _IS_OUTBOUND=true ;; esac
        ;;
    Bash)
        _CMD="$(printf '%s' "${_INPUT}" | jq -r '(.tool_input | objects | .command) // ""' 2>/dev/null)"
        case "${_CMD}" in
            *codex-companion*|*"codex exec"*|*"codex resume"*) _IS_OUTBOUND=true ;;
            *"gemini "*|*"openai "*|*"llm -m"*) _IS_OUTBOUND=true ;;
        esac
        ;;
esac
[ "${_IS_OUTBOUND}" = "true" ] || exit 0

# Resolve our own session token the same way every other model-turn writer does, so the
# consent a skill records under this session is the consent we read (writer/reader
# symmetry — the recurring bug class in this repo).
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "${_PLUGIN_ROOT}" ]; then
    _PLUGIN_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || _PLUGIN_ROOT=""
fi
_TOKEN=""
_LIB="${_PLUGIN_ROOT}/hooks/lib/session-token.sh"
# shellcheck source=/dev/null
. "${_LIB}" 2>/dev/null && command -v resolve_own_session_token >/dev/null 2>&1 \
    && _TOKEN="$(resolve_own_session_token 2>/dev/null)" || true
if [ -z "${_TOKEN}" ] && [ -r "${HOME}/.claude/.skill-session-token" ]; then
    _TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)" || _TOKEN=""
fi
if [ -z "${_TOKEN}" ]; then
    _announce "no session token resolved — consent for this outbound dispatch was NOT checked."
    exit 0
fi

_RECORD="${HOME}/.claude/.skill-outbound-consent-${_TOKEN}"
if [ ! -r "${_RECORD}" ]; then
    _announce "DISPATCHING OUTBOUND with NO recorded consent. The skill must show a disclosure preview, ask, and record the answer with scripts/record-outbound-consent.sh before sending."
    exit 0
fi

_TS="$(jq -r '.ts // empty' "${_RECORD}" 2>/dev/null)" || _TS=""
case "${_TS}" in ''|*[!0-9]*) _announce "consent record unreadable or malformed — treat this dispatch as UNCONSENTED."; exit 0 ;; esac

_NOW="$(date +%s 2>/dev/null)" || _NOW=""
case "${_NOW}" in ''|*[!0-9]*) _announce "clock unavailable — consent freshness NOT checked."; exit 0 ;; esac

# Bash 3.2: operands must be unquoted and validated-numeric (quoted operands abort).
_AGE=$(( _NOW - _TS ))
if [ "${_AGE}" -gt 900 ]; then
    _announce "consent on record is stale (older than 15 minutes). Re-confirm before dispatching."
fi
exit 0
