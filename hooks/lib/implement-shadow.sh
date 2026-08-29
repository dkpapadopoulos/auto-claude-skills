#!/bin/bash
# implement-shadow.sh — append one adjudicable shadow record per IMPLEMENT
# would-block event, so the deny-flip's push-replay backtest has a corpus.
#
# DIAGNOSTIC ONLY. It never influences a gate decision and fails open on every
# error path, so it is deliberately NOT in _GATE_ENFORCE_LIBS (same posture as
# scripts/push-gate-capture.sh).
#
# predicate_version is load-bearing: when the IMPLEMENT predicate changes, bump
# it, and NEVER pool records across versions when computing a rate. See
# openspec/changes/implement-shadow-event/design.md for the pre-registered
# false-block definition and decision rule.
#
# Raw command text is never written here — the transcript_path pointer is the
# adjudication surface, which keeps the secret posture identical to capture.

# 2 (#169): records may now carry would_block:false for episodes the IMPLEMENT
# leg resolved via attestation alone. Readers computing a false-block rate MUST
# filter `select(.would_block == true)` — schema 1 records are uniformly true,
# so that filter is correct across both versions.
#
# 3 (corpus-validity audit, F2): records carry `impl_evidence_detail`, a per-leg
# object naming what each evidence check actually returned. `impl_evidence_kind`
# is UNCHANGED ("none"/"attested") — it is asserted in two test files and pinned
# in three openspec specs, so the new information is additive, following the
# #133 sidecar precedent rather than widening a frozen field.
#
# Why this field is load-bearing: the leg's four evidence predicates each return
# 1 for BOTH "checked, no evidence" and "could not check" (e.g. _bridge_has
# returns 1 when the branch-ledger lib failed to source, when the function is
# undefined, AND when there is genuinely no record). Only the last means "no
# implementation work"; the first two are infrastructure failures where the
# constant advisory names the WRONG remedy — the pre-registered false_block
# condition. Re-deriving that after the fact is impossible: session-start GC
# deletes composition/invocation/attest state at 7 days
# (`hooks/session-start-hook.sh`), while the corpus needs months to reach n=29.
#
# That schema-3 change did NOT bump predicate_version: it changed what the
# record DESCRIBES, not when the leg fires. (The separate #219 bump below did
# change when the leg fires — the two are independent axes on purpose.)
IMPLEMENT_SHADOW_SCHEMA_VERSION=3
# 2 (#161): merge-path material_source is now measured against the merged PR's
# file list, not the branch-local delta. v1 merge records measured a different
# subject and MUST NOT be pooled with v2.
# 3 (#219): PUSH-path material_source is now measured against the tree and ref
# the pushed command actually names (`git -C <worktree>`, `cd <worktree> &&`, or
# a `git push origin <branch>` refspec), not against whatever the SESSION cwd
# happened to have checked out. That is the same wrong-subject defect #161 fixed
# for merges, and it changes when the leg fires: a push measured against a
# concurrent session's branch could report material_source on a branch that
# touched no source at all, and vice versa. v2 records measured a different
# subject and MUST NOT be pooled with v3.
IMPLEMENT_SHADOW_PREDICATE_VERSION=3

# implement_shadow_record <action> <repo> <session_token> <transcript_path> <evidence_kind> <diff_base> <material_source> [would_block] [evidence_detail] [rev]
#   action: push | gh-merge
#   evidence_kind: which evidence classes were tried and missed (e.g. "none")
#   diff_base: what the material-source check was measured against
#              (branch-local | pr:<n> | unresolved); defaults to branch-local
#   material_source: whether the measured subject touched material source
#              (true | false); defaults to true
#   would_block: whether the leg would have blocked (true | false); defaults to
#              true. false marks an episode the leg resolved via attestation
#              alone — recorded so the deny-flip corpus can measure how often
#              attestation, rather than work, satisfied the leg (#169).
#   evidence_detail: OPTIONAL space-separated "<leg>:<status>" pairs, e.g.
#              "ledger:missing invocation:missing bridge:cannot_check
#              attestation:missing". Vocabulary: present | missing |
#              cannot_check, plus `not_evaluated` RESERVED — the guard's two
#              call sites only fire once every leg has been consulted for every
#              slot, so nothing emits it today. It is named here so a future
#              short-circuiting caller has a value that is not a lie, but do not
#              write a query expecting it to appear: a `not_evaluated` filter
#              over the current corpus returns empty because no producer exists,
#              not because every leg ran. CONSTRAINT on future vocabulary: a
#              status value must contain NO colon and NO space. Both fail
#              SILENTLY, and differently (measured against the jq below, not
#              assumed): a colon-bearing value (`cannot_check:no_token`, a URL)
#              splits into 3 elements, fails `length == 2`, and the key is
#              DROPPED from the object — "invocation:cannot_check:no_token"
#              yields an object with no `invocation` key at all, and a string
#              whose every pair is colon-bearing degrades the whole field to
#              null. A space-bearing value is instead TRUNCATED at the space
#              ("invocation:has space" => `"invocation":"has"`), because the
#              outer split(" ") cuts it first and the orphan tail carries no
#              colon. Neither errors. Encode any sub-reason as a new flat value
#              or a separate key, never as a suffix.
#              Parsed into an object BY JQ, never
#              by bash — the caller is a hook running under Bash 3.2 and must
#              not hand-build JSON. Omitted or malformed => the field is null,
#              NOT a fabricated all-missing object: "not recorded" and "checked
#              and absent" are different states and an adjudicator must be able
#              to tell them apart.
# Always returns 0. Compact JSONL (jq -cn) because this is a line format.
implement_shadow_record() {
    command -v jq >/dev/null 2>&1 || return 0
    local _act="${1:-unknown}" _repo="${2:-}" _tok="${3:-}" _tp="${4:-}" _ev="${5:-none}" _db="${6:-branch-local}"
    local _ms="${7:-true}" _wb="${8:-true}" _ed="${9:-}" _rev="${10:-HEAD}"
    local _log _dir _ts _nonce _rid _branch _head
    _log="${IMPLEMENT_SHADOW_LOG:-${HOME}/.claude/.push-implement-shadow.jsonl}"
    _dir="$(dirname "${_log}" 2>/dev/null)" || return 0
    [ -d "${_dir}" ] || mkdir -p "${_dir}" 2>/dev/null || return 0
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || return 0
    [ -n "${_ts}" ] || return 0
    # Nonce keeps record_id unique when ts, pid and token all repeat.
    _nonce="${RANDOM:-0}${RANDOM:-0}$$"
    # If BOTH shasum and cksum are absent (neither on PATH), the pipeline's
    # stdout is empty, _rid ends up empty, and the next line returns 0 — the
    # event is silently skipped. Deliberate: this is the same fail-open
    # posture as every other failure mode in this recorder, not a bug.
    _rid="$(printf '%s|%s|%s|%s|%s' "${_ts}" "$$" "${_tok}" "${_act}" "${_nonce}" \
        | { shasum -a 256 2>/dev/null || cksum; } | tr -dc 'a-f0-9' | cut -c1-16)"
    [ -n "${_rid}" ] || return 0
    # The record names the SUBJECT the leg measured, not the checkout it ran in
    # (#219). `_rev` is the caller's already-validated revision, and `branch` must
    # describe the SAME thing `head_sha` and `material_source` were computed over
    # — episode identity is `(repo, branch, session_token)`, so a branch naming
    # one commit while head_sha names another splits or merges episodes that are
    # not the same work.
    #
    # Three cases, and collapsing the third into the second was a real defect
    # caught in review: a push can name a raw sha, a tag, or a remote-tracking
    # ref (`git push origin <sha>:refs/heads/x`). The guard resolves those to a
    # commit via `^{commit}`, so `head_sha` is right — but falling back to the
    # CHECKED-OUT branch there recorded a branch that has nothing to do with it.
    # `--abbrev-ref` on the rev itself is honest: a branch name for a branch, the
    # tag's short name for a tag, the sha for a detached revision.
    case "${_rev}" in
        refs/heads/*) _branch="${_rev#refs/heads/}" ;;
        HEAD|'')      _branch="$(git -C "${_repo}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || _branch="" ;;
        *)            _branch="$(git -C "${_repo}" rev-parse --abbrev-ref "${_rev}" 2>/dev/null)" || _branch="" ;;
    esac
    _head="$(git -C "${_repo}" rev-parse "${_rev}" 2>/dev/null)" || _head=""
    : >> "${_log}" 2>/dev/null || return 0
    chmod 0600 "${_log}" 2>/dev/null || true
    jq -cn \
        --argjson sv "${IMPLEMENT_SHADOW_SCHEMA_VERSION}" \
        --argjson pv "${IMPLEMENT_SHADOW_PREDICATE_VERSION}" \
        --arg rid "${_rid}" --arg ts "${_ts}" --arg act "${_act}" \
        --arg repo "${_repo}" --arg branch "${_branch}" --arg head "${_head}" \
        --arg tok "${_tok}" --arg tp "${_tp}" --arg ev "${_ev}" --arg db "${_db}" \
        --argjson ms "${_ms}" --argjson wb "${_wb}" --arg ed "${_ed}" \
        '{schema_version:$sv,record_id:$rid,ts:$ts,predicate_version:$pv,
          gate:"push-implement",would_block:$wb,action:$act,
          repo:$repo,branch:$branch,head_sha:$head,
          impl_in_chain:true,material_source:$ms,impl_evidence_kind:$ev,diff_base:$db,
          impl_evidence_detail:
            ($ed
             | if . == "" then null
               else ( [ split(" ")[]
                        | select(index(":"))
                        | split(":")
                        | select(length == 2 and .[0] != "" and .[1] != "")
                        | {(.[0]): .[1]} ]
                      | if length == 0 then null else add end )
               end),
          session_token:$tok,transcript_path:$tp}' \
        >> "${_log}" 2>/dev/null || return 0
    return 0
}
