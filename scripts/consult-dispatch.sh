#!/bin/bash
# consult-dispatch.sh — the ONLY sender panel and second-opinion may use for cross-family
# content. It refuses to send unless the user approved this exact package.
#
#   consult-dispatch.sh prepare <provider> <package-file>
#       Freeze the package and print its digest plus the exact AskUserQuestion to use.
#   consult-dispatch.sh send <digest> [--model <name>]
#       Send the frozen package read-only, if and only if a fresh, unused approval receipt
#       for <digest> exists in this conversation (written by
#       hooks/egress-consent-receipt-hook.sh from the user's answer).
#
# Exit codes: 0 sent · 2 usage/unsupported · 3 CANNOT VERIFY · 4 NOT APPROVED ·
#             5 MAY HAVE SENT · 6 secret-scan findings
#
# Refuses when it cannot verify — a deliberate, argued exception to this repo's
# fail-open convention (#198): the question here is authorisation, the scope is only this
# consultation, and the action is optional. The escape hatch is the announced
# `consultation.egress_consent: "warn"` setting in ~/.claude/skill-config.json.
# There is intentionally NO environment override for the codex or gitleaks binaries:
# one that changes what runs, or skips the scan, would itself be a bypass.
#
# Receipts are agent-writable files: this stops a model that SKIPS the ask, not one that
# forges a receipt. Design: openspec/changes/egress-consent-dispatcher/design.md
set -u

_err() { printf 'consult-dispatch: %s\n' "$*" >&2; }
_usage() {
    _err "usage: consult-dispatch.sh prepare <provider> <package-file>"
    _err "       consult-dispatch.sh send <digest> [--model <name>]"
    exit 2
}
_cannot() {
    _err "CANNOT VERIFY: $1 — nothing was sent. This is not a missing approval: asking the user again will not help.${2:+ $2}"
    exit 3
}
_not_approved() {
    _err "NOT APPROVED: $1 — nothing was sent."
    exit 4
}

_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "${_ROOT}" ]; then
    _ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || _ROOT=""
fi
# shellcheck source=/dev/null
if ! { . "${_ROOT}/hooks/lib/egress-consent.sh" 2>/dev/null \
        && command -v egress_digest_stdin >/dev/null 2>&1 \
        && . "${_ROOT}/hooks/lib/session-token.sh" 2>/dev/null \
        && command -v resolve_own_session_token_strict >/dev/null 2>&1; }; then
    _cannot "consent libraries not loadable under ${_ROOT:-<no plugin root>}"
fi

_own_token() {
    local _t
    _t="$(resolve_own_session_token_strict)" && egress_valid_token "${_t}" && { printf '%s' "${_t}"; return 0; }
    return 1
}
_NO_IDENTITY="no session identity for this conversation (CLAUDE_CODE_SESSION_ID is unset or has no transcript); the shared session token is never used here because it can name another conversation's approval"

_prepare() {
    [ $# -eq 2 ] || _usage
    local _prov="$1" _file="$2" _tok _d _pkg
    if [ "${_prov}" != "codex" ]; then
        _err "unsupported provider '${_prov}' (supported: codex) — nothing was prepared. Ask the user how to proceed."
        exit 2
    fi
    if [ ! -f "${_file}" ] || [ ! -r "${_file}" ] || [ ! -s "${_file}" ]; then
        _err "package file missing, unreadable or empty: ${_file}"
        exit 2
    fi
    if ! LC_ALL=C tr -d '\000' < "${_file}" | cmp -s - "${_file}"; then
        _err "package contains NUL bytes; only text packages can be shown to the user and sent."
        exit 2
    fi
    _tok="$(_own_token)" || _cannot "${_NO_IDENTITY}"
    _d="$(egress_digest_stdin < "${_file}")"
    egress_valid_digest "${_d}" || _cannot "could not hash the package (no shasum or sha256sum)"
    _pkg="$(egress_pkg_path "${_tok}" "${_d}")"
    egress_write_atomic "${_pkg}" < "${_file}" || _cannot "could not freeze the package at ${_pkg}"
    cat <<EOF
digest: ${_d}
frozen package: ${_pkg}
  (this exact text is what will be sent; trailing newlines aside, nothing may differ)

Now ask the user with AskUserQuestion — exactly ONE question, single-select:
  question: "<one line: what is sent, to whom> [egress-consent:${_d}]"
  option 1: label "${EGRESS_APPROVE_LABEL}"  preview: the COMPLETE package text, verbatim
  option 2: label "${EGRESS_DECLINE_LABEL}"   (no preview)
The marker goes in the question text only. Never pre-fill answers or annotations.
The preview must be the whole package; say in the question that Codex runs read-only
but its sandbox can still read other files on this machine.

After the user chooses "${EGRESS_APPROVE_LABEL}":
  bash "${_ROOT}/scripts/consult-dispatch.sh" send ${_d}
EOF
}

_send() {
    [ $# -ge 1 ] || _usage
    local _d="$1" _model="" _tok _pkg _grc _mode _v _now _r _ts _claimed="" _tmpd _iso _out _rc
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --model) [ $# -ge 2 ] || _usage; _model="$2"; shift 2 ;;
            *) _usage ;;
        esac
    done
    egress_valid_digest "${_d}" || _usage
    case "${_model}" in
        *[!A-Za-z0-9._-]*) _err "invalid model name: ${_model}"; exit 2 ;;
    esac

    command -v jq >/dev/null 2>&1 || _cannot "jq is unavailable, so approval receipts cannot be read" "Install jq, or run codex yourself outside the plugin."
    _tok="$(_own_token)" || _cannot "${_NO_IDENTITY}"
    _pkg="$(egress_pkg_path "${_tok}" "${_d}")"
    [ -f "${_pkg}" ] || _not_approved "no prepared package for digest ${_d} in this conversation (run prepare first)"
    [ "$(egress_digest_stdin < "${_pkg}")" = "${_d}" ] \
        || _cannot "the frozen package no longer matches its digest (it was modified after prepare)" "Prepare the package again; the user must approve the new one."
    command -v codex >/dev/null 2>&1 || { _err "codex CLI not found — nothing was sent. Ask the user how to proceed."; exit 2; }

    if command -v gitleaks >/dev/null 2>&1; then
        gitleaks stdin --no-banner --redact --exit-code 3 < "${_pkg}" > /dev/null 2>&1
        _grc=$?
        case "${_grc}" in
            0) ;;
            3) _err "SECRET SCAN FINDINGS: gitleaks flagged the package — nothing was sent and the approval was not used. Remove the secret, prepare again, and ask the user again."
               exit 6 ;;
            *) _cannot "gitleaks failed to run (exit ${_grc})" ;;
        esac
    else
        _err "note: gitleaks is not installed — this package was NOT secret-scanned."
    fi

    _mode="enforce"
    if [ -f "${HOME}/.claude/skill-config.json" ]; then
        _v="$(jq -r '.consultation.egress_consent // "enforce"' "${HOME}/.claude/skill-config.json" 2>/dev/null)"
        [ "${_v}" = "warn" ] && _mode="warn"
    fi

    if [ "${_mode}" = "warn" ]; then
        _err "consent enforcement is OFF (egress_consent=warn in ~/.claude/skill-config.json) — sending WITHOUT checking for the user's approval."
    else
        _now="$(date +%s 2>/dev/null)"
        case "${_now}" in ''|*[!0-9]*) _cannot "clock unavailable, so approval freshness cannot be checked" ;; esac
        for _r in "${HOME}/.claude/.skill-egress-receipt-${_tok}.${_d}."*; do
            [ -f "${_r}" ] || continue
            case "${_r}" in *.consumed|*.tmp.*) continue ;; esac
            _ts="$(jq -r --arg d "${_d}" 'select(type == "object" and .digest == $d) | .ts | numbers | floor' "${_r}" 2>/dev/null)"
            case "${_ts}" in ''|*[!0-9]*) continue ;; esac
            [ $(( _now - _ts )) -le "${EGRESS_RECEIPT_TTL}" ] || continue
            [ $(( _ts - _now )) -le 60 ] || continue
            # Only a successful rename authorises a send: two concurrent sends cannot
            # both claim one approval.
            if mv "${_r}" "${_r}.consumed" 2>/dev/null; then
                _claimed="${_r}"
                break
            fi
        done
        [ -n "${_claimed}" ] || _not_approved "no fresh, unused approval for digest ${_d}. Approvals come only from the user's answer to the consent question, expire after 15 minutes, and authorise one send. Ask the user again with the consent question from 'prepare'"
    fi

    _tmpd="${TMPDIR:-/tmp}"; _tmpd="${_tmpd%/}"
    _iso="$(mktemp -d "${_tmpd}/consult-iso.XXXXXX")" && _out="$(mktemp -d "${_tmpd}/consult-run.XXXXXX")" \
        || { _err "MAY HAVE SENT: no — but the approval was already used and a scratch directory could not be created. Ask the user again."; exit 5; }
    chmod 0700 "${_iso}" "${_out}"
    ( cd "${_iso}" && codex exec -s read-only -C "${_iso}" --skip-git-repo-check --ephemeral \
        -o "${_out}/answer.md" ${_model:+-m "${_model}"} - ) < "${_pkg}" > "${_out}/codex.log" 2>&1
    _rc=$?
    rmdir "${_iso}" 2>/dev/null
    if [ "${_rc}" -eq 0 ] && [ -s "${_out}/answer.md" ]; then
        printf 'sent to codex (read-only, isolated working directory)\n'
        printf 'answer: %s\n' "${_out}/answer.md"
        printf 'run directory (session scratch; delete with: rm -rf %s)\n' "${_out}"
        exit 0
    fi
    _err "MAY HAVE SENT: codex exited ${_rc} without a complete answer; the package may already have left this machine. Log: ${_out}/codex.log. The approval was used; a retry needs the user's approval again."
    exit 5
}

case "${1:-}" in
    prepare) shift; _prepare "$@" ;;
    send) shift; _send "$@" ;;
    *) _usage ;;
esac
