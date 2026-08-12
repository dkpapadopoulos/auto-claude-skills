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
# Diagnostic-only shadow recorder (Stage C1). Guarded source: absence must not
# affect the gate, and it is deliberately absent from _GATE_ENFORCE_LIBS.
[ -f "${_GC_ROOT}/hooks/lib/implement-shadow.sh" ] && \
    . "${_GC_ROOT}/hooks/lib/implement-shadow.sh" 2>/dev/null || true
# Advisory-path PR-diff resolver (#161). Guarded source: absence must not
# affect the gate, and it is deliberately absent from _GATE_ENFORCE_LIBS.
[ -f "${_GC_ROOT}/hooks/lib/pr-diff.sh" ] && \
    . "${_GC_ROOT}/hooks/lib/pr-diff.sh" 2>/dev/null || true

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
        command -v command_invokes_gh_merge >/dev/null 2>&1 || return 1
    # #155 follow-up: an UNBALANCED quote parse means the segmentation cannot be
    # trusted (the scanner has no backslash/comment/heredoc model, so an
    # apostrophe in `# don't forget` swallows the newline before a real push).
    # Precise detection would UNDER-detect there — a gate bypass — so drop to
    # the fail-closed substring path below. Older libs without the predicate
    # keep the previous behaviour rather than failing open on `command -v`.
    command -v command_parse_balanced >/dev/null 2>&1 || return 0
    command_parse_balanced "${_COMMAND}"
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
# The source is guarded (`&& … || true`) because an UNguarded `. lib` here trips
# `trap 'exit 0' ERR` ABOVE the deny checks below — the hook exits 0 and the push
# is silently allowed, which is the dangerous direction for a safety gate (#137).
# Confirming the function exists is part of the same guard, not belt-and-braces:
# `|| true` alone leaves a partially-sourced lib with the resolver undefined, and
# the command-not-found on the next line trips the very same ERR trap. The flag
# is what makes the `else` fallback reachable on a failed source.
_TOKEN_LIB_OK=false
if [ -f "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null && \
        command -v resolve_session_token_from_transcript >/dev/null 2>&1 && \
        _TOKEN_LIB_OK=true || true
fi
if [ "${_TOKEN_LIB_OK}" = true ]; then
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
        # Space-free action token for telemetry (F7): _GATE_ACTION is a
        # human-readable phrase with spaces, which would break the space-delimited
        # phase-gate-events.log line format (`skill=<...>`) if logged verbatim.
        _pe_action="push"
        [ "${_gc_is_push}" != "true" ] && [ "${_gc_is_ghmerge}" = "true" ] && _pe_action="gh-merge"

        # --- Diagnostic capture (issue #127) — OFF the decision path -------
        # Records which file ran + the live decision; on deny, a true on-disk
        # replay. NEVER sources capture code (a source-time failure could trip
        # the fail-open ERR trap and skip enforcement) — it fires an external
        # subprocess ONLY from a hardened EXIT trap. PUSH_GATE_CAPTURE_DISABLE=1
        # (set by the replay) prevents re-arming (recursion guard).
        _DECISION="allow"
        # Positive "reached the decision point" sentinel for the capture replay
        # (issue #127). The on-disk replay re-runs this guard, which is itself
        # fail-open (`trap 'exit 0' ERR`) — so an empty replay stdout cannot tell
        # "genuine allow" from "crashed / early-exit before this block". Under the
        # replay flag ONLY (never in live operation → no stdout impact), print a
        # sentinel here so the capture script can classify allow vs incomplete.
        [ "${PUSH_GATE_CAPTURE_REPLAY:-}" = "1" ] && printf '__PGC_EVALUATED__\n'
        if [ "${PUSH_GATE_CAPTURE_DISABLE:-}" != "1" ]; then
            _PG_CAPTURE_ACTIVE=true
            _pg_capture_on_exit() {
                trap - ERR    # a failing capture cmd must NOT re-fire `exit 0` ERR
                trap - EXIT
                [ "${_PG_CAPTURE_ACTIVE:-false}" = "true" ] || return 0
                (
                    exec </dev/null >/dev/null 2>&1   # never leak a byte to stdout
                    PGC_DECISION="${_DECISION:-allow}" PGC_ACTION="${_pe_action:-push}" \
                    PGC_COMMAND="${_COMMAND:-}" PGC_TRANSCRIPT="${_TRANSCRIPT:-}" \
                    PGC_SESSION_TOKEN="${_SESSION_TOKEN:-}" \
                    PGC_GUARD_PATH="${BASH_SOURCE:-$0}" \
                    PGC_PLUGIN_ROOT="${_PLUGIN_ROOT:-}" PGC_INPUT="${_INPUT:-}" \
                    "${_PLUGIN_ROOT}/scripts/push-gate-capture.sh"
                ) || true
                return 0
            }
            trap '_pg_capture_on_exit' EXIT
        fi

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
            _DECISION="deny:mutate-then-push"
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
        # phase-attest: lets the IMPLEMENT leg (below) accept an explicit,
        # logged skip attestation as evidence. Source-guarded like every other
        # lib here — a bad source must not trip the fail-open ERR trap into a
        # bypass (`|| true` absorbs a non-zero source exit).
        [ -f "${_PLUGIN_ROOT}/hooks/lib/phase-attest.sh" ] && \
            . "${_PLUGIN_ROOT}/hooks/lib/phase-attest.sh" 2>/dev/null || true
        # phase-evidence: defines phase_gate_log, used by the IMPLEMENT leg (Check 0)
        # BELOW. Must be sourced here — the later source (~C2 block) is after Check 0,
        # so without this the leg's telemetry call is a silent no-op and the
        # IMPLEMENT-warn event log (the deny-flip backtest baseline) stays empty.
        # Re-source there is idempotent. Source-guarded (no ERR-trap bypass).
        [ -f "${_PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" ] && \
            . "${_PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" 2>/dev/null || true
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
        # IMPLEMENT-only subset of _STALE_MSG (issue #161 I1). _STALE_MSG has
        # FIVE other writers (ledger staleness below, invocation-evidence /
        # bridge-acceptance notes, routing-delta, evaluator-surface) that are
        # ALL computed from the LOCAL branch — never true of the merged PR a
        # `gh pr merge` names. _flush_push_advisories must be able to flush
        # ONLY the IMPLEMENT text on a merge; this variable is that subset.
        # Always ALSO appended wherever _STALE_MSG gets the IMPLEMENT text
        # (line ~455 below), so the push path (which flushes _STALE_MSG in
        # full, unchanged) stays byte-identical.
        _IMPL_MSG=""
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
        # _invoc_has MILESTONE — session-local invocation-evidence leg (issue
        # #131). ~/.claude/.skill-invocation-evidence-<token> is written ONLY
        # by the completion hook on a successful Skill return (never the
        # walker), so it is real-invocation evidence of the same trust class
        # as the branch-ledger — without the ledger's cwd/branch-key
        # fragility or .completed's reset fragility. SAME resolved token
        # only: sibling tokens' files carry no repo/branch binding and would
        # over-accept another session's work. The review leg honors the
        # review-embedding proxies — PAIRED with skill-completion-hook.sh's
        # gating-milestone crediting case list.
        _invoc_has() {
            local _f="${HOME}/.claude/.skill-invocation-evidence-${_SESSION_TOKEN}"
            [ -f "${_f}" ] || return 1
            command -v jq >/dev/null 2>&1 || return 1
            # type guard: index() on a JSON *string* is substring search, so a
            # corrupt scalar file merely containing the name would satisfy it.
            case "$1" in
                requesting-code-review)
                    jq -e 'type=="array" and (index("requesting-code-review") != null
                        or index("subagent-driven-development") != null
                        or index("agent-team-execution") != null
                        or index("agent-team-review") != null)' "${_f}" >/dev/null 2>&1 ;;
                *)
                    jq -e --arg s "$1" 'type=="array" and (index($s) != null)' "${_f}" >/dev/null 2>&1 ;;
            esac
        }
        # _invoc_ok MILESTONE — _invoc_has + advisory note: this leg is
        # session-scoped (design D3 accepts the widening), so its acceptance
        # is surfaced like the bridge's, never silent. The advisory is
        # appended ONCE per milestone even though both the chain block and
        # the global gate consult this leg (issue #133 dedup; acceptance
        # itself stays idempotent). Soft SHA-binding (issue #133): when the
        # completion hook's sidecar holds a "<skill> <sha>" record for the
        # milestone (or a review-embedding proxy — PAIRED with _invoc_has's
        # case list) whose SHA is branch-bound by the SAME rule as the
        # ledger bridge, the advisory upgrades to name the bound SHA.
        # Binding NEVER gates acceptance — a hard SHA requirement would
        # re-break the #130 repro, where the recording cwd's SHA is
        # unrelated to the push branch. Fail-open: lib/file/SHA problems
        # just leave the unbound advisory.
        _INVOC_NOTED=""
        _INVOC_BASE=""
        _INVOC_BASE_RESOLVED=false
        _invoc_ok() {
            local _sf="${HOME}/.claude/.skill-invocation-evidence-sha-${_SESSION_TOKEN}"
            local _names="$1" _n _rskill _rsha _rest _bound=""
            _invoc_has "$1" || return 1
            case " ${_INVOC_NOTED} " in *" $1 "*) return 0 ;; esac
            _INVOC_NOTED="${_INVOC_NOTED} $1"
            case "$1" in requesting-code-review)
                _names="$1 subagent-driven-development agent-team-execution agent-team-review" ;;
            esac
            if [ -f "${_sf}" ] && [ "${_LEDGER_OK}" = "true" ] && [ -n "${_HEAD_SHA}" ] \
               && command -v branch_ledger_sha_is_branch_local >/dev/null 2>&1 \
               && command -v _branch_ledger_mainline_base >/dev/null 2>&1; then
                if [ "${_INVOC_BASE_RESOLVED}" != "true" ]; then
                    _INVOC_BASE_RESOLVED=true
                    _INVOC_BASE="$(_branch_ledger_mainline_base "${_proot}")" || _INVOC_BASE=""
                fi
                for _n in ${_names}; do
                    while IFS=' ' read -r _rskill _rsha _rest; do
                        [ "${_rskill}" = "${_n}" ] || continue
                        [ -n "${_rsha}" ] || continue
                        if branch_ledger_sha_is_branch_local "${_rsha}" "${_proot}" "${_HEAD_SHA}" "${_INVOC_BASE}"; then
                            _bound="${_rsha}"
                            break 2
                        fi
                    done < "${_sf}"
                done
            fi
            if [ -n "${_bound}" ]; then
                _STALE_MSG="${_STALE_MSG}${_STALE_MSG:+; }$1 accepted via session-local invocation evidence recorded at ${_bound} on this branch (real Skill return this session; SHA-bound — issue #133)."
            else
                _STALE_MSG="${_STALE_MSG}${_STALE_MSG:+; }$1 accepted via session-local invocation evidence (real Skill return this session; not branch-bound — issue #131)."
            fi
            return 0
        }
        # _bridge_has MILESTONE — cross-location branch-ledger read (issue
        # #131): sibling ledger keys (worktree/cwd split, detached HEAD,
        # branch rename, remote-URL variant), accepted only when the recorded
        # SHA is HEAD or a branch-local ancestor of HEAD (see
        # branch_ledger_bridge_has). Acceptance is advisory-noted, never
        # silent; tried only after every primary leg missed.
        _bridge_has() {
            local _bsha=""
            [ "${_LEDGER_OK}" = "true" ] || return 1
            command -v branch_ledger_bridge_has >/dev/null 2>&1 || return 1
            _bsha="$(branch_ledger_bridge_has "$1" "${_proot}")" || return 1
            _STALE_MSG="${_STALE_MSG}${_STALE_MSG:+; }$1 accepted via cross-location branch-ledger evidence recorded at ${_bsha:-unknown} on this branch (issue #131 bridge). Rerun if later commits changed reviewed content."
            return 0
        }
        # One exclusion rule, two subjects (#161). The push path measures the
        # branch-local delta; the merge path measures the merged PR's files.
        _names_touch_material_source() {
            local _f
            while IFS= read -r _f; do
                [ -n "$_f" ] || continue
                case "$_f" in docs/*|openspec/*|*.md) continue ;; *) return 0 ;; esac
            done <<EOF
$1
EOF
            return 1
        }
        # _diff_touches_material_source <proj_root> — 0 iff the branch diff
        # (mainline merge-base..HEAD) touches anything outside docs/openspec/*.md.
        # Reuses _branch_diff_names (verdict.sh, sourced above) so the IMPLEMENT
        # leg's diff base can never disagree with routing-governance/staleness's
        # base resolution — no separate merge-base logic invented here. Fail-open:
        # unresolvable base / verdict.sh unavailable => 1 (no advisory, never a
        # false-fire).
        _diff_touches_material_source() {
            local _names
            command -v _branch_diff_names >/dev/null 2>&1 || return 1
            _names="$(_branch_diff_names "${1:-}")" || return 1
            _names_touch_material_source "${_names}"
        }
        if [ "${_PUSHGATE_SKIP}" != "true" ] && [ -f "${_COMP_STATE}" ] && command -v jq >/dev/null 2>&1; then
            # Check 1: REVIEW in chain but not completed — deny with REVIEW message
            _review_in_chain=false
            _review_completed=false
            jq -e '.chain | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _review_in_chain=true
            jq -e '.completed | index("requesting-code-review")' "${_COMP_STATE}" >/dev/null 2>&1 && _review_completed=true
            _ledger_has "requesting-code-review" && _review_completed=true
            [ "${_review_completed}" = "false" ] && _invoc_ok "requesting-code-review" && _review_completed=true
            [ "${_review_completed}" = "false" ] && _bridge_has "requesting-code-review" && _review_completed=true
            if [ "${_review_in_chain}" = "true" ] && [ "${_review_completed}" = "false" ]; then
                _MSG="PUSH GATE — Expected: REVIEW → VERIFY → SHIP completed before push. Actual: requesting-code-review has not run on this chain. Do now: invoke Skill(superpowers:requesting-code-review), then retry the denied command."
                jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                _DECISION="deny:chain-review"
                exit 0
            fi

            # Check 2: VERIFY in chain but not completed — deny with VERIFY message
            _verif_in_chain=false
            _verif_completed=false
            jq -e '.chain | index("verification-before-completion")' "${_COMP_STATE}" >/dev/null 2>&1 && _verif_in_chain=true
            jq -e '.completed | index("verification-before-completion")' "${_COMP_STATE}" >/dev/null 2>&1 && _verif_completed=true
            _ledger_has "verification-before-completion" && _verif_completed=true
            [ "${_verif_completed}" = "false" ] && _invoc_ok "verification-before-completion" && _verif_completed=true
            [ "${_verif_completed}" = "false" ] && _bridge_has "verification-before-completion" && _verif_completed=true
            if [ "${_verif_in_chain}" = "true" ] && [ "${_verif_completed}" = "false" ]; then
                _MSG="PUSH GATE — Expected: verification-before-completion completed before push. Actual: it has not run on this active chain. Do now: invoke Skill(superpowers:verification-before-completion), then retry the denied command."
                jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                _DECISION="deny:chain-verify"
                exit 0
            fi

            # Check 0 (IMPLEMENT, WARN-FIRST): an implementation-slot skill is in
            # the chain but has no evidence, and the diff touches material source.
            # Accepts attestation (IMPLEMENT is not a gating milestone). Advisory
            # only — no permissionDecision. Deny-flip is a separate change gated on
            # phase-gate-backtest (<10% false-block). .completed does NOT satisfy it.
            _impl_in_chain=false; _impl_ok=false
            for _slot in executing-plans subagent-driven-development agent-team-execution; do
                jq -e --arg s "$_slot" '.chain | index($s)' "${_COMP_STATE}" >/dev/null 2>&1 && _impl_in_chain=true
            done
            # Spec requires this leg on a push OR merge; gating on push alone
            # made the sampled population narrower than the declared one.
            # Advisory-only, so this widens an advisory and never a deny.
            if [ "${_impl_in_chain}" = "true" ] && \
               { [ "${_gc_is_push}" = "true" ] || [ "${_gc_is_ghmerge}" = "true" ]; }; then
                # Two passes, NOT one (#169). The single loop short-circuited on
                # the first slot-then-class hit, so an attested executing-plans
                # beat a genuinely invoked agent-team-execution purely by check
                # order — and the recorded evidence class would have been wrong.
                # _impl_ok is a disjunction over the same predicates either way,
                # so the leg's DECISION is unchanged for every input; only the
                # label differs. Pass 1: real evidence across all slots.
                _impl_ev="none"
                for _slot in executing-plans subagent-driven-development agent-team-execution; do
                    [ "${_impl_ok}" = "false" ] && _ledger_has "$_slot" && _impl_ok=true
                    [ "${_impl_ok}" = "false" ] && _invoc_ok "$_slot" && _impl_ok=true
                    [ "${_impl_ok}" = "false" ] && _bridge_has "$_slot" && _impl_ok=true
                done
                # Pass 2: attestation, only once real evidence is ruled out for
                # EVERY slot. Reaching here with a hit means attestation alone
                # satisfied the leg, which is exactly what #169 wants counted.
                if [ "${_impl_ok}" = "false" ] && command -v phase_attested >/dev/null 2>&1; then
                    for _slot in executing-plans subagent-driven-development agent-team-execution; do
                        if [ "${_impl_ok}" = "false" ] && phase_attested "${_SESSION_TOKEN}" "$_slot"; then
                            _impl_ok=true
                            _impl_ev="attested"
                        fi
                    done
                fi
                # Skip the probe when real (non-attested) evidence was found:
                # neither record site fires on that path, so the detail would be
                # computed and discarded. The probe below is not free:
                # branch_ledger_dir -> branch_ledger_key runs `git remote
                # get-url origin`, `git symbolic-ref`, plus shasum/sha1sum and
                # cut — roughly 4 processes, not the single git call an earlier
                # version of this comment claimed.
                # The gate is deliberately NOT the narrower [ "${_impl_ok}" = "false" ]:
                # the attested record at the bottom of this block is written with
                # _impl_ok=true, so that form leaves _impl_detail unset and every
                # #169 attested episode silently records impl_evidence_detail:null
                # — the field would vanish for exactly the population it was added
                # to measure. Caught by test-push-gate-implement-leg.sh ("attested
                # record marks the attestation leg present"); verify by mutation
                # before narrowing this condition.
                _impl_detail=""
                if [ "${_impl_ok}" = "false" ] || [ "${_impl_ev}" = "attested" ]; then
                    # Per-leg evidence detail for the shadow record (corpus-validity
                    # audit, F2). Derived from the SAME preconditions the predicates
                    # use, but WITHOUT re-invoking them: _ledger_has / _invoc_ok /
                    # _bridge_has also serve the REVIEW and VERIFY legs and several
                    # of them APPEND TO _STALE_MSG on acceptance, so calling them
                    # again for a diagnostic would duplicate user-visible advisories
                    # and widen a diagnostic's blast radius onto the enforcement
                    # path. Reaching here means every leg was consulted for every
                    # slot and none matched, so each leg is "missing" unless its
                    # precondition made the check impossible — which is exactly the
                    # distinction the record needs: a cannot_check leg means the
                    # constant advisory below names the WRONG remedy (the
                    # pre-registered false_block condition), not that the push
                    # lacked implementation work.
                    _impl_det_ledger=missing
                    _impl_det_invoc=missing
                    _impl_det_bridge=missing
                    _impl_det_attest=missing
                    # Both ledger legs bottom out in branch_ledger_dir, which returns
                    # non-zero when the branch KEY cannot be resolved (not a git repo,
                    # unresolvable HEAD) — indistinguishable at the predicate's return
                    # code from "no record on this branch". Probing the key here is
                    # what separates them. branch_ledger_dir is pure (it prints a path;
                    # it does not mkdir), so this adds no side effect to the gate path.
                    # Under-reporting cannot_check as missing is the DANGEROUS
                    # direction: it makes a false_block look like a true_catch and so
                    # biases the pre-registered rate toward clearing the deny-flip.
                    _impl_det_key_ok=false
                    if [ "${_LEDGER_OK}" = "true" ] && \
                       command -v branch_ledger_dir >/dev/null 2>&1; then
                        if [ -n "$(branch_ledger_dir "${_proot}" 2>/dev/null)" ]; then
                            _impl_det_key_ok=true
                        fi
                    fi
                    if [ "${_impl_det_key_ok}" != "true" ]; then
                        _impl_det_ledger=cannot_check
                    fi
                    if [ "${_impl_det_key_ok}" != "true" ] || \
                       ! command -v branch_ledger_bridge_has >/dev/null 2>&1; then
                        _impl_det_bridge=cannot_check
                    fi
                    # An ABSENT evidence file is genuinely "missing" (nothing was
                    # recorded). The cannot_check case is a file that EXISTS but
                    # cannot be parsed: _invoc_has ends in `jq -e ... "${_f}"
                    # >/dev/null 2>&1`, so a truncated or corrupt file returns 1
                    # identically to "no record".
                    # Do NOT test the token or jq here: both are guaranteed by
                    # the time this runs (the guard exits at the top when
                    # _SESSION_TOKEN is empty, and this whole block is inside a
                    # `command -v jq` gate), so such a check is dead code that
                    # falsely implies the leg is covered — deleting the previous
                    # token/jq form changed no test, which is how it was found.
                    # A non-array parse (`type=="array"` failing) is deliberately
                    # NOT cannot_check: that is checked-and-rejected, i.e.
                    # missing. Only unparseable JSON means we could not look.
                    _impl_det_ief="${HOME}/.claude/.skill-invocation-evidence-${_SESSION_TOKEN}"
                    if [ -f "${_impl_det_ief}" ] && \
                       ! jq -e . "${_impl_det_ief}" >/dev/null 2>&1; then
                        _impl_det_invoc=cannot_check
                    fi
                    # Same class on the attestation leg: phase_attested ends in
                    # `jq -e --arg s "$step" 'has($s)' "$f" >/dev/null 2>&1`
                    # (hooks/lib/phase-attest.sh), so an unparseable attest file
                    # is indistinguishable from "not attested" at its exit code.
                    _impl_det_paf="${HOME}/.claude/.skill-phase-attest-${_SESSION_TOKEN}"
                    if ! command -v phase_attested >/dev/null 2>&1; then
                        _impl_det_attest=cannot_check
                    elif [ -f "${_impl_det_paf}" ] && \
                         ! jq -e . "${_impl_det_paf}" >/dev/null 2>&1; then
                        _impl_det_attest=cannot_check
                    fi
                    if [ "${_impl_ev}" = "attested" ]; then
                        _impl_det_attest=present
                    fi
                    _impl_detail="ledger:${_impl_det_ledger} invocation:${_impl_det_invoc} bridge:${_impl_det_bridge} attestation:${_impl_det_attest}"
                fi
                # Resolution and materiality are DISTINCT outcomes (#161 fix
                # round 1): a PR that resolved (gh returned a file list) but is
                # docs-only must record diff_base:"pr:<n>" with
                # material_source:false, NOT "unresolved" — "unresolved" is
                # reserved for "we couldn't look" (no ref, no gh, unauthed,
                # unknown PR, timeout), never for "we looked and it was
                # non-material". Fetch pr_changed_files exactly ONCE: its
                # non-emptiness alone decides resolved vs unresolved; its
                # content (tested via _names_touch_material_source, already
                # fetched, no second network call) decides materiality.
                _impl_db="branch-local"; _impl_material=false
                if [ "${_pe_action}" = "gh-merge" ]; then
                    _impl_db="unresolved"
                    _impl_pr=""
                    command -v pr_ref_from_command >/dev/null 2>&1 && \
                        _impl_pr="$(pr_ref_from_command "${_COMMAND}")"
                    if [ -n "${_impl_pr}" ] && command -v pr_changed_files >/dev/null 2>&1; then
                        _impl_pr_files="$(pr_changed_files "${_impl_pr}" "${_proot}")"
                        if [ -n "${_impl_pr_files}" ]; then
                            _impl_db="pr:${_impl_pr}"
                            _names_touch_material_source "${_impl_pr_files}" && _impl_material=true
                        fi
                    fi
                elif _diff_touches_material_source "${_proot}"; then
                    _impl_material=true
                fi
                # Any gh-merge outcome records (material, resolved-non-material,
                # or unresolved) so the corpus isn't silently missing the
                # resolved-non-material case (fix round 1, #161 review finding:
                # gating the write on _impl_db="unresolved" dropped that case
                # entirely once it started resolving to the correct pr:<n>
                # label instead of being mislabeled unresolved). Push keeps its
                # original, narrower gate (material-only) — this branch never
                # widens what a push records.
                if [ "${_impl_ok}" = "false" ] && \
                   { [ "${_impl_material}" = "true" ] || [ "${_pe_action}" = "gh-merge" ]; }; then
                    if [ "${_impl_material}" = "true" ]; then
                        _IMPL_TEXT="IMPLEMENT: this push edits source but no implementation-slot skill (executing-plans / subagent-driven-development / agent-team-execution) has invocation evidence on this chain. Invoke it, or record a deliberate skip: phase_attest executing-plans \"<reason>\". (advisory; will become a deny after backtest)"
                        _STALE_MSG="${_STALE_MSG}${_STALE_MSG:+; }${_IMPL_TEXT}"
                        _IMPL_MSG="${_IMPL_MSG}${_IMPL_MSG:+; }${_IMPL_TEXT}"
                        command -v phase_gate_log >/dev/null 2>&1 && phase_gate_log "push-implement" "warn" "${_pe_action}" "executing-plans"
                    fi
                    if command -v implement_shadow_record >/dev/null 2>&1; then
                        implement_shadow_record "${_pe_action}" "${_proot}" "${_SESSION_TOKEN}" "${_TRANSCRIPT:-}" "none" "${_impl_db}" "${_impl_material}" "true" "${_impl_detail}" || true
                    fi
                fi
                # Attestation-resolved episodes are recorded too, as
                # would_block:false — otherwise the deny-flip corpus can never
                # observe how often attestation, rather than work, satisfied
                # this leg (#169). Same population gate as the would-block
                # record above, so the two are directly comparable. Advisory
                # region: no permissionDecision, no exit, no new network call
                # (_impl_db/_impl_material are already computed above).
                if [ "${_impl_ev}" = "attested" ] && \
                   { [ "${_impl_material}" = "true" ] || [ "${_pe_action}" = "gh-merge" ]; }; then
                    if command -v implement_shadow_record >/dev/null 2>&1; then
                        implement_shadow_record "${_pe_action}" "${_proot}" "${_SESSION_TOKEN}" "${_TRANSCRIPT:-}" "attested" "${_impl_db}" "${_impl_material}" "false" "${_impl_detail}" || true
                    fi
                fi
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
                _DECISION="deny:verify-hardening"
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
            # Same-token invocation evidence, then the cross-location ledger
            # bridge (issue #131) — tried only after the primary legs miss.
            [ "${_g_review}" = "false" ] && _invoc_ok "requesting-code-review"         && _g_review=true
            [ "${_g_verify}" = "false" ] && _invoc_ok "verification-before-completion" && _g_verify=true
            [ "${_g_review}" = "false" ] && _bridge_has "requesting-code-review"         && _g_review=true
            [ "${_g_verify}" = "false" ] && _bridge_has "verification-before-completion" && _g_verify=true
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
                _DECISION="deny:global-failclosed"
                exit 0
            fi
        fi

        # --- Phase-enforcement C2: DESIGN/PLAN evidence on chain-covered pushes ---
        # (openspec/changes/phase-enforcement). WARN by default; DENY only when
        # ~/.claude/skill-config.json .phase_enforcement.outbound == "deny" —
        # that flip is gated on the replay backtest (<10% false-block), never
        # hardcoded. Evidence = the same shared predicate as skill-gate.sh.
        # Scoped to chain-covered work: an ACTIVE chain that includes
        # brainstorming, OR durable branch-ledger records of DESIGN/PLAN steps
        # (covers comp-state resets between sessions — codex #6). Ad-hoc
        # pushes stay ungated (false-block discipline).
        _pe_covered=false
        if [ -f "${_COMP_STATE}" ] && jq -e '.chain | index("brainstorming")' "${_COMP_STATE}" >/dev/null 2>&1; then
            _pe_covered=true
        elif [ "${_LEDGER_OK}" = "true" ]; then
            { branch_ledger_has "brainstorming" "${_proot}" || branch_ledger_has "writing-plans" "${_proot}"; } && _pe_covered=true
        fi
        if [ "${_PUSHGATE_SKIP}" != "true" ] && command -v jq >/dev/null 2>&1 \
           && [ "${_pe_covered}" = "true" ]; then
            if [ -f "${_PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" ]; then
                # shellcheck source=lib/phase-evidence.sh
                . "${_PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" 2>/dev/null || true
            fi
            if command -v phase_step_satisfied >/dev/null 2>&1; then
                _pe_missing=""
                for _pe_step in brainstorming writing-plans; do
                    if ! phase_step_satisfied "${_SESSION_TOKEN}" "${_pe_step}" "${_proot}"; then
                        _pe_missing="${_pe_step}"
                        break
                    fi
                done
                if [ -n "${_pe_missing}" ]; then
                    _pe_mode="$(jq -r '.phase_enforcement.outbound // "warn"' "${HOME}/.claude/skill-config.json" 2>/dev/null)" || _pe_mode="warn"
                    # Enum guard (symmetric with skill-gate.sh's C1 guard): only the
                    # exact strings deny|warn|off are honored; anything else falls to
                    # warn — the fail-open direction here (a typo can only weaken to
                    # advisory, never escalate to deny). "off" silences the C2 leg
                    # entirely, including telemetry.
                    case "${_pe_mode}" in deny|warn|off) ;; *) _pe_mode="warn" ;; esac
                    if [ "${_pe_mode}" != "off" ]; then
                    _PE_MSG="PHASE GATE (outbound): this chain-covered ${_GATE_ACTION} has no evidence for '${_pe_missing}'. Invoke Skill(superpowers:${_pe_missing}) or record an explicit skip (phase_attest ${_pe_missing} \"<reason>\") before shipping."
                    [ "${PUSH_GATE_CAPTURE_REPLAY:-}" != "1" ] && command -v phase_gate_log >/dev/null 2>&1 && phase_gate_log "outbound" "${_pe_mode}" "${_pe_action}" "${_pe_missing}"
                    if [ "${_pe_mode}" = "deny" ]; then
                        jq -n --arg msg "${_PE_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                        _DECISION="deny:phase-enforcement"
                        exit 0
                    fi
                    # warn mode: TELEMETRY ONLY (events log + SKILL_EXPLAIN stderr).
                    # The guard emits at most ONE JSON object per run — every existing
                    # systemMessage is paired with a deny + exit 0 (verified: no
                    # warn-and-continue precedent exists). A mid-guard JSON warn that
                    # falls through would put two objects on stdout when a later
                    # check denies. Same constraint as the "Soft staleness is NOT
                    # emitted here" comment at ~line 221.
                    [ -n "${SKILL_EXPLAIN:-}" ] && printf '[openspec-guard] %s\n' "${_PE_MSG}" >&2
                    fi
                fi
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
                    _DECISION="deny:routing-governance"
                    exit 0
                fi
            fi
        fi

        # Evaluator-surface advisory (NEVER a deny): the branch edits file(s)
        # that define what "verified" means, so a clean verdict is partly
        # self-referential evidence — surface it for the human PR reviewer.
        # Push-only (branch-local diff is the wrong delta for gh-merge, same
        # reasoning as routing-governance). Fail-open: predicate missing or
        # base unresolvable => silence. See
        # openspec/changes/evaluator-surface-advisory/design.md.
        if [ "${_gc_is_push}" = "true" ] && command -v diff_touches_evaluator >/dev/null 2>&1; then
            _eval_hits="$(diff_touches_evaluator "${_proot}" 2>/dev/null)" || _eval_hits=""
            if [ -n "${_eval_hits}" ]; then
                _eval_list="$(printf '%s' "${_eval_hits}" | tr '\n' ' ')"
                _STALE_MSG="${_STALE_MSG}${_STALE_MSG:+; }EVALUATOR SURFACE: this push modifies file(s) that define what verified means (${_eval_list}). The verification verdict is partly self-referential for this branch — call these files out for explicit human review in the PR."
            fi
        fi
fi

# Flush pending push advisories before any pre-SHIP early exit. _STALE_MSG is
# otherwise only emitted via the SHIP-phase _WARNINGS fold-in below, which
# silently dropped advisories for non-SHIP pushes (latent since the staleness
# advisory landed). Advisory channel only — no permissionDecision here (one
# would auto-approve and suppress downstream warnings; documented bug shape).
# _advisory_text_for_action — the SINGLE rule for what advisory text an action
# is allowed to surface. Echoes the text; returns 1 when nothing may be emitted.
#
# Issue #166 exists because this rule lived in TWO places. #161 narrowed the
# non-SHIP flush (_flush_push_advisories) so a resolved merge surfaces only the
# IMPLEMENT subset, but the SHIP-phase _WARNINGS fold-in is a separate mechanism
# and was left emitting the full _STALE_MSG — so the same branch-local staleness
# text still leaked onto `gh pr merge <other-PR>` during SHIP. Both callers now
# share this function; a future third caller must call it too rather than
# re-deriving the rule, which is how the divergence happened the first time.
#
# push  -> the full _STALE_MSG (unchanged, byte-identical to pre-#161)
# merge -> _IMPL_MSG only, and only when the PR subject resolved (diff_base pr:*)
# else  -> nothing: silence stays wherever the subject is unknown
_advisory_text_for_action() {
    if [ "${_gc_is_push:-false}" = "true" ]; then
        printf '%s' "${_STALE_MSG:-}"
        return 0
    fi
    case "${_impl_db:-unresolved}" in
        pr:*) printf '%s' "${_IMPL_MSG:-}"; return 0 ;;
        *) return 1 ;;
    esac
}

_flush_push_advisories() {
    # PUSH-only, historically: _STALE_MSG staleness text is computed from the
    # LOCAL branch HEAD, which for `gh pr merge <other>` is the wrong delta —
    # pre-flush behavior for gh-merge outside SHIP was silence, and that is
    # preserved (SHIP-phase merges still get the _WARNINGS fold-in below,
    # unchanged).
    #
    # Merges flush ONLY when the subject resolved (#161), and ONLY the
    # IMPLEMENT text (_IMPL_MSG), never the full _STALE_MSG (issue #161 I1
    # review finding). _STALE_MSG accumulates FIVE other writers — ledger
    # staleness, invocation-evidence / bridge-acceptance notes, routing-delta,
    # evaluator-surface — that are ALL computed from the LOCAL branch, which
    # for `gh pr merge <other>` is unrelated to the merged PR; flushing the
    # whole variable leaked branch-local advisory text onto merges of
    # unrelated PRs. _IMPL_MSG is a strict subset of _STALE_MSG (every
    # IMPLEMENT append also lands in _STALE_MSG), so this preserves the
    # original reasoning — silence stays wherever the subject is unknown —
    # while narrowing what a KNOWN-subject merge is allowed to surface.
    #
    # The push branch below is untouched: it still flushes _STALE_MSG in
    # full, byte-identical to before this change.
    local _msg
    _msg="$(_advisory_text_for_action)" || return 0
    [ -n "${_msg}" ] || return 0
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg msg "PUSH GATE (advisory): ${_msg}" \
            '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
    else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' \
            "$(printf 'PUSH GATE (advisory): %s' "${_msg}" | tr '\n"' ' ')"
    fi
}

# Check if we're in SHIP phase (signal file is JSON: {"skill":"...","phase":"..."})
_SIGNAL_FILE="${HOME}/.claude/.skill-last-invoked-${_SESSION_TOKEN}"
[ -f "${_SIGNAL_FILE}" ] || { _flush_push_advisories; exit 0; }
_PHASE=""
if command -v jq >/dev/null 2>&1; then
    _PHASE="$(jq -r '.phase // empty' "${_SIGNAL_FILE}" 2>/dev/null)" || true
else
    _PHASE="$(grep -o '"phase" *: *"[^"]*"' "${_SIGNAL_FILE}" | sed 's/"phase" *: *"//;s/"$//')" || true
fi
[ "${_PHASE}" = "SHIP" ] || { _flush_push_advisories; exit 0; }

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
# Source-guarded for the same reason as the token lib above (#137): an unguarded
# `. lib` trips `trap 'exit 0' ERR` and exits the hook early. This block sits
# below the push-gate deny checks, so a failure here is less severe than at the
# token lib — but it still silently skips the consolidation advisory, and the
# `else` branch exists precisely to cover a missing lib.
_CONSOL_LIB_OK=false
if [ -f "${_PLUGIN_ROOT}/hooks/lib/consol-marker.sh" ]; then
    # shellcheck source=lib/consol-marker.sh
    . "${_PLUGIN_ROOT}/hooks/lib/consol-marker.sh" 2>/dev/null && \
        command -v consol_marker_path >/dev/null 2>&1 && _CONSOL_LIB_OK=true || true
fi
if [ "${_CONSOL_LIB_OK}" = true ]; then
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
# Issue #166: this fold-in used _STALE_MSG unconditionally, so a SHIP-phase
# `gh pr merge <other-PR>` surfaced branch-local staleness text as though it
# described the merged PR — the same defect #161 fixed in the non-SHIP flush,
# surviving here because this is a different mechanism. Both now share
# _advisory_text_for_action so the rule cannot diverge again.
_SHIP_ADVISORY="$(_advisory_text_for_action)" || _SHIP_ADVISORY=""
if [ -n "${_SHIP_ADVISORY}" ]; then
    [ -n "${_WARNINGS}" ] && _WARNINGS="${_WARNINGS}
"
    _WARNINGS="${_WARNINGS}PUSH GATE (advisory): ${_SHIP_ADVISORY}"
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
