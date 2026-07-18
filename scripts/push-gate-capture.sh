#!/bin/bash
# push-gate-capture.sh — diagnostic subprocess for the push gate (issue #127).
# Invoked ONLY from openspec-guard.sh's EXIT trap, in a fully-redirected
# subshell. Writes ONE compact JSONL record per push/merge invocation to
# ~/.claude/.push-gate-invocation-log. Fail-open, diagnostic-only. NEVER runs
# on the guard's decision path (subprocess at EXIT). All input via PGC_* env.
# Bash 3.2 compatible.
#
# Accepted ceilings (diagnostic-only, fail-open):
#  - Concurrent sessions share ~/.claude; a very large deny record (> PIPE_BUF,
#    4096 on macOS) appended by two sessions at once could interleave. Records
#    are kept small (replay reduced to a decision LABEL, mirror capped) to stay
#    under PIPE_BUF in the common case.
#  - Payload arrives via env vars; a pathological multi-MB command could exceed
#    ARG_MAX and fail the subprocess before it can log — acceptable (fail-open).
set -u

command -v jq >/dev/null 2>&1 || exit 0   # jq-gated: diagnostic only

_dir="${HOME}/.claude"
LOG="${_dir}/.push-gate-invocation-log"
[ -d "${_dir}" ] || mkdir -p "${_dir}" 2>/dev/null || exit 0

_decision="${PGC_DECISION:-allow}"
_action="${PGC_ACTION:-unknown}"
_command="${PGC_COMMAND:-}"
_transcript="${PGC_TRANSCRIPT:-}"
_token="${PGC_SESSION_TOKEN:-}"
_guard="${PGC_GUARD_PATH:-}"
_proot="${PGC_PLUGIN_ROOT:-}"
_input="${PGC_INPUT:-}"
_err=""

# Command metadata only — the raw command is NEVER logged by default. Shell
# command text cannot be robustly de-secreted (inline `-c http.extraHeader=…`,
# quoted `TOKEN="Bearer x"` suffixes, etc.), so the safe-by-default record
# carries a hash, a length, and a coarse subcommand LABEL. Full text is opt-in
# via PUSH_GATE_CAPTURE_FULL_CMD=1 and even then best-effort redacted (the
# redaction is a documented ceiling, NOT secret-proof).
_clen="${#_command}"
_csha="$(printf '%s' "${_command}" | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | cut -d' ' -f1)" || _csha=""
# subcommand label: drop leading VAR=val env prefixes, keep the first two words
# (e.g. "git push", "gh pr"). Args/values (where secrets live) are dropped.
_label="$(printf '%s' "${_command}" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* )+//' | cut -d' ' -f1-2)" || _label=""
_cmdfull=""
if [ "${PUSH_GATE_CAPTURE_FULL_CMD:-}" = "1" ]; then
  # best-effort only (documented ceiling — NOT secret-proof; that's why full
  # text is opt-in). Rules: env prefixes; URL userinfo; and any quoted string
  # containing a credential keyword (covers `-c http.extraHeader="Authorization:
  # Bearer X"` and similar inline-header secrets).
  _cmdfull="$(printf '%s' "${_command}" \
    | sed -E 's/(^| )[A-Za-z_][A-Za-z0-9_]*=[^ ]*/\1<redacted-env>/g; s#://[^/@ ]*@#://<redacted>@#g; s/"[^"]*([Bb]earer|[Aa]uthorization|[Tt]oken|[Aa]pi[_-]?[Kk]ey|[Pp]assword)[^"]*"/"<redacted>"/g; s/([Aa]uthorization|[Bb]earer|[Tt]oken|[Aa]pi[_-]?[Kk]ey|[Pp]assword)([=:] ?)[^ "]+/\1\2<redacted>/g')" || _cmdfull=""
fi

# drift evidence: which file ran + its cksum + plugin version
_cksum=""
if [ -n "${_guard}" ] && [ -f "${_guard}" ]; then
  _cksum="$(cksum "${_guard}" 2>/dev/null)"
  [ -z "${_cksum}" ] && _err="cksum_failed"
fi
_ver=""
[ -n "${_proot}" ] && [ -f "${_proot}/.claude-plugin/plugin.json" ] && \
  _ver="$(jq -r '.version // empty' "${_proot}/.claude-plugin/plugin.json" 2>/dev/null)"

# On deny only: true on-disk replay + gate-status mirror. The replayed guard is
# itself fail-open (`trap 'exit 0' ERR`), so exit code and empty stdout do NOT
# distinguish "genuine allow" from "crashed / exited early before the push
# block". The guard prints a __PGC_EVALUATED__ sentinel (under
# PUSH_GATE_CAPTURE_REPLAY=1) when it reaches the push-decision point, so we
# classify POSITIVELY: deny / allow / incomplete.
_replay_decision=""; _replay_stderr=""; _replay_len=0; _mirror=""
case "${_decision}" in
  deny*)
    if [ -n "${_guard}" ] && [ -f "${_guard}" ]; then
      _rerr="${_dir}/.pgc-replay-stderr.$$"
      _rout="$(PUSH_GATE_CAPTURE_DISABLE=1 PUSH_GATE_CAPTURE_REPLAY=1 CLAUDE_PLUGIN_ROOT="${_proot}" bash "${_guard}" <<<"${_input}" 2>"${_rerr}")"
      _replay_len="${#_rout}"
      _replay_stderr="$(cut -c1-1000 < "${_rerr}" 2>/dev/null | tr '\n' ' ')"; rm -f "${_rerr}" 2>/dev/null
      case "${_rout}" in
        *'"permissionDecision":"deny"'*) _replay_decision="deny" ;;
        *__PGC_EVALUATED__*)             _replay_decision="allow" ;;
        *) _replay_decision="incomplete"; _err="${_err}${_err:+;}replay_incomplete" ;;
      esac
    else
      _replay_decision="no_guard"; _err="${_err}${_err:+;}replay_no_guard"
    fi
    if [ -n "${_proot}" ] && [ -f "${_proot}/scripts/gate-status.sh" ]; then
      # gate-status.sh may exit non-zero to SIGNAL status, not failure — so
      # trust its output and only flag when it produced nothing.
      _mirror="$(bash "${_proot}/scripts/gate-status.sh" 2>&1 | cut -c1-2000)"
      [ -z "${_mirror}" ] && _err="${_err}${_err:+;}mirror_empty"
    fi
    ;;
esac

case "${_clen}" in ''|*[!0-9]*) _clen=0 ;; esac
case "${_replay_len}" in ''|*[!0-9]*) _replay_len=0 ;; esac

# Secure the log BEFORE the first content write: a pre-existing 0644 log would
# otherwise leak its first appended record. umask handles a fresh file; the
# explicit touch+chmod fixes a pre-existing looser-mode file.
umask 077
: >> "${LOG}" 2>/dev/null || exit 0
chmod 0600 "${LOG}" 2>/dev/null || true

_line="$(jq -cn \
  --arg decision "${_decision}" --arg action "${_action}" \
  --arg guard "${_guard}" --arg cksum "${_cksum}" --arg ver "${_ver}" \
  --arg token "${_token}" --arg csha "${_csha}" --argjson clen "${_clen}" \
  --arg label "${_label}" --arg cmd "${_cmdfull}" \
  --arg transcript "${_transcript}" \
  --arg rdec "${_replay_decision}" --argjson rlen "${_replay_len}" \
  --arg rstderr "${_replay_stderr}" --arg mirror "${_mirror}" \
  --arg err "${_err}" --argjson pid "$$" \
  '{event:"exit",pid:$pid,action:$action,decision:$decision,
    guard_path:$guard,guard_cksum:$cksum,plugin_version:$ver,
    session_token:$token,command_sha:$csha,command_len:$clen,
    command_label:$label,command:$cmd,transcript_path:$transcript,
    ondisk_replay_decision:$rdec,replay_stdout_len:$rlen,
    replay_stderr:$rstderr,gate_status_mirror:$mirror,
    capture_error:(if $err=="" then null else $err end)}')" || exit 0

printf '%s\n' "${_line}" >> "${LOG}" 2>/dev/null || exit 0

# rotate: keep last 500 if the log exceeds 1000 lines
_n="$(wc -l < "${LOG}" 2>/dev/null | tr -d ' ')"
case "${_n}" in ''|*[!0-9]*) _n=0 ;; esac
if [ "${_n}" -gt 1000 ]; then
  tail -n 500 "${LOG}" > "${LOG}.tmp" 2>/dev/null && mv "${LOG}.tmp" "${LOG}" 2>/dev/null || true
  chmod 0600 "${LOG}" 2>/dev/null || true
fi
exit 0
