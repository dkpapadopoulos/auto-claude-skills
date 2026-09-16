#!/bin/bash
# outbound-consent-hook.sh — observes CROSS-FAMILY OUTBOUND DISPATCH that does not go
# through scripts/consult-dispatch.sh, and records it.
#
# WHY THIS EXISTS: panel and second-opinion must send through consult-dispatch.sh, which
# REFUSES without the user's approval of the exact package (see
# openspec/changes/egress-consent-dispatcher). Everything else that reaches a vendor —
# /codex:rescue, a direct `codex exec`, a proactive codex-rescue subagent, or a skill that
# skipped the dispatcher — is not consent-gated. This hook makes that traffic visible and
# writes a text-free record of it, so any future deny on bypasses is earned from data
# (the repo's warn-first convention). Measured 2026-09-16: ~250 such calls in 60 days.
#
# ADVISORY ONLY. It emits `systemMessage` and NEVER a permissionDecision, so it cannot
# block a dispatch and cannot become a bypass. Every inability-to-check is announced.
# Coverage is PARTIAL by construction: a dispatch shape whose text matches none of the
# patterns below is never seen (string-detection ceiling: variables, `bash -c`, scripts).
#
# Identity is PAYLOAD-first with no singleton fallback: the shared
# ~/.claude/.skill-session-token names whichever session wrote last (reproduced
# 2026-09-16 — the old model-side resolution misattributed a concurrent session's state).
#
# No `trap 'exit 0' ERR` on purpose: every failure path below is explicit.

# JSON-safe: C0 controls are dropped (a tab in a model-written subagent_type used to make
# the whole message unparseable, so the harness dropped the warning), backslash first.
_json_escape() {
    printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
_announce() {
    printf '{"systemMessage":"outbound-consent: %s"}\n' "$(_json_escape "$1")"
}

_INPUT="$(cat)"

# Cheap jq-free pre-filter. Deliberately LOOSE: false positives (OPENAI_API_KEY, a path
# like codex_settings.yaml) fall through to the precise classification below and exit
# silently. A false NEGATIVE is the unsafe direction and is the documented ceiling.
case "${_INPUT}" in
    *codex*|*Codex*|*CODEX*|*gemini*|*Gemini*|*GEMINI*|*openai*|*OpenAI*|*OPENAI*|*skill-egress-*) ;;
    *) exit 0 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    _announce "jq unavailable — could NOT check whether this is a cross-family dispatch outside scripts/consult-dispatch.sh."
    exit 0
fi

_META="$(printf '%s' "${_INPUT}" | jq -r '
    if type != "object" then empty else
    [ ((.tool_name // "") | tostring),
      (((.tool_input | objects | .subagent_type) // "") | tostring),
      ((.transcript_path // "") | tostring),
      (if (.agent_id // null) == null then "false" else "true" end)
    ] | join("\u001f") end' 2>/dev/null)"
if [ -z "${_META}" ]; then
    _announce "hook input unparseable — dispatch NOT checked."
    exit 0
fi
IFS=$'\x1f' read -r _TOOL _SUB _TP _SIDE <<EOF
${_META}
EOF

_SHAPE=""
_TOUCH=false
case "${_TOOL}" in
    Agent|Task)
        case "${_SUB}" in
            *codex*|*gemini*|*openai*) _SHAPE="agent:${_SUB}" ;;
        esac
        ;;
    Bash)
        _CMD="$(printf '%s' "${_INPUT}" | jq -r '((.tool_input | objects | .command) // "") | tostring' 2>/dev/null)"
        # Independent checks, highest-signal first, so a local companion verb in the same
        # command cannot hide a real send.
        case "${_CMD}" in
            *"codex exec"*|*"codex resume"*) _SHAPE="bash:codex-cli" ;;
        esac
        if [ -z "${_SHAPE}" ]; then
            case "${_CMD}" in
                *"gemini "*|*"openai "*|*"llm -m"*) _SHAPE="bash:other-vendor" ;;
            esac
        fi
        if [ -z "${_SHAPE}" ]; then
            case "${_CMD}" in
                *codex-companion*)
                    # The verb after the script name. Only these touch local job state;
                    # every other verb (task, review, adversarial-review, …) sends.
                    _VERB="$(printf '%s\n' "${_CMD}" \
                        | sed -n -E "s/.*codex-companion\.mjs[\"']?[[:space:]]+([^[:space:]\"']+).*/\1/p" \
                        | head -1)"
                    case "${_VERB}" in
                        ""|status|result|cancel|setup|--help|-h|task-resume-candidate) ;;
                        *) _SHAPE="bash:companion:${_VERB}" ;;
                    esac
                    ;;
            esac
        fi
        # Any egress state EXCEPT a pure read of the frozen package: globs such as
        # `.skill-egress-*` reach the approval records too and must be seen.
        _CMD_NOPKG="${_CMD//skill-egress-pkg-/}"
        case "${_CMD_NOPKG}" in
            *skill-egress-*) _TOUCH=true ;;
        esac
        ;;
esac

if [ -z "${_SHAPE}" ] && [ "${_TOUCH}" = "true" ]; then
    _SHAPE="bash:consent-state"
fi
[ -n "${_SHAPE}" ] || exit 0

_TOKEN=""
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "${_PLUGIN_ROOT}" ]; then
    _PLUGIN_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || _PLUGIN_ROOT=""
fi
# shellcheck source=/dev/null
_ID_NOTE=""
if . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null \
    && command -v session_token_from_transcript >/dev/null 2>&1; then
    _TOKEN="$(session_token_from_transcript "${_TP}")"
else
    _ID_NOTE=" (session identity unavailable: token library not loadable under ${_PLUGIN_ROOT:-<no plugin root>}, so the record carries no session)"
fi

_NOW="$(date +%s 2>/dev/null)"
case "${_NOW}" in ''|*[!0-9]*) _NOW=0 ;; esac
_LOG="${EGRESS_BYPASS_SHADOW_LOG:-${HOME}/.claude/.egress-bypass-shadow.jsonl}"
_RECORDED=false
_REC="$(jq -nc --arg shape "${_SHAPE}" --arg tool "${_TOOL}" --arg tok "${_TOKEN}" \
        --argjson side "${_SIDE}" --argjson ts "${_NOW}" \
    '{schema_version: 1, ts: $ts, tool: $tool, shape: ($shape | .[0:80]),
      sidechain: $side, session_token: (if $tok == "" then null else $tok end)}' 2>/dev/null)"
if [ -n "${_REC}" ] && ( umask 077 && printf '%s\n' "${_REC}" >> "${_LOG}" ) 2>/dev/null; then
    _RECORDED=true
    _LINES="$(wc -l < "${_LOG}" 2>/dev/null | tr -d ' ')"
    case "${_LINES}" in ''|*[!0-9]*) _LINES=0 ;; esac
    if [ "${_LINES}" -gt 2000 ]; then
        ( umask 077 && tail -n 1000 "${_LOG}" > "${_LOG}.tmp.$$" ) 2>/dev/null \
            && mv -f "${_LOG}.tmp.$$" "${_LOG}" 2>/dev/null || rm -f "${_LOG}.tmp.$$" 2>/dev/null
    fi
fi
_NOTE="${_ID_NOTE}"
if [ "${_RECORDED}" != "true" ]; then
    if [ -z "${_REC}" ]; then
        _NOTE="${_NOTE} (this observation was not recorded: the record could not be built)"
    else
        _NOTE="${_NOTE} (this observation was not recorded: ${_LOG} is not writable)"
    fi
fi

if [ "${_SHAPE}" = "bash:consent-state" ]; then
    _announce "a command names egress approval records (~/.claude/.skill-egress-{receipt,ask,veto}-*) directly. Only the AskUserQuestion hooks and scripts/consult-dispatch.sh may write them; a hand-written receipt forges the user's approval.${_NOTE}"
else
    _announce "cross-family dispatch outside scripts/consult-dispatch.sh (${_SHAPE}) — this send is NOT consent-gated, only observed. panel and second-opinion must send through the dispatcher.${_NOTE}"
fi
exit 0
