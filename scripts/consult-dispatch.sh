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
# The model's shell is zsh on macOS; this script is bash-only (unmatched globs are fatal in
# zsh). Re-exec rather than misbehave when someone runs `zsh consult-dispatch.sh`.
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi
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
    local _prov="$1" _file="$2" _tok _d _pkg _tmp
    if [ "${_prov}" != "codex" ]; then
        _err "unsupported provider '${_prov}' (supported: codex) — nothing was prepared. Ask the user how to proceed."
        exit 2
    fi
    if [ ! -f "${_file}" ] || [ ! -r "${_file}" ] || [ -z "$(cat "${_file}" 2>/dev/null)" ]; then
        _err "package file missing, unreadable, empty or blank: ${_file}"
        exit 2
    fi
    # NUL, and every C0 control other than TAB/LF: an ESC sequence can conceal text in a
    # rendered preview and a CR can overwrite a line, so the user would approve bytes they
    # could not see.
    if egress_has_hidden_chars < "${_file}"; then
        _err "package contains control characters (other than tab and newline) that could hide text from the user's preview."
        exit 2
    fi
    # A package the preview cannot carry byte-for-byte could never be approved; say so now
    # rather than looping on "paste it verbatim". Skipped when iconv is unavailable.
    if command -v iconv >/dev/null 2>&1 && ! iconv -f UTF-8 -t UTF-8 < "${_file}" > /dev/null 2>&1; then
        _err "package is not valid UTF-8, so it cannot be shown to the user verbatim."
        exit 2
    fi
    _tok="$(_own_token)" || _cannot "${_NO_IDENTITY}"
    # Freeze FIRST, then hash the frozen copy: the digest must describe the bytes that
    # will be sent, not a file the caller may still be writing.
    _tmp="${HOME}/.claude/.skill-egress-pkg-${_tok}.preparing.$$"
    egress_write_atomic "${_tmp}" < "${_file}" || _cannot "could not freeze the package under ${HOME}/.claude"
    _d="$(egress_digest_stdin < "${_tmp}")"
    if ! egress_valid_digest "${_d}"; then
        rm -f "${_tmp}"
        _cannot "could not hash the package (no shasum or sha256sum)"
    fi
    _pkg="$(egress_pkg_path "${_tok}" "${_d}")"
    mv -f "${_tmp}" "${_pkg}" 2>/dev/null || { rm -f "${_tmp}"; _cannot "could not freeze the package at ${_pkg}"; }
    cat <<EOF
digest: ${_d}
frozen package: ${_pkg}
  (this exact text is what will be sent; trailing newlines aside, nothing may differ)

Now ask the user with AskUserQuestion — exactly ONE question, single-select:
  question: "<one line: what is sent, to whom> [egress-consent:${_d}]"
  option 1: label "${EGRESS_DECLINE_LABEL}"   (no preview) — FIRST, so the default declines
  option 2: label "${EGRESS_APPROVE_LABEL}"  preview: the COMPLETE package text, verbatim
The marker goes in the question text only. Never pre-fill answers or annotations.
The preview must be the whole package; say in the question that Codex runs read-only
but its sandbox can still read other files on this machine.
Asking again about this package withdraws any earlier, unused approval of it.

After the user chooses "${EGRESS_APPROVE_LABEL}":
  bash "${_ROOT}/scripts/consult-dispatch.sh" send ${_d}
EOF
}

_ISO=""
_OUT=""
_KEEP_OUT=false
_cleanup() {
    [ -n "${_ISO}" ] && rm -rf "${_ISO}" 2>/dev/null
    [ "${_KEEP_OUT}" = "true" ] || { [ -n "${_OUT}" ] && rm -rf "${_OUT}" 2>/dev/null; }
    return 0
}
trap _cleanup EXIT

_send() {
    [ $# -ge 1 ] || _usage
    local _d="$1" _model="" _tok _pkg _copy _pd _grc _mode _v _now _r _ts _ask _veto _claimed="" _tmpd _rc
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --model) [ $# -ge 2 ] || _usage; _model="$2"; shift 2 ;;
            *) _usage ;;
        esac
    done
    egress_valid_digest "${_d}" || _usage
    case "${_model}" in
        -*|*[!A-Za-z0-9._-]*) _err "invalid model name: ${_model}"; exit 2 ;;
    esac

    command -v jq >/dev/null 2>&1 || _cannot "jq is unavailable, so approval receipts cannot be read" "Install jq, or run codex yourself outside the plugin."
    _tok="$(_own_token)" || _cannot "${_NO_IDENTITY}"
    _pkg="$(egress_pkg_path "${_tok}" "${_d}")"
    [ -f "${_pkg}" ] || _not_approved "no prepared package for digest ${_d} in this conversation (run prepare first)"
    command -v codex >/dev/null 2>&1 || { _err "codex CLI not found — nothing was sent. Ask the user how to proceed."; exit 2; }

    # Private working space BEFORE anything is claimed, so a failure here costs no approval.
    _tmpd="$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)" \
        || _cannot "the temporary directory ${TMPDIR:-/tmp} is not usable"
    _ISO="$(mktemp -d "${_tmpd}/consult-iso.XXXXXX" 2>/dev/null)" || _ISO=""
    _OUT="$(mktemp -d "${_tmpd}/consult-run.XXXXXX" 2>/dev/null)" || _OUT=""
    { [ -n "${_ISO}" ] && [ -n "${_OUT}" ] && chmod 0700 "${_ISO}" "${_OUT}"; } \
        || _cannot "could not create private scratch directories under ${_tmpd}"
    # Codex would load AGENTS.md and git context from an enclosing repository — content the
    # user never saw in the preview.
    if command -v git >/dev/null 2>&1 && git -C "${_ISO}" rev-parse --git-dir > /dev/null 2>&1; then
        _cannot "the isolated directory ${_ISO} is inside a git repository (TMPDIR=${_tmpd}); Codex would load that repository's context" "Point TMPDIR outside any repository."
    fi

    # Read the frozen package exactly ONCE. Everything after this point — digest check,
    # secret scan, send — uses the private copy, so nothing can change in between.
    _copy="${_OUT}/package"
    egress_write_atomic "${_copy}" < "${_pkg}" || _cannot "could not copy the frozen package"
    _pd="$(egress_digest_stdin < "${_copy}")"
    egress_valid_digest "${_pd}" || _cannot "could not hash the package (no shasum or sha256sum)"
    [ "${_pd}" = "${_d}" ] \
        || _cannot "the frozen package no longer matches its digest (it was modified after prepare)" "Prepare the package again; the user must approve the new one."

    if command -v gitleaks >/dev/null 2>&1; then
        # From the empty isolated directory, without config overrides, ignoring inline
        # `gitleaks:allow` comments and any .gitleaksignore: each of those would otherwise
        # let the package itself, the caller's tree, or the environment silence the scan.
        ( cd "${_ISO}" && env -u GITLEAKS_CONFIG -u GITLEAKS_CONFIG_TOML \
            gitleaks stdin --no-banner --redact --exit-code 3 --ignore-gitleaks-allow \
                --gitleaks-ignore-path "${_ISO}" < "${_copy}" > /dev/null 2>&1 )
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
        _veto="$(egress_veto_ts "${_tok}" "${_d}")"
        _now="$(date +%s 2>/dev/null)"
        case "${_now}" in ''|*[!0-9]*) _cannot "clock unavailable, so approval freshness cannot be checked" ;; esac
        for _r in "$(egress_receipt_path "${_tok}" "${_d}" "")"*; do
            [ -f "${_r}" ] || continue
            case "${_r}" in *.consumed|*.revoked|*.tmp.*) continue ;; esac
            read -r _ts _ask <<EOF
$(jq -r --arg d "${_d}" 'select(type == "object" and .digest == $d) | "\(.ts | numbers | floor) \(.ask_ts | numbers | floor)"' "${_r}" 2>/dev/null)
EOF
            case "${_ts}" in ''|*[!0-9]*) continue ;; esac
            case "${_ask:-}" in ''|*[!0-9]*) continue ;; esac
            # A decline of this package asked at the same time or later wins, whatever
            # order the harness delivered the answers in.
            [ "${_ask}" -gt "${_veto}" ] || continue
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

    # Everything Codex loads on its own is egress the preview never showed. Measured live
    # 2026-09-16: from an empty directory a plain `codex exec` still ran 18 user/plugin
    # hooks and started MCP servers. These flags removed both while still reaching the
    # model. A global ~/.codex/AGENTS.md is NOT known to be excluded (residual risk).
    _KEEP_OUT=true
    ( cd "${_ISO}" && codex exec -s read-only -C "${_ISO}" --skip-git-repo-check --ephemeral \
        --ignore-user-config --disable hooks --disable plugins --disable memories --disable apps \
        -o "${_OUT}/answer.md" ${_model:+-m "${_model}"} - ) < "${_copy}" > "${_OUT}/codex.log" 2>&1
    _rc=$?
    if [ "${_rc}" -eq 0 ] && [ -s "${_OUT}/answer.md" ]; then
        printf 'sent to codex (read-only, isolated working directory)\n'
        printf 'answer: %s\n' "${_OUT}/answer.md"
        printf 'run directory (session scratch; delete with: rm -rf %s)\n' "${_OUT}"
        exit 0
    fi
    _err "MAY HAVE SENT: codex exited ${_rc} without a complete answer; the package may already have left this machine. Log: ${_OUT}/codex.log. The approval was used; a retry needs the user's approval again."
    exit 5
}

case "${1:-}" in
    prepare) shift; _prepare "$@" ;;
    send) shift; _send "$@" ;;
    *) _usage ;;
esac
