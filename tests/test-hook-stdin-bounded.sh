#!/usr/bin/env bash
# tests/test-hook-stdin-bounded.sh — #188
#
# A TTY CHECK IS NOT AN INPUT-AVAILABLE CHECK. A socket or FIFO is not a TTY, so
# `[ ! -t 0 ]` passes and an unbounded `cat` waits for an EOF that never
# arrives. Measured against session-start-hook.sh before the fix: it hangs
# indefinitely on a never-EOF FIFO. skill-activation-hook.sh and
# skill-completion-hook.sh read stdin with no guard at all, so they shared it.
#
# The failure is silent — it reads as "slow", not as a fault. The original #142
# report idled a full suite run about two hours before anyone looked.
#
# THE RED CONTROL IS IN THIS FILE, not just in the commit message. Each hook is
# run through a HARNESS whose blocking behaviour is proven by a deliberately
# unbounded reader in the same harness: if that control ever stops hanging, the
# harness has stopped testing what it claims and every cell below is vacuous.
#
# macOS has no `timeout(1)`, so the watchdog is inline (Bash 3.2).
#
# COZEMPIC IS STUBBED (#369). session-start-hook.sh runs `cozempic init` when it
# is on PATH, and on a fresh HOME — which every cell here uses — a real install
# measured 23 s (its first-run update check) against the 8 s watchdog, so the
# session-start cell read 'hung' on any machine with cozempic and passed on CI,
# which has none. Every hook run gets a stub first on PATH; the slow-stub cell
# below is the one that measures what a slow cozempic does to the hook.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

_STUBS="$(mktemp -d /tmp/acs-stdin-stubs-XXXXXX)"
mkdir -p "${_STUBS}/fast" "${_STUBS}/slow"
printf '#!/bin/sh\nexit 0\n' > "${_STUBS}/fast/cozempic"
# Records its pid so the cell can reap it, then outlives the watchdog.
printf '#!/bin/sh\necho $$ >> "%s/slow.pids"\nexec sleep 20\n' "${_STUBS}" > "${_STUBS}/slow/cozempic"
chmod +x "${_STUBS}/fast/cozempic" "${_STUBS}/slow/cozempic"
_STUB_PATH="${_STUBS}/fast"

# _run_against_fifo <command...> -> prints "hung" or "terminated"
_run_against_fifo() {
    local _work _fifo _holder _runner _i=0 _res
    _work="$(mktemp -d /tmp/acs-stdin-XXXXXX)"
    _fifo="${_work}/in"
    mkfifo "${_fifo}" 2>/dev/null || { echo "cannot-check"; rm -rf "${_work}"; return; }
    # Holds the write end open so readers never see EOF.
    sleep 30 > "${_fifo}" &
    _holder=$!
    HOME="${_work}/home" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" PATH="${_STUB_PATH}:${PATH}" \
        "$@" < "${_fifo}" > "${_work}/out" 2>&1 &
    _runner=$!
    while [ "${_i}" -lt 8 ]; do
        kill -0 "${_runner}" 2>/dev/null || break
        sleep 1; _i=$(( _i + 1 ))
    done
    if kill -0 "${_runner}" 2>/dev/null; then
        kill -9 "${_runner}" 2>/dev/null; _res=hung
    else
        _res=terminated
    fi
    kill -9 "${_holder}" 2>/dev/null
    wait "${_runner}" 2>/dev/null
    rm -rf "${_work}"
    printf '%s' "${_res}"
}

test_harness_actually_blocks() {
    # THE RED CONTROL. An unbounded reader must hang in this harness. Without
    # it, a harness that never blocks would make every cell below pass while
    # proving nothing.
    local r
    r="$(_run_against_fifo /bin/bash -c 'cat > /dev/null')"
    if [ "${r}" = "hung" ]; then
        _record_pass "the harness blocks an unbounded reader (control)"
    else
        _record_fail "the harness blocks an unbounded reader (control)" \
            "got '${r}' — the FIFO is not blocking, so every cell below is vacuous"
    fi
}

test_session_start_is_bounded() {
    local r; r="$(_run_against_fifo /bin/bash "${PROJECT_ROOT}/hooks/session-start-hook.sh")"
    [ "${r}" = "terminated" ] && _record_pass "session-start-hook terminates on a never-EOF FIFO" \
        || _record_fail "session-start-hook terminates on a never-EOF FIFO" "got '${r}'"
}

test_session_start_does_not_wait_on_cozempic() {
    # #369. A slow `cozempic init` must neither hold the hook open nor hold its
    # stdout: Claude Code reads a hook's stdout to EOF, so a detached child that
    # inherited it would stall SessionStart exactly as waiting on it would. The
    # `$( )` capture is what makes the second failure visible — it waits for EOF.
    local r
    _STUB_PATH="${_STUBS}/slow"
    r="$(_run_against_fifo /bin/bash -c '_o="$(/bin/bash "$1")"; exit 0' _ \
        "${PROJECT_ROOT}/hooks/session-start-hook.sh")"
    _STUB_PATH="${_STUBS}/fast"
    if [ -s "${_STUBS}/slow.pids" ]; then
        kill $(cat "${_STUBS}/slow.pids") 2>/dev/null
    else
        r="cannot-check (the slow cozempic stub never ran)"
    fi
    [ "${r}" = "terminated" ] && _record_pass "session-start does not wait on, or hand its stdout to, a slow cozempic init" \
        || _record_fail "session-start does not wait on, or hand its stdout to, a slow cozempic init" "got '${r}'"
}

test_activation_is_bounded() {
    local r; r="$(_run_against_fifo /bin/bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh")"
    [ "${r}" = "terminated" ] && _record_pass "skill-activation-hook terminates on a never-EOF FIFO" \
        || _record_fail "skill-activation-hook terminates on a never-EOF FIFO" "got '${r}'"
}

test_completion_is_bounded() {
    local r; r="$(_run_against_fifo /bin/bash "${PROJECT_ROOT}/hooks/skill-completion-hook.sh")"
    [ "${r}" = "terminated" ] && _record_pass "skill-completion-hook terminates on a never-EOF FIFO" \
        || _record_fail "skill-completion-hook terminates on a never-EOF FIFO" "got '${r}'"
}

test_payload_still_parses() {
    # The happy path must be unchanged. `$( )` strips trailing newlines exactly
    # as `$(cat)` did, so a payload written and closed normally reads the same.
    local got
    got="$(printf '%s' '{"session_id":"abc-123","transcript_path":"/tmp/t.jsonl"}' \
        | /bin/bash -c '
            _l=""
            while IFS= read -r -t 2 _l; do printf "%s\n" "$_l"; _l=""; done
            [ -n "$_l" ] && printf "%s" "$_l"
            exit 0' | jq -r '.session_id' 2>/dev/null)"
    [ "${got}" = "abc-123" ] && _record_pass "a normal payload still parses (happy path unchanged)" \
        || _record_fail "a normal payload still parses" "got '${got}', expected abc-123"
}

test_empty_stdin_does_not_become_an_early_exit() {
    # FAIL-OPEN. A timeout must yield an empty payload and let the hook carry on
    # into the work it exists to do; converting "no payload" into an early exit
    # would skip registry building, which is worse than the hang.
    local rc _h
    _h="$(mktemp -d)"
    HOME="${_h}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" PATH="${_STUBS}/fast:${PATH}" \
        /bin/bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" < /dev/null >/dev/null 2>&1
    rc=$?
    rm -rf "${_h}"
    [ "${rc}" -eq 0 ] && _record_pass "empty stdin still exits 0 (fail-open preserved)" \
        || _record_fail "empty stdin still exits 0" "exit was ${rc}"
}

test_no_unbounded_cat_remains() {
    # The three hooks are named because they are the ones that read a payload.
    local h bad=""
    for h in session-start-hook skill-activation-hook skill-completion-hook; do
        grep -qE '=\"?\$\(cat 2>/dev/null\)' "${PROJECT_ROOT}/hooks/${h}.sh" && bad="${bad} ${h}"
    done
    [ -z "${bad}" ] && _record_pass "no payload hook reads stdin with an unbounded cat" \
        || _record_fail "no payload hook reads stdin with an unbounded cat" "still unbounded:${bad}"
}

test_harness_actually_blocks
test_session_start_is_bounded
test_session_start_does_not_wait_on_cozempic
test_activation_is_bounded
test_completion_is_bounded
test_payload_still_parses
test_empty_stdin_does_not_become_an_early_exit
test_no_unbounded_cat_remains

rm -rf "${_STUBS}"
print_summary
