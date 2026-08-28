#!/usr/bin/env bash
# record-review-verdict.sh — write the owned REVIEW verdict artifact (#197).
#
# Two providers, one schema:
#   --provider local-agent|human|agent-team-review   a review that ran here
#   --from-github <pr>                               import real PR reviews
#
# The artifact answers "did a review happen and did it pass", which the push
# gate's REVIEW status leg cannot: Skill(...) returns the instruction body, so
# the milestone is credited before any reviewer could have run.
#
# REFUSES to write an unbound clean verdict. A clean verdict with no reviewed
# subject is a claim about nothing, and would be indistinguishable from a real
# one to every reader. Without --base/--head (or a resolvable PR) the verdict
# is forced to could-not-review, which is honest and still records provenance.
#
# Bash 3.2. Read-only against git; the only write is the artifact itself.

set -u

_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || _ROOT=""
_HERE="$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd)"
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_HERE}/.." && pwd)}"

PROVIDER=""; VERDICT=""; BASE=""; HEAD_ARG=""; FINDINGS=""; UNRESOLVED=""
FROM_GH=""; DISPATCH_ATTEMPTED="false"; DISPATCH_SUCCEEDED="false"

_usage() {
    cat >&2 <<'EOF'
usage: record-review-verdict.sh --provider <p> --verdict <v> [--base SHA --head SHA]
                                [--findings N] [--unresolved-blocking N]
                                [--dispatch-attempted] [--dispatch-succeeded]
       record-review-verdict.sh --from-github <pr-number> [--provider github-import]

  --verdict   clean | findings-open | could-not-review
  --provider  local-agent | human | agent-team-review | github-import

A clean verdict REQUIRES --base and --head (or a resolvable PR); without a
reviewed subject the verdict is downgraded to could-not-review.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --provider)             PROVIDER="${2:-}"; shift 2 ;;
        --verdict)              VERDICT="${2:-}"; shift 2 ;;
        --base)                 BASE="${2:-}"; shift 2 ;;
        --head)                 HEAD_ARG="${2:-}"; shift 2 ;;
        --findings)             FINDINGS="${2:-}"; shift 2 ;;
        --unresolved-blocking)  UNRESOLVED="${2:-}"; shift 2 ;;
        --from-github)          FROM_GH="${2:-}"; shift 2 ;;
        --dispatch-attempted)   DISPATCH_ATTEMPTED="true"; shift ;;
        --dispatch-succeeded)   DISPATCH_SUCCEEDED="true"; shift ;;
        -h|--help)              _usage; exit 0 ;;
        *) echo "record-review-verdict: unknown argument '$1'" >&2; _usage; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "record-review-verdict: jq required" >&2; exit 2; }

# ---- token: own-session-first, never the bare singleton (issue #157) --------
if [ -n "${SKILL_SESSION_TOKEN:-}" ]; then
    TOKEN="${SKILL_SESSION_TOKEN}"
else
    TOKEN="$(. "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null && resolve_own_session_token 2>/dev/null)" || TOKEN=""
    [ -n "${TOKEN}" ] || TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
[ -n "${TOKEN}" ] || { echo "record-review-verdict: no session token resolved" >&2; exit 2; }

# ---- provider 2: import a real GitHub review -------------------------------
# The only forgery-resistant provider, and therefore never the default. Its
# ABSENCE must never be read as evidence of anything: no network, no PR, or a
# private repo all look identical here.
if [ -n "${FROM_GH}" ]; then
    case "${FROM_GH}" in
        ''|*[!0-9]*) echo "record-review-verdict: --from-github takes a bare PR number" >&2; exit 2 ;;
    esac
    PROVIDER="${PROVIDER:-github-import}"
    _GH="$(gh pr view "${FROM_GH}" --json reviews,headRefOid,baseRefOid 2>/dev/null)" || _GH=""
    if [ -z "${_GH}" ]; then
        echo "record-review-verdict: could not read PR #${FROM_GH} (no network, no gh, or no such PR)" >&2
        VERDICT="could-not-review"
    else
        DISPATCH_ATTEMPTED="true"; DISPATCH_SUCCEEDED="true"
        [ -n "${HEAD_ARG}" ] || HEAD_ARG="$(printf '%s' "${_GH}" | jq -r '.headRefOid // empty' 2>/dev/null)"
        [ -n "${BASE}" ]     || BASE="$(printf '%s' "${_GH}" | jq -r '.baseRefOid // empty' 2>/dev/null)"
        _APPROVED="$(printf '%s' "${_GH}" | jq '[.reviews[]? | select(.state=="APPROVED")] | length' 2>/dev/null)"
        _BLOCKING="$(printf '%s' "${_GH}" | jq '[.reviews[]? | select(.state=="CHANGES_REQUESTED")] | length' 2>/dev/null)"
        _TOTAL="$(printf '%s' "${_GH}" | jq '[.reviews[]?] | length' 2>/dev/null)"
        [ -n "${FINDINGS}" ]   || FINDINGS="${_TOTAL:-0}"
        [ -n "${UNRESOLVED}" ] || UNRESOLVED="${_BLOCKING:-0}"
        if [ -z "${VERDICT}" ]; then
            if [ "${_BLOCKING:-0}" -gt 0 ] 2>/dev/null; then VERDICT="findings-open"
            elif [ "${_APPROVED:-0}" -gt 0 ] 2>/dev/null; then VERDICT="clean"
            else VERDICT="could-not-review"; fi
        fi
    fi
fi

[ -n "${PROVIDER}" ] || { echo "record-review-verdict: --provider is required" >&2; _usage; exit 2; }
case "${PROVIDER}" in
    local-agent|human|agent-team-review|github-import) ;;
    *) echo "record-review-verdict: unknown provider '${PROVIDER}'" >&2; exit 2 ;;
esac
case "${VERDICT}" in
    clean|findings-open|could-not-review) ;;
    *) echo "record-review-verdict: --verdict must be clean|findings-open|could-not-review" >&2; exit 2 ;;
esac

# Dispatch telemetry provenance (spec: observed-dispatch-telemetry).
# The --from-github path above already derived these from a real PR; mark it.
# Otherwise prefer an OBSERVED reviewer-subagent return over the caller's
# flags: if the caller asserts a dispatch that was never observed, the
# artifact must say `asserted`, because that disagreement is the signal.
# Absence records as "not observed", never as an observed negative (D3).
DISPATCH_EVIDENCE="asserted"
# Gated on the PR having actually RESOLVED (_GH non-empty, set at the
# `gh pr view` call above), not on DISPATCH_ATTEMPTED — that flag is also
# `true` when the CALLER passed --dispatch-attempted, so gating on it alone
# would label a pure assertion "imported" for an unresolvable PR (no network,
# no gh, wrong number, private repo): the spec's binding rule is `imported`
# only for a resolvable PR. `${_GH:-}` is required: _GH is only assigned
# inside the `--from-github` branch above, and this file runs under `set -u`.
if [ -n "${FROM_GH}" ] && [ -n "${_GH:-}" ]; then
    DISPATCH_EVIDENCE="imported"
else
    _ODT_OK=false
    # D4: this read MUST resolve the branch-ledger key the same way
    # hooks/reviewer-evidence-hook.sh's write does. branch_ledger_key hashes
    # the RAW path string AND branch name, so a non-canonical path on either
    # side yields a different directory and this read silently misses. Both
    # currently derive the path half from `git rev-parse --show-toplevel`
    # with no proj_root arg. Give one side an explicit root and you must give
    # it to the other.
    #
    # The branch half is derived from THIS script's own cwd, same as the
    # hook derives it from the dispatching session's cwd — running this
    # script from a different worktree than the one the reviewer was
    # dispatched from (the repo's own using-git-worktrees pattern) resolves a
    # different branch and this read misses even when the repo is identical.
    # Safe (falls through to "asserted", D3), just usually the case in that
    # workflow. See design.md Trade-offs.
    . "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null && command -v branch_ledger_has >/dev/null 2>&1 && _ODT_OK=true || true
    if [ "${_ODT_OK}" = "true" ] && branch_ledger_has "reviewer-ran" 2>/dev/null; then
        DISPATCH_ATTEMPTED="true"; DISPATCH_SUCCEEDED="true"
        DISPATCH_EVIDENCE="observed"
    fi
fi

# ---- resolve + validate the reviewed subject -------------------------------
[ -n "${HEAD_ARG}" ] || HEAD_ARG="$(git -C "${_ROOT:-.}" rev-parse HEAD 2>/dev/null)" || HEAD_ARG=""
_resolve() { git -C "${_ROOT:-.}" rev-parse --verify "${1}^{commit}" 2>/dev/null; }
_B="$( [ -n "${BASE}" ] && _resolve "${BASE}" )" || _B=""
_H="$( [ -n "${HEAD_ARG}" ] && _resolve "${HEAD_ARG}" )" || _H=""

# THE REFUSAL. An unbound clean verdict is a claim about nothing and is
# indistinguishable from a real one downstream, so it is downgraded rather than
# rejected outright — a recorded could-not-review still carries provenance and
# still tells the gate a provider ran, which silence would not.
if [ "${VERDICT}" = "clean" ] && { [ -z "${_B}" ] || [ -z "${_H}" ]; }; then
    echo "record-review-verdict: refusing a clean verdict with no reviewed subject (need --base and --head); recording could-not-review instead" >&2
    VERDICT="could-not-review"
fi

DIGEST=""
if [ -n "${_B}" ] && [ -n "${_H}" ]; then
    # shellcheck disable=SC1090
    . "${_PLUGIN_ROOT}/hooks/lib/review-verdict.sh" 2>/dev/null || true
    if command -v review_verdict_subject_digest >/dev/null 2>&1; then
        DIGEST="$(review_verdict_subject_digest "${_ROOT}" "${_B}" "${_H}" 2>/dev/null)" || DIGEST=""
    fi
fi
FILE_COUNT=0
if [ -n "${_B}" ] && [ -n "${_H}" ]; then
    FILE_COUNT="$(git -C "${_ROOT:-.}" diff --name-only "${_B}" "${_H}" 2>/dev/null | grep -c . 2>/dev/null)" || FILE_COUNT=0
fi

# Numeric hygiene: a non-numeric arg must not reach the artifact, where the
# reader's `tonumber? // 1` would silently read it as "blocking".
case "${FINDINGS:-0}"   in ''|*[!0-9]*) FINDINGS=0 ;;   esac
case "${UNRESOLVED:-0}" in ''|*[!0-9]*) UNRESOLVED=0 ;; esac

OUT="${HOME}/.claude/.skill-review-verdict-${TOKEN}"
mkdir -p "${HOME}/.claude" 2>/dev/null || true
TMP="$(mktemp "${OUT}.XXXXXX")" || { echo "record-review-verdict: cannot write ${OUT}" >&2; exit 2; }

jq -nc \
    --arg provider "${PROVIDER}" \
    --arg base "${_B}" --arg head "${_H}" \
    --arg digest "${DIGEST}" --arg verdict "${VERDICT}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson fc "${FILE_COUNT:-0}" \
    --argjson ft "${FINDINGS:-0}" \
    --argjson ub "${UNRESOLVED:-0}" \
    --argjson da "${DISPATCH_ATTEMPTED}" \
    --argjson ds "${DISPATCH_SUCCEEDED}" \
    --arg de "${DISPATCH_EVIDENCE}" \
    '{schema_version:2, provider:$provider,
      reviewed_base_sha:$base, reviewed_head_sha:$head,
      changed_file_digest:$digest, changed_file_count:$fc,
      findings_total:$ft, unresolved_blocking:$ub, verdict:$verdict,
      dispatch_attempted:$da, dispatch_succeeded:$ds, dispatch_evidence:$de,
      ts:$ts, writer:"record-review-verdict.sh"}' > "${TMP}" 2>/dev/null \
  || { rm -f "${TMP}"; echo "record-review-verdict: failed to build the record" >&2; exit 2; }

mv -f "${TMP}" "${OUT}" 2>/dev/null || { rm -f "${TMP}"; exit 2; }
echo "review verdict written: ${OUT}"
jq -c '{provider,verdict,reviewed_head_sha,changed_file_count,unresolved_blocking}' "${OUT}" 2>/dev/null
