# Plan: push-gate-precondition-canary (3 TDD tasks, audit F5)

Branch: `fix/push-gate-precondition-canary` (off main @ 743c4a3).
Spec: `openspec/changes/push-gate-precondition-canary/` (committed).

## Task 1 — RED: behavioral canary tests (tests/test-push-gate-canary.sh)

- [x] Harness: copy hooks/ + config/ into a temp plugin root; sandboxed HOME;
      run the REAL session-start hook (`echo '{}' | CLAUDE_PLUGIN_ROOT=$T bash
      $T/hooks/session-start-hook.sh`).
- [x] Healthy root → output does NOT contain `PUSH-GATE CANARY`.
- [x] Syntax-broken `hooks/lib/branch-ledger.sh` (inject `$(( "1" / 1 ))`
      Bash-3.2 killer) → canary present, names `branch-ledger.sh`.
- [x] Deleted `hooks/lib/verdict.sh` → canary present, names `verdict.sh`.
- [x] jq-less PATH (NOJQ_BIN pattern from test-push-gate-failclosed.sh) →
      fallback message states the push gate falls open.
- [x] All red against current hook.

## Task 2 — GREEN: implement canary (hooks/session-start-hook.sh)

- [x] jq-less early-exit MSG: append gate-falls-open sentence (plain ASCII).
- [x] Canary block before WARNING_COUNT: hardcoded component list with PAIRED
      note; `[ -f ]` per file; ONE `/bin/bash -n` batched fork; per-file
      re-check only on failure; at most one WARNINGS append; wrapped fail-open.
- [x] `/bin/bash -n` the hook; Task 1 green; existing session-start/banner/
      registry suites green.

## Task 3 — Docs + verification

- [x] CLAUDE.md: extend the fail-open gotcha with the canary pointer.
- [x] CHANGELOG `[Unreleased]` Added entry.
- [x] Timing check: session-start wall-clock delta with canary (healthy path)
      stays within budget (~single-digit ms added).
- [x] Full suite green; fresh verdict at HEAD; push as separate command.
