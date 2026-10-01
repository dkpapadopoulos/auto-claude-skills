#!/bin/bash
# verify-shadow.sh — append one shadow record per VERIFY measured-verdict event,
# so the deny-flip has a corpus to be decided on. Issue #301.
#
# DIAGNOSTIC ONLY. It never influences a gate decision and fails open on every
# error path, so it is deliberately NOT in _GATE_ENFORCE_LIBS — same posture as
# implement-shadow.sh and review-shadow.sh.
#
# The decision rule, the classification vocabulary, the episode definition and
# the starvation backstop are pre-registered in
# openspec/changes/verify-measured-verdict/design.md. The reader is
# scripts/verify-shadow-adjudicate.sh and ships in the same change as this
# writer: #239's REVIEW corpus reached its floor and nobody could see it.
#
# `classification` is the pre-registered vocabulary, exactly one per record:
#   explained_ladder  a clean verdict covers the commit, hand-authored rung
#   unexplained       the leg would block for any other reason
#   cannot_check      the verdict could not be read; NEVER counted unexplained
# `reason` is descriptive detail under it (absent | unbound | not-clean |
# unrecognised-source | hand-authored | unparseable | no-discovery-source |
# lib-unavailable | ...). It exists so a record is adjudicable rather than a
# bare count, and it is not part of the decision rule.
#
# `would_block` is false for cannot_check: the leg is fail-open, so a verdict it
# could not read is one it would not block on even after a deny-flip.
#
# `repo_id` is the origin URL (userinfo stripped), falling back to the common
# git dir and then the path. It is recorded at WRITE time because the
# pre-registered diversity clause counts REPOSITORIES, and a worktree path
# resolved at read time may no longer exist — and two worktrees of one
# repository must not read as two repos.
#
# Raw command text is never written. transcript_path is the adjudication
# pointer.
#
# predicate_version: bump when the leg's FIRE CONDITION changes, or when a
# change alters what a pooled episode key or classification MEANS, and never
# pool across versions. schema_version: bump for purely descriptive additions.
VERIFY_SHADOW_SCHEMA_VERSION=1
VERIFY_SHADOW_PREDICATE_VERSION=1

verify_shadow_record() {
    # <session_token> <subj_root> <classification> <reason> <action>
    #   [<subj_rev>] [<transcript_path>] [<material_source:true|false>] [<discovery_source>]
    local token="${1:-}" proot="${2:-}" class="${3:-}" reason="${4:-}" action="${5:-push}"
    local rev="${6:-HEAD}" tp="${7:-}" material="${8:-}" src="${9:-}"
    local log branch head repo repo_id ts rec rid nonce wb
    command -v jq >/dev/null 2>&1 || return 0

    # The vocabulary is closed. A record outside it could not be classified by
    # the reader, so it is not written at all rather than written wrong.
    case "${class}" in
        explained_ladder|unexplained) wb=true ;;
        cannot_check)                 wb=false ;;
        *) return 0 ;;
    esac

    log="${VERIFY_SHADOW_LOG:-${HOME}/.claude/.push-verify-shadow.jsonl}"
    mkdir -p "$(dirname "$log")" 2>/dev/null || return 0

    # Every field is best-effort: a record with a hole is adjudicable, a missing
    # record is not. Same three-case branch rule as review-shadow.sh — a push
    # can name a raw sha or a tag, and falling back to the CHECKED-OUT branch
    # there would record a branch unrelated to the sha.
    case "${rev}" in
        refs/heads/*) branch="${rev#refs/heads/}" ;;
        HEAD|'')      branch="$(git -C "${proot:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch="" ;;
        *)            branch="$(git -C "${proot:-.}" rev-parse --abbrev-ref "${rev}" 2>/dev/null)" || branch="" ;;
    esac
    head="$(git -C "${proot:-.}" rev-parse "${rev:-HEAD}" 2>/dev/null)" || head=""
    repo="$(git -C "${proot:-.}" rev-parse --show-toplevel 2>/dev/null)" || repo=""
    repo_id="$(git -C "${proot:-.}" remote get-url origin 2>/dev/null)" || repo_id=""
    if [ -n "${repo_id}" ]; then
        # A remote URL can embed a credential (https://user:token@host/...).
        # Strip the userinfo; scp-style git@host:path has no "://" and is kept.
        repo_id="$(printf '%s' "${repo_id}" | sed 's#^\([A-Za-z][A-Za-z0-9+.-]*://\)[^/@]*@#\1#')" || repo_id=""
    fi
    if [ -z "${repo_id}" ]; then
        repo_id="$(git -C "${proot:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || repo_id=""
    fi
    [ -n "${repo_id}" ] || repo_id="${repo}"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts=""

    # discovery_source is model-authored text. Record it only when it looks like
    # a rung name; anything else is reduced to a marker, never copied.
    case "${src}" in
        '') : ;;
        *[!a-z0-9:._-]*) src="other" ;;
    esac
    [ "${#src}" -le 64 ] || src="other"

    case "${material}" in true|false) : ;; *) material="null" ;; esac

    nonce="$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -dc 'a-f0-9')"
    [ -n "${nonce}" ] || nonce="$(date +%N 2>/dev/null | tr -dc '0-9')"
    rid="$(printf '%s|%s|%s|%s|%s' "${ts}" "$$" "${token}" "${action}" "${nonce}" \
        | { shasum -a 256 2>/dev/null || cksum; } | tr -dc 'a-f0-9' | cut -c1-16)"
    [ -n "${rid}" ] || return 0

    rec="$(jq -nc \
        --argjson sv "${VERIFY_SHADOW_SCHEMA_VERSION}" \
        --argjson pv "${VERIFY_SHADOW_PREDICATE_VERSION}" \
        --argjson wb "${wb}" --argjson mat "${material}" \
        --arg rid "$rid" --arg ts "$ts" --arg repo "$repo" --arg repo_id "$repo_id" \
        --arg branch "$branch" --arg head "$head" --arg token "$token" \
        --arg action "$action" --arg class "$class" --arg reason "$reason" \
        --arg src "$src" --arg tp "$tp" \
        '{schema_version:$sv, predicate_version:$pv, record_id:$rid,
          ts:$ts, repo:$repo, repo_id:$repo_id, branch:$branch, head_sha:$head,
          session_token:$token, action:$action,
          would_block:$wb, classification:$class, reason:$reason,
          discovery_source:$src, material_source:$mat,
          transcript_path:$tp}' 2>/dev/null)" || return 0
    [ -n "$rec" ] || return 0

    # No rotation, deliberately: it would drop records the decision rule has not
    # yet been read against. At the measured rate this log grows a few lines a
    # month.
    printf '%s\n' "$rec" >> "$log" 2>/dev/null || return 0
    chmod 600 "$log" 2>/dev/null || true
    return 0
}
