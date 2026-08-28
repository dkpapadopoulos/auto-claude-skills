#!/bin/bash
# cozempic-wrapper.sh — Find and run cozempic with PATH discovery
# Usage: cozempic-wrapper.sh <command> [args...]
# Exits silently (0) if cozempic is not installed.
#
# When invoked with `doctor` as the first argument, also runs the
# context-economy monorepo-subdir detector and prints any hint on stdout
# BEFORE exec'ing cozempic. Respects ACSM_QUIET_SUBDIR=1.
#
# `checkpoint` is registered on hooks.json's `^(Task|Agent)$` PostToolUse
# matcher (observed-dispatch-telemetry, R3: widened from a dead `^Task$`-only
# matcher), so on any machine with cozempic installed this now execs on EVERY
# subagent dispatch. Measured (this machine, cozempic 1.8.39, three runs):
# wall time ~0.19-0.21s (`timeout: 5` in hooks.json has ample headroom), but
# it DOES write to both streams every time — stdout: "  No team state
# detected." (26 bytes); stderr: "  Cozempic: local hooks redundant (global
# hooks active) — …" (140 bytes). A PostToolUse hook writing to stdout is a
# harness-visible side effect; this was flagged as a concern for the
# controller to weigh, not fixed here.

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
