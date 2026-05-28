#!/bin/bash
# cozempic-wrapper.sh — Find and run cozempic with PATH discovery
# Usage: cozempic-wrapper.sh <command> [args...]
# Exits silently (0) if cozempic is not installed.
#
# When invoked with `doctor` as the first argument, also runs the
# context-economy monorepo-subdir detector and prints any hint on stdout
# BEFORE exec'ing cozempic. Respects ACSM_QUIET_SUBDIR=1.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

if [ "${1:-}" = "doctor" ]; then
    DETECT_SCRIPT="${PLUGIN_ROOT}/scripts/detect-monorepo-subdir.sh"
    if [ -x "${DETECT_SCRIPT}" ]; then
        bash "${DETECT_SCRIPT}" 2>/dev/null || true
    fi
fi

if ! command -v cozempic >/dev/null 2>&1; then
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
fi

command -v cozempic >/dev/null 2>&1 && exec cozempic "$@"
exit 0
