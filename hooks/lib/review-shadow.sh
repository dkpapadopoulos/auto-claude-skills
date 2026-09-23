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
#   cannot-check the reader lib did not load        -> candidate FALSE BLOCK
#                (the registration's false_block covers an infrastructure reason
#                 "the advisory misnames"; this leg's cannot-check text makes no
#                 claim at all, so treating it as always-false_block is an
#                 INTERPRETATION, erring away from clearing the flip)
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

# Version constants are EXPORTED so the reader derives them instead of pinning
# its own literals. The IMPLEMENT pair proved what an independent pin costs: a
# producer bump silently blacked out the corpus -- `--status` reported 0
# episodes with live records counted "unpoolable", which reads exactly like an
# empty corpus, on the one instrument that must never fake that state.
#
# schema_version 2 (was 1): the record now names the command's SUBJECT rather
# than the session checkout.
#
# predicate_version 2 (was 1) has TWO independent grounds, and recording only
# the first would leave the door open to re-pooling the old corpus later:
#
#   (a) `78aa21e` changed this leg's own FIRE CONDITION (below), and
#   (b) the recorder fix itself qualifies, because `repo` and `branch` are not
#       description. They ARE the episode key `(repo, branch, session_token)` --
#       the denominator the floor and the Clopper-Pearson bound are computed
#       over -- and `head_sha` is what an adjudicator follows to decide whether
#       a review really happened. A session-derived branch can name a
#       CONCURRENT session's parked branch, so pooling can silently split one
#       real episode into two (inflating n toward the floor, the dangerous
#       direction) or collapse two into one, and it can send an adjudicator to
#       the wrong branch's history with no way to notice afterwards.
#
# So the rule stated above -- "fire condition -> predicate, describes -> schema"
# -- HAS A GAP, and this record is the evidence. The test is not "does this
# change when the leg fires" but "does this change what a pooled episode
# denominator, or a pooled true_catch/false_block label, MEANS". Read it that
# way before deciding the next bump; read it literally and you will reach the
# wrong answer here in good faith, which is how this leg got into this state.
#
# On (a): this bump belongs to `78aa21e` ("measure the push
# gate's subject from the gated command, not the session cwd", #219, 2026-09-01)
# and is being recorded late. That commit moved this leg's OWN fire condition --
# `_diff_touches_material_source` and `review_verdict_covers_head` both went from
# the session root to the resolved subject -- and bumped implement-shadow.sh
# while leaving this file untouched. So:
#
#   predicate_version 1 = pre-#219  fire condition (session-derived)
#   predicate_version 2 = post-#219 fire condition (subject-derived)
#
# Every record written before this line existed says `1` and spans BOTH, because
# the field that exists to partition them was never moved. Such records are
# reportable but MUST NOT be pooled into a rate, and a reader must say which of
# those two it is doing -- silently counting them and silently dropping them are
# equally wrong, and the second is what blacked out the IMPLEMENT corpus.
#
# A timestamp does NOT recover the provenance: sessions run a cached plugin
# version, so a record's date does not tell you which guard wrote it.
REVIEW_SHADOW_SCHEMA_VERSION=2
REVIEW_SHADOW_PREDICATE_VERSION=2

review_shadow_record() {
    # <session_token> <subj_root> <reason> <action:push|merge> [<subj_rev>]
    local token="${1:-}" proot="${2:-}" reason="${3:-}" action="${4:-push}"
    local rev="${5:-HEAD}"
    local log branch head repo ts rec rid nonce
    command -v jq >/dev/null 2>&1 || return 0

    log="${REVIEW_SHADOW_LOG:-${HOME}/.claude/.push-review-shadow.jsonl}"
    mkdir -p "$(dirname "$log")" 2>/dev/null || return 0

    # Every field is best-effort. An unresolvable branch or HEAD records as an
    # empty string rather than aborting: a record with a hole is adjudicable,
    # a missing record is not. Consumers MUST split on tabs with awk -F'\t' or
    # \x1f, never with bash `read` — tab is IFS whitespace, so an empty branch
    # would collapse and shift every later column (the shadow-adjudicate bug).
    #
    # The record names the SUBJECT the leg measured, not the checkout the hook
    # ran in (#219). Every predicate this leg fires on -- material_source and
    # review_verdict_covers_head -- is already evaluated against the resolved
    # subject, so a record describing the session's tree describes something the
    # decision was not about. Episode identity is `(repo, branch,
    # session_token)` and `head_sha` is the adjudication anchor, so this is not
    # cosmetic: it splits or merges episodes that are not the same work, and
    # points an adjudicator at a commit nobody was blocked over.
    #
    # Same three-case rule as implement-shadow.sh, and collapsing the third into
    # the second was a real defect there: a push can name a raw sha, a tag, or a
    # remote-tracking ref, which the guard resolves via `^{commit}`, so falling
    # back to the CHECKED-OUT branch would record a branch unrelated to the sha.
    case "${rev}" in
        refs/heads/*) branch="${rev#refs/heads/}" ;;
        HEAD|'')      branch="$(git -C "${proot:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch="" ;;
        *)            branch="$(git -C "${proot:-.}" rev-parse --abbrev-ref "${rev}" 2>/dev/null)" || branch="" ;;
    esac
    head="$(git -C "${proot:-.}" rev-parse "${rev:-HEAD}" 2>/dev/null)" || head=""
    repo="$(git -C "${proot:-.}" rev-parse --show-toplevel 2>/dev/null)" || repo=""
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts=""

    # A stable per-record handle, so an adjudication can name the record it
    # labels. Nonce keeps it unique when ts, pid and token all repeat -- which
    # they demonstrably do: the v1 corpus holds nine pairs of BYTE-IDENTICAL
    # lines (same second, same everything), each pair two genuinely distinct
    # gate invocations. Any id derived from content alone is therefore not
    # injective over this leg's own history.
    #
    # NOT a length check, deliberately. Review suggested rejecting a short id;
    # that would DROP a would-block event to avoid a cosmetic defect, trading
    # real data for tidiness. The record is what matters; the handle only has to
    # address it.
    #
    # The `cksum` fallback is DEGRADED but usable, and the contract below says so
    # because the previous wording did not. Measured: `cksum` prints decimal, so
    # `tr -dc 'a-f0-9'` keeps only digits and the id is ~9 numeric chars, not 16
    # hex -- non-empty, so the guard passes and the record IS written. The old
    # comment claimed the event would be "skipped", which was simply false for
    # that path, and a future reader could have relied on it. Collision risk
    # stays negligible (~10^9 space, a few hundred records, and the nonce is in
    # the hash input), and it is reached only if `shasum` is absent.
    #
    # Genuinely empty output is still silent, matching every other path here.
    nonce="$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -dc 'a-f0-9')"
    [ -n "${nonce}" ] || nonce="$(date +%N 2>/dev/null | tr -dc '0-9')"
    rid="$(printf '%s|%s|%s|%s|%s' "${ts}" "$$" "${token}" "${action}" "${nonce}" \
        | { shasum -a 256 2>/dev/null || cksum; } | tr -dc 'a-f0-9' | cut -c1-16)"
    [ -n "${rid}" ] || return 0

    rec="$(jq -nc \
        --argjson sv "${REVIEW_SHADOW_SCHEMA_VERSION}" \
        --argjson pv "${REVIEW_SHADOW_PREDICATE_VERSION}" \
        --arg rid "$rid" \
        --arg ts "$ts" --arg repo "$repo" --arg branch "$branch" \
        --arg head "$head" --arg token "$token" --arg reason "$reason" \
        --arg action "$action" --arg tp "${CLAUDE_CODE_TRANSCRIPT_PATH:-}" \
        '{schema_version:$sv, predicate_version:$pv, record_id:$rid,
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
