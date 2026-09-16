#!/bin/bash
# egress-consent.sh — single source for the cross-family egress consent contract.
#
# Sourced by hooks/egress-consent-ask-hook.sh, hooks/egress-consent-receipt-hook.sh and
# scripts/consult-dispatch.sh. The three MUST agree byte-for-byte on the digest and the
# state-file names: a digest that differs between the dispatcher and the receipt hook
# turns every approval into a refusal, and a path that differs turns it into a silent
# no-op. That is why nothing here may be re-derived at a call site.
#
# Design: openspec/changes/egress-consent-dispatcher/design.md
# Bash 3.2 compatible. Defines functions and constants only; sourcing has no side effect.

EGRESS_APPROVE_LABEL="Approve and send"
EGRESS_DECLINE_LABEL="Do not send"
EGRESS_RECEIPT_TTL=900

# egress_sha256 — stdin -> lowercase hex sha256. rc 1 when no hasher exists.
egress_sha256() {
    local _h=""
    if command -v shasum >/dev/null 2>&1; then
        _h="$(shasum -a 256 2>/dev/null)" || return 1
    elif command -v sha256sum >/dev/null 2>&1; then
        _h="$(sha256sum 2>/dev/null)" || return 1
    else
        return 1
    fi
    _h="${_h%% *}"
    [ -n "${_h}" ] || return 1
    printf '%s' "${_h}"
}

# egress_digest_stdin — THE canonical digest: sha256 over stdin with trailing newlines
# removed ($(cat) strips them) and nothing else normalised. Trailing newlines are what a
# model copying a file into a tool argument most often adds or drops, and they cannot
# change meaning; internal whitespace can (code, quotes, delimiters), so it is kept.
egress_digest_stdin() {
    local _c
    _c="$(cat)" || return 1
    printf '%s' "${_c}" | egress_sha256
}

egress_valid_digest() {
    case "${1:-}" in
        *[!0123456789abcdef]*|"") return 1 ;;
    esac
    [ "${#1}" -eq 64 ]
}

# Tool-use ids and tokens are embedded in file names whose fields are separated by '.',
# so '.' and '/' are both rejected.
egress_valid_id() {
    case "${1:-}" in
        ""|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    return 0
}

egress_valid_token() {
    case "${1:-}" in
        session-*) ;;
        *) return 1 ;;
    esac
    egress_valid_id "$1"
}

egress_ask_path()     { printf '%s/.claude/.skill-egress-ask-%s.%s' "${HOME}" "$1" "$2"; }
egress_receipt_path() { printf '%s/.claude/.skill-egress-receipt-%s.%s.%s' "${HOME}" "$1" "$2" "$3"; }
egress_pkg_path()     { printf '%s/.claude/.skill-egress-pkg-%s.%s' "${HOME}" "$1" "$2"; }
# A decline record for one package: holds the ask time of the latest declined consent
# question, so an approval whose ask is not newer can never be used — whatever order the
# harness delivers parallel answers in.
egress_veto_path()    { printf '%s/.claude/.skill-egress-veto-%s.%s' "${HOME}" "$1" "$2"; }

# egress_has_hidden_chars — stdin; rc 0 when it contains a C0 control character other
# than TAB and LF (ESC sequences can conceal text in a rendered preview; CR can overwrite
# a line). NUL is included.
egress_has_hidden_chars() {
    local _in
    _in="$(mktemp "${TMPDIR:-/tmp}/egress-cc.XXXXXX" 2>/dev/null)" || return 0
    cat > "${_in}"
    if LC_ALL=C tr -d '\000-\010\013-\037' < "${_in}" | cmp -s - "${_in}"; then
        rm -f "${_in}"; return 1
    fi
    rm -f "${_in}"; return 0
}

# egress_revoke_unused <token> [digest] — rename every unused receipt of this conversation
# (for one digest, or all digests when omitted) to .revoked. Prints "<revoked> <failed>".
# Renamed, never deleted, so the history stays auditable.
egress_revoke_unused() {
    local _r _ok=0 _bad=0 _pat
    if [ -n "${2:-}" ]; then
        _pat="$(egress_receipt_path "$1" "$2" "")"
    else
        _pat="${HOME}/.claude/.skill-egress-receipt-${1}."
    fi
    for _r in "${_pat}"*; do
        [ -f "${_r}" ] || continue
        case "${_r}" in *.consumed|*.revoked|*.tmp.*) continue ;; esac
        if mv "${_r}" "${_r}.revoked" 2>/dev/null; then _ok=$((_ok + 1)); else _bad=$((_bad + 1)); fi
    done
    printf '%s %s' "${_ok}" "${_bad}"
}

# egress_record_veto <token> <digest> <ask_ts> — keep the LATEST declined ask time.
egress_record_veto() {
    local _v _old=0
    _v="$(egress_veto_path "$1" "$2")"
    case "${3:-}" in ''|*[!0-9]*) return 1 ;; esac
    if [ -f "${_v}" ]; then
        _old="$(cat "${_v}" 2>/dev/null)"
        case "${_old}" in ''|*[!0-9]*) _old=0 ;; esac
    fi
    [ "$3" -gt "${_old}" ] || return 0
    printf '%s\n' "$3" | egress_write_atomic "${_v}"
}

# egress_veto_ts <token> <digest> — prints the latest declined ask time, or 0.
egress_veto_ts() {
    local _t
    _t="$(cat "$(egress_veto_path "$1" "$2")" 2>/dev/null)"
    case "${_t}" in ''|*[!0-9]*) _t=0 ;; esac
    printf '%s' "${_t}"
}

# egress_write_atomic <dest> — stdin -> <dest>, owner-only, via tmp + mv so a reader never
# sees a partial file. EMPTY input is a failure: callers pipe a jq document in, and a jq
# error must not leave a receipt-shaped empty file behind. rc non-zero on any failure (the
# temp file is removed).
egress_write_atomic() {
    local _dest="$1" _tmp="${1}.tmp.$$" _rc=0
    ( umask 077 && cat > "${_tmp}" ) || _rc=1
    [ "${_rc}" -eq 0 ] && [ ! -s "${_tmp}" ] && _rc=1
    if [ "${_rc}" -eq 0 ]; then
        mv -f "${_tmp}" "${_dest}" 2>/dev/null || _rc=1
    fi
    [ "${_rc}" -eq 0 ] || rm -f "${_tmp}" 2>/dev/null
    return "${_rc}"
}
