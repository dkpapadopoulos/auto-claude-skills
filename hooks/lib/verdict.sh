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

# SUBJECT COMMIT (issue #219). Every helper below that used to hardcode `HEAD`
# now takes an OPTIONAL trailing <commit>: the commit the gated command actually
# acts on, which is not the checked-out HEAD whenever the command names another
# ref (`git push origin <branch>`) or acts in another worktree (`git -C`).
# Omitting it resolves `HEAD` exactly as before, so every existing caller and
# every external consumer (scripts/gate-status.sh, tests) is unchanged.
#
# The caller resolves and VALIDATES the commit; these helpers pass it to git as
# a revision, never as a path or flag.

# verdict_sha_is_head <token> <proj_root> [commit] — 0 iff artifact .sha is the
# subject commit exactly (HEAD when no commit is given).
verdict_sha_is_head() {
    local token="${1:-}" proot="${2:-}" rev="${3:-HEAD}" sha head
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse "$rev" 2>/dev/null)" || return 1
    [ -n "$head" ] && [ "$sha" = "$head" ]
}

# verdict_covers_head <token> <proj_root> [commit] — 0 iff .sha == the subject
# commit or is an ancestor of it on the branch. This is the branch-scoping the
# token-scoped artifact lacks: an unrelated (cross-branch) or missing sha never
# covers the subject.
verdict_covers_head() {
    local token="${1:-}" proot="${2:-}" rev="${3:-HEAD}" sha head
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse "$rev" 2>/dev/null)" || return 1
    [ -z "$head" ] && return 1
    [ "$sha" = "$head" ] && return 0
    git -C "${proot:-.}" merge-base --is-ancestor "$sha" "$head" 2>/dev/null
}

# verdict_resolve_token <session_token> <proj_root> [commit] — pick the token whose verdict
# is authoritative for the CURRENT push. The verdict is bound to the COMMIT (sha),
# NOT the session: the project-verification writer has no stdin payload, while this
# hook resolves payload-first (issue #51). Concurrent sessions clobber the shared
# singleton (last-writer-wins) so the two tokens diverge and a token-scoped read
# would never find the verdict — a live deadlock.
#
# As of issue #156 the writer no longer *depends* on the singleton — it resolves
# own-session-first via session-token.sh::resolve_own_session_token, the same
# identity this hook derives — so the common case is now leg 1, not the bridge.
# The bridge is still required and NOT redundant: it covers the degraded writer
# paths (no CLAUDE_CODE_SESSION_ID, no transcript on disk, lib unavailable, an
# explicit SKILL_SESSION_TOKEN) and genuinely cross-session verification. Do not
# read this bridge as evidence that a Bash-turn writer cannot do better.
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
    local session_token="${1:-}" proot="${2:-}" rev="${3:-HEAD}" head f base tok best_clean=""
    # 1. Own verdict at EXACT HEAD -> use it, no sibling scan (byte-identical fast path).
    #    NOTE: verdict_sha_is_head, NOT verdict_covers_head — an own ANCESTOR verdict must
    #    NOT short-circuit past a sibling verdict measured at the exact HEAD (issue #123).
    if [ -n "$session_token" ] && verdict_sha_is_head "$session_token" "$proot" "$rev"; then
        printf '%s' "$session_token"; return 0
    fi
    head="$(git -C "${proot:-.}" rev-parse "$rev" 2>/dev/null)" || head=""
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
            verdict_sha_is_head "$tok" "$proot" "$rev" || continue   # jq-confirm exact HEAD (grep can match other fields)
            if verdict_has_test_failure "$tok"; then printf '%s' "$tok"; return 0; fi
            [ -z "$best_clean" ] && verdict_is_clean "$tok" && best_clean="$tok"
        done <<EOF
$(grep -lF "$head" "${HOME}/.claude/.skill-project-verified-"* 2>/dev/null)
EOF
        [ -n "$best_clean" ] && { printf '%s' "$best_clean"; return 0; }
    fi
    # 3. No exact-HEAD verdict anywhere -> fall back to the session's OWN coverage, which
    #    ACCEPTS an ANCESTOR (scoped to the own token — forgery posture). Else unchanged.
    if [ -n "$session_token" ] && verdict_covers_head "$session_token" "$proot" "$rev"; then
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

# verdict_test_delta <token> — echo the recorded test_delta (covered|missing|n/a|"").
verdict_test_delta() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -r '.test_delta // ""' "$f" 2>/dev/null
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

# _routing_base <proj_root> [commit] — best-available mainline merge-base for the
# subject commit (HEAD when none is given).
_routing_base() {
    local proot="${1:-.}" rev="${2:-HEAD}" ref b up
    # `@{upstream}` with no left-hand side means the CHECKED-OUT branch's
    # upstream, which is the wrong branch as soon as the subject is another one.
    # Ask for the subject's own upstream instead; a sha (or a branch with no
    # upstream) simply fails to resolve and the loop falls through.
    up="${rev}@{upstream}"
    for ref in origin/HEAD "$up" origin/main main origin/master master; do
        b="$(git -C "$proot" merge-base "$rev" "$ref" 2>/dev/null)" && [ -n "$b" ] && { printf '%s' "$b"; return 0; }
    done
    return 1
}

# verdict_routing_delta <token> <proj_root> — 0 iff routing paths changed between
# the verdict's sha and HEAD (i.e., routing work POST-DATES the verdict, so the
# clean verdict does not cover it). Used by the routing gate to decide whether an
# ancestor-clean verdict is still authoritative. Fail-open: sha unknown/unreadable
# => 1 (no detectable delta => don't manufacture a false-block).
verdict_routing_delta() {
    local token="${1:-}" proot="${2:-}" rev="${3:-HEAD}" sha head names
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse "$rev" 2>/dev/null)" || return 1
    names="$(git -C "${proot:-.}" diff --name-only "$sha" "$head" 2>/dev/null)" || return 1
    printf '%s\n' "$names" | grep -Eq '^(skills|config|hooks)/'
}

# _branch_diff_names <proj_root> [commit] — name-only branch diff (mainline
# merge-base..subject, HEAD when no commit is given), shared by
# diff_touches_routing and diff_touches_evaluator so the deny gate and the
# advisory can never disagree on what the branch changed.
# Fail-open: unresolvable root/base or git error => non-zero, no output.
_branch_diff_names() {
    local proot="${1:-}" rev="${2:-HEAD}" head base
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$proot" ] && return 1
    head="$(git -C "$proot" rev-parse "$rev" 2>/dev/null)" || return 1
    base="$(_routing_base "$proot" "$rev")" || return 1
    git -C "$proot" diff --name-only "$base" "$head" 2>/dev/null
}

# diff_touches_routing <proj_root> [commit] — 0 iff the branch diff
# (base..subject) touches a routing path. Fail-open: unresolvable base => 1.
diff_touches_routing() {
    local names
    names="$(_branch_diff_names "${1:-}" "${2:-HEAD}")" || return 1
    printf '%s\n' "$names" | grep -Eq '^(skills|config|hooks)/'
}

# _EVALUATOR_SURFACES — files whose edit changes what "verified" means or what
# the gate TRUSTS: the drift-canary manifest (hooks/openspec-guard.sh +
# session-start's _GATE_ENFORCE_LIBS; superset enforced by
# tests/test-evaluator-surface.sh), the gate declaration (.verify.yml), the
# measurement chain (verdict writer, gaming checker, and the runner
# .verify.yml names — tests/run-tests.sh IS the whole local gate, so listing
# the declaration without the runner guards the signpost and not the road:
# neutering the runner changes what every later verdict means and fired
# nothing, issue #189), and the branch-ledger milestone writer
# (skill-completion-hook.sh — the gate trusts what it records). The
# activation-hook walker is deliberately EXCLUDED: it is the most-edited file
# in the repo, and listing it would make this advisory near-constant noise;
# that objection does NOT extend to the runner, measured at 2 commits in the
# last 200 against the walker's 103. Individual tests/test-*.sh files stay out
# for the same churn reason — the runner alone is the meaning-bearing file.
# SCOPE: this list is matched against the CONSUMING repo's diff, so unlike the
# ACS-only paths here, `tests/run-tests.sh` (like `.verify.yml` before it, the
# existing generic precedent) can also fire in a user repo that happens to use
# that path. Acceptable because the entry is advisory-only and a repo with that
# file almost certainly means it as its runner; a repo that does not can ignore
# one line of text. Deriving the runner from `.verify.yml` instead was rejected:
# it puts a YAML parse on the PreToolUse hot path (~50ms budget) to remove a
# false positive that costs nothing.
# Consumed ONLY by the advisory path — this list must never join a fail-closed
# deny (design D1, evaluator-surface-advisory).
_EVALUATOR_SURFACES="hooks/openspec-guard.sh hooks/skill-gate.sh hooks/lib/verdict.sh hooks/lib/branch-ledger.sh hooks/lib/git-command.sh hooks/lib/session-token.sh hooks/lib/phase-evidence.sh hooks/lib/phase-attest.sh hooks/skill-completion-hook.sh .verify.yml scripts/verify-and-record.sh skills/project-verification/scripts/gate-gaming-check.sh tests/run-tests.sh"

# diff_touches_evaluator <proj_root> — 0 iff the branch diff (mainline
# merge-base..HEAD) touches an evaluator surface; prints each touched surface
# on its own line. Exact whole-path membership (awk index over the padded
# list): surfaces are files, not trees, so a lookalike path cannot over-fire;
# one fork instead of a grep per surface (PreToolUse hot path). Fail-open:
# unresolvable base/git error => 1, no output (advisory silence, never a block).
diff_touches_evaluator() {
    local names hits
    names="$(_branch_diff_names "${1:-}" "${2:-HEAD}")" || return 1
    hits="$(printf '%s\n' "$names" | awk -v s=" ${_EVALUATOR_SURFACES} " '$0 != "" && index(s, " " $0 " ")' 2>/dev/null)" || return 1
    [ -n "$hits" ] || return 1
    printf '%s\n' "$hits"
}
