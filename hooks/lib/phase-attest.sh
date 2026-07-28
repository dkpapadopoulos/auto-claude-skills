#!/bin/bash
# phase-attest.sh — explicit skip-attestation for composition-chain steps.
# phase_attest <step> <reason> records a logged, review-surfaced skip in
# ~/.claude/.skill-phase-attest-<token>. Gating milestones are NEVER
# attestable: the writer refuses them here AND every reader re-checks
# (two independent locks, like the max_iterations role-allowlist).
# Spec: openspec/changes/phase-enforcement (Scenario 2, 3).

PHASE_ATTEST_GATING_EXCLUDE="requesting-code-review verification-before-completion"

# session-token.sh owns the `session-<transcript-basename>` format ("defined
# HERE and only here") — source it rather than re-deriving the shape below.
# Guarded: if it is unavailable, token resolution degrades to the singleton.
#
# SELF-LOCATION MUST BE SHELL-PORTABLE. This lib is sourced BY THE MODEL in its
# Bash turn, and that shell is not always bash — on macOS it is zsh, where
# `${BASH_SOURCE[0]}` is EMPTY. The former one-liner then computed
# `dirname ""` = `.` = the CWD, found no sibling session-token.sh, skipped the
# source, left resolve_own_session_token undefined, and fell through to the
# shared singleton — silently making the own-session-first fix of #151/#156
# INERT on the exact path it was written for (measured live: an attestation
# landed in a concurrent conversation's file). The whole test suite runs under
# bash, so nothing caught it. Regression: tests/test-phase-attest-shell-portability.sh.
#
# zsh sets $0 to the sourced file's path; bash sets it to the shell name — so
# trust $0 only when it names THIS file. Deliberately NO install-root fallback
# (CLAUDE_PLUGIN_ROOT / git toplevel): those resolve from the environment or
# the CWD, so a copy of this lib sitting anywhere would silently bind to
# whichever repo the process happens to be in, and the documented "lib absent
# => degrade to the singleton" contract would no longer hold (pinned by
# tests/test-skill-gate.sh's lone-lib case, which caught exactly that). A shell
# that provides neither BASH_SOURCE nor a path-valued $0 degrades as before.
# `${BASH_SOURCE:-}`, NOT `${BASH_SOURCE[0]:-}`: the array subscript lives in
# the NAME, so `:-` cannot save it and POSIX sh (dash) dies with `Bad
# substitution` — taking phase_attest and phase_attested down with it instead of
# degrading. Bare $BASH_SOURCE is element 0 in bash and a valid empty scalar
# everywhere else. Same idiom as hooks/openspec-guard.sh.
_PHASE_ATTEST_SELF="${BASH_SOURCE:-}"
if [ -z "${_PHASE_ATTEST_SELF}" ]; then
    # Only a $0 carrying a DIRECTORY is usable. A bare `phase-attest.sh` (zsh
    # resolving a `. phase-attest.sh` through $path) would make dirname yield
    # `.` = the CWD — the same CWD-derived root rejected above, and a proven
    # arbitrary-code-execution path: an attacker-planted ./session-token.sh in
    # the process's directory would be sourced. Degrading to the singleton is
    # strictly safer than guessing a directory.
    case "$0" in
        */phase-attest.sh) _PHASE_ATTEST_SELF="$0" ;;
    esac
fi
_PHASE_ATTEST_DIR=""
if [ -n "${_PHASE_ATTEST_SELF}" ]; then
    # CDPATH= : with CDPATH set, `cd` prints the resolved path, which the
    # substitution would capture in addition to pwd's output.
    _PHASE_ATTEST_DIR="$(CDPATH= cd "$(dirname "${_PHASE_ATTEST_SELF}")" 2>/dev/null && pwd)" || _PHASE_ATTEST_DIR=""
fi
[ -f "${_PHASE_ATTEST_DIR:-}/session-token.sh" ] && . "${_PHASE_ATTEST_DIR}/session-token.sh" 2>/dev/null || true

# _phase_attest_token: resolve OUR conversation's token the same way every
# reader does (payload-first, issue #51) rather than trusting the singleton.
# attest runs in the model's Bash turn, which has no hook payload — but it does
# carry CLAUDE_CODE_SESSION_ID, and the reader-side token is
# session-<transcript basename> where that basename IS the session id, so the
# two resolve identically. The singleton is last-writer-wins across concurrent
# sessions and regularly names a DIFFERENT conversation: pre-fix, three attests
# minutes apart in one session landed in three token files and the gate — which
# resolves payload-first — saw none of them (issue #151, reproduced live).
# The resolution itself lives in session-token.sh (which owns the token format
# and is shared with the other Bash-turn writer, issue #156); when that lib is
# unavailable this degrades to the singleton, never to a locally re-derived
# shape that could drift from the readers'.
_phase_attest_token() {
    if command -v resolve_own_session_token >/dev/null 2>&1; then
        resolve_own_session_token
        return 0
    fi
    cat "${HOME}/.claude/.skill-session-token" 2>/dev/null
}

phase_attest() {
    local step="${1:-}" reason="${2:-}"
    [ -z "$step" ] && { echo "[phase-attest] usage: phase_attest <step> <reason>" >&2; return 1; }
    [ -z "$reason" ] && { echo "[phase-attest] a reason is required — attestation is an auditable decision" >&2; return 1; }
    # Substring match on a space-padded list, NOT `for ex in $LIST`: zsh does
    # not word-split unquoted scalar expansions, so the loop form iterated ONCE
    # over the whole string and this lock silently accepted every gating
    # milestone under the model's actual shell (see phase-attest's self-location
    # note). `case` behaves identically in bash, zsh and sh.
    case " ${PHASE_ATTEST_GATING_EXCLUDE} " in
        *" ${step} "*)
            echo "[phase-attest] REFUSED: '$step' is a gating milestone and cannot be attested away (invoke the real skill)" >&2
            return 1
            ;;
    esac
    command -v jq >/dev/null 2>&1 || { echo "[phase-attest] jq required" >&2; return 1; }
    local token; token="$(_phase_attest_token)"
    [ -z "$token" ] && { echo "[phase-attest] no session token" >&2; return 1; }
    local f="${HOME}/.claude/.skill-phase-attest-${token}" tmp
    local base
    base="$(jq -c 'if type=="object" then . else {} end' "$f" 2>/dev/null)" || base=""
    [ -z "$base" ] && base="{}"
    tmp="$(printf '%s' "$base" | jq --arg s "$step" --arg r "$reason" \
        '. + {($s): {reason: $r, ts: (now | todate)}}' 2>/dev/null)" || return 1
    [ -z "$tmp" ] && { echo "[phase-attest] internal: merge produced no output" >&2; return 1; }
    printf '%s\n' "$tmp" > "${f}.tmp.$$" 2>/dev/null && mv "${f}.tmp.$$" "$f" 2>/dev/null || return 1
    # Token is logged and echoed: a scattered write is then visible in the
    # telemetry and to the model, instead of failing silently at the gate (#151).
    printf '%s gate=attest decision=recorded step=%s token=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$step" "$token" \
        >> "${HOME}/.claude/.phase-gate-events.log" 2>/dev/null || true
    echo "[phase-attest] recorded skip of '$step' under ${token} — visible at REVIEW" >&2
    return 0
}

# phase_attested <token> <step> — 0 iff attested AND not a gating milestone.
phase_attested() {
    local token="${1:-}" step="${2:-}"
    [ -z "$token" ] || [ -z "$step" ] && return 1
    # Reader-side half of the two independent locks — same zsh word-splitting
    # hazard as the writer above; keep both in the `case` form.
    case " ${PHASE_ATTEST_GATING_EXCLUDE} " in
        *" ${step} "*) return 1 ;;
    esac
    command -v jq >/dev/null 2>&1 || return 1
    local f="${HOME}/.claude/.skill-phase-attest-${token}"
    [ -f "$f" ] || return 1
    jq -e --arg s "$step" 'has($s)' "$f" >/dev/null 2>&1
}
