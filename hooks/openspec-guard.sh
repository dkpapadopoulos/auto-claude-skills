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

# Cheap pre-filter: only a command mentioning "git" can be a git write, and
# only one mentioning "gh" can be a gh merge — skip the precise (char-scan)
# parser for the overwhelming majority of Bash calls. Every real git/gh
# invocation (bare, */path, env-prefixed, -C/-R form) contains the substring.
case "${_COMMAND}" in *git*|*gh*) ;; *) exit 0 ;; esac

# Precise git-write detection (fail-open): source the predicate. If unavailable,
# the substring fallbacks below preserve the original (fail-closed) behavior.
_GC_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -f "${_GC_ROOT}/hooks/lib/git-command.sh" ] && \
    . "${_GC_ROOT}/hooks/lib/git-command.sh" 2>/dev/null || true

# Bound the worst case: the precise detector is an O(n^2) char-scan parser, so
# only use it below a size cap; above it, fall back to the (fail-closed)
# substring check so a huge git-containing command can't stall the hot path.
_GC_MAX=4096   # above this, use the substring fallback (fail-closed) — bounds cost
_gc_precise() {
    # Both predicates are required: the fast-path and gate body call
    # command_invokes_gh_merge too — if the lib were ever split and only one
    # loaded, an unbound call would ERR-trap the whole gate open. Check both.
    [ "${#_COMMAND}" -le "${_GC_MAX}" ] && \
        command -v command_invokes_git_write >/dev/null 2>&1 && \
        command -v command_invokes_gh_merge >/dev/null 2>&1
}

# Fast path: only proceed for a REAL git commit/push or gh-merge invocation.
# Precise when the detector lib loaded and the command is small; substring
# fallback (fail-closed) otherwise.
if _gc_precise; then
    if ! command_invokes_git_write "${_COMMAND}" \
       && ! command_invokes_gh_merge "${_COMMAND}"; then
        exit 0
    fi
else
    case "${_COMMAND}" in
        *"git commit"*|*"git push"*|*"gh pr merge"*|*mergePullRequest*|*pulls/*merge*) ;;
        *) exit 0 ;;
    esac
fi

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
# Two gates fire independent of any composition chain (both fail-open on infra error):
#   1. Global fail-closed gate (below) — EVERY agent push must carry a durable REVIEW
#      record and a passing VERIFY signal for this branch. Closes the prior hole where a
#      push from a non-driven session (no composition state) was allowed unconditionally.
#   2. Routing-governance gate (further below) — pushes touching routing files
#      (skills/|config/|hooks/) in a skill-routing plugin repo require a clean
#      verification verdict. Routing changes are high-risk by nature, not by phase.
# Fail-open guards for both: missing lib / missing jq / not a routing repo /
# unresolvable diff base => no gate (never a false-block).
if _gc_precise; then
    _gc_is_push=false; command_invokes_git_write "${_COMMAND}" "push" && _gc_is_push=true
    _gc_is_ghmerge=false; command_invokes_gh_merge "${_COMMAND}" && _gc_is_ghmerge=true
else
    case "${_COMMAND}" in *"git push"*) _gc_is_push=true ;; *) _gc_is_push=false ;; esac
    case "${_COMMAND}" in
        *"gh pr merge"*|*mergePullRequest*|*pulls/*merge*) _gc_is_ghmerge=true ;;
        *) _gc_is_ghmerge=false ;;
    esac
fi
# gh-merge is a remote mutation that ships code without a push — it passes the
# SAME evidence gates (audit F2). Evidence is the CURRENT session/branch proxy;
# GitHub branch protection is the per-PR backstop (see design doc).
if [ "${_gc_is_push}" = "true" ] || [ "${_gc_is_ghmerge}" = "true" ]; then
        # Explicit bypass — HUMAN-ONLY by construction. This is a Claude Code PreToolUse
        # hook: it only sees pushes the AGENT runs through the Bash tool — a human pushing
        # from their own terminal never reaches here, which is the primary escape hatch.
        # For an in-session override, honor ACSM_SKIP_PUSH_GATE=1 ONLY as an env var in the
        # hook's own process, which is inherited from the environment that launched Claude
        # Code — a human sets it at launch; the agent cannot mutate our process env from a
        # Bash subshell. We deliberately do NOT scan the command string for the token: the
        # agent composes that string, so an inline scan would be an agent-forgeable bypass,
        # which defeats a fail-CLOSED gate. When set, ALL push-gate denials are skipped;
        # SHIP-phase advisories below still emit.
        _PUSHGATE_SKIP=false
        [ "${ACSM_SKIP_PUSH_GATE:-}" = "1" ] && _PUSHGATE_SKIP=true
        _GATE_ACTION="pushing this branch"
        [ "${_gc_is_push}" != "true" ] && [ "${_gc_is_ghmerge}" = "true" ] && _GATE_ACTION="merging this PR"

        # Compound mutate-then-push deny (audit F2). The gate evaluates PRE-EXEC
        # state: any evidence below describes the CURRENT HEAD, so a commit/merge/
        # rebase created inline in the same command would push unverified content
        # (and evade the routing-delta check — the new commit can't be diffed yet).
        # Unconditional (evidence cannot save it by definition); honors the human
        # bypass; fail-open when the predicate or jq is unavailable.
        if [ "${_PUSHGATE_SKIP}" != "true" ] && [ "${_gc_is_push}" = "true" ] \
           && command -v jq >/dev/null 2>&1 \
           && command -v command_git_mutate_before_push >/dev/null 2>&1 \
           && [ "${#_COMMAND}" -le "${_GC_MAX}" ] \
           && command_git_mutate_before_push "${_COMMAND}"; then
            _MSG="PUSH GATE: this command mutates history (commit/merge/rebase/cherry-pick/revert/am) and pushes in ONE command. The gate evaluates evidence for the CURRENT commit, so the pushed result would be unverified. Run the mutation first, re-run verification if content changed, then run git push as a separate command."
            jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
            exit 0
        fi
        _COMP_STATE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
        # Durable per-(repo+branch) ledger: gate readiness that survives chain
        # re-anchors. Fail-safe: if the helper or branch key is unavailable, the
        # ledger checks are simply false and the .completed path below governs.
        _LEDGER_OK=false
        if [ -f "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" ]; then
            # shellcheck source=lib/branch-ledger.sh
            . "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" && _LEDGER_OK=true
        fi
        # Verdict layer: STATUS (a gating Skill returned, tracked above) is NOT a
        # passing VERDICT. verdict.sh reads the owned SHA-fresh verification verdict.
        # `|| true` so a non-zero source cannot trip `trap 'exit 0' ERR`.
        _VERDICT_OK=false
        if [ -f "${_PLUGIN_ROOT}/hooks/lib/verdict.sh" ]; then
            # shellcheck source=lib/verdict.sh
            . "${_PLUGIN_ROOT}/hooks/lib/verdict.sh" 2>/dev/null && _VERDICT_OK=true || true
        fi
        _HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
        # Bind the verdict to the COMMIT, not the session. The payload-less
        # project-verification SKILL writes under the shared singleton's token while
        # this hook resolves payload-first (issue #51); concurrent sessions clobber the
        # singleton so the two diverge and a token-scoped read would deadlock. Verdict
        # reads below use _VERDICT_TOKEN: identical to _SESSION_TOKEN whenever the
        # session's own verdict covers HEAD, otherwise a sibling artifact bound to the
        # same HEAD (failure-preferring). Composition/ledger/signal reads stay session-
        # scoped. Fail-open: token unchanged if the lib is unavailable.
        _proot="$(git rev-parse --show-toplevel 2>/dev/null || true)"
        _VERDICT_TOKEN="${_SESSION_TOKEN}"
        if [ "${_VERDICT_OK}" = "true" ]; then
            _VERDICT_TOKEN="$(verdict_resolve_token "${_SESSION_TOKEN}" "${_proot}")" || _VERDICT_TOKEN="${_SESSION_TOKEN}"
            [ -z "${_VERDICT_TOKEN}" ] && _VERDICT_TOKEN="${_SESSION_TOKEN}"
        fi
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
        if [ "${_PUSHGATE_SKIP}" != "true" ] && [ -f "${_COMP_STATE}" ] && command -v jq >/dev/null 2>&1; then
            # Check 1: REVIEW in chain but not completed — deny with REVIEW message
            _review_in_chain=false
            _review_completed=false
            jq -e '.chain | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _review_in_chain=true
            jq -e '.completed | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _review_completed=true
            _ledger_has "requesting-code-review" && _review_completed=true
            if [ "${_review_in_chain}" = "true" ] && [ "${_review_completed}" = "false" ]; then
                _MSG="PUSH GATE — Expected: REVIEW → VERIFY → SHIP completed before push. Actual: requesting-code-review has not run on this chain. Do now: invoke Skill(superpowers:requesting-code-review), then retry the denied command."
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
                _MSG="PUSH GATE — Expected: verification-before-completion completed before push. Actual: it has not run on this active chain. Do now: invoke Skill(superpowers:verification-before-completion), then retry the denied command."
                jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                exit 0
            fi

            # Verify-verdict hardening (fail-open): status != verdict. A recorded
            # verify milestone means the Skill returned, NOT that tests passed. If an
            # owned verdict is AT HEAD and shows a test failure, deny even when status
            # says completed. A failure is authoritative only for the exact commit it
            # was measured at, so we require sha == HEAD (not merely ancestor): an
            # ancestor/stale/cross-branch/absent verdict => no denial (a later HEAD may
            # be fixed). This is the false-block guard.
            if [ "${_VERDICT_OK}" = "true" ] && [ "${_verif_in_chain}" = "true" ] \
               && verdict_sha_is_head "${_VERDICT_TOKEN}" "" \
               && verdict_has_test_failure "${_VERDICT_TOKEN}"; then
                _gates="$(verdict_failing_gates "${_VERDICT_TOKEN}")" || true
                _MSG="PUSH GATE: verification-before-completion is recorded, but the verification verdict at HEAD reports failing gate(s): ${_gates}. Fix and re-run Skill(auto-claude-skills:project-verification) before retrying."
                jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                exit 0
            fi

            # Soft staleness is NOT emitted here (no early exit, no permissionDecision):
            # doing so would auto-approve the lower-confidence path and suppress the
            # SHIP-phase advisories below. Instead _STALE_MSG is folded into _WARNINGS in
            # the SHIP-phase block so all advisories emit together as one additionalContext.
        fi

        # Global fail-closed gate — fires for EVERY push, composition or not. Closes
        # the pre-existing fail-open hole: a push with no active composition state used
        # to be allowed unconditionally, so the whole gate could be sidestepped by just
        # not being in a driven session. Now every push must carry, for THIS branch,
        # both a durable REVIEW record and a passing VERIFY signal. The checks reuse the
        # same durable artifacts the composition block trusts (branch-ledger milestones,
        # + a session-local .completed fallback for the write-lag window, + a SHA-bound
        # clean verdict as stronger VERIFY evidence). Fail-open on INFRASTRUCTURE error:
        # the block only runs when the ledger lib actually loaded (_LEDGER_OK) AND jq is
        # present — a check that cannot run never blocks. jq is required because every
        # evidence leg needs it: the ledger's sole WRITER (skill-completion-hook.sh)
        # exits early without jq so the ledger is never populated, the .completed
        # fallback is jq-guarded, and the verdict lib returns non-clean without jq. So
        # without jq no evidence is establishable and the gate must fall open (matches
        # the composition block above and CLAUDE.md "jq is optional at runtime").
        # Only a check that runs and finds NO record denies.
        # Bypass: _PUSHGATE_SKIP (human terminal push, or human-set ACSM_SKIP_PUSH_GATE=1 env).
        if [ "${_PUSHGATE_SKIP}" != "true" ] && [ "${_LEDGER_OK}" = "true" ] && command -v jq >/dev/null 2>&1; then
            _g_review=false
            _g_verify=false
            branch_ledger_has "requesting-code-review"         "${_proot}" && _g_review=true
            branch_ledger_has "verification-before-completion" "${_proot}" && _g_verify=true
            # Same-session fallback: composition .completed (the durable ledger write can
            # lag skill completion within the session that just ran the skill).
            if [ -f "${_COMP_STATE}" ] && command -v jq >/dev/null 2>&1; then
                jq -e '.completed | index("requesting-code-review")'         "${_COMP_STATE}" >/dev/null 2>&1 && _g_review=true
                jq -e '.completed | index("verification-before-completion")' "${_COMP_STATE}" >/dev/null 2>&1 && _g_verify=true
            fi
            # A clean verification verdict covering HEAD is stronger (SHA-bound) evidence
            # of VERIFY than the status milestone, so it also satisfies the verify leg.
            if [ "${_g_verify}" = "false" ] && [ "${_VERDICT_OK}" = "true" ] \
               && verdict_is_clean "${_VERDICT_TOKEN}" && verdict_covers_head "${_VERDICT_TOKEN}" "${_proot}"; then
                _g_verify=true
            fi
            if [ "${_g_review}" = "false" ] || [ "${_g_verify}" = "false" ]; then
                _need=""
                [ "${_g_review}" = "false" ] && _need="requesting-code-review"
                [ "${_g_verify}" = "false" ] && _need="${_need}${_need:+ and }verification-before-completion"
                _MSG="PUSH GATE (fail-closed): ${_GATE_ACTION} requires ${_need} to have run, but no record exists for it on this branch. Invoke the missing Skill(s) and let them complete, then retry. To bypass intentionally: run the command from your own terminal, or relaunch Claude Code with ACSM_SKIP_PUSH_GATE=1 set in its environment."
                # jq presence is guaranteed by the block guard above.
                jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                exit 0
            fi
        fi

        # Routing-governance gate (fail-closed, scoped). In a skill-routing plugin
        # repo, pushes touching routing paths (skills/|config/|hooks/) require a CLEAN
        # verdict covering the branch. Fires regardless of composition chain — routing
        # changes are high-risk by nature, not by phase. Fail-safe: no lib, not a
        # routing repo, or an unresolvable diff base => no gate (never a false-block).
        # Push-only by design: the origin/main...HEAD delta describes the LOCAL
        # branch, which for `gh pr merge <other>` is unrelated — extending the
        # check to merges would compare the wrong branch (see F2 design doc).
        if [ "${_PUSHGATE_SKIP}" != "true" ] && [ "${_gc_is_push}" = "true" ] && [ "${_VERDICT_OK}" = "true" ]; then
            # _proot resolved once above, alongside _VERDICT_TOKEN.
            if is_routing_repo "${_proot}" && diff_touches_routing "${_proot}"; then
                if verdict_is_clean "${_VERDICT_TOKEN}" && verdict_covers_head "${_VERDICT_TOKEN}" "${_proot}" \
                   && { verdict_sha_is_head "${_VERDICT_TOKEN}" "${_proot}" || ! verdict_routing_delta "${_VERDICT_TOKEN}" "${_proot}"; }; then
                    # Clean verdict at HEAD, OR at an ancestor whose routing files are
                    # unchanged since (a benign non-routing follow-up) — allow. The
                    # ancestor case only warns so follow-up commits aren't re-blocked.
                    if ! verdict_sha_is_head "${_VERDICT_TOKEN}" "${_proot}"; then
                        _STALE_MSG="${_STALE_MSG}${_STALE_MSG:+; }routing change: the clean verification verdict covers an earlier commit, not HEAD (routing files unchanged since). Re-run project-verification to refresh."
                    fi
                    : # allow
                else
                    # No clean covering verdict, OR the clean verdict is an ancestor and
                    # routing files CHANGED after it (an unverified routing delta) — deny.
                    _MSG="PUSH GATE (routing governance): this push modifies routing files (skills/, config/, or hooks/) but no clean verification verdict covering these changes exists. Run Skill(auto-claude-skills:project-verification) until it reports a clean verdict, then push."
                    jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                    exit 0
                fi
            fi
        fi
fi

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
