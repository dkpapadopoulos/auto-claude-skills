#!/usr/bin/env bash
# verdict.sh — read + interpret the owned verification verdict artifact
# (~/.claude/.skill-project-verified-<token>) and routing-diff scope. Separates
# STATUS (a gating Skill returned) from VERDICT (it actually passed). Bash 3.2.
# All functions fail-open: on any error they return "no usable verdict / no
# scope" so the push gate falls back to the status layer (never a false-block).

verdict_artifact_path() {
    local token="${1:-}"
    [ -z "$token" ] && return 1
    printf '%s' "${HOME}/.claude/.skill-project-verified-${token}"
}

_verdict_sha() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -r '.sha // empty' "$f" 2>/dev/null
}

# verdict_sha_is_head <token> <proj_root> — 0 iff artifact .sha == HEAD exactly.
verdict_sha_is_head() {
    local token="${1:-}" proot="${2:-}" sha head
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || return 1
    [ -n "$head" ] && [ "$sha" = "$head" ]
}

# verdict_covers_head <token> <proj_root> — 0 iff .sha == HEAD or is an ancestor
# of HEAD on the branch. This is the branch-scoping the token-scoped artifact
# lacks: an unrelated (cross-branch) or missing sha never covers HEAD.
verdict_covers_head() {
    local token="${1:-}" proot="${2:-}" sha head
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || return 1
    [ -z "$head" ] && return 1
    [ "$sha" = "$head" ] && return 0
    git -C "${proot:-.}" merge-base --is-ancestor "$sha" "$head" 2>/dev/null
}

# verdict_resolve_token <session_token> <proj_root> — pick the token whose verdict
# is authoritative for the CURRENT push. The verdict is bound to the COMMIT (sha),
# NOT the session: the project-verification SKILL has no stdin payload and can only
# derive its token from the shared singleton, while this hook resolves payload-first
# (issue #51). Concurrent sessions clobber the singleton (last-writer-wins) so the two
# tokens diverge and a token-scoped read would never find the verdict — a live deadlock.
#
# Precedence (issue #123 — an EXACT-HEAD verdict, ANY token, outranks an own ANCESTOR one):
#   1. Own token's verdict at EXACT HEAD -> use it (strongest own evidence; byte-identical
#      fast path, no sibling scan). Ancestor-only own coverage NO LONGER short-circuits here.
#   2. Cross-token bridge: sibling artifacts bound to the EXACT HEAD; a FAILURE at HEAD
#      outranks a clean one (deny-bias / anti-gate-gaming). This is now ALSO reached when the
#      own verdict covers HEAD only via an ANCESTOR — pre-#123 that ancestor short-circuit
#      shadowed a genuine sibling exact-HEAD verdict and false-blocked routing-governance.
#   3. Own token's ANCESTOR coverage (fallback) -> use it; else <session_token> unchanged
#      (absent/stale semantics preserved).
# This widens WHEN the bridge is consulted, not WHAT it accepts: cross-token acceptance stays
# EXACT-HEAD only (ancestor acceptance is scoped to the own token), so no forgery surface is
# added (token-scoping was session-isolation, never a security property). The grep -F prefilter
# on the HEAD sha still bounds the jq/git forks to the few files naming HEAD (usually 0-2).
# Fail-open: echoes <session_token> on any error.
verdict_resolve_token() {
    local session_token="${1:-}" proot="${2:-}" head f base tok best_clean=""
    # 1. Own verdict at EXACT HEAD -> use it, no sibling scan (byte-identical fast path).
    #    NOTE: verdict_sha_is_head, NOT verdict_covers_head — an own ANCESTOR verdict must
    #    NOT short-circuit past a sibling verdict measured at the exact HEAD (issue #123).
    if [ -n "$session_token" ] && verdict_sha_is_head "$session_token" "$proot"; then
        printf '%s' "$session_token"; return 0
    fi
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || head=""
    if [ -n "$head" ]; then
        # 2. Cross-token bridge: sibling artifacts bound to the EXACT HEAD. Failure@HEAD
        #    outranks clean (deny-bias). Own token skipped — steps 1/3 own it. A grep -F
        #    prefilter on the HEAD sha bounds the jq/git forks to the files naming HEAD.
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            base="${f##*/}"                               # fork-free basename (bash 3.2; no BSD -- ambiguity)
            tok="${base#.skill-project-verified-}"
            [ -z "$tok" ] && continue
            [ "$tok" = "$session_token" ] && continue
            verdict_sha_is_head "$tok" "$proot" || continue   # jq-confirm exact HEAD (grep can match other fields)
            if verdict_has_test_failure "$tok"; then printf '%s' "$tok"; return 0; fi
            [ -z "$best_clean" ] && verdict_is_clean "$tok" && best_clean="$tok"
        done <<EOF
$(grep -lF "$head" "${HOME}/.claude/.skill-project-verified-"* 2>/dev/null)
EOF
        [ -n "$best_clean" ] && { printf '%s' "$best_clean"; return 0; }
    fi
    # 3. No exact-HEAD verdict anywhere -> fall back to the session's OWN coverage, which
    #    ACCEPTS an ANCESTOR (scoped to the own token — forgery posture). Else unchanged.
    if [ -n "$session_token" ] && verdict_covers_head "$session_token" "$proot"; then
        printf '%s' "$session_token"; return 0
    fi
    printf '%s' "$session_token"
}

# verdict_has_test_failure <token> — 0 iff present+parseable AND .failed non-empty.
# Positive-evidence only: a missing/malformed artifact returns 1 (no failure),
# so verify-hardening never denies for absence.
verdict_has_test_failure() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e '((.failed // []) | length) > 0' "$f" >/dev/null 2>&1
}

# verdict_is_clean <token> — 0 iff present+parseable AND fully clean (same
# predicate deploy-gate uses for local verification of record).
verdict_is_clean() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e '((.failed // []) | length == 0)
       and ((.could_not_verify // []) | length == 0)
       and ((.gate_gaming_status // "") == "clean")' "$f" >/dev/null 2>&1
}

# verdict_failing_gates <token> — prints comma-joined .failed command names.
verdict_failing_gates() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 0
    [ -f "$f" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '((.failed // []) | join(", "))' "$f" 2>/dev/null || true
}

# is_routing_repo <proj_root> — 0 iff this looks like a skill-routing plugin repo
# (has config/default-triggers.json). Scopes the routing-governance gate.
is_routing_repo() {
    local proot="${1:-}"
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$proot" ] && [ -f "${proot}/config/default-triggers.json" ]
}

# _routing_base <proj_root> — best-available mainline merge-base for HEAD.
_routing_base() {
    local proot="${1:-.}" ref b
    for ref in origin/HEAD '@{upstream}' origin/main main origin/master master; do
        b="$(git -C "$proot" merge-base HEAD "$ref" 2>/dev/null)" && [ -n "$b" ] && { printf '%s' "$b"; return 0; }
    done
    return 1
}

# verdict_routing_delta <token> <proj_root> — 0 iff routing paths changed between
# the verdict's sha and HEAD (i.e., routing work POST-DATES the verdict, so the
# clean verdict does not cover it). Used by the routing gate to decide whether an
# ancestor-clean verdict is still authoritative. Fail-open: sha unknown/unreadable
# => 1 (no detectable delta => don't manufacture a false-block).
verdict_routing_delta() {
    local token="${1:-}" proot="${2:-}" sha head names
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || return 1
    names="$(git -C "${proot:-.}" diff --name-only "$sha" "$head" 2>/dev/null)" || return 1
    printf '%s\n' "$names" | grep -Eq '^(skills|config|hooks)/'
}

# _branch_diff_names <proj_root> — name-only branch diff (mainline merge-base
# ..HEAD), shared by diff_touches_routing and diff_touches_evaluator so the
# deny gate and the advisory can never disagree on what the branch changed.
# Fail-open: unresolvable root/base or git error => non-zero, no output.
_branch_diff_names() {
    local proot="${1:-}" head base
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$proot" ] && return 1
    head="$(git -C "$proot" rev-parse HEAD 2>/dev/null)" || return 1
    base="$(_routing_base "$proot")" || return 1
    git -C "$proot" diff --name-only "$base" "$head" 2>/dev/null
}

# diff_touches_routing <proj_root> — 0 iff the branch diff (base..HEAD) touches a
# routing path. Fail-open: unresolvable base => 1 (no gate).
diff_touches_routing() {
    local names
    names="$(_branch_diff_names "${1:-}")" || return 1
    printf '%s\n' "$names" | grep -Eq '^(skills|config|hooks)/'
}

# _EVALUATOR_SURFACES — files whose edit changes what "verified" means or what
# the gate TRUSTS: the drift-canary manifest (hooks/openspec-guard.sh +
# session-start's _GATE_ENFORCE_LIBS; superset enforced by
# tests/test-evaluator-surface.sh), the gate declaration (.verify.yml), the
# measurement chain (verdict writer, gaming checker), and the branch-ledger
# milestone writer (skill-completion-hook.sh — the gate trusts what it
# records). The activation-hook walker is deliberately EXCLUDED: it is the
# most-edited file in the repo, and listing it would make this advisory
# near-constant noise. Consumed ONLY by the advisory path — this list must
# never join a fail-closed deny (design D1, evaluator-surface-advisory).
_EVALUATOR_SURFACES="hooks/openspec-guard.sh hooks/skill-gate.sh hooks/lib/verdict.sh hooks/lib/branch-ledger.sh hooks/lib/git-command.sh hooks/lib/session-token.sh hooks/lib/phase-evidence.sh hooks/lib/phase-attest.sh hooks/skill-completion-hook.sh .verify.yml scripts/verify-and-record.sh skills/project-verification/scripts/gate-gaming-check.sh"

# diff_touches_evaluator <proj_root> — 0 iff the branch diff (mainline
# merge-base..HEAD) touches an evaluator surface; prints each touched surface
# on its own line. Exact whole-path membership (awk index over the padded
# list): surfaces are files, not trees, so a lookalike path cannot over-fire;
# one fork instead of a grep per surface (PreToolUse hot path). Fail-open:
# unresolvable base/git error => 1, no output (advisory silence, never a block).
diff_touches_evaluator() {
    local names hits
    names="$(_branch_diff_names "${1:-}")" || return 1
    hits="$(printf '%s\n' "$names" | awk -v s=" ${_EVALUATOR_SURFACES} " '$0 != "" && index(s, " " $0 " ")' 2>/dev/null)" || return 1
    [ -n "$hits" ] || return 1
    printf '%s\n' "$hits"
}
