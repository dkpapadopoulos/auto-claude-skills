#!/bin/bash
# OpenSpec guard — warns on git commit/push if openspec-ship hasn't run
# PreToolUse hook. Bash 3.2 compatible. Exits 0 always (warning only, fail-open).

# Fail-open: any error → silent exit (never block the user)
trap 'exit 0' ERR

# Read tool input from stdin (PreToolUse provides JSON with tool_input)
_INPUT="$(cat)"

# Extract transcript_path + command in ONE jq fork (\x1f-joined; transcript
# first — a path cannot contain \x1f, the command may contain anything).
_COMMAND=""
_TRANSCRIPT=""
if command -v jq >/dev/null 2>&1; then
    _FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[.transcript_path // "", .tool_input.command // ""] | join("\u001f")' 2>/dev/null)" || _FIELDS=""
    _TRANSCRIPT="${_FIELDS%%$'\x1f'*}"
    _COMMAND="${_FIELDS#*$'\x1f'}"
else
    # Fallback: grep for command field (may miss commands with embedded quotes)
    _COMMAND="$(printf '%s' "${_INPUT}" | grep -o '"command" *: *"[^"]*"' | head -1 | sed 's/"command" *: *"//;s/"$//')" || true
fi

# Fast path: only care about git commit/push
case "${_COMMAND}" in
    *"git commit"*|*"git push"*) ;;
    *) exit 0 ;;
esac

# Resolve session token payload-first (issue #51): the singleton is shared
# across concurrent sessions (last-writer-wins) and may name ANOTHER session.
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
if [ -f "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh"
    _SESSION_TOKEN="$(resolve_session_token_from_transcript "${_TRANSCRIPT}")"
else
    [ -f "${HOME}/.claude/.skill-session-token" ] && \
        _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
[ -z "${_SESSION_TOKEN}" ] && exit 0

# --- Push gate (fires on all git push, independent of phase) ---
# Replaces hookify require-review-before-push rule with state-aware checks.
# Gate order matches the canonical chain: REVIEW → VERIFY → SHIP. Review is
# checked first because skipping review and then chasing verification is the
# recurring failure mode — the more actionable message wins.
# Ad-hoc pushes (no composition) are allowed — no gate needed for unplanned work.
case "${_COMMAND}" in
    *"git push"*)
        _COMP_STATE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
        # Durable per-(repo+branch) ledger: gate readiness that survives chain
        # re-anchors. Fail-safe: if the helper or branch key is unavailable, the
        # ledger checks are simply false and the .completed path below governs.
        _LEDGER_OK=false
        if [ -f "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" ]; then
            # shellcheck source=lib/branch-ledger.sh
            . "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" && _LEDGER_OK=true
        fi
        _HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
        _STALE_MSG=""
        # _ledger_has MILESTONE — returns 0 if ledger satisfies; accumulates stale
        # warning text in _STALE_MSG when the recorded SHA differs from HEAD.
        _ledger_has() {
            [ "${_LEDGER_OK}" = "true" ] || return 1
            branch_ledger_has "$1" || return 1
            local _ls; _ls="$(branch_ledger_sha "$1")"
            if [ -n "${_HEAD_SHA}" ] && [ -n "${_ls}" ] && [ "${_ls}" != "${_HEAD_SHA}" ]; then
                _STALE_MSG="${_STALE_MSG}${_STALE_MSG:+; }$1 stale: recorded at ${_ls}, HEAD is ${_HEAD_SHA}. Rerun if new commits changed reviewed content."
            fi
            return 0
        }
        if [ -f "${_COMP_STATE}" ] && command -v jq >/dev/null 2>&1; then
            # Check 1: REVIEW in chain but not completed — deny with REVIEW message
            _review_in_chain=false
            _review_completed=false
            jq -e '.chain | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _review_in_chain=true
            jq -e '.completed | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _review_completed=true
            _ledger_has "requesting-code-review" && _review_completed=true
            if [ "${_review_in_chain}" = "true" ] && [ "${_review_completed}" = "false" ]; then
                _MSG="PUSH GATE: A composition chain is active and requesting-code-review has not been completed. Complete the REVIEW → VERIFY → SHIP sequence before pushing. Invoke Skill(superpowers:requesting-code-review) first."
                jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                exit 0
            fi

            # Check 2: VERIFY in chain but not completed — deny with VERIFY message
            _verif_in_chain=false
            _verif_completed=false
            jq -e '.chain | index("verification-before-completion")' "${_COMP_STATE}" >/dev/null 2>&1 && _verif_in_chain=true
            jq -e '.completed | index("verification-before-completion")' "${_COMP_STATE}" >/dev/null 2>&1 && _verif_completed=true
            _ledger_has "verification-before-completion" && _verif_completed=true
            if [ "${_verif_in_chain}" = "true" ] && [ "${_verif_completed}" = "false" ]; then
                _MSG="PUSH GATE: A composition chain is active and verification-before-completion has not run. Complete the REVIEW → VERIFY → SHIP sequence before pushing. Invoke Skill(superpowers:verification-before-completion) first."
                jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                exit 0
            fi

            # Soft staleness is NOT emitted here (no early exit, no permissionDecision):
            # doing so would auto-approve the lower-confidence path and suppress the
            # SHIP-phase advisories below. Instead _STALE_MSG is folded into _WARNINGS in
            # the SHIP-phase block so all advisories emit together as one additionalContext.
        fi
        ;;
esac

# Check if we're in SHIP phase (signal file is JSON: {"skill":"...","phase":"..."})
_SIGNAL_FILE="${HOME}/.claude/.skill-last-invoked-${_SESSION_TOKEN}"
[ -f "${_SIGNAL_FILE}" ] || exit 0
_PHASE=""
if command -v jq >/dev/null 2>&1; then
    _PHASE="$(jq -r '.phase // empty' "${_SIGNAL_FILE}" 2>/dev/null)" || true
else
    _PHASE="$(grep -o '"phase" *: *"[^"]*"' "${_SIGNAL_FILE}" | sed 's/"phase" *: *"//;s/"$//')" || true
fi
[ "${_PHASE}" = "SHIP" ] || exit 0

# Compute project root unconditionally (needed by all checks)
_proj_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_WARNINGS=""

# --- Check 1: Has openspec-ship run? ---
_openspec_ok=false
if command -v openspec >/dev/null 2>&1; then
    if [ -d "${_proj_root}/openspec/changes" ]; then
        for _d in "${_proj_root}/openspec/changes"/*/; do
            [ -d "${_d}" ] && _openspec_ok=true && break
        done
    fi
else
    if grep -q "openspec-ship" "${_SIGNAL_FILE}" 2>/dev/null; then
        _openspec_ok=true
    fi
fi
if [ "${_openspec_ok}" = "false" ]; then
    _WARNINGS="OPENSPEC GUARD: openspec-ship has not run this session. As-built documentation will be lost if you commit now. Invoke Skill(auto-claude-skills:openspec-ship) first, or proceed if documentation is not needed for this change."
fi

# --- Check 2: Has memory consolidation been performed? ---
# Marker path is keyed off the git remote URL (stable across worktrees/clones
# of the same repo); path-based fallback when no remote is configured.
# (_PLUGIN_ROOT is resolved once, above, alongside token resolution.)
_consol_marker=""
if [ -f "${_PLUGIN_ROOT}/hooks/lib/consol-marker.sh" ]; then
    # shellcheck source=lib/consol-marker.sh
    . "${_PLUGIN_ROOT}/hooks/lib/consol-marker.sh"
    _consol_marker="$(consol_marker_path "${_proj_root}")"
else
    _proj_hash="$(printf '%s' "${_proj_root}" | shasum | cut -d' ' -f1)"
    _consol_marker="${HOME}/.claude/.context-stack-consolidated-${_proj_hash}"
fi
_consol_ok=false
if [ -f "${_consol_marker}" ]; then
    _marker_time="$(stat -f %m "${_consol_marker}" 2>/dev/null || stat -c %Y "${_consol_marker}" 2>/dev/null || echo 0)"
    _last_commit="$(git -C "${_proj_root}" log -1 --format=%ct 2>/dev/null || echo 0)"
    [ "${_marker_time}" -ge "${_last_commit}" ] && _consol_ok=true
fi
if [ "${_consol_ok}" = "false" ]; then
    [ -n "${_WARNINGS}" ] && _WARNINGS="${_WARNINGS}
"
    _WARNINGS="${_WARNINGS}CONSOLIDATION GUARD: Memory consolidation has not been performed this session. Learnings may be lost. Run the memory consolidation step from ship-and-learn before committing."
fi

# --- Check 3: Are archived delta specs synced to canonical? ---
_unsynced=false
if [ -d "${_proj_root}/openspec/changes/archive" ]; then
    for _delta in "${_proj_root}/openspec/changes/archive"/*/specs/*/spec.md; do
        [ -f "${_delta}" ] || continue
        _cap="$(basename "$(dirname "${_delta}")")"
        _canonical="${_proj_root}/openspec/specs/${_cap}/spec.md"
        if [ -f "${_canonical}" ]; then
            _canon_time="$(stat -f %m "${_canonical}" 2>/dev/null || stat -c %Y "${_canonical}" 2>/dev/null || echo 0)"
            _delta_time="$(stat -f %m "${_delta}" 2>/dev/null || stat -c %Y "${_delta}" 2>/dev/null || echo 0)"
            if [ "${_canon_time}" -lt "${_delta_time}" ]; then
                _unsynced=true
                break
            fi
        else
            _unsynced=true
            break
        fi
    done
fi
if [ "${_unsynced}" = "true" ]; then
    [ -n "${_WARNINGS}" ] && _WARNINGS="${_WARNINGS}
"
    _WARNINGS="${_WARNINGS}OPENSPEC GUARD: Archived delta specs may not be synced to canonical specs at openspec/specs/. Consider running openspec validate or manually merging delta changes before committing."
fi

# --- Check 4: Has REVIEW (requesting-code-review) been completed? ---
_review_ok=true
_COMP_STATE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
if [ -f "${_COMP_STATE}" ] && command -v jq >/dev/null 2>&1; then
    # Only warn if requesting-code-review is in the chain but not in completed
    _in_chain=false
    _in_completed=false
    jq -e '.chain | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _in_chain=true
    jq -e '.completed | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _in_completed=true
    # Ledger-aware (same OR as the push gate): a durable branch milestone counts as
    # completed, so this advisory does not contradict a ledger-satisfied push gate.
    if [ "${_in_completed}" = "false" ] && [ -f "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" ]; then
        . "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null && \
            branch_ledger_has "requesting-code-review" && _in_completed=true
    fi
    if [ "${_in_chain}" = "true" ] && [ "${_in_completed}" = "false" ]; then
        _review_ok=false
    fi
fi
if [ "${_review_ok}" = "false" ]; then
    [ -n "${_WARNINGS}" ] && _WARNINGS="${_WARNINGS}
"
    _WARNINGS="${_WARNINGS}REVIEW GUARD: requesting-code-review is in the composition chain but was not completed. Invoke Skill(superpowers:requesting-code-review) before shipping, or proceed if review is not needed for this change."
fi

# Fold in the push-gate's soft staleness advisory (set during the git-push case above),
# so it emits together with the other SHIP advisories instead of via an early-exit
# permissionDecision that would auto-approve and suppress them.
if [ -n "${_STALE_MSG:-}" ]; then
    [ -n "${_WARNINGS}" ] && _WARNINGS="${_WARNINGS}
"
    _WARNINGS="${_WARNINGS}PUSH GATE (advisory): ${_STALE_MSG}"
fi

# --- Emit combined warnings ---
if [ -n "${_WARNINGS}" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg msg "${_WARNINGS}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
    else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$(printf '%s' "${_WARNINGS}" | tr '\n' ' ')"
    fi
fi
exit 0
