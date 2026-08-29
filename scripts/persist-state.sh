#!/bin/bash
# persist-state.sh — the ONE place session-openspec-state is written from a
# model Bash turn. It resolves the session token internally and calls the
# matching openspec_state_* function, so the model authors only the payload
# (intent text, change slug) and never retypes token-resolution logic.
#
# WHY THIS EXISTS: that resolution was previously an inline ~150-word
# incantation duplicated across both trigger configs, both main hooks, and
# three SKILL.md bodies, kept in sync only by a content test. Correctness
# depended on the model re-deriving it correctly every time — the root cause of
# the repo's longest-running bug class (writer/reader token symmetry: #51/#97/
# #122/#131/#133/#151/#156/#157), including two skills that hand-rolled the
# WRONG copy (the forbidden singleton read). Single-sourcing it here makes the
# fix structural: there is nothing left to hand-roll. Mirrors the posture of
# scripts/verify-and-record.sh (token resolved internally, model authors none).
#
# Usage:
#   persist-state.sh set-intent          "<confirmed intent> :: out-of-scope: <...>"
#   persist-state.sh upsert-change       "<slug>" "<plan_path>" "<spec_path>" "<capability>" "<design_path>"
#   persist-state.sh set-discovery-path  "<slug>" "<path>"
#   persist-state.sh set-hypotheses      "<slug>" "<hyps_json_array>"
#
# Args AFTER the op map positionally onto the openspec_state_* signature AFTER
# the token — i.e. the same order the lib expects, minus the token.
#
# Exit: 0 = op dispatched (the lib's own no-op-on-empty semantics still apply);
# 2 = unknown/missing op; 1 = the state lib could not be sourced. A degraded
# token (lib absent) falls back to the singleton exactly as the readers do, so
# a missing session-token.sh degrades rather than fails.
#
# Bash 3.2.
set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# --- token: resolve_own_session_token -> singleton ---------------------------
# This is the OPENSPEC-STATE resolution, which is NOT the same as the verdict
# family's. Deliberately does NOT honor SKILL_SESSION_TOKEN, unlike
# verify-and-record.sh: no openspec-state reader (the PLAN design guard) honors
# that override, so writing under it would land state nobody reads — the exact
# #157 "write state nobody reads" anti-pattern. Byte-for-byte the OLD inline
# incantation this script replaces: resolve_own_session_token (payload-derived,
# matching the reader), else the shared last-writer-wins singleton.
TOKEN=""
if [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=../hooks/lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_own_session_token >/dev/null 2>&1 && TOKEN="$(resolve_own_session_token)"
fi
# NB: NO `|| echo default` tail (unlike verify-and-record.sh). Under a double
# degrade (lib absent AND no singleton file), the old inline incantation left
# TOKEN empty and every openspec_state_* helper no-ops on an empty token — the
# documented fail-open contract. A literal "default" would instead WRITE
# ~/.claude/.skill-openspec-state-default, a dead file no reader falls back to,
# collidable across concurrently-degraded sessions. Keep the empty-token no-op.
[ -n "$TOKEN" ] || TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)" || true

# --- state lib ---------------------------------------------------------------
if [ ! -f "${PLUGIN_ROOT}/hooks/lib/openspec-state.sh" ]; then
    echo "persist-state: hooks/lib/openspec-state.sh not found under ${PLUGIN_ROOT}" >&2
    exit 1
fi
# shellcheck source=../hooks/lib/openspec-state.sh
. "${PLUGIN_ROOT}/hooks/lib/openspec-state.sh" 2>/dev/null || { echo "persist-state: could not source openspec-state.sh" >&2; exit 1; }

_usage() {
    echo "persist-state: usage: persist-state.sh <set-intent|upsert-change|set-discovery-path|set-hypotheses> [args...]" >&2
}

[ "$#" -ge 1 ] || { _usage; exit 2; }
_op="$1"; shift

case "${_op}" in
    set-intent)         command -v openspec_state_set_intent         >/dev/null 2>&1 && openspec_state_set_intent         "$TOKEN" "$@" ;;
    upsert-change)      command -v openspec_state_upsert_change      >/dev/null 2>&1 && openspec_state_upsert_change      "$TOKEN" "$@" ;;
    set-discovery-path) command -v openspec_state_set_discovery_path >/dev/null 2>&1 && openspec_state_set_discovery_path "$TOKEN" "$@" ;;
    set-hypotheses)     command -v openspec_state_set_hypotheses     >/dev/null 2>&1 && openspec_state_set_hypotheses     "$TOKEN" "$@" ;;
    *) echo "persist-state: unknown op '${_op}'" >&2; _usage; exit 2 ;;
esac
exit 0
