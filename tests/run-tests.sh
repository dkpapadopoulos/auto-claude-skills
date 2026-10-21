#!/usr/bin/env bash
# run-tests.sh — Discovers and runs all test-*.sh files in the tests/ directory.
# Bash 3.2 compatible (macOS default). CI-ready: exits 1 on any failure.

set -u

# Self-guard stdin (#142). No test in this suite reads the runner's stdin, but
# several invoke hooks that do — hooks/session-start-hook.sh reads its payload
# with `$(cat)` behind a `[ ! -t 0 ]` check, and a TTY check is not an "input
# available" check. When the caller's fd 0 is a socket or FIFO (routine in agent
# sessions) that `cat` blocks forever waiting for an EOF that never arrives, and
# the suite parks mid-run at near-zero CPU with no error — one observed run sat
# idle roughly two hours. Relying on callers to pass `< /dev/null` failed: a
# fresh session or CI path that forgets it re-hangs. Redirecting here is
# inherited by every discovered test file at once.
# Regression: tests/test-suite-stdin-guard.sh
exec < /dev/null

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# A stub `cozempic` first on PATH for every file (#369). session-start-hook.sh
# starts `cozempic init` detached when one is installed; on the fresh HOME most
# tests give it, a real one ran 23 s and outlived the test, and CI has none, so
# no file may depend on what is installed. tests/test-helpers.sh::setup_test_env
# stubs it too, for a file run on its own; several files run session-start
# without setup_test_env, hence this.
# Regression: tests/test-setup-env-cozempic-stub.sh
STUB_BIN="$(mktemp -d "${TMPDIR:-/tmp}/acs-run-stubs.XXXXXX")" || STUB_BIN=""
if [ -n "${STUB_BIN}" ]; then
    printf '#!/bin/sh\nexit 0\n' > "${STUB_BIN}/cozempic"
    chmod +x "${STUB_BIN}/cozempic"
    export PATH="${STUB_BIN}:${PATH}"
    trap 'rm -rf "${STUB_BIN}"' EXIT
fi

# Completion sentinel (#263). The summary block below is shape-identical to the
# one tests/test-helpers.sh::print_summary emits at the end of EVERY individual
# test file — same frame, same four-space padding, one word apart. So a reader
# that lands on a per-file block, tailing a running log or reading one that was
# reaped partway, cannot tell it from this runner's own terminal block.
#
# That made suite completion assertable only by ABSENCE, and nothing asserted
# it: on a real reaped run (2026-08-27) 91 of 122 files had executed, with
# thousands of PASS assertions and not one `FAIL:` line. Every signal a normal
# check inspects said green.
#
# This line is the one thing a per-file block cannot produce. Consumers must
# gate a pass claim on its PRESENCE, never on the absence of `FAIL:` lines —
# see scripts/assert-suite-complete.sh, which is the supported reader.
# Regression: tests/test-suite-completion.sh
emit_completion_sentinel() {
    printf 'ACS-RUN-TESTS-COMPLETE files=%d passed=%d failed=%d status=%s\n' \
        "${TOTAL_FILES}" "${PASSED_FILES}" "${FAILED_FILES}" "$1"
}

TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
FAILED_NAMES=""

# Tracked-tree check (#367). A test that rewrites a tracked file and does not
# restore it byte for byte used to pass unnoticed: a full green run left
# config/fallback-registry.json one byte short (measured 2026-09-29 and
# 2026-10-20), waiting for the next `git add -A`. The tree's state is taken
# before and after every file, and the file after which it differs FAILS, so
# the culprit is the one named. The runner cannot tell a test's write from
# something else editing the tree meanwhile (another session, an editor save),
# so the message names both causes; either one spoils the run as a gate.
#
# State = the status lines AND a checksum of HEAD plus the diff against it: a
# file that was modified before the run and is changed again keeps its status
# line, and a verification run before committing is exactly that dirty-tree
# case; a commit or branch switch can leave both unchanged, so HEAD is in it.
# Untracked files are not the tracked tree and are ignored.
# Regression: tests/test-suite-tree-unchanged.sh
TREE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
tree_status() { git -C "${TREE_ROOT}" status --porcelain --untracked-files=no 2>/dev/null; }
tree_sum() {
    { git -C "${TREE_ROOT}" rev-parse -q --verify HEAD
      git -C "${TREE_ROOT}" diff HEAD --no-ext-diff --binary; } 2>/dev/null | cksum
}
TREE_CHECK=on
git -C "${TREE_ROOT}" rev-parse --verify -q HEAD >/dev/null 2>&1 || TREE_CHECK=off

# The fallback registry. hooks/session-start-hook.sh regenerates the tracked
# config/fallback-registry.json whenever it is out of date with
# config/default-triggers.json (its step 10c, skipped under _SKILL_TEST_MODE),
# and many test files run that hook against this checkout. So after a routing
# edit the first of them rewrote the file, and the check above failed THAT
# file for it. The runner runs the hook once, after the header and before any
# snapshot, so the regeneration is the runner's own and no test is blamed. The
# run still FAILS when it changed the file: the committed fallback is out of
# date, and a pass would record a clean verdict for that commit while the sync
# test in test-registry.sh, which reads the regenerated copy, cannot fail. A stub
# `claude` keeps the hook's Serena auto-register step, the other step test mode
# skips, off the real CLI.
FALLBACK_REGENERATED=""
FB_FILE="${TREE_ROOT}/config/fallback-registry.json"
FB_HOOK="${TREE_ROOT}/hooks/session-start-hook.sh"
FB_REASON="config/fallback-registry.json was out of date with config/default-triggers.json at the start of the run; it has been regenerated. Commit it with the routing change and run again."

# Discover test files (excluding test-helpers.sh itself)
test_files=""
for f in "${SCRIPT_DIR}"/test-*.sh; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
        test-helpers.sh) continue ;;
    esac
    test_files="${test_files} ${f}"
done

if [ -z "${test_files}" ]; then
    echo "No test files found in ${SCRIPT_DIR}/test-*.sh"
    emit_completion_sentinel none
    exit 0
fi

echo "============================================"
echo "  auto-claude-skills test runner"
echo "============================================"
echo ""
if [ "${TREE_CHECK}" = off ]; then
    echo "NOTE: ${TREE_ROOT} is not a git checkout with a commit, so this run cannot check"
    echo "      that tests leave the tracked tree unchanged (#367)."
    echo ""
fi
if [ "${TREE_CHECK}" = on ] && [ -n "${STUB_BIN}" ] && [ -f "${FB_FILE}" ] && [ -f "${FB_HOOK}" ]; then
    echo "Checking config/fallback-registry.json against config/default-triggers.json ..."
    mkdir -p "${STUB_BIN}/fb-bin" "${STUB_BIN}/fb-home"
    printf '#!/bin/sh\nexit 0\n' > "${STUB_BIN}/fb-bin/claude"
    chmod +x "${STUB_BIN}/fb-bin/claude"
    fb_before="$(cksum < "${FB_FILE}")"
    HOME="${STUB_BIN}/fb-home" PATH="${STUB_BIN}/fb-bin:${PATH}" CLAUDE_PLUGIN_ROOT="${TREE_ROOT}" \
        _SKILL_TEST_MODE= bash "${FB_HOOK}" > /dev/null 2>&1
    [ "$(cksum < "${FB_FILE}")" = "${fb_before}" ] || FALLBACK_REGENERATED=yes
    if [ -n "${FALLBACK_REGENERATED}" ]; then
        echo "FAIL (runner): ${FB_REASON}"
        echo "      The tests still run; this run will fail."
    fi
    echo ""
fi

for test_file in ${test_files}; do
    name="$(basename "${test_file}")"
    echo "--- Running: ${name} ---"
    TOTAL_FILES=$((TOTAL_FILES + 1))

    if [ "${TREE_CHECK}" = on ]; then
        before_status="$(tree_status)"
        before_sum="$(tree_sum)"
    fi
    file_ok=0
    bash "${test_file}" && file_ok=1
    if [ "${TREE_CHECK}" = on ]; then
        after_status="$(tree_status)"
        after_sum="$(tree_sum)"
        if [ "${after_status}" != "${before_status}" ] || [ "${after_sum}" != "${before_sum}" ]; then
            file_ok=0
            echo "FAIL (runner): the tracked tree changed while ${name} ran (the test, or a concurrent edit):"
            printf '%s\n' "${after_status}" | while IFS= read -r line; do
                [ -n "${line}" ] || continue
                case "
${before_status}
" in
                    *"
${line}
"*) ;;
                    *) echo "    ${line}" ;;
                esac
            done
            # A line that DISAPPEARED is a change too: a file modified before
            # the run and reverted (or committed) during it.
            printf '%s\n' "${before_status}" | while IFS= read -r line; do
                [ -n "${line}" ] || continue
                case "
${after_status}
" in
                    *"
${line}
"*) ;;
                    *) echo "    ${line}  (this status line is gone or changed)" ;;
                esac
            done
            [ "${after_status}" = "${before_status}" ] \
                && echo "    (an already-modified file's content changed; status lines are unchanged)"
        fi
    fi

    if [ "${file_ok}" -eq 1 ]; then
        PASSED_FILES=$((PASSED_FILES + 1))
    else
        FAILED_FILES=$((FAILED_FILES + 1))
        if [ -n "${FAILED_NAMES}" ]; then
            FAILED_NAMES="${FAILED_NAMES}, ${name}"
        else
            FAILED_NAMES="${name}"
        fi
    fi
    echo ""
done

echo "============================================"
printf "  Files run:    %d\n" "${TOTAL_FILES}"
printf "  Files passed: %d\n" "${PASSED_FILES}"
printf "  Files failed: %d\n" "${FAILED_FILES}"
echo "============================================"

if [ "${FAILED_FILES}" -gt 0 ] || [ -n "${FALLBACK_REGENERATED}" ]; then
    echo ""
    [ -n "${FAILED_NAMES}" ] && echo "Failed: ${FAILED_NAMES}"
    # Last, so a verdict's short excerpt of this log keeps it.
    [ -n "${FALLBACK_REGENERATED}" ] && echo "Failed (runner): ${FB_REASON}"
    emit_completion_sentinel fail
    exit 1
fi

echo "All test files passed."
emit_completion_sentinel pass
exit 0
