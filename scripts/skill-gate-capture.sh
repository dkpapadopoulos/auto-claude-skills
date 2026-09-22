#!/bin/bash
# skill-gate-capture.sh — diagnostic subprocess for the skill gate (issue #177).
#
# WHY THIS EXISTS. Two `Skill(...)` calls were denied live by a PreToolUse:Skill
# hook, and replaying hooks/skill-gate.sh on disk with the same payload ALLOWS
# every time — including for a control skill. The live denier could not be
# identified, and unlike the push gate there was no record to adjudicate
# against. This is the Skill-gate analogue of #127/#128.
#
# The diagnostic question it answers is precisely: when the live gate denied,
# what did the ON-DISK gate decide for the same payload? Three answers, and the
# third is the one the push-gate instrument had to learn to distinguish:
#
#   deny  + deny   -> the on-disk gate explains the live decision
#   deny  + allow  -> DRIFT: the live denier is not this file as it exists now
#   deny  + incomplete -> the replay never reached a decision (crashed or
#                         early-exited), which is NOT an allow
#
# The replayed gate is itself fail-open (`trap 'exit 0' ERR`), so an empty
# replay stdout cannot be read as "allowed". skill-gate.sh therefore prints a
# `__SGC_EVALUATED__` sentinel under the replay flag ONLY, and this script
# classifies POSITIVELY on that sentinel rather than on silence.
#
# Invoked ONLY from skill-gate.sh's hardened EXIT trap, in a fully-redirected
# subshell. Never sourced: a source-time failure inside the gate would trip its
# fail-open ERR trap and skip enforcement. Diagnostic-only; every path exits 0.
# Bash 3.2 compatible.
set -u

command -v jq >/dev/null 2>&1 || exit 0   # jq-gated: diagnostic only

_dir="${HOME}/.claude"
[ -d "${_dir}" ] || exit 0
_log="${_dir}/.skill-gate-invocation-log"

# 0600 BEFORE the first write: the record carries a skill name and a session
# token, and the file is created by whichever session logs first.
if [ ! -e "${_log}" ]; then
    : > "${_log}" 2>/dev/null || exit 0
    chmod 600 "${_log}" 2>/dev/null || :
fi

_decision="${SGC_DECISION:-allow}"
_skill="${SGC_SKILL:-}"
_gate="${SGC_GATE_PATH:-}"
_replay="not-attempted"

# --- on-disk replay, deny only ----------------------------------------------
# Only a deny is worth the second run: an allow that the on-disk gate also
# allows tells us nothing, and this runs synchronously in an EXIT trap.
case "${_decision}" in
    deny*)
        if [ -n "${SGC_INPUT:-}" ] && [ -r "${_gate}" ]; then
            _rout="$(
                printf '%s' "${SGC_INPUT}" \
                | SKILL_GATE_CAPTURE_DISABLE=1 SKILL_GATE_CAPTURE_REPLAY=1 \
                  /bin/bash "${_gate}" 2>/dev/null
            )" || _rout=""
            # Deny BEFORE the sentinel: the sentinel precedes every deny site,
            # so a deny replay contains both and testing the sentinel first
            # would classify every deny as an allow. This is the exact ordering
            # bug that made the push-gate instrument report "drift confirmed"
            # for every one of its first 26 records.
            case "${_rout}" in
                *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*)
                    _replay="deny" ;;
                *__SGC_EVALUATED__*)
                    _replay="allow" ;;
                *)
                    _replay="incomplete" ;;
            esac
        else
            _replay="cannot-replay"
        fi
        ;;
esac

_rec="$(jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
    --arg decision "${_decision}" \
    --arg skill "${_skill}" \
    --arg replay "${_replay}" \
    --arg token "${SGC_SESSION_TOKEN:-}" \
    --arg gate "${_gate}" \
    --arg cksum "$( [ -r "${_gate}" ] && cksum < "${_gate}" 2>/dev/null | awk '{print $1}' )" \
    --arg transcript "${SGC_TRANSCRIPT:-}" \
    '{ts:$ts,schema_version:1,decision:$decision,skill:$skill,
      ondisk_replay_decision:$replay,session_token:$token,
      gate_path:$gate,gate_cksum:$cksum,transcript_path:$transcript}' 2>/dev/null)" || exit 0

[ -n "${_rec}" ] || exit 0
printf '%s\n' "${_rec}" >> "${_log}" 2>/dev/null || exit 0

# rotate to the last 500, atomically
_n="$(wc -l < "${_log}" 2>/dev/null | tr -d ' ')"
case "${_n}" in
    ''|*[!0-9]*) exit 0 ;;
esac
if [ "${_n}" -gt 500 ]; then
    _tmp="${_log}.tmp.$$"
    if (umask 077; tail -n 500 "${_log}" > "${_tmp}" 2>/dev/null); then
        mv "${_tmp}" "${_log}" 2>/dev/null || rm -f "${_tmp}" 2>/dev/null
    else
        rm -f "${_tmp}" 2>/dev/null
    fi
fi
exit 0
