#!/bin/bash
# cozempic-wrapper.sh — Find and run cozempic with PATH discovery
# Usage: cozempic-wrapper.sh <command> [args...]
# Exits silently (0) if cozempic is not installed.
#
# When invoked with `doctor` as the first argument, also runs the
# context-economy monorepo-subdir detector and prints any hint on stdout
# BEFORE exec'ing cozempic. Respects ACSM_QUIET_SUBDIR=1.
#
# STDOUT IS SUPPRESSED FOR EVERY VERB EXCEPT `doctor`.
#
# All four hooks.json registrations of this wrapper are hooks — `guard
# --daemon` (SessionStart) and three `checkpoint` entries (PostToolUse) — and
# stdout is the harness's structured channel for a hook, so passing the child's
# stdout through is a harness-visible side effect on every fire. Measured (this
# machine, cozempic 1.8.39, three runs): ~0.19-0.21s wall time, writing 26
# bytes to stdout ("  No team state detected.") and 140 to stderr every time.
# That was tolerable while the `^Task$` matcher was dead; the
# observed-dispatch-telemetry change widened it to `^(Task|Agent)$`, so it now
# fires on EVERY subagent dispatch.
#
# STDERR IS DELIBERATELY LEFT ALONE. It is not part of any hook's contract, and
# it is where a genuine cozempic failure would surface — silencing it would buy
# quiet by deleting diagnostics. Redirect stdout only.
#
# `doctor` is the one user-facing verb (it prints the monorepo-subdir hint
# above, then cozempic's own report) and KEEPS stdout. Any future verb added to
# hooks.json inherits the suppression; `tests/test-cozempic-wrapper.sh` pins
# the verb population so a new one cannot slip in unexercised.

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

if command -v cozempic >/dev/null 2>&1; then
    # `doctor` is user-facing; every other verb is hook-invoked and must not
    # write to the harness's stdout channel. stderr passes through in both.
    if [ "${1:-}" = "doctor" ]; then
        exec cozempic "$@"
    else
        exec cozempic "$@" >/dev/null
    fi
fi
exit 0
