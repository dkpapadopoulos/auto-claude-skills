#!/bin/bash
# review-shadow.sh — append one adjudicable shadow record per REVIEW-VERDICT
# would-block event, so the deny-flip has a corpus to be decided on. Issue #197.
#
# DIAGNOSTIC ONLY. It never influences a gate decision and fails open on every
# error path, so it is deliberately NOT in _GATE_ENFORCE_LIBS — same posture as
# implement-shadow.sh, pr-diff.sh and scripts/push-gate-capture.sh.
#
# WHY A CORPUS AND NOT A DENY. The REVIEW verdict leg ships warn-only because
# the obvious strict rule is already known to be bad: naive exact-HEAD review
# staleness measured 56-94% false blocks with ZERO catches
# (openspec/changes/gate-status/backtest-results.md). The pre-registered
# decision rule, bands, episode definition and n floor live in
# openspec/changes/review-verdict/design.md and were registered BEFORE the
# observation window so the result cannot be reinterpreted afterwards.
#
# predicate_version is load-bearing: when the leg's FIRE CONDITION changes, bump
# it, and NEVER pool records across versions when computing a rate. Changing what
# a record merely DESCRIBES bumps schema_version instead, leaving the corpus
# poolable and the horizon un-restarted (the #169/#133 precedent).
#
# `reason` is the leg's own classification and is the field that makes a record
# adjudicable rather than a bare count:
#   absent       no verdict artifact covering HEAD  -> candidate TRUE CATCH
#   not-clean    a verdict exists and is not clean  -> candidate TRUE CATCH
#   unbound      clean, but not bound to this HEAD  -> the ancestor-policy question
#   cannot-check the reader lib did not load        -> ALWAYS a false_block
#
# That last row is why the field exists at all. Every one of these would render
# an identical "no review" advisory to the user, but `cannot-check` means the
# gate could not look, and an advisory that names the wrong remedy is the
# pre-registered false_block condition (the #198 lesson). Collapsing them into a
# single bit would bias the measured rate toward CLEARING the deny-flip, which
# is the direction that must never be guessed.
#
# Raw command text is never written. transcript_path is the adjudication
# pointer, keeping the secret posture identical to push-gate-capture.

review_shadow_record() {
    # <session_token> <proj_root> <reason> <action:push|merge>
    local token="${1:-}" proot="${2:-}" reason="${3:-}" action="${4:-push}"
    local log branch head repo ts rec
    command -v jq >/dev/null 2>&1 || return 0

    log="${REVIEW_SHADOW_LOG:-${HOME}/.claude/.push-review-shadow.jsonl}"
    mkdir -p "$(dirname "$log")" 2>/dev/null || return 0

    # Every field is best-effort. An unresolvable branch or HEAD records as an
    # empty string rather than aborting: a record with a hole is adjudicable,
    # a missing record is not. Consumers MUST split on tabs with awk -F'\t' or
    # \x1f, never with bash `read` — tab is IFS whitespace, so an empty branch
    # would collapse and shift every later column (the shadow-adjudicate bug).
    branch="$(git -C "${proot:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch=""
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || head=""
    repo="$(git -C "${proot:-.}" rev-parse --show-toplevel 2>/dev/null)" || repo=""
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts=""

    rec="$(jq -nc \
        --arg ts "$ts" --arg repo "$repo" --arg branch "$branch" \
        --arg head "$head" --arg token "$token" --arg reason "$reason" \
        --arg action "$action" --arg tp "${CLAUDE_CODE_TRANSCRIPT_PATH:-}" \
        '{schema_version:1, predicate_version:1,
          ts:$ts, repo:$repo, branch:$branch, head_sha:$head,
          session_token:$token, action:$action,
          would_block:true, reason:$reason,
          transcript_path:$tp}' 2>/dev/null)" || return 0
    [ -n "$rec" ] || return 0

    # No rotation in v1, deliberately. The capture log rotates 1000->500, which
    # here would silently drop UNADJUDICATED events and quietly bias the rate.
    # This leg fires only when STATUS is already satisfied, so it will accrue
    # more slowly than the IMPLEMENT corpus (measured 0.22 episodes/day) and
    # 500 records is far away. If the rate ever rises, rotation MUST exclude
    # unadjudicated records or snapshot their facts before dropping them.
    printf '%s\n' "$rec" >> "$log" 2>/dev/null || return 0
    chmod 600 "$log" 2>/dev/null || true
    return 0
}
