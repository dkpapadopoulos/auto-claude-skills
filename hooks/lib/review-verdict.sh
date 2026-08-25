#!/usr/bin/env bash
# review-verdict.sh — read + interpret the owned REVIEW verdict artifact
# (~/.claude/.skill-review-verdict-<token>). Issue #197.
#
# WHY THIS EXISTS. The push gate's REVIEW leg records INVOCATION, never WORK:
# Skill(...) returns the INSTRUCTION BODY, so PostToolUse ^Skill$ fires BEFORE
# any reviewer dispatch is attempted. No enrichment of that payload can ever
# witness a review, because at the moment the hook runs the work has not
# happened. This lib is the VERDICT half of the same STATUS/VERDICT split that
# hooks/lib/verdict.sh already gives VERIFY: status answers "did the skill
# return", verdict answers "did a review happen and did it pass".
#
# ADVISORY ONLY in this change. Consumed by the guard's warn-first review leg,
# which sets no permissionDecision. Consequently this file is deliberately NOT
# in session-start's _GATE_ENFORCE_LIBS (same posture as implement-shadow.sh
# and pr-diff.sh). PAIRED: if the leg ever becomes gate-enforcing, this file
# MUST be added to that list, or a broken install falls open in silence.
#
# Bash 3.2. Every function fails open — absent, unreadable, malformed, or
# unparseable artifacts return "no usable verdict", never a block.

review_verdict_artifact_path() {
    local token="${1:-}"
    [ -z "$token" ] && return 1
    printf '%s' "${HOME}/.claude/.skill-review-verdict-${token}"
}

# review_verdict_field <token> <field> — echo one top-level scalar, empty on
# any failure. Callers must treat empty as "unknown", never as a value.
review_verdict_field() {
    local token="${1:-}" field="${2:-}" f
    [ -n "$field" ] || return 1
    f="$(review_verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    # `type=="object"` guards the non-object shapes (a bare array parses fine
    # as JSON and would otherwise yield null rather than a refusal).
    jq -er --arg k "$field" 'select(type=="object") | .[$k] // empty' "$f" 2>/dev/null
}

_review_verdict_head_sha() {
    review_verdict_field "${1:-}" reviewed_head_sha
}

# review_verdict_is_clean <token> — 0 iff the artifact is present, parseable,
# an object, and asserts a terminal CLEAN review.
#
# `unresolved_blocking > 0` disqualifies even when .verdict says "clean": a
# provider that contradicts itself is not evidence, and the deny-bias belongs
# on the side of demanding another look. Note this is a claim about the
# ARTIFACT only — binding it to a commit is review_verdict_covers_head's job,
# and callers gating on "reviewed" MUST require both.
review_verdict_is_clean() {
    local token="${1:-}" f
    f="$(review_verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e 'select(type=="object")
       | ((.verdict // "") == "clean")
       and (((.unresolved_blocking // 0) | tonumber? // 1) == 0)' "$f" >/dev/null 2>&1
}

# review_verdict_covers_head <token> <proj_root> — 0 iff reviewed_head_sha is
# bound to THIS branch: equal to HEAD, or a branch-local ancestor of HEAD.
#
# Deliberately reuses branch_ledger_sha_is_branch_local rather than
# re-deriving the rule: #131/#133 both bit on two implementations of one
# binding rule drifting apart. When branch-ledger.sh is unavailable the
# fallback is EXACT-HEAD ONLY — strictly narrower, never wider, so a missing
# lib cannot widen what binds.
#
# Ancestor acceptance is deliberate. Naive exact-HEAD staleness was measured
# at 56-94% false blocks with ZERO catches (openspec/changes/gate-status/
# backtest-results.md); repeating it would be a known-bad design. Review-fix
# commits are NOT classified — that heuristic is exactly the fitted matching
# the publish-guard design rejects. The delta is recorded and measured instead.
review_verdict_covers_head() {
    local token="${1:-}" proot="${2:-}" sha head base=""
    sha="$(_review_verdict_head_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$proot" ] || return 1
    head="$(git -C "$proot" rev-parse HEAD 2>/dev/null)" || return 1
    [ -z "$head" ] && return 1
    [ "$sha" = "$head" ] && return 0

    command -v branch_ledger_sha_is_branch_local >/dev/null 2>&1 || return 1
    command -v _branch_ledger_mainline_base >/dev/null 2>&1 || return 1
    base="$(_branch_ledger_mainline_base "$proot" 2>/dev/null)" || base=""
    branch_ledger_sha_is_branch_local "$sha" "$proot" "$head" "$base"
}

# review_verdict_delta_files <token> <proj_root> — echo how many files changed
# since the reviewed sha. Telemetry for the shadow corpus, NOT a predicate:
# it is the input to deciding later whether ancestor acceptance is too loose,
# which is a question the corpus answers and a guess cannot. Empty on failure.
review_verdict_delta_files() {
    local token="${1:-}" proot="${2:-}" sha head n
    sha="$(_review_verdict_head_sha "$token")" || return 1
    [ -n "$sha" ] || return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$proot" ] || return 1
    head="$(git -C "$proot" rev-parse HEAD 2>/dev/null)" || return 1
    [ "$sha" = "$head" ] && { printf '0'; return 0; }
    n="$(git -C "$proot" diff --name-only "$sha" "$head" 2>/dev/null | grep -c . 2>/dev/null)" || return 1
    printf '%s' "${n:-0}"
}

# review_verdict_subject_digest <proj_root> <base> <head> — the changed-file
# digest a writer records. Two branches can share a HEAD sha in a
# worktree-heavy repo, so the artifact is bound to the DIFF, not only a commit.
review_verdict_subject_digest() {
    local proot="${1:-}" base="${2:-}" head="${3:-}" names hasher
    [ -n "$proot" ] && [ -n "$base" ] && [ -n "$head" ] || return 1
    names="$(git -C "$proot" diff --name-only "$base" "$head" 2>/dev/null | LC_ALL=C sort)" || return 1
    if command -v shasum >/dev/null 2>&1; then hasher="shasum -a 256"
    elif command -v sha256sum >/dev/null 2>&1; then hasher="sha256sum"
    else return 1; fi
    printf '%s' "$names" | $hasher 2>/dev/null | cut -c1-12
}
