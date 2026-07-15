#!/bin/bash
# gate-status.sh — explain what the push gate (hooks/openspec-guard.sh) would
# do for `git push` from this repo, right now, and why.
#
# PURELY OBSERVATIONAL: prints a report and always exits 0. It never writes
# state and its output must never be wired into an enforcement decision — the
# guard is the only decider. ("Confusing gates produce human bypasses" — this
# script exists so the bypass is never the first resort.)
#
# Design constraints (post-audit triage 2026-07-15, item 2):
#   (a) sources the guard's OWN evidence libs (verdict.sh, branch-ledger.sh,
#       session-token.sh) and mirrors openspec-guard.sh's decision ORDER —
#       evidence parsing is never reimplemented here;
#   (b) observational only (exit 0 always);
#   (c) docs/enforcement-map.md ships in the same change; --help must stay in
#       sync with it (tests/test-gate-status.sh pins shared phrases);
#   (d) staleness line uses hooks/lib/staleness-delta.sh — the SAME classifier
#       the 2026-07-15 backtest ran (advisory stands: 0 catches / 48 PRs).
#
# Bash 3.2. Fail-open: a missing lib or tool is REPORTED, never fatal.

_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'HELP'
gate-status.sh — explain what the push gate would do for `git push` right now.

Observational only: exits 0 always; never blocks anything itself.

The push gate (hooks/openspec-guard.sh) evaluates, in ORDER:
  1. compound mutate-then-push   deny if one command commits/merges/rebases
                                 AND pushes (evidence is pre-exec; always
                                 split the push into its own command)
  2. chain REVIEW gate           deny if requesting-code-review is in the
                                 active composition chain but not completed
  3. chain VERIFY gate           deny if verification-before-completion is in
                                 the chain but not completed
  4. verify-hardening            deny if the verification verdict AT HEAD
                                 reports failing gates (sha must equal HEAD)
  5. global fail-closed gate     deny any agent push without a REVIEW record
                                 AND a VERIFY signal for this branch
                                 (ledger, .completed, or clean verdict @HEAD)
  6. routing governance          deny pushes touching skills/|config/|hooks/
                                 in a routing repo without a clean verdict
                                 covering those changes
  gh pr merge / gh api merge traverse gates 2-5 like a push (audit F2).
  REVIEW staleness (HEAD moved past the review SHA) is ADVISORY BY DESIGN —
  backtested 2026-07-15: every deny variant would have blocked 56-94% of
  clean merges and caught 0 defects (openspec/changes/gate-status/).

Bypasses (human-only): push from your own terminal, or launch Claude Code
with ACSM_SKIP_PUSH_GATE=1 in its environment.

Full map: docs/enforcement-map.md
HELP
    exit 0
fi

# --- source the guard's evidence libs (report, never die) -------------------
_missing=""
for _lib in session-token.sh branch-ledger.sh verdict.sh staleness-delta.sh; do
    if [ -f "${_ROOT}/hooks/lib/${_lib}" ]; then
        # shellcheck disable=SC1090
        . "${_ROOT}/hooks/lib/${_lib}" 2>/dev/null || _missing="${_missing} ${_lib}"
    else
        _missing="${_missing} ${_lib}"
    fi
done
_HAS_JQ=true; command -v jq >/dev/null 2>&1 || _HAS_JQ=false

_proot="$(git rev-parse --show-toplevel 2>/dev/null || true)"
_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo 'DETACHED')"
_head="$(git rev-parse HEAD 2>/dev/null || true)"
_short="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"

echo "PUSH GATE STATUS — branch ${_branch} @ ${_short}"
[ -z "${_proot}" ] && { echo "  not a git repository — the push gate never fires here"; exit 0; }
[ -n "${_missing}" ] && echo "  WARNING: guard lib(s) unavailable:${_missing} — the affected gates FALL OPEN (see PUSH-GATE CANARY)"
[ "${_HAS_JQ}" = "false" ] && echo "  WARNING: jq missing — no evidence is establishable; gates 2-5 fall OPEN (CLAUDE.md: jq optional)"
[ "${ACSM_SKIP_PUSH_GATE:-}" = "1" ] && echo "  NOTE: ACSM_SKIP_PUSH_GATE=1 is set in THIS shell — if Claude Code was launched with it, all denials are skipped"

# --- session/verdict token ---------------------------------------------------
_token=""
command -v resolve_session_token_from_transcript >/dev/null 2>&1 && \
    _token="$(resolve_session_token_from_transcript "")"
if [ -z "${_token}" ]; then
    echo "  session token : UNRESOLVED (no singleton) — chain gates (2-3) read no state; global gate (5) still applies"
else
    echo "  session token : ${_token} (from the shared singleton — a hook mid-session resolves payload-first and may differ under concurrent sessions, issue #51)"
fi
_vtoken="${_token}"
if command -v verdict_resolve_token >/dev/null 2>&1 && [ -n "${_token}" ]; then
    _vtoken="$(verdict_resolve_token "${_token}" "${_proot}")" || _vtoken="${_token}"
    [ -z "${_vtoken}" ] && _vtoken="${_token}"
    if [ "${_vtoken}" != "${_token}" ]; then
        echo "  verdict token : ${_vtoken} (commit-bound bridge to a sibling session's verdict at this exact HEAD)"
    fi
fi

# --- evidence ----------------------------------------------------------------
echo ""
echo "Evidence"
_led() { command -v branch_ledger_has >/dev/null 2>&1 && branch_ledger_has "$1" "${_proot}"; }
_led_sha() { command -v branch_ledger_sha >/dev/null 2>&1 && branch_ledger_sha "$1" "${_proot}"; }
_comp() {  # _comp <milestone> <field: chain|completed> — mirrors the guard's jq reads
    [ "${_HAS_JQ}" = "true" ] || return 1
    [ -n "${_token}" ] || return 1
    [ -f "${HOME}/.claude/.skill-composition-state-${_token}" ] || return 1
    jq -e ".$2 | index(\"$1\")" "${HOME}/.claude/.skill-composition-state-${_token}" >/dev/null 2>&1
}
_ev_line() {  # _ev_line <label> <milestone>
    local src="" sha=""
    if _led "$2"; then
        sha="$(_led_sha "$2")"
        src="ledger @ ${sha:-?}"
        [ -n "${sha}" ] && [ -n "${_head}" ] && [ "${sha}" != "${_head}" ] && src="${src} (not HEAD)"
    fi
    _comp "$2" completed && src="${src}${src:+ + }.completed"
    echo "  $1: ${src:-NO RECORD for this branch}"
}
_ev_line "REVIEW  (requesting-code-review)        " "requesting-code-review"
_ev_line "VERIFY  (verification-before-completion)" "verification-before-completion"

_v_state="absent"; _v_sha=""; _v_pos=""
if command -v verdict_is_clean >/dev/null 2>&1 && [ -n "${_vtoken}" ]; then
    _v_sha="$(_verdict_sha "${_vtoken}" 2>/dev/null || true)"
    if [ -n "${_v_sha}" ]; then
        if verdict_is_clean "${_vtoken}"; then _v_state="clean"
        elif verdict_has_test_failure "${_vtoken}"; then _v_state="FAILED (gates: $(verdict_failing_gates "${_vtoken}"))"
        else _v_state="not clean (could_not_verify / gate-gaming suspect — advisory only)"
        fi
        if verdict_sha_is_head "${_vtoken}" "${_proot}"; then _v_pos="= HEAD"
        elif verdict_covers_head "${_vtoken}" "${_proot}"; then _v_pos="ancestor of HEAD"
        else _v_pos="does NOT cover HEAD (stale or cross-branch)"
        fi
    fi
fi
echo "  verification verdict: ${_v_state}${_v_sha:+; sha ${_v_sha} (${_v_pos})}"

_is_routing=false; _touches_routing=false
command -v is_routing_repo >/dev/null 2>&1 && is_routing_repo "${_proot}" && _is_routing=true
command -v diff_touches_routing >/dev/null 2>&1 && diff_touches_routing "${_proot}" && _touches_routing=true
echo "  routing repo: ${_is_routing}; branch diff touches skills/|config/|hooks/: ${_touches_routing}"

# --- decision replay (guard order; deny checks reuse the lib predicates) -----
echo ""
echo "Decision replay (openspec-guard.sh order) for: git push"
_deny=""; _deny_fix=""
_say() { printf '  %-28s: %s\n' "$1" "$2"; }
_say "1 mutate-then-push" "per-command check — never combine commit/merge/rebase with push in one command"

_chain_state_ok=false
[ "${_HAS_JQ}" = "true" ] && [ -n "${_token}" ] && [ -f "${HOME}/.claude/.skill-composition-state-${_token}" ] && _chain_state_ok=true
if [ "${_chain_state_ok}" = "true" ]; then
    _r_done=false; { _comp requesting-code-review completed || _led requesting-code-review; } && _r_done=true
    if _comp requesting-code-review chain && [ "${_r_done}" = "false" ]; then
        _say "2 chain REVIEW gate" "WOULD DENY"
        _deny="${_deny:-2 chain REVIEW gate}"; _deny_fix="${_deny_fix:-invoke Skill(superpowers:requesting-code-review)}"
    else _say "2 chain REVIEW gate" "pass"; fi
    _v_done=false; { _comp verification-before-completion completed || _led verification-before-completion; } && _v_done=true
    if _comp verification-before-completion chain && [ "${_v_done}" = "false" ]; then
        _say "3 chain VERIFY gate" "WOULD DENY"
        _deny="${_deny:-3 chain VERIFY gate}"; _deny_fix="${_deny_fix:-invoke Skill(superpowers:verification-before-completion)}"
    else _say "3 chain VERIFY gate" "pass"; fi
    if command -v verdict_sha_is_head >/dev/null 2>&1 && _comp verification-before-completion chain \
       && verdict_sha_is_head "${_vtoken}" "${_proot}" && verdict_has_test_failure "${_vtoken}"; then
        _say "4 verify-hardening" "WOULD DENY (failing verdict at HEAD)"
        _deny="${_deny:-4 verify-hardening}"; _deny_fix="${_deny_fix:-fix failures, re-run Skill(auto-claude-skills:project-verification)}"
    else _say "4 verify-hardening" "pass (denies only on a FAILED verdict exactly at HEAD)"; fi
else
    _say "2 chain REVIEW gate" "n/a (no composition state for this token)"
    _say "3 chain VERIFY gate" "n/a"
    _say "4 verify-hardening" "n/a"
fi

if command -v branch_ledger_has >/dev/null 2>&1 && [ "${_HAS_JQ}" = "true" ]; then
    _g_r=false; _g_v=false
    _led requesting-code-review && _g_r=true
    _led verification-before-completion && _g_v=true
    _comp requesting-code-review completed && _g_r=true
    _comp verification-before-completion completed && _g_v=true
    if [ "${_g_v}" = "false" ] && command -v verdict_is_clean >/dev/null 2>&1 \
       && verdict_is_clean "${_vtoken}" && verdict_covers_head "${_vtoken}" "${_proot}"; then _g_v=true; fi
    if [ "${_g_r}" = "false" ] || [ "${_g_v}" = "false" ]; then
        _need=""
        [ "${_g_r}" = "false" ] && _need="requesting-code-review"
        [ "${_g_v}" = "false" ] && _need="${_need}${_need:+ and }verification-before-completion"
        _say "5 global fail-closed gate" "WOULD DENY (no record of: ${_need})"
        _deny="${_deny:-5 global fail-closed gate}"; _deny_fix="${_deny_fix:-run the missing Skill(s): ${_need}}"
    else _say "5 global fail-closed gate" "pass"; fi
else
    _say "5 global fail-closed gate" "FALLS OPEN (ledger lib or jq unavailable)"
fi

if [ "${_is_routing}" = "true" ] && [ "${_touches_routing}" = "true" ] && command -v verdict_is_clean >/dev/null 2>&1; then
    if verdict_is_clean "${_vtoken}" && verdict_covers_head "${_vtoken}" "${_proot}" \
       && { verdict_sha_is_head "${_vtoken}" "${_proot}" || ! verdict_routing_delta "${_vtoken}" "${_proot}"; }; then
        if verdict_sha_is_head "${_vtoken}" "${_proot}"; then
            _say "6 routing governance" "pass (clean verdict at HEAD)"
        else
            _say "6 routing governance" "pass (clean ancestor verdict, routing unchanged since) — refresh advised"
        fi
    else
        _say "6 routing governance" "WOULD DENY (no clean verdict covering the routing changes)"
        _deny="${_deny:-6 routing governance}"; _deny_fix="${_deny_fix:-run Skill(auto-claude-skills:project-verification) to a clean verdict at HEAD}"
    fi
else
    _say "6 routing governance" "n/a (not a routing repo, or no routing paths in branch diff)"
fi

echo ""
if [ -n "${_deny}" ]; then
    echo "=> git push NOW: WOULD DENY at ${_deny}"
    echo "   next action: ${_deny_fix}"
    echo "   (human bypass: push from your own terminal, or ACSM_SKIP_PUSH_GATE=1 at Claude Code launch)"
else
    echo "=> git push NOW: WOULD ALLOW (gh pr merge traverses the same gates 2-5)"
fi

# --- staleness observation (advisory BY DESIGN — see backtest) ---------------
echo ""
echo "Staleness (observation only; deny backtested 2026-07-15: 0 catches, 56-94% false blocks)"
_rsha="$(_led_sha requesting-code-review)"
if [ -z "${_rsha}" ]; then
    echo "  no review SHA recorded on this branch — staleness unknown"
elif [ "${_rsha}" = "${_head}" ]; then
    echo "  review recorded at HEAD — no post-review delta"
else
    _delta="$(command -v staleness_delta >/dev/null 2>&1 && staleness_delta "${_rsha}" "${_head}" "${_proot}")"
    if [ -n "${_delta}" ]; then
        echo "  review @ ${_rsha}; post-review delta to HEAD: ${_delta}"
        echo "  (docs = docs/**, openspec/**, *.md; src = everything else; re-review if src is substantive)"
    else
        echo "  review @ ${_rsha}; delta unknown (SHA not in local history?)"
    fi
fi
exit 0
