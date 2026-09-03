#!/bin/bash
# test-zero-match-log-perms.sh — the zero-match diagnostic log holds RAW PROMPT
# TEXT (truncated to 200 chars), so it must be 0600 like every other local
# diagnostic corpus. `.push-gate-invocation-log` stores only a command SHA and
# is already secured (scripts/push-gate-capture.sh); this file stores the more
# sensitive content and was world-readable (0644) until this test existed.
#
# The prompt text is deliberately NOT hashed: it IS the diagnostic value — the
# log exists so an author can see which prompts matched no trigger and write a
# trigger for them. Hashing would leave an unusable log. Securing the file is
# the fix; redacting it is not.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
_TMP="$(mktemp -d)"
trap 'rm -rf "${_TMP}"' EXIT

_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

# MUTATION NOTE (measured, do not assume otherwise): deleting the WRITE-PATH
# `umask 077` + chmod leaves every cell below GREEN, because the post-rotation
# chmod runs on every invocation and tightens the file before this test can
# observe it. Cells (1) and (2) are therefore satisfied by EITHER mechanism and
# pin neither on its own; only cell (4) pins the rotation chmod (mutation-
# verified: removing it fails cell 4 alone).
#
# The write-path securing is still correct and must not be deleted as "dead".
# In the FIXED code the chmod PRECEDES the append, so no prompt text is ever
# written to a 0644 file. Remove that chmod and the append lands on a
# pre-existing 0644 log first, leaking that record, with only the later
# post-rotation chmod tightening it afterwards. It is a pre-write ORDERING
# property, not a final state.
# That window is what scripts/push-gate-capture.sh's "secure BEFORE the first
# content write" comment exists to close. It is not observable from outside the
# hook, so no assertion here covers it — that is a known gap, not an oversight.

# A prompt that matches no trigger, so the zero-match writer runs.
_ZM_PROMPT='xyzzy plugh frobnicate qwertyuiop'

# --- (1) fresh log is created 0600 -----------------------------------------
export HOME="${_TMP}/h1"; mkdir -p "${HOME}/.claude"
cp "${PROJECT_ROOT}/config/fallback-registry.json" "${HOME}/.claude/.skill-registry-cache.json" 2>/dev/null
printf '%s' "$(jq -nc --arg p "${_ZM_PROMPT}" '{"prompt":$p}')" \
  | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" >/dev/null 2>&1
_LOG="${HOME}/.claude/.skill-zero-match-log"
assert_file_exists "zero-match log is written for an unmatched prompt" "${_LOG}"
assert_equals "fresh zero-match log is mode 0600" "600" "$(_mode "${_LOG}")"

# --- (2) a PRE-EXISTING 0644 log is tightened before the next append --------
# This is the leak that matters: an already-loose file keeps leaking every new
# prompt appended to it. umask alone does not fix an existing file.
export HOME="${_TMP}/h2"; mkdir -p "${HOME}/.claude"
cp "${PROJECT_ROOT}/config/fallback-registry.json" "${HOME}/.claude/.skill-registry-cache.json" 2>/dev/null
_LOG2="${HOME}/.claude/.skill-zero-match-log"
printf 'pre-existing loose line\n' > "${_LOG2}"
chmod 0644 "${_LOG2}"
assert_equals "control: log starts 0644" "644" "$(_mode "${_LOG2}")"
printf '%s' "$(jq -nc --arg p "${_ZM_PROMPT}" '{"prompt":$p}')" \
  | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" >/dev/null 2>&1
assert_equals "pre-existing 0644 log is tightened to 0600" "600" "$(_mode "${_LOG2}")"

# --- (3) the prompt text is still recorded (the fix must not redact) --------
assert_contains "prompt text is still logged (diagnostic value preserved)" \
  "frobnicate" "$(cat "${_LOG2}" 2>/dev/null)"

# --- (4) ROTATION must not reset the mode -----------------------------------
# Rotation is `tail > $LOG.tmp; mv $LOG.tmp $LOG`. The .tmp file is created
# fresh under the AMBIENT umask, and mv carries its mode onto the log — so a
# log secured at write time silently reverts to 0644 on the next rotation.
# Securing only the write path is an incomplete fix.
export HOME="${_TMP}/h3"; mkdir -p "${HOME}/.claude"
cp "${PROJECT_ROOT}/config/fallback-registry.json" "${HOME}/.claude/.skill-registry-cache.json" 2>/dev/null
_LOG3="${HOME}/.claude/.skill-zero-match-log"
# 150 lines forces the >100 line-count rotation on the next append
_i=0; : > "${_LOG3}"
while [ "${_i}" -lt 150 ]; do printf 'filler line %s\n' "${_i}" >> "${_LOG3}"; _i=$((_i+1)); done
chmod 0600 "${_LOG3}"
assert_equals "control: log starts 0600 with 150 lines" "600" "$(_mode "${_LOG3}")"
printf '%s' "$(jq -nc --arg p "${_ZM_PROMPT}" '{"prompt":$p}')" \
  | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" >/dev/null 2>&1
_lines3="$(wc -l < "${_LOG3}" 2>/dev/null | tr -d ' ')"
assert_equals "control: rotation actually ran (trimmed to 100)" "100" "${_lines3}"
assert_equals "log is still 0600 AFTER rotation" "600" "$(_mode "${_LOG3}")"

# --- (5) STRUCTURAL: the rotation .tmp is created under umask 077 -----------
# The .tmp holds the same raw prompt text as the log and exists only between
# `tail >` and `mv`, so its mode cannot be sampled at rest from here. This is a
# source-shape assertion, weaker than the behavioural cells above, and labelled
# as such: it pins that the umask wrapper was not dropped, nothing more. BOTH
# rotation branches must be wrapped -- checking one would pass while the other
# leaked.
_wrapped="$(grep -c 'umask 077; tail -n .* > "${_ZM_LOG}.tmp"' "${HOOK}" 2>/dev/null)"
assert_equals "both rotation .tmp writes are umask-077 wrapped (structural)" "2" "${_wrapped}"

print_summary
exit $?
