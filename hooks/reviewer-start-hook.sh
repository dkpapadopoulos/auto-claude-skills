#!/bin/bash
# reviewer-start-hook.sh — SubagentStart
#
# Records the commit a subagent was pointed at: HEAD as the subagent STARTS,
# before it does any work. The reviewer join (reviewer-evidence-hook.sh +
# reviewer-completion-hook.sh, hooks/lib/reviewer-pairing.sh) stamps the
# `reviewer-returned` milestone with this sha.
#
# Why a third hook: for a FOREGROUND dispatch, PostToolUse(Agent) fires ~30ms
# AFTER SubagentStop (measured on CLI 2.1.236, 3 of 3), so the dispatch hook's
# HEAD is the HEAD after the reviewer finished. A material commit made during
# the review (by the reviewer itself, or a concurrent session in a shared
# checkout) was then recorded as reviewed, and the REVIEW leg credited it
# (final review I2, ruling F3, review-credit-from-evidence). SubagentStart fires
# before the subagent runs in either mode.
#
# Records EVERY subagent, like the completion half: this payload has no
# `description`, so the dispatch hook's classifier cannot run here, and a start
# record is not a credit. The dispatch hook still classifies; the completion
# hook still has to see the agent finish on the same branch.
#
# A recorder: it emits nothing on stdout, sets no permissionDecision, and every
# failure path exits 0 silently. A failure here only loses the start record, and
# the join then records `-` for a foreground reviewer, which never credits.
# Never sourced by the guard, so NOT in _GATE_ENFORCE_LIBS.
#
# Bash 3.2 compatible.

trap 'exit 0' ERR
set -uo pipefail

_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "${_PLUGIN_ROOT}" ]; then
    # Split, not `X="${VAR:-$(…)}"`: a failing substitution in a top-level
    # assignment trips the ERR trap at that line (see reviewer-completion-hook.sh).
    _PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)" || _PLUGIN_ROOT=""
fi
[ -n "${_PLUGIN_ROOT}" ] || exit 0

_INPUT="$(cat 2>/dev/null)"
[ -z "${_INPUT}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# One jq fork, \x1f-joined (the repo's field separator; never \n).
_FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[
    (.hook_event_name // "" | tostring),
    (.session_id // "" | tostring),
    (.agent_id // "" | tostring)
  ] | join("\u001f")' 2>/dev/null)" || exit 0
[ -z "${_FIELDS}" ] && exit 0

_EVENT="${_FIELDS%%$'\x1f'*}";  _R1="${_FIELDS#*$'\x1f'}"
_SID="${_R1%%$'\x1f'*}"
_AID="${_R1#*$'\x1f'}"

# Registered on SubagentStart only; a widened registration must not start
# writing start records on another event.
[ "${_EVENT}" = "SubagentStart" ] || exit 0
[ -n "${_AID}" ] || exit 0

# #137 source-guard form, probing the lib's LAST definition (cell (s) in
# tests/test-reviewer-completion-hook.sh pins it for every pairing hook).
_PAIR_OK=false
# shellcheck source=lib/reviewer-pairing.sh
. "${_PLUGIN_ROOT}/hooks/lib/reviewer-pairing.sh" 2>/dev/null && command -v reviewer_pairing_note_mismatch >/dev/null 2>&1 && _PAIR_OK=true || true
[ "${_PAIR_OK}" = "true" ] || exit 0

_LEDGER_OK=false
# shellcheck source=lib/branch-ledger.sh
. "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null && command -v branch_ledger_key >/dev/null 2>&1 && _LEDGER_OK=true || true
[ "${_LEDGER_OK}" = "true" ] || exit 0

# The key binds the record to a (repo, branch); a start on another branch than
# the join's is never read (reviewer_pairing_start_sha).
_KEY="$(branch_ledger_key 2>/dev/null)" || _KEY=""
[ -n "${_KEY}" ] || exit 0
_SHA="$(git rev-parse HEAD 2>/dev/null)" || _SHA=""
reviewer_pairing_note_start "${_SID}" "${_AID}" "${_KEY}" "${_SHA}" || true

exit 0
