#!/usr/bin/env bash
# test-suite-isolation.sh — the suite must not reach outside the HOME and
# TMPDIR it gives itself (#372).
#
# Measured 2026-10-23 on one full green run: session-start ran against the real
# HOME twice (tests/test-mcp-connection-probe.sh), rewriting the real
# ~/.claude/.skill-registry-cache.json from the checkout; the installed `claude`
# CLI ran 119 times from 17 files; and six acs-test.* dirs were left in TMPDIR,
# 781 of them accumulated since 2026-10-08. Every run was green.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-suite-isolation.sh ==="

W="$(mktemp -d "${TMPDIR:-/tmp}/acs-isolation.XXXXXX")"
trap 'rm -rf "${W}"' EXIT

test_mcp_probe_file_leaves_the_starting_home_untouched() {
    # The file is started with a stand-in for the user's HOME; a stub `claude`
    # that prints nothing keeps its end-to-end cell on the announced skip.
    local h="${W}/probe-home" b="${W}/probe-bin"
    mkdir -p "${h}" "${b}"
    printf '#!/bin/sh\nexit 0\n' > "${b}/claude"
    chmod +x "${b}/claude"
    HOME="${h}" PATH="${b}:${PATH}" bash "${SCRIPT_DIR}/test-mcp-connection-probe.sh" \
        < /dev/null > "${W}/probe.log" 2>&1
    local rc=$?
    assert_equals "test-mcp-connection-probe.sh passes under a stand-in HOME" "0" "${rc}"
    local left
    left="$(cd "${h}" && find . -mindepth 1 2>/dev/null | head -5 | tr '\n' ' ')"
    assert_equals "test-mcp-connection-probe.sh writes nothing into the HOME it was started with" "" "${left}"
}

test_mcp_probe_file_leaves_the_starting_home_untouched

print_summary
